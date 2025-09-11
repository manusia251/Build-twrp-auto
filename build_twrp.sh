#!/bin/bash
set -e

# Arguments
DEVICE_TREE=$1
DEVICE_BRANCH=$2
DEVICE_CODENAME=$3
MANIFEST_BRANCH=${4:-"twrp-11"}
TARGET_RECOVERY_IMAGE=${5:-"vendor_boot"}

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
echo "     TWRP Vendor Boot Builder for $DEVICE_CODENAME"
echo "     Target: vendor_boot.img"
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

# Update BoardConfig.mk - but don't duplicate if already exists
if ! grep -q "BOARD_BOOT_HEADER_VERSION := 4" $DEVICE_PATH/BoardConfig.mk 2>/dev/null; then
    debug "Adding vendor_boot configuration to BoardConfig.mk..."
    cat >> $DEVICE_PATH/BoardConfig.mk << 'EOF'

# Vendor Boot Configuration
BOARD_BOOT_HEADER_VERSION := 4
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_INCLUDE_DTB_IN_BOOTIMG := false
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := $(strip $(shell cat $(DEVICE_PATH)/modules.load.recovery))

# MediaTek TPD Touchscreen (built-in driver, no module needed)
TW_CUSTOM_TOUCH_PATH := "/dev/input/event2"
TW_LOAD_VENDOR_MODULES := ""
TW_INPUT_BLACKLIST := "hbtp_vm"
TW_SCREEN_BLANK_ON_BOOT := false
TW_NO_SCREEN_BLANK := true

# Recovery as vendor_boot
BOARD_USES_RECOVERY_AS_VENDOR_BOOT := true
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true

# Additional flags for better touch support
TW_THEME := portrait_hdpi
TW_DEVICE_VERSION := "MTK-TPD"
EOF
fi

# Create init.recovery.X6512.rc for MediaTek TPD
debug "Creating init.recovery.${DEVICE_CODENAME}.rc for MediaTek TPD (built-in)..."
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
INIT_EOF

# Create default.prop for ADB
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
PROP_EOF

# Create recovery.fstab with vendor_boot partition
if [ ! -f "$DEVICE_PATH/recovery.fstab" ]; then
    debug "Creating recovery.fstab with vendor_boot support..."
    cat > $DEVICE_PATH/recovery.fstab << 'FSTAB_EOF'
# mount point    fstype    device                                        flags
/system          ext4      /dev/block/mapper/system                     flags=display="System";logical
/vendor          ext4      /dev/block/mapper/vendor                     flags=display="Vendor";logical
/product         ext4      /dev/block/mapper/product                    flags=display="Product";logical
/system_ext      ext4      /dev/block/mapper/system_ext                 flags=display="System_ext";logical
/boot            emmc      /dev/block/by-name/boot                      flags=display="Boot";backup=1;flashimg=1
/recovery        emmc      /dev/block/by-name/recovery                  flags=display="Recovery";backup=1;flashimg=1
/vendor_boot     emmc      /dev/block/by-name/vendor_boot               flags=display="Vendor Boot";backup=1;flashimg=1
/data            f2fs      /dev/block/by-name/userdata                  flags=fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized
/cache           ext4      /dev/block/by-name/cache                     flags=display="Cache"
/metadata        ext4      /dev/block/by-name/metadata                  flags=display="Metadata"
/persist         ext4      /dev/block/by-name/persist                   flags=display="Persist"
/misc            emmc      /dev/block/by-name/misc                      flags=display="Misc"

# Removable storage
/external_sd     auto      /dev/block/mmcblk1p1                         flags=display="MicroSD";storage;wipeingui;removable
/usb_otg         auto      /dev/block/sda1                              flags=display="USB Storage";storage;wipeingui;removable
FSTAB_EOF
fi

# Create vendorsetup.sh
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

# Force vendor_boot build
export BOARD_USES_RECOVERY_AS_VENDOR_BOOT=true
export BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT=true

