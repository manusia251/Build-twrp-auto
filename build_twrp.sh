#!/bin/bash
set -e

# Arguments
DEVICE_TREE=$1
DEVICE_BRANCH=$2
DEVICE_CODENAME=$3
MANIFEST_BRANCH=${4:-"twrp-12.1"}
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
echo "     Branch: $MANIFEST_BRANCH"
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

# Initialize TWRP manifest with specified branch
debug "Initializing TWRP manifest (branch: $MANIFEST_BRANCH)..."
repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b $MANIFEST_BRANCH --git-lfs || {
    error "Failed to initialize manifest"
    exit 1
}

debug "Syncing source code..."
repo sync -c --force-sync --no-tags --no-clone-bundle -j$(nproc --all) --optimized-fetch --prune || {
    error "Failed to sync source"
    exit 1
}

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

# Check existing BoardConfig.mk
debug "Checking existing BoardConfig.mk..."
if [ -f "$DEVICE_PATH/BoardConfig.mk" ]; then
    debug "BoardConfig.mk exists, will append our configs"
else
    debug "BoardConfig.mk not found, creating new one"
    touch $DEVICE_PATH/BoardConfig.mk
fi

# Append boot configuration to BoardConfig.mk
debug "Adding boot.img configuration to BoardConfig.mk..."
cat >> $DEVICE_PATH/BoardConfig.mk << 'EOF'

# TWRP Boot Configuration for MTK A/B
BOARD_BOOT_HEADER_VERSION := 2
BOARD_KERNEL_BASE := 0x40000000
BOARD_KERNEL_CMDLINE := bootopt=64S3,32S1,32S1 buildvariant=user
BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive
BOARD_KERNEL_PAGESIZE := 2048
BOARD_RAMDISK_OFFSET := 0x11b00000
BOARD_KERNEL_TAGS_OFFSET := 0x07880000
BOARD_DTB_OFFSET := 0x07880000
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb_offset $(BOARD_DTB_OFFSET)

# Partition sizes
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432

# A/B OTA
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += boot system vendor product system_ext
BOARD_USES_RECOVERY_AS_BOOT := true
TARGET_NO_RECOVERY := false

# Dynamic partitions
BOARD_SUPER_PARTITION_SIZE := 4685037568
BOARD_SUPER_PARTITION_GROUPS := infinix_dynamic_partitions
BOARD_INFINIX_DYNAMIC_PARTITIONS_SIZE := 4680843264
BOARD_INFINIX_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor product system_ext

# TWRP specific flags
TW_THEME := portrait_hdpi
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_LIBRESETPROP := true
TW_HAS_DOWNLOAD_MODE := true
TW_NO_LEGACY_PROPS := true

# MediaTek touchscreen
TW_CUSTOM_TOUCH_PATH := "/dev/input/event2"
TW_SCREEN_BLANK_ON_BOOT := false
TW_NO_SCREEN_BLANK := true
TW_INPUT_BLACKLIST := "hbtp_vm"
TW_MAX_BRIGHTNESS := 2047
TW_DEFAULT_BRIGHTNESS := 1200

# Encryption
TW_INCLUDE_CRYPTO := true
TW_USE_FSCRYPT_POLICY := 2
TW_INCLUDE_FBE_METADATA_DECRYPT := true

# System properties override
TW_OVERRIDE_SYSTEM_PROPS := "ro.bootmode=recovery;ro.build.fingerprint=Infinix/X6512-OP/Infinix-X6512:11/RP1A.200720.011/240220V535:user/release-keys"

# Other TWRP flags
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_USE_TOOLBOX := true
TW_INCLUDE_NTFS_3G := true
TW_INCLUDE_FUSE_EXFAT := true
TW_INCLUDE_FUSE_NTFS := true
TW_INCLUDE_LOGICAL := true
TW_EXCLUDE_TWRPAPP := true
TW_NO_HAPTICS := true
EOF

