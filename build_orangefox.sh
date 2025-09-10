#!/bin/bash

# OrangeFox Recovery Builder Script for Infinix X6512
# With touchscreen fix, theme fix, and full OrangeFox features support

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

# System info
debug_log "System information:"
debug_log "OS: $(lsb_release -d 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME)"
debug_log "Kernel: $(uname -r)"
debug_log "Architecture: $(uname -m)"
debug_log "Available memory: $(free -h | grep Mem | awk '{print $2}')"
debug_log "Available disk space: $(df -h / | tail -1 | awk '{print $4}')"

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
git config --global url."https://gitlab.com/".insteadOf git@gitlab.com:
git config --global url."https://github.com/".insteadOf git@github.com:
git config --global url."https://".insteadOf git://
git config --global http.sslVerify false

# Check if repo is available
if ! command -v repo &> /dev/null; then
    warning_msg "repo command not found, installing..."
    export REPO_URL='https://gerrit.googlesource.com/git-repo'
    curl -s $REPO_URL -o /usr/local/bin/repo
    chmod +x /usr/local/bin/repo
fi

echo "--- Starting sync process... ---"

# Check if build environment already exists
if [ -f build/envsetup.sh ] || [ -f build/make/envsetup.sh ]; then
    warning_msg "Build environment already exists, skipping sync..."
else
    echo "--- Using TWRP 12.1 minimal manifest... ---"
    rm -rf .repo
    repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-12.1 --git-lfs --no-repo-verify

    echo "--- Starting repo sync... ---"
    repo sync -c --force-sync --no-tags --no-clone-bundle -j4 --optimized-fetch --prune
fi

# Clone OrangeFox vendor if not present
if [ ! -d vendor/recovery ]; then
    echo "--- Cloning OrangeFox vendor... ---"
    git clone https://gitlab.com/OrangeFox/vendor/recovery.git -b fox_12.1 vendor/recovery --depth=1
fi

cd "$WORK_DIR"

# Clone device tree
echo "--- Clone device tree... ---"
debug_log "Cloning device tree from: $DEVICE_TREE"

DEVICE_PATH="device/infinix/$DEVICE_CODENAME"
if [ -d "$DEVICE_PATH" ]; then
    debug_log "Removing existing device tree..."
    rm -rf "$DEVICE_PATH"
fi

git clone "$DEVICE_TREE" -b "$DEVICE_BRANCH" "$DEVICE_PATH" || error_exit "Failed to clone device tree"

if [ ! -d "$DEVICE_PATH" ]; then
    error_exit "Device tree directory not found after cloning!"
fi

debug_log "Device tree contents:"
ls -la "$DEVICE_PATH"

# Fix device tree configuration (remove obsolete exports)
echo "--- Fixing device tree configuration... ---"
if [ -f "$DEVICE_PATH/BoardConfig.mk" ]; then
    debug_log "Fixing BoardConfig.mk..."
    sed -i 's/^export OF_USE_KEY_HANDLER/# OF_USE_KEY_HANDLER/' "$DEVICE_PATH/BoardConfig.mk"
    sed -i 's/^export TW_/# TW_/' "$DEVICE_PATH/BoardConfig.mk"
fi

# Add theme fix to BoardConfig.mk if not present
echo "--- Fixing theme configuration... ---"
if ! grep -q "TW_THEME" "$DEVICE_PATH/BoardConfig.mk"; then
    warning_msg "TW_THEME not set in BoardConfig.mk! Adding default for screen 1612x720 (portrait_hdpi)..."
    cat >> "$DEVICE_PATH/BoardConfig.mk" << 'EOF'

# Theme configuration for OrangeFox/TWRP (fixed for 1612x720 portrait screen)
TW_THEME := portrait_hdpi
TARGET_SCREEN_WIDTH := 720
TARGET_SCREEN_HEIGHT := 1612
EOF
    success_msg "Theme configuration added to BoardConfig.mk!"
else
    debug_log "TW_THEME already set in BoardConfig.mk, skipping..."
fi

# Apply touchscreen fixes
echo "--- Applying touchscreen fixes... ---"
debug_log "Fixing touchscreen driver: omnivision_tcm_spi (spi2.0)"

mkdir -p "$DEVICE_PATH/recovery/root/sbin"
mkdir -p "$DEVICE_PATH/recovery/root/vendor/lib/modules"

cat > "$DEVICE_PATH/recovery/root/init.recovery.touchscreen.rc" << 'EOF'
on early-init
    # Enable ADB debugging
    setprop ro.adb.secure 0
    setprop ro.debuggable 1
    setprop persist.sys.usb.config adb
    setprop service.adb.root 1

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
    
    # Start ADB daemon
    start adbd

