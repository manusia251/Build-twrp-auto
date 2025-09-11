#!/bin/bash
set -e

# Arguments
DEVICE_TREE=$1
DEVICE_BRANCH=$2
DEVICE_CODENAME=$3
MANIFEST_BRANCH=${4:-"twrp-11"}
TARGET_RECOVERY_IMAGE=${5:-"boot"}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Debug function
debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Error function
error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Success function
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo "================================================"
echo "     TWRP Boot Builder for $DEVICE_CODENAME"
echo "     Target: boot.img (A/B MTK device)"
echo "     Touch: MediaTek TPD (built-in driver)"
echo "================================================"

# Working directory
WORK_DIR="/tmp/cirrus-ci-build/twrp"
mkdir -p $WORK_DIR
cd $WORK_DIR

# Git config
debug "Configuring git..."
git config --global user.name "manusia"
git config --global user.email "ndktau@gmail.com"
git config --global url.https://github.com/.insteadOf git@github.com:
git config --global url.https://.insteadOf git://

# Install repo if not exists
if ! command -v repo &> /dev/null; then
    debug "Installing repo tool..."
    curl https://storage.googleapis.com/git-repo-downloads/repo > /tmp/repo
    chmod a+x /tmp/repo
    sudo mv /tmp/repo /usr/local/bin/repo || mv /tmp/repo /usr/local/bin/repo
fi

# Initialize TWRP manifest
debug "Initializing TWRP manifest..."
repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-11 --git-lfs || {
    error "Failed to initialize manifest"
    exit 1
}

debug "Syncing source code..."
repo sync -c --force-sync --no-tags --no-clone-bundle -j$(nproc --all) --optimized-fetch --prune || {
    error "Failed to sync source"
    exit 1
}

# Fix missing VTS files
debug "Fixing missing VTS files..."
mkdir -p test/vts/tools/build
cat > test/vts/tools/build/Android.host_config.mk << 'EOF'
# Dummy VTS config file for TWRP build
LOCAL_PATH := $(call my-dir)
EOF

# Clone device tree
debug "Cloning device tree from $DEVICE_TREE..."
DEVICE_PATH="device/infinix/$DEVICE_CODENAME"
rm -rf $DEVICE_PATH
git clone $DEVICE_TREE -b $DEVICE_BRANCH $DEVICE_PATH || {
    error "Failed to clone device tree"
    exit 1
}

# Create necessary directories
debug "Creating recovery directory structure..."
mkdir -p $DEVICE_PATH/recovery/root

# First, let's check what BoardConfig.mk contains
debug "Current BoardConfig.mk content:"
cat $DEVICE_PATH/BoardConfig.mk || true

# Update BoardConfig.mk for boot.img (MTK Android 11 A/B, match getvar)
if ! grep -q "BOARD_BOOT_HEADER_VERSION := 2" $DEVICE_PATH/BoardConfig.mk 2>/dev/null; then
    debug "Adding boot.img configuration to BoardConfig.mk..."
    cat >> $DEVICE_PATH/BoardConfig.mk << 'EOF'

