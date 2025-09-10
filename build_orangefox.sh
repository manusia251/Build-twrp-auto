#!/bin/bash

# OrangeFox Recovery Builder Script for Infinix X6512
# With touchscreen fix and full OrangeFox features support
# Enhanced error handling and debugging

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
debug_log "OS: $(lsb_release -d 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME)"
debug_log "Kernel: $(uname -r)"
debug_log "Architecture: $(uname -m)"
debug_log "Available memory: $(free -h | grep Mem | awk '{print $2}')"
debug_log "Available disk space: $(df -h / | tail -1 | awk '{print $4}')"

# Check if SSH is installed
if command -v ssh &> /dev/null; then
    debug_log "SSH is installed: $(ssh -V 2>&1)"
else
    warning_msg "SSH not installed, will use HTTPS for git operations"
fi

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
debug_log "Setting up git configuration for HTTPS..."
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

# SYNC SECTION - Simplified approach
echo "--- Starting simplified sync process... ---"

# Check if already synced
if [ -f build/envsetup.sh ] || [ -f build/make/envsetup.sh ]; then
    success_msg "Build environment already exists, skipping sync"
else
    # Use TWRP minimal manifest for reliability
    echo "--- Using TWRP 12.1 minimal manifest... ---"
    
    # Clean any previous attempts
    rm -rf .repo
    
    # Initialize with TWRP minimal manifest (most reliable)
    repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-12.1 --git-lfs --no-repo-verify || {
        error_exit "Failed to initialize repository!"
    }
    
    # Sync with fewer threads for stability
    echo "--- Starting repo sync (this may take a while)... ---"
    repo sync -c --force-sync --no-tags --no-clone-bundle -j4 --optimized-fetch --prune || {
        warning_msg "Sync had issues, trying with single thread..."
        repo sync -c --force-sync --no-tags --no-clone-bundle -j1 || {
            error_exit "Repository sync failed completely!"
        }
    }
    
    # Clone OrangeFox vendor if not present
    if [ ! -d vendor/recovery ]; then
        echo "--- Cloning OrangeFox vendor... ---"
        git clone https://gitlab.com/OrangeFox/vendor/recovery.git -b fox_12.1 vendor/recovery --depth=1 || {
            warning_msg "Failed to clone OrangeFox vendor, will build as TWRP"
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

# Remove existing device tree if present
DEVICE_PATH="device/infinix/$DEVICE_CODENAME"
if [ -d "$DEVICE_PATH" ]; then
    debug_log "Removing existing device tree..."
    rm -rf "$DEVICE_PATH"
fi

# Clone device tree
git clone "$DEVICE_TREE" -b "$DEVICE_BRANCH" "$DEVICE_PATH" || error_exit "Failed to clone device tree"

# Verify device tree
if [ ! -d "$DEVICE_PATH" ]; then
    error_exit "Device tree directory not found after cloning!"
fi

debug_log "Device tree contents:"
ls -la "$DEVICE_PATH"

# Check for required device tree files
echo "--- Checking device tree configuration... ---"
REQUIRED_FILES=("AndroidProducts.mk" "BoardConfig.mk")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$DEVICE_PATH/$file" ]; then
        warning_msg "$file not found in device tree!"
    fi
done

# Create AndroidProducts.mk if missing
if [ ! -f "$DEVICE_PATH/AndroidProducts.mk" ]; then
    echo "--- Creating AndroidProducts.mk... ---"
    cat > "$DEVICE_PATH/AndroidProducts.mk" << EOF
PRODUCT_MAKEFILES := \\
    \$(LOCAL_DIR)/twrp_${DEVICE_CODENAME}.mk

COMMON_LUNCH_CHOICES := \\
    twrp_${DEVICE_CODENAME}-eng \\
    twrp_${DEVICE_CODENAME}-userdebug \\
    twrp_${DEVICE_CODENAME}-user
EOF
fi

# Create device makefile if missing
if [ ! -f "$DEVICE_PATH/twrp_${DEVICE_CODENAME}.mk" ]; then
    echo "--- Creating twrp_${DEVICE_CODENAME}.mk... ---"
    cat > "$DEVICE_PATH/twrp_${DEVICE_CODENAME}.mk" << EOF
