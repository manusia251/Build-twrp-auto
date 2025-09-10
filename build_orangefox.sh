#!/bin/bash

# OrangeFox Recovery Builder Script for Infinix X6512
# Fixed version with proper device configuration

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

# Force HTTPS instead of SSH
export USE_SSH=0

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
debug_log "OS: $(cat /etc/os-release | grep PRETTY_NAME)"
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

# Git configuration for HTTPS
debug_log "Setting up git configuration..."
git config --global user.name "manusia"
git config --global user.email "ndktau@gmail.com"
git config --global url."https://gitlab.com/".insteadOf "git@gitlab.com:"
git config --global url."https://github.com/".insteadOf "git@github.com:"
git config --global url."https://".insteadOf "git://"
git config --global http.sslVerify false

# Check if repo is available
if ! command -v repo &> /dev/null; then
    warning_msg "repo command not found, installing..."
    curl -s https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo
    chmod +x /usr/local/bin/repo
fi

# SYNC SECTION
echo "--- Starting sync process... ---"

# Check if already synced
if [ -f build/envsetup.sh ] || [ -f build/make/envsetup.sh ]; then
    success_msg "Build environment already exists, skipping sync"
else
    echo "--- Using TWRP 12.1 minimal manifest... ---"
    rm -rf .repo
    
    repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-12.1 --git-lfs --no-repo-verify || {
        error_exit "Failed to initialize repository!"
    }
    
    echo "--- Starting repo sync... ---"
    repo sync -c --force-sync --no-tags --no-clone-bundle -j4 --optimized-fetch --prune || {
        warning_msg "Sync had issues, trying with single thread..."
        repo sync -c --force-sync --no-tags --no-clone-bundle -j1
    }
    
    # Clone OrangeFox vendor
    if [ ! -d vendor/recovery ]; then
        echo "--- Cloning OrangeFox vendor... ---"
        git clone https://gitlab.com/OrangeFox/vendor/recovery.git -b fox_12.1 vendor/recovery --depth=1 || {
            warning_msg "Failed to clone OrangeFox vendor"
        }
    fi
fi

cd "$WORK_DIR"

# Verify build environment
if [ ! -f build/envsetup.sh ] && [ ! -f build/make/envsetup.sh ]; then
    error_exit "Build environment not found!"
fi

echo "--- Clone device tree... ---"
debug_log "Cloning device tree from: $DEVICE_TREE"

# Remove existing device tree
DEVICE_PATH="device/infinix/$DEVICE_CODENAME"
if [ -d "$DEVICE_PATH" ]; then
    debug_log "Removing existing device tree..."
    rm -rf "$DEVICE_PATH"
fi

# Clone device tree
git clone "$DEVICE_TREE" -b "$DEVICE_BRANCH" "$DEVICE_PATH" || error_exit "Failed to clone device tree"

if [ ! -d "$DEVICE_PATH" ]; then
    error_exit "Device tree directory not found!"
fi

debug_log "Device tree contents:"
ls -la "$DEVICE_PATH"

# FIX DEVICE TREE FILES
echo "--- Fixing device tree configuration... ---"

# Fix BoardConfig.mk - Remove problematic export
if [ -f "$DEVICE_PATH/BoardConfig.mk" ]; then
    debug_log "Fixing BoardConfig.mk..."
    # Remove or comment problematic export lines
    sed -i 's/^export OF_USE_KEY_HANDLER/# OF_USE_KEY_HANDLER/' "$DEVICE_PATH/BoardConfig.mk"
    sed -i 's/^export TW_/# TW_/' "$DEVICE_PATH/BoardConfig.mk" 2>/dev/null || true
    
    # Add our configurations properly (without export)
    if ! grep -q "# Fixed TouchScreen Configuration" "$DEVICE_PATH/BoardConfig.mk"; then
        cat >> "$DEVICE_PATH/BoardConfig.mk" << 'EOF'

# Fixed TouchScreen Configuration
RECOVERY_TOUCHSCREEN_SWAP_XY := false
RECOVERY_TOUCHSCREEN_FLIP_X := false
RECOVERY_TOUCHSCREEN_FLIP_Y := false
BOARD_RECOVERY_TOUCHSCREEN_DEBUG := true
TARGET_RECOVERY_DEVICE_MODULES += omnivision_tcm_spi
TW_LOAD_VENDOR_MODULES := omnivision_tcm_spi.ko
TW_USE_KEY_CODE_WAKE_DEVICE := true
BOARD_HAS_NO_SELECT_BUTTON := true
TW_INPUT_BLACKLIST := 
TW_EXCLUDE_DEFAULT_USB_INIT := false
BOARD_ALWAYS_INSECURE := true
BOARD_USES_RECOVERY_AS_BOOT := true
BOARD_BUILD_SYSTEM_ROOT_IMAGE := false
EOF
    fi
fi

# Fix AndroidProducts.mk
debug_log "Fixing AndroidProducts.mk..."
cat > "$DEVICE_PATH/AndroidProducts.mk" << EOF
PRODUCT_MAKEFILES := \\
    \$(LOCAL_DIR)/twrp_${DEVICE_CODENAME}.mk \\
    \$(LOCAL_DIR)/omni_${DEVICE_CODENAME}.mk

