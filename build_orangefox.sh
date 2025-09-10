#!/bin/bash

# OrangeFox Recovery Builder Script for Infinix X6512
# With touchscreen fix and full OrangeFox features support

set -e
set -x

# Enable debug mode
DEBUG=1

# Arguments
DEVICE_TREE=$1
DEVICE_BRANCH=$2
DEVICE_CODENAME=$3
MANIFEST_BRANCH=$4
TARGET_RECOVERY_IMAGE=$5

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Debug function
debug_log() {
    if [ "$DEBUG" -eq 1 ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# Error handling function
error_exit() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Success message function
success_msg() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Warning message function
warning_msg() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo "================================================"
echo "     OrangeFox Recovery Builder for X6512       "
echo "================================================"

# Check arguments
debug_log "Checking arguments..."
if [ -z "$DEVICE_TREE" ] || [ -z "$DEVICE_BRANCH" ] || [ -z "$DEVICE_CODENAME" ]; then
    error_exit "Missing required arguments!"
fi

# Setup work directory
WORK_DIR="/tmp/cirrus-ci-build/orangefox"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"
debug_log "Working directory: $(pwd)"

# Git configuration
debug_log "Setting up git configuration..."
git config --global user.name "manusia"
git config --global user.email "ndktau@gmail.com"

echo "--- Clone OrangeFox sync script... ---"
debug_log "Cloning from: https://gitlab.com/OrangeFox/sync.git"

if [ -d sync_dir ]; then
    debug_log "sync_dir already exists, removing..."
    rm -rf sync_dir
fi

git clone https://gitlab.com/OrangeFox/sync.git -b master sync_dir || error_exit "Failed to clone OrangeFox sync script"

if [ ! -d sync_dir ]; then
    error_exit "sync_dir not found after cloning!"
fi

cd sync_dir
debug_log "Contents of sync_dir:"
ls -la

echo "--- Syncing OrangeFox source code... ---"
SYNC_PATH=$(realpath ../)
debug_log "Sync path: $SYNC_PATH"

# Use fox_12.1 since fox_11.0 is no longer supported
if [ -f orangefox_sync.sh ]; then
    debug_log "Found orangefox_sync.sh, using fox_12.1 branch..."
    bash orangefox_sync.sh --branch 12.1 --path "$SYNC_PATH" || error_exit "Failed to sync OrangeFox source"
else
    error_exit "orangefox_sync.sh not found!"
fi

cd "$SYNC_PATH"
debug_log "Checking build system files..."

# Wait for sync to complete
sleep 5

# Check if build environment exists
if [ ! -f build/envsetup.sh ] && [ ! -f build/make/envsetup.sh ]; then
    warning_msg "Build environment not found, waiting for sync to complete..."
    sleep 10
    
    if [ ! -f build/envsetup.sh ] && [ ! -f build/make/envsetup.sh ]; then
        error_exit "Build environment still not found after waiting!"
    fi
fi

echo "--- Clone device tree... ---"
debug_log "Cloning device tree from: $DEVICE_TREE"

# Remove existing device tree if present
DEVICE_PATH="device/infinix/$DEVICE_CODENAME"
if [ -d "$DEVICE_PATH" ]; then
    debug_log "Removing existing device tree..."
    rm -rf "$DEVICE_PATH"
fi

# Clone device tree
git clone "$DEVICE_TREE" -b "$DEVICE_BRANCH" "$DEVICE_PATH" || error_exit "Failed to clone device tree"

# Apply touchscreen fixes
echo "--- Applying touchscreen fixes... ---"
debug_log "Fixing touchscreen driver: omnivision_tcm_spi (spi2.0)"

# Create touchscreen fix patch
cat > "$DEVICE_PATH/recovery/root/init.recovery.touchscreen.rc" << 'EOF'
on boot
    # Touchscreen fix for omnivision_tcm_spi
    write /sys/bus/spi/devices/spi2.0/accessible 1
    chmod 0666 /dev/spidev2.0
    chown system system /dev/spidev2.0
    
    # Load touchscreen module
    insmod /vendor/lib/modules/omnivision_tcm_spi.ko
    
    # Set touchscreen permissions
    chmod 0666 /dev/input/event*
    chown system input /dev/input/event*
    
    # Enable touchscreen debugging
    write /sys/module/omnivision_tcm_spi/parameters/debug_level 1
EOF

# Update init.rc to include touchscreen fix
if [ -f "$DEVICE_PATH/recovery/root/init.rc" ]; then
    echo "import /init.recovery.touchscreen.rc" >> "$DEVICE_PATH/recovery/root/init.rc"
fi

# Create custom vendorsetup.sh for OrangeFox variables
echo "--- Setting up OrangeFox build variables... ---"
cat > "$DEVICE_PATH/vendorsetup.sh" << 'EOF'
# OrangeFox build vars
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

# A/B device configuration
export FOX_AB_DEVICE=1
export FOX_VIRTUAL_AB_DEVICE=1
export FOX_RECOVERY_BOOT_PARTITION="/dev/block/by-name/boot"

# Super partition support
export OF_DYNAMIC_PARTITIONS=1
export OF_NO_RELOAD_AFTER_DECRYPTION=1

# Touchscreen and navigation support
export OF_ALLOW_DISABLE_NAVBAR=0
export OF_SCREEN_H=2400
export OF_STATUS_H=100
export OF_STATUS_INDENT_LEFT=48
export OF_STATUS_INDENT_RIGHT=48
export OF_HIDE_NOTCH=1
export OF_CLOCK_POS=1

# Enable keyboard/mouse support for non-touch control
export TW_USE_MOUSE_INPUT=1
export TW_ENABLE_VIRTUAL_MOUSE=1

# Enable ADB by default for debugging
export OF_FORCE_ENABLE_ADB=1
export OF_SKIP_ADB_SECURE=1

# Additional debugging
export OF_DEBUG_MODE=1
export TW_INCLUDE_RESETPROP=true
export TW_INCLUDE_REPACKTOOLS=true

# UI customization
export OF_USE_GREEN_LED=0
export FOX_DELETE_AROMAFM=1
export FOX_ENABLE_APP_MANAGER=1
export OF_USE_HEXDUMP=1

# Decryption support
export OF_FBE_METADATA_MOUNT_IGNORE=1
export OF_PATCH_AVB20=1
export OF_DONT_PATCH_ENCRYPTED_DEVICE=1

# Build as boot.img instead of recovery.img
export FOX_RECOVERY_INSTALL_PARTITION="boot"
export FOX_REPLACE_BOOTIMAGE_DATE=1
export FOX_BUGGED_AOSP_ARB_WORKAROUND="1616300800" # Tue Mar 21 2021

# Device info
export OF_MAINTAINER="manusia"
export FOX_BUILD_TYPE="Unofficial"
export FOX_VERSION="R11.1"

# Fix common issues
export OF_FIX_OTA_UPDATE_MANUAL_FLASH_ERROR=1
export OF_DISABLE_MIUI_OTA_BY_DEFAULT=1
export OF_NO_MIUI_OTA_VENDOR_BACKUP=1
export OF_NO_SAMSUNG_SPECIAL=1

echo "OrangeFox build variables loaded for X6512"
EOF

# Create BoardConfig additions for touchscreen
echo "--- Updating BoardConfig for touchscreen support... ---"
cat >> "$DEVICE_PATH/BoardConfig.mk" << 'EOF'

# Touchscreen configuration
RECOVERY_TOUCHSCREEN_SWAP_XY := false
RECOVERY_TOUCHSCREEN_FLIP_X := false
RECOVERY_TOUCHSCREEN_FLIP_Y := false

# Enable touch driver debugging
BOARD_RECOVERY_TOUCHSCREEN_DEBUG := true

# SPI touchscreen support
TARGET_RECOVERY_DEVICE_MODULES += omnivision_tcm_spi
TW_LOAD_VENDOR_MODULES := "omnivision_tcm_spi.ko"

# Non-touch navigation support
TW_USE_KEY_CODE_WAKE_DEVICE := true
BOARD_HAS_NO_SELECT_BUTTON := true

# Enable virtual mouse for navigation without touch
TW_INPUT_BLACKLIST := ""
TW_EXCLUDE_DEFAULT_USB_INIT := false

# ADB configuration
BOARD_ALWAYS_INSECURE := true
EOF

# Setup build environment
echo "--- Setting up build environment... ---"
source build/envsetup.sh || source build/make/envsetup.sh || error_exit "Failed to source envsetup.sh"

# Add device to lunch menu
add_lunch_combo "twrp_${DEVICE_CODENAME}-eng" || warning_msg "Failed to add lunch combo"

# Select device
echo "--- Selecting device: ${DEVICE_CODENAME} ---"
lunch "twrp_${DEVICE_CODENAME}-eng" || lunch "omni_${DEVICE_CODENAME}-eng" || error_exit "Failed to lunch device"

# Clean previous builds
echo "--- Cleaning previous builds... ---"
make clean || warning_msg "Clean failed, continuing anyway..."

# Start building
echo "--- Starting OrangeFox build... ---"
debug_log "Building with TARGET_RECOVERY_IMAGE=$TARGET_RECOVERY_IMAGE"

# Set target to boot image
export TW_DEVICE_VERSION="1.0_manusia"
export TARGET_PREBUILT_KERNEL="$DEVICE_PATH/prebuilt/kernel"

# Build the recovery
if [ "$TARGET_RECOVERY_IMAGE" == "boot" ]; then
    debug_log "Building boot image..."
    mka bootimage -j$(nproc --all) 2>&1 | tee build.log || error_exit "Build failed!"
else
    debug_log "Building recovery image..."
    mka recoveryimage -j$(nproc --all) 2>&1 | tee build.log || error_exit "Build failed!"
fi

# Find and copy output files
echo "--- Collecting output files... ---"
OUT_DIR="out/target/product/$DEVICE_CODENAME"
OUTPUT_DIR="/tmp/cirrus-ci-build/output"
mkdir -p "$OUTPUT_DIR"

# Find the built image
if [ "$TARGET_RECOVERY_IMAGE" == "boot" ]; then
    if [ -f "$OUT_DIR/boot.img" ]; then
        cp "$OUT_DIR/boot.img" "$OUTPUT_DIR/OrangeFox-${DEVICE_CODENAME}-boot.img"
        success_msg "Boot image copied to output"
        
        # Create flashable zip
        debug_log "Creating flashable zip..."
        cd "$OUT_DIR"
        if [ -f "OrangeFox-*.zip" ]; then
            cp OrangeFox-*.zip "$OUTPUT_DIR/"
            success_msg "Flashable zip copied to output"
        fi
    else
        error_exit "boot.img not found!"
    fi
else
    if [ -f "$OUT_DIR/recovery.img" ]; then
        cp "$OUT_DIR/recovery.img" "$OUTPUT_DIR/OrangeFox-${DEVICE_CODENAME}-recovery.img"
        success_msg "Recovery image copied to output"
    else
        error_exit "recovery.img not found!"
    fi
fi

# Copy build log
cp build.log "$OUTPUT_DIR/" || warning_msg "Failed to copy build log"

# List output files
echo "--- Output files ---"
ls -lah "$OUTPUT_DIR"

# Create device info file
cat > "$OUTPUT_DIR/device_info.txt" << EOF
Device: Infinix X6512
Android Version: 11
Partition Type: A/B with Super partition
Recovery Type: Boot image (no recovery partition)
Touchscreen: omnivision_tcm_spi (spi2.0) - FIXED
OrangeFox Version: R11.1
Build Date: $(date)
Builder: manusia
Features:
- Full OrangeFox features enabled
- Touchscreen support fixed
- Non-touch navigation enabled (keyboard/mouse)
- ADB enabled by default
- Debug mode enabled
EOF

success_msg "Build completed successfully!"
echo "================================================"
echo "       OrangeFox Build Complete!                "
echo "================================================"