# Inherit from common AOSP config
\$(call inherit-product, \$(SRC_TARGET_DIR)/product/aosp_base.mk)

# Inherit some common TWRP stuff
\$(call inherit-product, vendor/twrp/config/common.mk)

# Device identifier
PRODUCT_DEVICE := ${DEVICE_CODENAME}
PRODUCT_NAME := twrp_${DEVICE_CODENAME}
PRODUCT_BRAND := Infinix
PRODUCT_MODEL := X6512
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
debug_log "Fixing touchscreen driver: omnivision_tcm_spi (spi2.0)"

# Create recovery directory structure
mkdir -p "$DEVICE_PATH/recovery/root/sbin"
mkdir -p "$DEVICE_PATH/recovery/root/vendor/lib/modules"

# Create touchscreen fix init script
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

# Create vendorsetup.sh for OrangeFox
echo "--- Setting up OrangeFox build variables... ---"
cat > "$DEVICE_PATH/vendorsetup.sh" << 'EOF'
# OrangeFox Configuration for X6512
export FOX_RECOVERY_SYSTEM_PARTITION="/dev/block/mapper/system"
export FOX_RECOVERY_VENDOR_PARTITION="/dev/block/mapper/vendor"
export FOX_USE_BASH_SHELL=1
export FOX_ASH_IS_BASH=1
export FOX_USE_TAR_BINARY=1
export FOX_USE_SED_BINARY=1
export FOX_USE_XZ_UTILS=1
export FOX_USE_NANO_EDITOR=1
export OF_ENABLE_LPTOOLS=1
export FOX_AB_DEVICE=1
export FOX_VIRTUAL_AB_DEVICE=1
export FOX_RECOVERY_BOOT_PARTITION="/dev/block/by-name/boot"
export OF_DYNAMIC_PARTITIONS=1
export OF_SCREEN_H=2400
export OF_STATUS_H=100
export OF_STATUS_INDENT_LEFT=48
export OF_STATUS_INDENT_RIGHT=48
export OF_HIDE_NOTCH=1
export OF_CLOCK_POS=1
export TW_USE_MOUSE_INPUT=1
export TW_ENABLE_VIRTUAL_MOUSE=1
export OF_FORCE_ENABLE_ADB=1
export OF_SKIP_ADB_SECURE=1
export PLATFORM_SECURITY_PATCH="2099-12-31"
export TW_DEFAULT_LANGUAGE="en"
export OF_MAINTAINER="manusia"
export FOX_BUILD_TYPE="Unofficial"
export FOX_VERSION="R11.1"
export FOX_RECOVERY_INSTALL_PARTITION="boot"
export ALLOW_MISSING_DEPENDENCIES=true
echo "OrangeFox build variables loaded for X6512"
EOF

# Update BoardConfig.mk
echo "--- Updating BoardConfig.mk... ---"
if [ -f "$DEVICE_PATH/BoardConfig.mk" ]; then
    # Add our configurations if not already present
    if ! grep -q "RECOVERY_TOUCHSCREEN" "$DEVICE_PATH/BoardConfig.mk"; then
        cat >> "$DEVICE_PATH/BoardConfig.mk" << 'EOF'

# Touchscreen configuration
RECOVERY_TOUCHSCREEN_SWAP_XY := false
RECOVERY_TOUCHSCREEN_FLIP_X := false
RECOVERY_TOUCHSCREEN_FLIP_Y := false
BOARD_RECOVERY_TOUCHSCREEN_DEBUG := true
TARGET_RECOVERY_DEVICE_MODULES += omnivision_tcm_spi
TW_LOAD_VENDOR_MODULES := "omnivision_tcm_spi.ko"
TW_USE_KEY_CODE_WAKE_DEVICE := true
BOARD_HAS_NO_SELECT_BUTTON := true
TW_INPUT_BLACKLIST := ""
TW_EXCLUDE_DEFAULT_USB_INIT := false
BOARD_ALWAYS_INSECURE := true
BOARD_USES_RECOVERY_AS_BOOT := true
BOARD_BUILD_SYSTEM_ROOT_IMAGE := false
EOF
    fi
fi