on property:ro.debuggable=1
    start adbd
    
service adbd /sbin/adbd --root_seclabel=u:r:su:s0
    disabled
    socket adbd stream 660 system system
    seclabel u:r:adbd:s0
EOF

cat > "$DEVICE_PATH/recovery/root/sbin/fix_touch.sh" << 'EOF'
#!/sbin/sh
# Touchscreen fix script for omnivision_tcm_spi

echo "Starting touchscreen fix..." >> /tmp/recovery.log

# Wait for device to settle
sleep 2

# Check if module exists
if [ -f /vendor/lib/modules/omnivision_tcm_spi.ko ]; then
    # Load touchscreen module if not loaded
    if ! lsmod | grep -q omnivision_tcm_spi; then
        insmod /vendor/lib/modules/omnivision_tcm_spi.ko
        echo "Touchscreen module loaded" >> /tmp/recovery.log
    fi
fi

# Set permissions
chmod 666 /dev/input/event* 2>/dev/null
chmod 666 /dev/spidev2.0 2>/dev/null

# Enable touchscreen
echo 1 > /sys/bus/spi/devices/spi2.0/accessible 2>/dev/null

# Enable ADB
setprop ro.adb.secure 0
setprop ro.debuggable 1
setprop persist.sys.usb.config adb
setprop service.adb.root 1

# Log success
echo "Touchscreen fix applied at $(date)" >> /tmp/recovery.log
EOF

chmod +x "$DEVICE_PATH/recovery/root/sbin/fix_touch.sh"

# Update init.rc to include touchscreen fix
if [ -f "$DEVICE_PATH/recovery/root/init.rc" ]; then
    echo "import /init.recovery.touchscreen.rc" >> "$DEVICE_PATH/recovery/root/init.rc"
else
    cat > "$DEVICE_PATH/recovery/root/init.rc" << 'EOF'
import /init.recovery.touchscreen.rc

on init
    # Run touchscreen fix
    exec u:r:recovery:s0 -- /sbin/fix_touch.sh
EOF
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
export OF_STATUS_INDENT_LEFT=48
export OF_STATUS_INDENT_RIGHT=48
export OF_HIDE_NOTCH=1
export OF_CLOCK_POS=1

# Enable keyboard/mouse support for non-touch control
export TW_USE_MOUSE_INPUT=1
export TW_ENABLE_VIRTUAL_MOUSE=1
export TW_HAS_USB_STORAGE=1

# Enable ADB by default for debugging
export OF_FORCE_ENABLE_ADB=1
export OF_SKIP_ADB_SECURE=1
export PLATFORM_SECURITY_PATCH="2099-12-31"
export TW_DEFAULT_LANGUAGE="en"

# Additional debugging
export OF_DEBUG_MODE=1
export TW_INCLUDE_RESETPROP=true
export TW_INCLUDE_REPACKTOOLS=true
export TW_INCLUDE_LIBRESETPROP=true

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
export OF_SKIP_FBE_DECRYPTION=1

echo "OrangeFox build variables loaded for X6512"
EOF

# Update BoardConfig for touchscreen support
echo "--- Updating BoardConfig for touchscreen support... ---"
if [ -f "$DEVICE_PATH/BoardConfig.mk" ]; then
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
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_CRYPTO_FBE := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true

# Build as boot image
BOARD_USES_RECOVERY_AS_BOOT := true
BOARD_BUILD_SYSTEM_ROOT_IMAGE := false
EOF
fi

# Setup build environment
echo "--- Setting up build environment... ---"
if [ -f build/envsetup.sh ]; then
    debug_log "Sourcing build/envsetup.sh..."
    source build/envsetup.sh || error_exit "Failed to source build/envsetup.sh"
elif [ -f build/make/envsetup.sh ]; then
    debug_log "Sourcing build/make/envsetup.sh..."
    source build/make/envsetup.sh || error_exit "Failed to source build/make/envsetup.sh"
else
    error_exit "Failed to find envsetup.sh"
fi

# Disable roomservice to avoid unnecessary fetches
export DISABLE_ROOMSERVICE=1

# Add lunch combo manually
debug_log "Adding device to lunch menu..."
add_lunch_combo "twrp_${DEVICE_CODENAME}-eng" 2>/dev/null || true
add_lunch_combo "omni_${DEVICE_CODENAME}-eng" 2>/dev/null || true

# List available lunch options
echo "--- Available lunch options: ---"
get_lunch_menu | grep -i "$DEVICE_CODENAME"