COMMON_LUNCH_CHOICES := \\
    twrp_${DEVICE_CODENAME}-eng \\
    twrp_${DEVICE_CODENAME}-userdebug \\
    twrp_${DEVICE_CODENAME}-user \\
    omni_${DEVICE_CODENAME}-eng \\
    omni_${DEVICE_CODENAME}-userdebug \\
    omni_${DEVICE_CODENAME}-user
EOF

# Create twrp_X6512.mk if not exists
if [ ! -f "$DEVICE_PATH/twrp_${DEVICE_CODENAME}.mk" ]; then
    debug_log "Creating twrp_${DEVICE_CODENAME}.mk..."
    cat > "$DEVICE_PATH/twrp_${DEVICE_CODENAME}.mk" << EOF
# Inherit from common AOSP config
\$(call inherit-product, \$(SRC_TARGET_DIR)/product/aosp_base.mk)

# Inherit some common TWRP stuff
\$(call inherit-product, vendor/twrp/config/common.mk)

# Inherit device configuration
\$(call inherit-product, device/infinix/${DEVICE_CODENAME}/device.mk)

# Device identifier
PRODUCT_DEVICE := ${DEVICE_CODENAME}
PRODUCT_NAME := twrp_${DEVICE_CODENAME}
PRODUCT_BRAND := Infinix
PRODUCT_MODEL := Infinix X6512
PRODUCT_MANUFACTURER := Infinix

# A/B support
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \\
    boot \\
    system \\
    vendor \\
    product \\
    odm
EOF
fi

# Apply touchscreen fixes
echo "--- Applying touchscreen fixes... ---"
mkdir -p "$DEVICE_PATH/recovery/root/sbin"
mkdir -p "$DEVICE_PATH/recovery/root/vendor/lib/modules"

# Create touchscreen init script
cat > "$DEVICE_PATH/recovery/root/init.recovery.touchscreen.rc" << 'EOF'
on early-init
    setprop ro.adb.secure 0
    setprop ro.debuggable 1
    setprop persist.sys.usb.config adb
    setprop service.adb.root 1

on boot
    write /sys/bus/spi/devices/spi2.0/accessible 1
    chmod 0666 /dev/spidev2.0
    chown system system /dev/spidev2.0
    insmod /vendor/lib/modules/omnivision_tcm_spi.ko
    chmod 0666 /dev/input/event*
    chown system input /dev/input/event*
    write /sys/module/omnivision_tcm_spi/parameters/debug_level 1
    start adbd

service adbd /sbin/adbd --root_seclabel=u:r:su:s0
    disabled
    socket adbd stream 660 system system
    seclabel u:r:adbd:s0
EOF

# Create touchscreen fix script
cat > "$DEVICE_PATH/recovery/root/sbin/fix_touch.sh" << 'EOF'
#!/sbin/sh
echo "Starting touchscreen fix..." >> /tmp/recovery.log
sleep 2
if [ -f /vendor/lib/modules/omnivision_tcm_spi.ko ]; then
    if ! lsmod | grep -q omnivision_tcm_spi; then
        insmod /vendor/lib/modules/omnivision_tcm_spi.ko
        echo "Touchscreen module loaded" >> /tmp/recovery.log
    fi
fi
chmod 666 /dev/input/event* 2>/dev/null
chmod 666 /dev/spidev2.0 2>/dev/null
echo 1 > /sys/bus/spi/devices/spi2.0/accessible 2>/dev/null
setprop ro.adb.secure 0
setprop ro.debuggable 1
echo "Touchscreen fix applied at $(date)" >> /tmp/recovery.log
EOF

chmod +x "$DEVICE_PATH/recovery/root/sbin/fix_touch.sh"

# Create vendorsetup.sh with OrangeFox variables
echo "--- Setting up OrangeFox build variables... ---"
cat > "$DEVICE_PATH/vendorsetup.sh" << 'EOF'
# OrangeFox Configuration for X6512
FOX_RECOVERY_SYSTEM_PARTITION="/dev/block/mapper/system"
FOX_RECOVERY_VENDOR_PARTITION="/dev/block/mapper/vendor"
FOX_USE_BASH_SHELL=1
FOX_ASH_IS_BASH=1
FOX_USE_TAR_BINARY=1
FOX_USE_SED_BINARY=1
FOX_USE_XZ_UTILS=1
FOX_USE_NANO_EDITOR=1
OF_ENABLE_LPTOOLS=1
FOX_AB_DEVICE=1
FOX_VIRTUAL_AB_DEVICE=1
FOX_RECOVERY_BOOT_PARTITION="/dev/block/by-name/boot"
OF_DYNAMIC_PARTITIONS=1
OF_SCREEN_H=2400
OF_STATUS_H=100
OF_STATUS_INDENT_LEFT=48
OF_STATUS_INDENT_RIGHT=48
OF_HIDE_NOTCH=1
OF_CLOCK_POS=1
TW_USE_MOUSE_INPUT=1
TW_ENABLE_VIRTUAL_MOUSE=1
OF_FORCE_ENABLE_ADB=1
OF_SKIP_ADB_SECURE=1
PLATFORM_SECURITY_PATCH="2099-12-31"
TW_DEFAULT_LANGUAGE="en"
OF_MAINTAINER="manusia"
FOX_BUILD_TYPE="Unofficial"
FOX_VERSION="R11.1"
FOX_RECOVERY_INSTALL_PARTITION="boot"
ALLOW_MISSING_DEPENDENCIES=true
echo "OrangeFox build variables loaded for X6512"
EOF