# Create init.recovery.rc
debug "Creating init.recovery.${DEVICE_CODENAME}.rc..."
cat > $DEVICE_PATH/recovery/root/init.recovery.${DEVICE_CODENAME}.rc << 'INIT_EOF'
on init
    # Create necessary directories
    mkdir /mnt/vendor/persist 0700 root root
    
    # Clear misc partition to prevent bootloop
    exec u:r:recovery:s0 -- /system/bin/dd if=/dev/zero of=/dev/block/by-name/misc bs=1 count=1024
    
    # Enable ADB
    setprop sys.usb.config adb
    setprop persist.sys.usb.config adb
    setprop persist.service.adb.enable 1
    setprop persist.service.debuggable 1
    setprop ro.adb.secure 0
    setprop service.adb.root 1

on boot
    # Start ADB
    start adbd
    
    # MediaTek touchscreen
    chmod 0666 /dev/input/event2
    chown system input /dev/input/event2
    chmod 0666 /dev/input/event0
    chmod 0666 /dev/input/event1
    chmod 0666 /dev/input/event3
    
    # Enable touchscreen
    write /sys/devices/virtual/input/input2/enabled 1

on property:ro.debuggable=0
    setprop ro.debuggable 1

on property:ro.secure=1
    setprop ro.secure 0

service adbd /system/bin/adbd --root_seclabel=u:r:su:s0
    disabled
    socket adbd stream 660 system system
    seclabel u:r:adbd:s0

service bootctl_fix /system/bin/sh -c "dd if=/dev/zero of=/dev/block/by-name/misc bs=1 count=1024"
    oneshot
    seclabel u:r:recovery:s0

on property:init.svc.recovery=running
    start bootctl_fix
INIT_EOF

# Create default.prop
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

# MediaTek specific
ro.mtk.tpd.devicename=mtk-tpd
persist.mtk.tpd.enabled=1

# A/B specific
ro.boot.slot_suffix=_a
PROP_EOF

# Create recovery.fstab
debug "Creating recovery.fstab..."
cat > $DEVICE_PATH/recovery.fstab << 'FSTAB_EOF'
# mount point    fstype    device                                        flags
/system          ext4      /dev/block/mapper/system                     flags=display="System";logical;slotselect
/vendor          ext4      /dev/block/mapper/vendor                     flags=display="Vendor";logical;slotselect
/product         ext4      /dev/block/mapper/product                    flags=display="Product";logical;slotselect
/system_ext      ext4      /dev/block/mapper/system_ext                 flags=display="System_ext";logical;slotselect
/boot            emmc      /dev/block/by-name/boot                      flags=display="Boot";backup=1;flashimg=1;slotselect
/data            f2fs      /dev/block/by-name/userdata                  flags=fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized
/metadata        ext4      /dev/block/by-name/metadata                  flags=display="Metadata"
/persist         ext4      /dev/block/by-name/persist                   flags=display="Persist"
/misc            emmc      /dev/block/by-name/misc                      flags=display="Misc"
/super           emmc      /dev/block/by-name/super                     flags=display="Super";backup=1

# Removable storage
/external_sd     auto      /dev/block/mmcblk1p1                         flags=display="MicroSD";storage;wipeingui;removable
/usb_otg         auto      /dev/block/sda1                              flags=display="USB Storage";storage;wipeingui;removable
FSTAB_EOF

# Create twrp.flags
debug "Creating twrp.flags..."
cat > $DEVICE_PATH/twrp.flags << 'FLAGS_EOF'
# Boot partitions
/boot_a          emmc      /dev/block/by-name/boot_a                    flags=backup=1;flashimg=1
/boot_b          emmc      /dev/block/by-name/boot_b                    flags=backup=1;flashimg=1

# System image
/system_image    emmc      /dev/block/mapper/system                     flags=backup=1;flashimg=1
/vendor_image    emmc      /dev/block/mapper/vendor                     flags=backup=1;flashimg=1
FLAGS_EOF