# Debug flags
export TARGET_USES_LOGD=true
export TWRP_INCLUDE_LOGCAT=true
export TW_CRYPTO_SYSTEM_VOLD_DEBUG=true

echo "========================================"
echo "TWRP vendor_boot variables loaded"
echo "Device: X6512"
echo "Touch: MediaTek TPD (built-in)"
echo "Input: /dev/input/event2"
echo "Resolution: 720x1612"
echo "Multi-touch: 5 slots"
echo "========================================"
VENDOR_EOF

chmod +x $DEVICE_PATH/vendorsetup.sh

# Create empty module files (since mtk-tpd is built-in)
debug "Creating empty module files (mtk-tpd is built-in)..."
echo "# MediaTek TPD is built-in to kernel, no modules needed" > $DEVICE_PATH/modules.load.vendor_boot
echo "# MediaTek TPD is built-in to kernel, no modules needed" > $DEVICE_PATH/modules.load.recovery

# Setup build environment
debug "Setting up build environment..."
source build/envsetup.sh

# Export build variables
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL=C
export TW_EXCLUDE_DEFAULT_USB_INIT=true
export TW_USE_TOOLBOX=true
export BUILD_BROKEN_DUP_RULES=true
export BUILD_BROKEN_MISSING_REQUIRED_MODULES=true
export BOARD_VNDK_VERSION=current
export PRODUCT_FULL_TREBLE_OVERRIDE=false

# Load device configuration
source $DEVICE_PATH/vendorsetup.sh

# Build configuration
debug "Setting up build configuration..."
lunch twrp_${DEVICE_CODENAME}-eng || {
    error "Failed to setup build configuration"
    exit 1
}

# Clean previous builds
debug "Cleaning previous builds..."
make clean

# Remove problematic makefiles
debug "Removing problematic makefiles..."
find . -name "Android.mk" -path "*/vts/*" -exec rm -f {} \; 2>/dev/null || true

# Check available build targets
debug "Checking available build targets..."
make help 2>&1 | grep -E "boot|recovery|vendor" || true

# First, try building recovery ramdisk
debug "Building recovery ramdisk..."
make recoveryimage-nodeps -j$(nproc --all) 2>&1 | tee build.log || {
    echo "Recovery ramdisk build failed, trying alternative..."
}

# If no vendor_boot yet, try bootimage
if [ ! -f "out/target/product/$DEVICE_CODENAME/vendor_boot.img" ]; then
    debug "Trying bootimage build..."
    make bootimage -j$(nproc --all) 2>&1 | tee -a build.log || {
        echo "Boot image build also failed..."
    }
fi

# Check for any ramdisk or boot images
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
    "$OUTPUT_DIR/vendor_boot.img"
    "$OUTPUT_DIR/vendor-boot.img"
    "$OUTPUT_DIR/boot.img"
    "$OUTPUT_DIR/recovery.img"
    "$OUTPUT_DIR/ramdisk.img"
    "$OUTPUT_DIR/ramdisk-recovery.img"
    "$OUTPUT_DIR/ramdisk-recovery.cpio"
    "$OUTPUT_DIR/ramdisk-recovery.cpio.gz"
    "$OUTPUT_DIR/vendor_ramdisk.img"
    "$OUTPUT_DIR/vendor_ramdisk.cpio"
    "$OUTPUT_DIR/vendor_ramdisk.cpio.gz"
    "$OUTPUT_DIR/obj/PACKAGING/target_files_intermediates/*/IMAGES/boot.img"
    "$OUTPUT_DIR/obj/PACKAGING/target_files_intermediates/*/IMAGES/vendor_boot.img"
)

for OUTPUT in "${POSSIBLE_OUTPUTS[@]}"; do
    if [ -f "$OUTPUT" ] || ls $OUTPUT 2>/dev/null; then
        OUTPUT_FOUND=$(ls $OUTPUT 2>/dev/null | head -1)
        success "Found output: $OUTPUT_FOUND"
        break
    fi