# Setup build environment
echo "--- Setting up build environment... ---"
cd "$WORK_DIR"

if [ -f build/envsetup.sh ]; then
    debug_log "Sourcing build/envsetup.sh..."
    source build/envsetup.sh
elif [ -f build/make/envsetup.sh ]; then
    debug_log "Sourcing build/make/envsetup.sh..."
    source build/make/envsetup.sh
else
    error_exit "envsetup.sh not found!"
fi

success_msg "Build environment loaded!"

# List available lunch options
echo "--- Available lunch options: ---"
lunch 2>&1 | grep -E "(omni_${DEVICE_CODENAME}|twrp_${DEVICE_CODENAME})" || true

# Try lunch with omni first (more likely to work)
echo "--- Selecting device: omni_${DEVICE_CODENAME}-eng ---"
if lunch "omni_${DEVICE_CODENAME}-eng"; then
    success_msg "Device selected: omni_${DEVICE_CODENAME}-eng"
elif lunch "twrp_${DEVICE_CODENAME}-eng"; then
    success_msg "Device selected: twrp_${DEVICE_CODENAME}-eng"
else
    error_exit "Failed to lunch device!"
fi

# Verify lunch was successful
if [ -z "$TARGET_PRODUCT" ]; then
    error_exit "Lunch failed - TARGET_PRODUCT not set!"
fi

echo "================================================"
echo "Target Product: $TARGET_PRODUCT"
echo "Target Device: $TARGET_DEVICE"
echo "Target Build Variant: $TARGET_BUILD_VARIANT"
echo "================================================"

# Clean previous builds
echo "--- Cleaning previous builds... ---"
make clean 2>/dev/null || warning_msg "Clean failed, continuing..."

# Set build variables
export TW_DEVICE_VERSION="1.0_manusia"
export ALLOW_MISSING_DEPENDENCIES=true

# Check for prebuilt kernel
if [ -f "$DEVICE_PATH/prebuilt/kernel" ]; then
    export TARGET_PREBUILT_KERNEL="$DEVICE_PATH/prebuilt/kernel"
    success_msg "Using prebuilt kernel"
else
    warning_msg "Prebuilt kernel not found"
fi

# Start building
echo "================================================"
echo "        Starting Build Process                  "
echo "================================================"

# Build recovery/boot image
if [ "$TARGET_RECOVERY_IMAGE" == "boot" ]; then
    echo "--- Building boot image... ---"
    mka bootimage -j$(nproc --all) 2>&1 | tee build.log || {
        warning_msg "bootimage failed, trying recoveryimage..."
        mka recoveryimage -j$(nproc --all) 2>&1 | tee -a build.log
    }
else
    echo "--- Building recovery image... ---"
    mka recoveryimage -j$(nproc --all) 2>&1 | tee build.log
fi

# Collect output files
echo "--- Collecting output files... ---"
OUT_DIR="out/target/product/$DEVICE_CODENAME"
OUTPUT_DIR="/tmp/cirrus-ci-build/output"
mkdir -p "$OUTPUT_DIR"

if [ -d "$OUT_DIR" ]; then
    # Find and copy all images and zips
    find "$OUT_DIR" -name "*.img" -o -name "*.zip" | while read file; do
        cp "$file" "$OUTPUT_DIR/" || true
        echo "Copied: $(basename $file)"
    done
fi

# Copy build log
cp build.log "$OUTPUT_DIR/" 2>/dev/null || true

# Create info file
cat > "$OUTPUT_DIR/device_info.txt" << EOF
Device: Infinix X6512
Android: 11
Partition: A/B with Super partition
Recovery: Boot image (no recovery partition)
Touchscreen: omnivision_tcm_spi (spi2.0) - FIXED
Builder: manusia
Email: ndktau@gmail.com
Build Date: $(date)
Product: $TARGET_PRODUCT
Variant: $TARGET_BUILD_VARIANT

Features:
- OrangeFox/TWRP recovery
- Touchscreen support for omnivision_tcm_spi
- ADB enabled by default
- Non-touch navigation support
- Virtual A/B support
- Super partition support

Usage:
1. Flash: fastboot flash boot <image_name>.img
2. For touch issues: adb shell /sbin/fix_touch.sh
EOF

echo "================================================"
echo "           Build Process Complete!              "
echo "================================================"
ls -lah "$OUTPUT_DIR"
echo "================================================"