# Select device with fallback
echo "--- Selecting device: ${DEVICE_CODENAME} ---"
LUNCH_SUCCESS=0
for option in "twrp_${DEVICE_CODENAME}-eng" "omni_${DEVICE_CODENAME}-eng" "fox_${DEVICE_CODENAME}-eng"; do
    if lunch "$option"; then
        success_msg "Lunch successful with $option!"
        LUNCH_SUCCESS=1
        break
    else
        warning_msg "Lunch $option failed, trying next..."
    fi
done

if [ $LUNCH_SUCCESS -ne 1 ]; then
    error_exit "All lunch attempts failed! Check device tree config (e.g., twrp_X6512.mk exists?)"
fi

# Verify TW_THEME after lunch
debug_log "Verifying TW_THEME..."
TW_THEME_SET=$(get_build_var TW_THEME)
if [ -z "$TW_THEME_SET" ]; then
    error_exit "TW_THEME not set after lunch! Check BoardConfig.mk."
else
    success_msg "TW_THEME set to: $TW_THEME_SET"
fi

# Clean previous builds
echo "--- Cleaning previous builds... ---"
m clean || warning_msg "Clean failed, continuing anyway..."

# Start building
echo "--- Starting OrangeFox build... ---"
debug_log "Building with TARGET_RECOVERY_IMAGE=$TARGET_RECOVERY_IMAGE"

# Set additional build variables
export TW_DEVICE_VERSION="1.0_manusia"
export TARGET_PREBUILT_KERNEL="$DEVICE_PATH/prebuilt/kernel"
export ALLOW_MISSING_DEPENDENCIES=true

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

debug_log "Looking for output images in: $OUT_DIR"
if [ -d "$OUT_DIR" ]; then
    ls -la "$OUT_DIR/" | grep -E "\.img|\.zip"
    
    # Copy boot image
    if [ -f "$OUT_DIR/boot.img" ]; then
        cp "$OUT_DIR/boot.img" "$OUTPUT_DIR/OrangeFox-${DEVICE_CODENAME}-boot.img"
        success_msg "Boot image copied to output"
    fi
    
    # Copy recovery image if exists
    if [ -f "$OUT_DIR/recovery.img" ]; then
        cp "$OUT_DIR/recovery.img" "$OUTPUT_DIR/OrangeFox-${DEVICE_CODENAME}-recovery.img"
        success_msg "Recovery image copied to output"
    fi
    
    # Find and copy OrangeFox zip
    for zip_file in "$OUT_DIR"/OrangeFox*.zip; do
        if [ -f "$zip_file" ]; then
            cp "$zip_file" "$OUTPUT_DIR/"
            success_msg "OrangeFox zip copied: $(basename $zip_file)"
        fi
    done
else
    error_exit "Output directory not found: $OUT_DIR"
fi

# Copy build log
cp build.log "$OUTPUT_DIR/" 2>/dev/null || warning_msg "Failed to copy build log"

# Create device info file
cat > "$OUTPUT_DIR/device_info.txt" << EOF
Device: Infinix X6512
Android Version: 11
Partition Type: A/B with Super partition
Recovery Type: Boot image (no recovery partition)
Touchscreen: omnivision_tcm_spi (spi2.0) - FIXED
Screen Resolution: 720x1612 (portrait_hdpi theme applied)
OrangeFox Version: R11.1 (fox_12.1 base)
Build Date: $(date)
Builder: manusia
Email: ndktau@gmail.com

Features:
- Full OrangeFox features enabled
- Touchscreen support fixed for omnivision_tcm_spi
- Non-touch navigation enabled (keyboard/mouse support)
- ADB enabled by default for debugging
- Debug mode enabled
- Virtual A/B support
- Super partition support
- Boot image output (no recovery partition)

Instructions:
1. Flash boot.img using fastboot:
   fastboot flash boot OrangeFox-X6512-boot.img
   
2. Or use the OrangeFox zip installer if available

3. For touchscreen issues:
   - ADB is enabled by default
   - Connect USB and use: adb shell
   - Run: /sbin/fix_touch.sh
   
4. Non-touch navigation:
   - Use USB OTG with keyboard/mouse
   - Volume keys for navigation
   - Power button for selection
EOF

# List output files
echo "--- Output files ---"
ls -lah "$OUTPUT_DIR"

success_msg "Build completed successfully!"
echo "================================================"
echo "       OrangeFox Build Complete!                "
echo "================================================"
echo "Output directory: $OUTPUT_DIR"
echo "================================================"