done

# If we found boot.img but need vendor_boot.img, try to convert
if [ -n "$OUTPUT_FOUND" ] && [[ "$OUTPUT_FOUND" == *"boot.img"* ]] && [ "$TARGET_RECOVERY_IMAGE" == "vendor_boot" ]; then
    debug "Found boot.img, attempting to extract and create vendor_boot.img..."
    
    # Create temp directory
    TEMP_DIR="$OUTPUT_DIR/boot_extract"
    mkdir -p $TEMP_DIR
    
    # Try to unpack boot.img
    if command -v unpackbootimg &> /dev/null; then
        unpackbootimg -i "$OUTPUT_FOUND" -o "$TEMP_DIR" || {
            python3 system/tools/mkbootimg/unpack_bootimg.py --boot_img "$OUTPUT_FOUND" --out "$TEMP_DIR" || true
        }
    fi
    
    # Look for ramdisk
    RAMDISK=""
    if [ -f "$TEMP_DIR/ramdisk" ]; then
        RAMDISK="$TEMP_DIR/ramdisk"
    elif [ -f "$TEMP_DIR/boot.img-ramdisk" ]; then
        RAMDISK="$TEMP_DIR/boot.img-ramdisk"
    elif [ -f "$TEMP_DIR/boot.img-ramdisk.gz" ]; then
        RAMDISK="$TEMP_DIR/boot.img-ramdisk.gz"
    fi
    
    if [ -n "$RAMDISK" ] && [ -f "$DEVICE_PATH/prebuilt/dtb.img" ]; then
        debug "Creating vendor_boot.img from boot.img components..."
        
        # If ramdisk is compressed, use as is
        if [[ "$RAMDISK" == *.gz ]]; then
            cp "$RAMDISK" "$OUTPUT_DIR/vendor_ramdisk.img"
        else
            # Compress ramdisk if not already
            gzip -c "$RAMDISK" > "$OUTPUT_DIR/vendor_ramdisk.img"
        fi
        
        # Create vendor_boot.img
        python3 system/tools/mkbootimg/mkbootimg.py \
            --header_version 4 \
            --vendor_ramdisk "$OUTPUT_DIR/vendor_ramdisk.img" \
            --dtb "$DEVICE_PATH/prebuilt/dtb.img" \
            --vendor_cmdline "bootopt=64S3,32S1,32S1 buildvariant=user" \
            --base 0x40000000 \
            --pagesize 2048 \
            --vendor_ramdisk_offset 0x11b00000 \
            --tags_offset 0x07880000 \
            --dtb_offset 0x07880000 \
            --vendor_boot "$OUTPUT_DIR/vendor_boot.img" 2>&1 || {
                error "Failed to create vendor_boot.img"
            }
        
        if [ -f "$OUTPUT_DIR/vendor_boot.img" ]; then
            OUTPUT_FOUND="$OUTPUT_DIR/vendor_boot.img"
            success "Successfully converted boot.img to vendor_boot.img"
        fi
    fi
fi

# Final output handling
if [ -n "$OUTPUT_FOUND" ]; then
    success "Build completed successfully!"
    echo "Output: $OUTPUT_FOUND"
    echo "Size: $(du -h "$OUTPUT_FOUND" | cut -f1)"
    
    # Create output directory
    mkdir -p /tmp/cirrus-ci-build/output
    
    # Determine output name based on what we found
    if [[ "$OUTPUT_FOUND" == *"vendor_boot"* ]]; then
        OUTPUT_NAME="twrp-vendor_boot-${DEVICE_CODENAME}-$(date +%Y%m%d-%H%M%S).img"
    else
        OUTPUT_NAME="twrp-$(basename "$OUTPUT_FOUND" .img)-${DEVICE_CODENAME}-$(date +%Y%m%d-%H%M%S).img"
    fi
    
    cp "$OUTPUT_FOUND" "/tmp/cirrus-ci-build/output/$OUTPUT_NAME"
    
    # Copy build log
    cp build.log /tmp/cirrus-ci-build/output/
    
    # If we have a ramdisk, also save it
    if [ -f "$OUTPUT_DIR/ramdisk-recovery.img" ] || [ -f "$OUTPUT_DIR/vendor_ramdisk.img" ]; then
        cp "$OUTPUT_DIR/ramdisk-recovery.img" /tmp/cirrus-ci-build/output/ramdisk-recovery.img 2>/dev/null || true
        cp "$OUTPUT_DIR/vendor_ramdisk.img" /tmp/cirrus-ci-build/output/vendor_ramdisk.img 2>/dev/null || true
    fi
    
    # Create detailed info file
    cat > /tmp/cirrus-ci-build/output/build_info.txt << EOF
