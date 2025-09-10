#!/bin/bash
set -e
set -x

# Enable debug
DEBUG=1

# Arguments
DEVICE_TREE=$1
DEVICE_BRANCH=$2
DEVICE_CODENAME=$3
MANIFEST_BRANCH=$4
TARGET_RECOVERY_IMAGE=$5

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "================================================"
echo "     OrangeFox Recovery Builder for $DEVICE_CODENAME       "
echo "================================================"

# Debug function
debug_log() {
    if [ "$DEBUG" -eq 1 ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# System info
debug_log "System information:"
debug_log "OS: $(cat /etc/os-release | grep PRETTY_NAME)"
debug_log "Kernel: $(uname -r)"
debug_log "Architecture: $(uname -m)"
debug_log "Available memory: $(free -h | grep Mem | awk '{print $2}')"
debug_log "Available disk space: $(df -h / | tail -1 | awk '{print $4}')"

# Check arguments
debug_log "Checking arguments..."
if [ -z "$DEVICE_TREE" ] || [ -z "$DEVICE_BRANCH" ] || [ -z "$DEVICE_CODENAME" ]; then
    echo "Usage: $0 <device_tree_url> <device_branch> <device_codename> <manifest_branch> <target_recovery_image>"
    exit 1
fi

# Working directory
WORK_DIR="/tmp/cirrus-ci-build/orangefox"
mkdir -p $WORK_DIR
cd $WORK_DIR
debug_log "Working directory: $(pwd)"

# Git config
debug_log "Setting up git configuration..."
git config --global user.name "manusia"
git config --global user.email "ndktau@gmail.com"
git config --global url.https://gitlab.com/.insteadOf git@gitlab.com:
git config --global url.https://github.com/.insteadOf git@github.com:
git config --global url.https://.insteadOf git://
git config --global http.sslVerify false

# Check if repo is installed
if ! command -v repo &> /dev/null; then
    echo "--- Installing repo tool... ---"
    curl https://storage.googleapis.com/git-repo-downloads/repo > /usr/local/bin/repo
    chmod a+x /usr/local/bin/repo
fi

echo "--- Starting sync process... ---"

# Check if already synced
if [ -f "build/envsetup.sh" ] || [ -f "build/make/envsetup.sh" ]; then
    echo "--- Source already synced, skipping... ---"
else
    echo "--- Using TWRP 12.1 minimal manifest... ---"
    rm -rf .repo
    repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-12.1 --git-lfs --no-repo-verify
    
    echo "--- Starting repo sync... ---"
    repo sync -c --force-sync --no-tags --no-clone-bundle -j4 --optimized-fetch --prune
    
    # Clone OrangeFox vendor
    if [ ! -d "vendor/recovery" ]; then
        echo "--- Cloning OrangeFox vendor... ---"
        git clone https://gitlab.com/OrangeFox/vendor/recovery.git -b fox_12.1 vendor/recovery --depth=1
    fi
fi

cd $WORK_DIR

# Clone device tree
echo "--- Clone device tree... ---"
debug_log "Cloning device tree from: $DEVICE_TREE"
DEVICE_PATH="device/infinix/$DEVICE_CODENAME"

if [ -d "$DEVICE_PATH" ]; then
    echo "Device tree already exists, removing..."
    rm -rf $DEVICE_PATH
fi

git clone $DEVICE_TREE -b $DEVICE_BRANCH $DEVICE_PATH

if [ ! -d "$DEVICE_PATH" ]; then
    echo "Error: Failed to clone device tree"
    exit 1
fi

debug_log "Device tree contents:"
ls -la $DEVICE_PATH

# Fix device tree makefile names
echo "--- Fixing device tree makefiles... ---"
cd $DEVICE_PATH

# Check and create necessary makefiles
if [ ! -f "twrp_${DEVICE_CODENAME}.mk" ] && [ -f "omni_${DEVICE_CODENAME}.mk" ]; then
    debug_log "Creating twrp_${DEVICE_CODENAME}.mk from omni_${DEVICE_CODENAME}.mk"
    cp "omni_${DEVICE_CODENAME}.mk" "twrp_${DEVICE_CODENAME}.mk"
    sed -i "s/omni_/twrp_/g" "twrp_${DEVICE_CODENAME}.mk"
    sed -i "s/vendor\/omni/vendor\/twrp/g" "twrp_${DEVICE_CODENAME}.mk"
fi

# Update AndroidProducts.mk
if [ -f "AndroidProducts.mk" ]; then
    debug_log "Updating AndroidProducts.mk..."
    cat > AndroidProducts.mk << EOF
PRODUCT_MAKEFILES := \\
    \$(LOCAL_DIR)/twrp_${DEVICE_CODENAME}.mk

COMMON_LUNCH_CHOICES := \\
    twrp_${DEVICE_CODENAME}-user \\
    twrp_${DEVICE_CODENAME}-userdebug \\
    twrp_${DEVICE_CODENAME}-eng
EOF
fi

cd $WORK_DIR

# Apply touchscreen fixes
echo "--- Applying touchscreen fixes... ---"
debug_log "Fixing touchscreen driver: omnivision_tcm_spi (spi2.0)"

mkdir -p $DEVICE_PATH/recovery/root/sbin
mkdir -p $DEVICE_PATH/recovery/root/vendor/lib/modules

# Create touchscreen fix script
cat > $DEVICE_PATH/recovery/root/sbin/fix_touch.sh << 'TOUCH_EOF'
#!/sbin/sh
# Touchscreen fix for omnivision_tcm_spi

echo "Fixing touchscreen..."

# Load module if exists
if [ -f /vendor/lib/modules/omnivision_tcm_spi.ko ]; then
    insmod /vendor/lib/modules/omnivision_tcm_spi.ko
fi

# Enable touchscreen
if [ -d /sys/bus/spi/devices/spi2.0 ]; then
    echo 1 > /sys/bus/spi/devices/spi2.0/input/input0/enabled 2>/dev/null
fi

# Enable ADB
setprop persist.sys.usb.config adb
setprop persist.service.adb.enable 1
setprop persist.service.debuggable 1
setprop ro.adb.secure 0
start adbd

exit 0
TOUCH_EOF

chmod +x $DEVICE_PATH/recovery/root/sbin/fix_touch.sh

# Create init.recovery.rc addition
cat > $DEVICE_PATH/recovery/root/init.recovery.${DEVICE_CODENAME}.rc << 'INIT_EOF'
on init
    # Enable ADB
    setprop sys.usb.config adb
    setprop persist.sys.usb.config adb
    setprop persist.service.adb.enable 1
    setprop persist.service.debuggable 1
    setprop ro.adb.secure 0
    
on boot
    # Fix touchscreen
    exec u:r:recovery:s0 -- /sbin/fix_touch.sh
    
    # Start ADB
    start adbd

on property:ro.debuggable=0
    setprop ro.debuggable 1
INIT_EOF

# Update vendorsetup.sh with OrangeFox variables
echo "--- Setting up OrangeFox build variables... ---"
cat > $DEVICE_PATH/vendorsetup.sh << 'VENDOR_EOF'
# OrangeFox Configuration
export FOX_RECOVERY_SYSTEM_PARTITION="/dev/block/mapper/system"
export FOX_RECOVERY_VENDOR_PARTITION="/dev/block/mapper/vendor"
export FOX_USE_BASH_SHELL=1
export FOX_ASH_IS_BASH=1
export FOX_USE_TAR_BINARY=1
export FOX_USE_SED_BINARY=1
export FOX_USE_XZ_UTILS=1
export FOX_USE_NANO_EDITOR=1
export OF_ENABLE_LPTOOLS=1
export OF_NO_TREBLE_COMPATIBILITY_CHECK=1

# A/B device
export FOX_AB_DEVICE=1
export FOX_VIRTUAL_AB_DEVICE=1
export FOX_RECOVERY_BOOT_PARTITION="/dev/block/by-name/boot"

# Dynamic partitions
export OF_DYNAMIC_PARTITIONS=1

# UI
export OF_ALLOW_DISABLE_NAVBAR=0
export OF_STATUS_INDENT_LEFT=48
export OF_STATUS_INDENT_RIGHT=48
export OF_HIDE_NOTCH=1
export OF_CLOCK_POS=1

# Enable touch alternatives
export TW_USE_MOUSE_INPUT=1
export TW_ENABLE_VIRTUAL_MOUSE=1
export TW_HAS_USB_STORAGE=1

# Force enable ADB
export OF_FORCE_ENABLE_ADB=1
export OF_SKIP_ADB_SECURE=1

# Security
export PLATFORM_SECURITY_PATCH="2099-12-31"
export TW_DEFAULT_LANGUAGE="en"

# Debug
export OF_DEBUG_MODE=1
export TW_INCLUDE_RESETPROP=true
export TW_INCLUDE_REPACKTOOLS=true
export TW_INCLUDE_LIBRESETPROP=true

# OrangeFox specific
export OF_USE_GREEN_LED=0
export FOX_DELETE_AROMAFM=1
export FOX_ENABLE_APP_MANAGER=1
export OF_USE_HEXDUMP=1
export OF_FBE_METADATA_MOUNT_IGNORE=1
export OF_PATCH_AVB20=1
export OF_DONT_PATCH_ENCRYPTED_DEVICE=1
export FOX_RECOVERY_INSTALL_PARTITION="boot"
export FOX_REPLACE_BOOTIMAGE_DATE=1
export FOX_BUGGED_AOSP_ARB_WORKAROUND="1616300800"

# Build info
export OF_MAINTAINER="manusia"
export FOX_BUILD_TYPE="Unofficial"
export FOX_VERSION="R11.1"

# OTA
export OF_FIX_OTA_UPDATE_MANUAL_FLASH_ERROR=1
export OF_DISABLE_MIUI_OTA_BY_DEFAULT=1
export OF_NO_MIUI_OTA_VENDOR_BACKUP=1
export OF_NO_SAMSUNG_SPECIAL=1
export OF_SKIP_FBE_DECRYPTION=1

echo "OrangeFox build variables loaded for $DEVICE_CODENAME"
VENDOR_EOF

# Update BoardConfig.mk
echo "--- Updating BoardConfig for touchscreen support... ---"
if [ -f "$DEVICE_PATH/BoardConfig.mk" ]; then
    cat >> $DEVICE_PATH/BoardConfig.mk << 'BOARD_EOF'

# Touchscreen Configuration
RECOVERY_TOUCHSCREEN_SWAP_XY := false
RECOVERY_TOUCHSCREEN_FLIP_X := false
RECOVERY_TOUCHSCREEN_FLIP_Y := false
TW_INPUT_BLACKLIST := "hbtp_vm"

# Enable Navigation
BOARD_HAS_NO_SELECT_BUTTON := true
TW_HAS_USB_STORAGE := true
TW_NO_USB_STORAGE := false

# ADB
TW_EXCLUDE_DEFAULT_USB_INIT := true
TARGET_USE_CUSTOM_LUN_FILE_PATH := /config/usb_gadget/g1/functions/mass_storage.0/lun.%d/file

# Debug
TW_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true
BOARD_EOF
fi

# Build recovery
echo "--- Setting up build environment... ---"
cd $WORK_DIR

if [ -f "build/envsetup.sh" ]; then
    debug_log "Sourcing build/envsetup.sh..."
    source build/envsetup.sh
elif [ -f "build/make/envsetup.sh" ]; then
    debug_log "Sourcing build/make/envsetup.sh..."
    source build/make/envsetup.sh
else
    echo "Error: envsetup.sh not found!"
    exit 1
fi

# Set environment
export DISABLE_ROOMSERVICE=1

echo "--- Starting build... ---"
echo "Lunch target: twrp_${DEVICE_CODENAME}-eng"

# Try lunch
lunch twrp_${DEVICE_CODENAME}-eng || {
    echo "twrp lunch failed, trying omni..."
    lunch omni_${DEVICE_CODENAME}-eng
}

# Clean build
echo "--- Cleaning old builds... ---"
make clean

# Build recovery
echo "--- Building recovery (this will take time)... ---"
if [ "$TARGET_RECOVERY_IMAGE" = "boot" ]; then
    echo "Building boot image..."
    mka bootimage -j$(nproc --all) 2>&1 | tee build.log
else
    echo "Building recovery image..."
    mka recoveryimage -j$(nproc --all) 2>&1 | tee build.log
fi

# Check output
echo "--- Checking build output... ---"
OUTPUT_DIR="out/target/product/$DEVICE_CODENAME"

if [ -f "$OUTPUT_DIR/boot.img" ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Boot image built successfully!"
    echo "Location: $OUTPUT_DIR/boot.img"
    
    # Copy to output
    mkdir -p /tmp/cirrus-ci-build/output
    cp $OUTPUT_DIR/boot.img /tmp/cirrus-ci-build/output/OrangeFox-${FOX_VERSION:-R11.1}-${DEVICE_CODENAME}-$(date +%Y%m%d).img
    
    echo "Output files:"
    ls -lah /tmp/cirrus-ci-build/output/
elif [ -f "$OUTPUT_DIR/recovery.img" ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Recovery image built successfully!"
    echo "Location: $OUTPUT_DIR/recovery.img"
    
    # Copy to output
    mkdir -p /tmp/cirrus-ci-build/output
    cp $OUTPUT_DIR/recovery.img /tmp/cirrus-ci-build/output/OrangeFox-${FOX_VERSION:-R11.1}-${DEVICE_CODENAME}-$(date +%Y%m%d).img
    
    echo "Output files:"
    ls -lah /tmp/cirrus-ci-build/output/
else
    echo -e "${RED}[ERROR]${NC} Build failed! Check build.log for details"
    echo "Last 50 lines of build.log:"
    tail -50 build.log
    exit 1
fi

echo "================================================"
echo "     Build Complete!                            "
echo "================================================"