# Boot Configuration (match getvar: Android 11, header v2 for MTK)
BOARD_BOOT_HEADER_VERSION := 2
BOARD_KERNEL_BASE := 0x40000000
BOARD_KERNEL_CMDLINE := bootopt=64S3,32S1,32S1 buildvariant=user androidboot.selinux=permissive
BOARD_KERNEL_PAGESIZE := 2048
BOARD_RAMDISK_OFFSET := 0x11b00000
BOARD_KERNEL_TAGS_OFFSET := 0x07880000
BOARD_DTB_OFFSET := 0x07880000
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb_offset $(BOARD_DTB_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb $(DEVICE_PATH)/prebuilt/dtb.img  # Use DTB from device tree

# Boot partition size (match getvar: 32MB / 0x2000000)
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432

# A/B device flags (match getvar: dynamic partitions, slot-count:2)
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += boot system vendor product system_ext
BOARD_USES_RECOVERY_AS_BOOT := true
BOARD_BUILD_SYSTEM_ROOT_IMAGE := false
TARGET_NO_RECOVERY := false
TARGET_COPY_OUT_VENDOR := vendor
TARGET_USES_UEFI := false  # MTK specific

# MediaTek TPD Touchscreen (built-in driver, no module needed)
TW_CUSTOM_TOUCH_PATH := "/dev/input/event2"
TW_LOAD_VENDOR_MODULES := ""
TW_INPUT_BLACKLIST := "hbtp_vm"
TW_SCREEN_BLANK_ON_BOOT := false
TW_NO_SCREEN_BLANK := true

# TWRP Configuration (MTK tweaks)
TW_THEME := portrait_hdpi
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_LIBRESETPROP := true
TW_HAS_DOWNLOAD_MODE := true  # Untuk MTK Download Mode
TW_USE_MODEL_HARDWARE_ID_FOR_DEVICE_ID := true
TW_ALWAYS_RM_RF := true  # Clean cache agresif

# Fix boot loop/fastboot stuck (agresif clear BCB/misc untuk MTK)
TW_NO_LEGACY_PROPS := true
TW_OVERRIDE_SYSTEM_PROPS := "ro.bootmode=recovery;ro.build.fingerprint=Infinix/X6512-OP/Infinix-X6512:11/RP1A.200720.011/240220V535:user/release-keys"  # Match vendor-fingerprint dari getvar
EOF
fi

# Create init.recovery.X6512.rc with boot loop prevention (tambah clear misc agresif untuk MTK fastboot stuck)
debug "Creating init.recovery.${DEVICE_CODENAME}.rc with boot loop fix..."
cat > $DEVICE_PATH/recovery/root/init.recovery.${DEVICE_CODENAME}.rc << 'INIT_EOF'
on init
    # Create mount points
    mkdir /mnt/vendor/persist 0700 root root
    mount ext4 /dev/block/by-name/persist /mnt/vendor/persist rw
    
    # Enable ADB debugging
    setprop sys.usb.config adb
    setprop persist.sys.usb.config adb
    setprop persist.service.adb.enable 1
    setprop persist.service.debuggable 1
    setprop ro.adb.secure 0
    setprop service.adb.root 1
    
    # MediaTek TPD is built-in, no module loading needed
    # Debug: log touch device info
    exec u:r:recovery:s0 -- /system/bin/sh -c "ls -la /dev/input/ > /tmp/input_devices.log"
    exec u:r:recovery:s0 -- /system/bin/sh -c "cat /proc/bus/input/devices > /tmp/input_info.log"

    # Agresif clear BCB/misc untuk hindari fastboot stuck di MTK
    exec u:r:recovery:s0 -- /system/bin/dd if=/dev/zero of=/dev/block/by-name/misc bs=1 count=1024

on boot
    # Start ADB daemon
    start adbd
    
    # MediaTek TPD touchscreen permissions
    chmod 0666 /dev/input/event2
    chown system input /dev/input/event2
    
    # Additional input device permissions
    chmod 0666 /dev/input/event0
    chmod 0666 /dev/input/event1
    chmod 0666 /dev/input/event3
    
    # MediaTek TPD sysfs permissions
    chmod 0666 /sys/devices/virtual/input/input2/enabled
    chown system input /sys/devices/virtual/input/input2/enabled
    
    # Enable touchscreen via sysfs
    write /sys/devices/virtual/input/input2/enabled 1
    
    # TPD debug and settings (if available)
    chmod 0666 /sys/devices/virtual/misc/tpd_em_log/tpd_em_log
    chmod 0666 /sys/module/tpd_debug/parameters/tpd_em_log
    chmod 0666 /sys/module/tpd_setting/parameters/tpd_mode
    
    # Set TPD mode to normal operation
    write /sys/module/tpd_setting/parameters/tpd_mode 1
    
    # Enable TPD debug for troubleshooting
    write /sys/module/tpd_debug/parameters/tpd_em_log 1
    
    # Log touchscreen status
    exec u:r:recovery:s0 -- /system/bin/sh -c "echo 'TPD Status:' > /tmp/tpd_status.log"
    exec u:r:recovery:s0 -- /system/bin/sh -c "cat /sys/devices/virtual/input/input2/enabled >> /tmp/tpd_status.log"
    exec u:r:recovery:s0 -- /system/bin/sh -c "ls -la /sys/bus/platform/drivers/mtk-tpd >> /tmp/tpd_status.log"

    # Tambahan clear BCB on boot untuk MTK
    exec u:r:recovery:s0 -- /system/bin/dd if=/dev/zero of=/dev/block/by-name/misc bs=1 count=1024

on property:ro.debuggable=0
    setprop ro.debuggable 1

on property:ro.secure=1
    setprop ro.secure 0

on property:persist.sys.usb.config=none
    setprop persist.sys.usb.config adb

# Service for ADB
service adbd /system/bin/adbd --root_seclabel=u:r:su:s0
    disabled
    socket adbd stream 660 system system
    seclabel u:r:adbd:s0

on property:sys.usb.config=adb
    start adbd

# Service to monitor touchscreen status
service touch_monitor /system/bin/sh -c "while true; do cat /sys/devices/virtual/input/input2/enabled > /tmp/touch_state; sleep 5; done"
    user root
    group root
    disabled
    oneshot

on property:twrp.touch.debug=1
    start touch_monitor

# Boot control service to prevent boot loops/fastboot stuck
service bootctl_service /system/bin/sh -c "if [ -f /cache/recovery/command ]; then rm -f /cache/recovery/command; fi; dd if=/dev/zero of=/dev/block/by-name/misc bs=1 count=1024"
    oneshot
    seclabel u:r:recovery:s0

on property:init.svc.recovery=running
    start bootctl_service

# Clear BCB (Boot Control Block) to prevent recovery boot loop
on property:sys.boot_completed=1
    exec u:r:recovery:s0 -- /system/bin/sh -c "dd if=/dev/zero of=/dev/block/by-name/misc bs=1 count=32 seek=0"
INIT_EOF

# Create default.prop for ADB (match getvar fingerprint)
debug "Creating default.prop..."
cat > $DEVICE_PATH/recovery/root/default.prop << 'PROP_EOF'
ro.secure=0
ro.adb.secure=0
ro.debuggable=1
persist.sys.usb.config=adb
persist.service.adb.enable=1
persist.service.debuggable=1
service.adb.root=1
sys.usb.config=adb

# MediaTek TPD properties
ro.mtk.tpd.devicename=mtk-tpd
ro.mtk.tpd.driver=built-in
persist.mtk.tpd.enabled=1

# Boot control properties to prevent loops (match getvar)
ro.boot.recovery_as_boot=true
ro.boot.slot_suffix=_a
ro.build.fingerprint=Infinix/X6512-OP/Infinix-X6512:11/RP1A.200720.011/240220V535:user/release-keys
PROP_EOF

# Create recovery.fstab with A/B support (match getvar dynamic partitions)
if [ ! -f "$DEVICE_PATH/recovery.fstab" ]; then
    debug "Creating recovery.fstab with A/B support..."
    cat > $DEVICE_PATH/recovery.fstab << 'FSTAB_EOF'
# mount point    fstype    device                                        flags
/system          ext4      /dev/block/mapper/system                     flags=display="System";logical;slotselect
/vendor          ext4      /dev/block/mapper/vendor                     flags=display="Vendor";logical;slotselect
/product         ext4      /dev/block/mapper/product                    flags=display="Product";logical;slotselect
/system_ext      ext4      /dev/block/mapper/system_ext                 flags=display="System_ext";logical;slotselect
/boot            emmc      /dev/block/by-name/boot                      flags=display="Boot";backup=1;flashimg=1;slotselect
/data            f2fs      /dev/block/by-name/userdata                  flags=fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized
/cache           ext4      /dev/block/by-name/cache                     flags=display="Cache"
/metadata        ext4      /dev/block/by-name/metadata                  flags=display="Metadata"
/persist         ext4      /dev/block/by-name/persist                   flags=display="Persist"
/misc            emmc      /dev/block/by-name/misc                      flags=display="Misc"
/super           emmc      /dev/block/by-name/super                     flags=display="Super";backup=1

# Removable storage
/external_sd     auto      /dev/block/mmcblk1p1                         flags=display="MicroSD";storage;wipeingui;removable
/usb_otg         auto      /dev/block/sda1                              flags=display="USB Storage";storage;wipeingui;removable
FSTAB_EOF
fi

# Create twrp.flags to handle A/B slots properly
debug "Creating twrp.flags..."
cat > $DEVICE_PATH/twrp.flags << 'FLAGS_EOF'
# Boot partitions
/boot_a          emmc      /dev/block/by-name/boot_a                    flags=display="Boot A";backup=1;flashimg=1
/boot_b          emmc      /dev/block/by-name/boot_b                    flags=display="Boot B";backup=1;flashimg=1

# System Image backups
/system_image    emmc      /dev/block/mapper/system                     flags=backup=1;flashimg=1;display="System Image"
/vendor_image    emmc      /dev/block/mapper/vendor                     flags=backup=1;flashimg=1;display="Vendor Image"
FLAGS_EOF

# Create vendorsetup.sh (tweak untuk MTK)
debug "Creating vendorsetup.sh..."
cat > $DEVICE_PATH/vendorsetup.sh << 'VENDOR_EOF'
# MediaTek TPD touchscreen configuration (built-in driver)
export TW_CUSTOM_TOUCH_PATH="/dev/input/event2"
export TW_LOAD_VENDOR_MODULES=""
export TW_MAX_BRIGHTNESS=2047
export TW_DEFAULT_BRIGHTNESS=1200

# Touch resolution from getevent
export TW_TOUCH_X_RESOLUTION=720
export TW_TOUCH_Y_RESOLUTION=1612

# Force boot.img build for MTK (no vendor_boot)
export BOARD_USES_RECOVERY_AS_BOOT=true
export BOARD_BUILD_SYSTEM_ROOT_IMAGE=false
export TARGET_NO_RECOVERY=false

# A/B device configuration (match getvar)
export AB_OTA_UPDATER=true

# Debug flags
export TARGET_USES_LOGD=true
export TWRP_INCLUDE_LOGCAT=true
export TW_CRYPTO_SYSTEM_VOLD_DEBUG=true

echo "========================================"
echo "TWRP boot.img variables loaded"
echo "Device: X6512 (MTK A/B Android 11)"
echo "Touch: MediaTek TPD (built-in)"
echo "Input: /dev/input/event2"
echo "Resolution: 720x1612"
echo "Multi-touch: 5 slots"
echo "========================================"
VENDOR_EOF

chmod +x $DEVICE_PATH/vendorsetup.sh

# Create empty module files (since mtk-tpd is built-in)
debug "Creating empty module files (mtk-tpd is built-in)..."
echo "# MediaTek TPD is built-in to kernel, no modules needed" > $DEVICE_PATH/modules.load.boot
echo "# MediaTek TPD is built-in to kernel, no modules needed" > $DEVICE_PATH/modules.load.recovery

# Setup build environment
debug "Setting up build environment..."
source build/envsetup.sh

# Export build variables (tambah untuk MTK Android 11)
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL=C
export TW_EXCLUDE_DEFAULT_USB_INIT=true
export TW_USE_TOOLBOX=true
export BUILD_BROKEN_DUP_RULES=true
export BUILD_BROKEN_MISSING_REQUIRED_MODULES=true
export BOARD_VNDK_VERSION=30  # Match version-vndk dari getvar
export PRODUCT_FULL_TREBLE_OVERRIDE=true  # Karena treble-enabled:true
export TARGET_SYSTEM_PROP=system.prop  # Fix syntax: hilangkan := (ini yang error)

# Load device configuration
source $DEVICE_PATH/vendorsetup.sh

# Build configuration
debug "Setting up build configuration..."
lunch twrp_${DEVICE_CODENAME}-eng || {
    error "Failed to setup build configuration"
    exit 1
}

# Clean previous builds (lebih agresif untuk hindari cache error)
debug "Cleaning previous builds..."
make clobber || true
rm -rf out/ || true
make clean

# Remove problematic makefiles
debug "Removing problematic makefiles..."
find . -name "Android.mk" -path "*/vts/*" -exec rm -f {} \; 2>/dev/null || true

# Check available build targets
debug "Checking available build targets..."
make help 2>&1 | grep -E "boot|recovery|vendor" || true

# Build boot image (coba recoveryimage jika bootimage gagal)
debug "Building boot image..."
make bootimage -j$(nproc --all) 2>&1 | tee build.log || {
    error "Boot image build failed, trying recovery image..."
    make recoveryimage -j$(nproc --all) 2>&1 | tee -a build.log || {
        error "Recovery image build also failed"
    }
}

# Check for output
OUTPUT_DIR="out/target/product/$DEVICE_CODENAME"
OUTPUT_FOUND=""

# Debug: List ALL files in output directory
debug "Listing all files in output directory..."
if [ -d "$OUTPUT_DIR" ]; then
    find $OUTPUT_DIR -type f -name "*.img" -o -name "*.cpio" -o -name "*.gz" -o -name "ramdisk*" 2>/dev/null | while read file; do
        debug "Found: $file ($(du -h "$file" | cut -f1))"
    done
else
    error "Output directory doesn't exist!"
fi

# Extended list of possible outputs
POSSIBLE_OUTPUTS=(
    "$OUTPUT_DIR/boot.img"
    "$OUTPUT_DIR/recovery.img"
    "$OUTPUT_DIR/boot_a.img"
    "$OUTPUT_DIR/boot_b.img"
    "$OUTPUT_DIR/ramdisk.img"
    "$OUTPUT_DIR/ramdisk-recovery.img"
    "$OUTPUT_DIR/ramdisk-recovery.cpio"
    "$OUTPUT_DIR/ramdisk-recovery.cpio.gz"
    "$OUTPUT_DIR/obj/PACKAGING/target_files_intermediates/*/IMAGES/boot.img"
    "$OUTPUT_DIR/obj/PACKAGING/target_files_intermediates/*/IMAGES/recovery.img"
)

for OUTPUT in "${POSSIBLE_OUTPUTS[@]}"; do
    if [ -f "$OUTPUT" ] || ls $OUTPUT 2>/dev/null; then
        OUTPUT_FOUND=$(ls $OUTPUT 2>/dev/null | head -1)
        success "Found output: $OUTPUT_FOUND"
        break
    fi
done

# Final output handling
if [ -n "$OUTPUT_FOUND" ]; then
    success "Build completed successfully!"
    echo "Output: $OUTPUT_FOUND"
    echo "Size: $(du -h "$OUTPUT_FOUND" | cut -f1)"
    
    # Create output directory
    mkdir -p /tmp/cirrus-ci-build/output
    
    # Determine output name
    OUTPUT_NAME="twrp-boot-${DEVICE_CODENAME}-$(date +%Y%m%d-%H%M%S).img"
    
    cp "$OUTPUT_FOUND" "/tmp/cirrus-ci-build/output/$OUTPUT_NAME"
    
    # Copy build log
    cp build.log /tmp/cirrus-ci-build/output/
    
    # Create detailed info file (tambah note MTK)
    cat > /tmp/cirrus-ci-build/output/build_info.txt << EOF
TWRP Build Information
======================
Device: $DEVICE_CODENAME
Date: $(date)
Source: $DEVICE_TREE
Branch: $DEVICE_BRANCH
Output: $OUTPUT_NAME
Size: $(du -h "/tmp/cirrus-ci-build/output/$OUTPUT_NAME" | cut -f1)
Type: boot.img (MTK A/B Android 11)

Features:
- ADB enabled by default (root access)
- MediaTek TPD touchscreen support (built-in driver)
- A/B slot support with agresif BCB clear
- Boot loop/fastboot stuck prevention for MTK

Flash Instructions (untuk MTK tanpa temporary boot):
==================
1. Reboot to bootloader: adb reboot bootloader
2. Flash TWRP: fastboot flash boot_a $OUTPUT_NAME
3. For both slots: fastboot flash boot_b $OUTPUT_NAME
4. Erase misc: fastboot erase misc
5. Set active slot: fastboot --set-active=a
6. Reboot to recovery manual: Matikan HP, tekan Vol Up + Power

To boot system normally:
- In TWRP, go to Reboot > System

Touch Device Information:
========================
Device Name: mtk-tpd
Input Path: /dev/input/event2
Resolution: 720x1612
Multi-touch: 5 slots

Notes:
- Built for boot.img target (device tree from boot.img)
- Agresif clear misc/BCB untuk hindari fastboot stuck di MTK
- Match getvar: Android 11, dynamic partitions

Build Type: Boot Image (A/B MTK)
EOF
    
    # Generate checksums
    cd /tmp/cirrus-ci-build/output
    sha256sum *.img > sha256sums.txt
    
    echo ""
    success "Build artifacts:"
    ls -lah /tmp/cirrus-ci-build/output/
    
    echo ""
    echo "================================================"
    echo "         TWRP Build Complete!                   "
    echo "================================================"
    echo "Features enabled:"
    echo "✓ ADB with root access"
    echo "✓ MediaTek TPD touchscreen (built-in)"
    echo "✓ A/B slot support"
    echo "✓ MTK fastboot stuck prevention"
    echo "✓ Output: boot.img"
    echo "================================================"
else
    error "Build failed! No output image found"
    echo ""
    echo "Checking last 50 lines of build log for errors:"
    echo "================================================"
    grep -i "error\|failed\|failure" build.log | tail -50 || echo "No specific errors found"
    
    # Still save build log even on failure
    mkdir -p /tmp/cirrus-ci-build/output
    cp build.log /tmp/cirrus-ci-build/output/build_failed.log
    
    exit 1
fi