TWRP Build Information
======================
Device: $DEVICE_CODENAME
Date: $(date)
Source: $DEVICE_TREE
Branch: $DEVICE_BRANCH
Output: $OUTPUT_NAME
Size: $(du -h "/tmp/cirrus-ci-build/output/$OUTPUT_NAME" | cut -f1)
Type: $(basename "$OUTPUT_FOUND" .img)

Features:
- ADB enabled by default (root access)
- MediaTek TPD touchscreen support (built-in driver)
- Built for vendor_boot (if supported by device)

Touch Device Information:
========================
Device Name: mtk-tpd
Input Path: /dev/input/event2
Sysfs Path: /sys/devices/virtual/input/input2
Resolution: 720x1612
Multi-touch: 5 slots (0-4)
Driver Type: Built-in (no kernel module needed)

Touch Events Supported:
- BTN_TOUCH
- ABS_X (0-719)
- ABS_Y (0-1611)
- ABS_MT_POSITION_X/Y
- ABS_MT_TRACKING_ID
- ABS_MT_SLOT (5 slots)

MediaTek TPD Debug Paths:
- /sys/devices/virtual/misc/tpd_em_log
- /sys/bus/platform/drivers/mtk-tpd
- /sys/module/tpd_debug
- /sys/module/tpd_setting
- /sys/module/tpd_misc

Notes:
- Touch driver is integrated into kernel (no .ko module)
- LCD state notifications handled via tpd_fb_notifier_callback
- Touch resume handled via GTP touch_resume_workqueue_callback

Build Type: $([[ "$OUTPUT_FOUND" == *"vendor_boot"* ]] && echo "Vendor Boot Image" || echo "Recovery/Boot Image")
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
    echo "✓ Multi-touch support (5 slots)"
    echo "✓ Resolution: 720x1612"
    echo "✓ Output: $(basename "$OUTPUT_FOUND")"
    echo "================================================"
else
    error "Build failed! No output image found"
    echo ""
    echo "Checking last 50 lines of build log for errors:"
    echo "================================================"
    grep -i "error\|failed\|failure" build.log | tail -50 || echo "No specific errors found"
    
    echo ""
    echo "All files in out directory:"
    if [ -d "out/" ]; then
        find out/ -type f -name "*.img" -o -name "*.cpio" -o -name "ramdisk*" 2>/dev/null | head -20 || echo "No relevant files found"
    fi
    
    echo ""
    echo "Checking if out/target/product directory exists:"
    ls -la out/target/product/ 2>/dev/null || echo "Product directory not found"
    
    echo ""
    echo "Debug information saved to build.log"
    
    # Still save build log even on failure
    mkdir -p /tmp/cirrus-ci-build/output
    cp build.log /tmp/cirrus-ci-build/output/build_failed.log
    
    # Save any partial outputs
    if [ -d "$OUTPUT_DIR" ]; then
        find $OUTPUT_DIR -type f -name "*.img" -o -name "*.cpio" -o -name "ramdisk*" 2>/dev/null | while read file; do
            cp "$file" /tmp/cirrus-ci-build/output/ 2>/dev/null || true
        done
    fi
    
    exit 1
fi