# Create vendorsetup.sh
debug "Creating vendorsetup.sh..."
cat > $DEVICE_PATH/vendorsetup.sh << 'VENDOR_EOF'
# Device specific exports
export TW_CUSTOM_TOUCH_PATH="/dev/input/event2"
export TW_MAX_BRIGHTNESS=2047
export TW_DEFAULT_BRIGHTNESS=1200
export TW_SCREEN_BLANK_ON_BOOT=false
export TW_NO_SCREEN_BLANK=true

echo "========================================"
echo "TWRP configuration loaded"
echo "Device: X6512 (MTK A/B)"
echo "Branch: twrp-12"
echo "Target: boot.img"
echo "========================================"
VENDOR_EOF

chmod +x $DEVICE_PATH/vendorsetup.sh

# Create empty modules files
debug "Creating empty module files..."
touch $DEVICE_PATH/modules.load.boot
touch $DEVICE_PATH/modules.load.recovery

# Setup build environment
debug "Setting up build environment..."
source build/envsetup.sh

# Basic exports only - no problematic ones
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL=C

# Load device configuration
source $DEVICE_PATH/vendorsetup.sh

# Build configuration
debug "Setting up build configuration..."
lunch twrp_${DEVICE_CODENAME}-eng || {
    error "Failed to setup build configuration"
    exit 1
}

# Clean build
debug "Cleaning previous builds..."
make clean

# Build boot image
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

debug "Checking for output files..."
if [ -d "$OUTPUT_DIR" ]; then
    # List all potential outputs
    for file in boot.img recovery.img ramdisk-recovery.img; do
        if [ -f "$OUTPUT_DIR/$file" ]; then
            OUTPUT_FOUND="$OUTPUT_DIR/$file"
            success "Found: $OUTPUT_FOUND"
            break
        fi
    done
fi

# Final output handling
if [ -n "$OUTPUT_FOUND" ]; then
    success "Build completed successfully!"
    echo "Output: $OUTPUT_FOUND"
    echo "Size: $(du -h "$OUTPUT_FOUND" | cut -f1)"
    
    # Create output directory
    mkdir -p /tmp/cirrus-ci-build/output
    OUTPUT_NAME="twrp-${DEVICE_CODENAME}-$(date +%Y%m%d-%H%M%S).img"
    cp "$OUTPUT_FOUND" "/tmp/cirrus-ci-build/output/$OUTPUT_NAME"
    cp build.log /tmp/cirrus-ci-build/output/
    
    # Create info file
    cat > /tmp/cirrus-ci-build/output/build_info.txt << EOF
TWRP Build Information
======================
Device: $DEVICE_CODENAME
Date: $(date)
Branch: $MANIFEST_BRANCH
Output: $OUTPUT_NAME
Size: $(du -h "/tmp/cirrus-ci-build/output/$OUTPUT_NAME" | cut -f1)

Flash Instructions:
==================
1. Reboot to bootloader: adb reboot bootloader
2. Flash to both slots:
   fastboot flash boot_a $OUTPUT_NAME
   fastboot flash boot_b $OUTPUT_NAME
3. Erase misc: fastboot erase misc
4. Set active slot: fastboot --set-active=a
5. Reboot to recovery: Hold Vol Up + Power

Features:
- ADB root enabled
- MediaTek touchscreen support
- A/B slot support
- Dynamic partitions
EOF
    
    echo ""
    success "Build artifacts:"
    ls -lah /tmp/cirrus-ci-build/output/
    echo ""
    echo "================================================"
    echo "         TWRP Build Complete!                   "
    echo "================================================"
else
    error "Build failed! No output image found"
    echo ""
    echo "Checking last 50 lines of build log for errors:"
    echo "================================================"
    grep -i "error\|failed\|failure" build.log | tail -50 || echo "No specific errors found"
    
    mkdir -p /tmp/cirrus-ci-build/output
    cp build.log /tmp/cirrus-ci-build/output/build_failed.log
    
    exit 1
fi