# Setup build environment
echo "--- Setting up build environment... ---"
cd "$WORK_DIR"

# Source the environment setup
if [ -f build/envsetup.sh ]; then
    debug_log "Sourcing build/envsetup.sh..."
    source build/envsetup.sh
elif [ -f build/make/envsetup.sh ]; then
    debug_log "Sourcing build/make/envsetup.sh..."
    source build/make/envsetup.sh
else
    error_exit "envsetup.sh not found!"
fi

# The output you see is normal, let's continue...
success_msg "Build environment loaded successfully!"

# Add device to lunch menu (may already be done by envsetup)
debug_log "Adding device to lunch menu..."
add_lunch_combo "twrp_${DEVICE_CODENAME}-eng" 2>/dev/null || true

# List available lunch options
echo "--- Available lunch options: ---"
lunch 2>&1 | grep -i "$DEVICE_CODENAME" || warning_msg "Device not in lunch menu"

# Select device
echo "--- Selecting device: twrp_${DEVICE_CODENAME}-eng ---"
lunch "twrp_${DEVICE_CODENAME}-eng" || {
    warning_msg "Standard lunch failed, trying alternatives..."
    lunch "omni_${DEVICE_CODENAME}-eng" || {
        # Try to find any matching lunch option
        LUNCH_OPTION=$(lunch 2>&1 | grep -i "$DEVICE_CODENAME" | head -1 | awk '{print $1}')
        if [ -n "$LUNCH_OPTION" ]; then
            lunch "$LUNCH_OPTION" || error_exit "Failed to lunch device!"
        else
            error_exit "No matching lunch option found!"
        fi
    }
}

# Verify lunch was successful
if [ -z "$TARGET_PRODUCT" ]; then
    error_exit "Lunch failed - TARGET_PRODUCT not set!"
fi

success_msg "Device selected: $TARGET_PRODUCT"

# Clean previous builds
echo "--- Cleaning previous builds... ---"
make clean 2>/dev/null || warning_msg "Clean failed, continuing..."

# Set build variables
export TW_DEVICE_VERSION="1.0_manusia"
export ALLOW_MISSING_DEPENDENCIES=true

# Check if kernel exists
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
echo "Target: $TARGET_PRODUCT"
echo "Device: $DEVICE_CODENAME"
echo "Type: Boot image (A/B device)"
echo "================================================"

# Build command based on target
if [ "$TARGET_RECOVERY_IMAGE" == "boot" ]; then
    echo "--- Building boot image... ---"
    mka bootimage -j$(nproc --all) 2>&1 | tee build.log || {
        warning_msg "bootimage target failed, trying recoveryimage..."
        mka recoveryimage -j$(nproc --all) 2>&1 | tee -a build.log || {
            warning_msg "recoveryimage failed, trying generic make..."
            make -j$(nproc --all) 2>&1 | tee -a build.log || error_exit "All build attempts failed!"
        }
    }
else
    echo "--- Building recovery image... ---"
    mka recoveryimage -j$(nproc --all) 2>&1 | tee build.log || error_exit "Build failed!"
fi

# Find and copy output files
echo "--- Collecting output files... ---"
OUT_DIR="out/target/product/$DEVICE_CODENAME"
OUTPUT_DIR="/tmp/cirrus-ci-build/output"
mkdir -p "$OUTPUT_DIR"

# Search for output images
debug_log "Searching for images in: $OUT_DIR"
if [ -d "$OUT_DIR" ]; then
    # List all img files
    echo "Found images:"
    find "$OUT_DIR" -name "*.img" -type f 2>/dev/null | while read img; do
        echo "  - $(basename $img)"
        cp "$img" "$OUTPUT_DIR/" || true
    done
    
    # List all zip files
    echo "Found zips:"
    find "$OUT_DIR" -name "*.zip" -type f 2>/dev/null | while read zip; do
        echo "  - $(basename $zip)"
        cp "$zip" "$OUTPUT_DIR/" || true
    done
else
    warning_msg "Output directory not found: $OUT_DIR"
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
3. USB OTG keyboard/mouse supported
EOF

# List final output
echo "================================================"
echo "           Build Complete!                      "
echo "================================================"
ls -lah "$OUTPUT_DIR"
echo "================================================"
