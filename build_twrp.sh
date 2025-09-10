#!/bin/bash
#
# OrangeFox Recovery Builder for Android 11 - Best Practice Method
# Target: boot.img for A/B device (MT6761)
# Strategy: TWRP 11 base + selective OrangeFox features
# =======================================================================

set -euo pipefail

# Enable debugging conditionally
[[ "${DEBUG:-0}" == "1" ]] && set -x

# ============== Configuration ==============
DEVICE_TREE_URL="${1:-https://github.com/manusia251/twrp-test.git}"
DEVICE_TREE_BRANCH="${2:-main}"
DEVICE_CODENAME="${3:-X6512}"
MANIFEST_BRANCH="${4:-twrp-11}"  # Use TWRP 11 as base
BUILD_TARGET="${5:-boot}"
VENDOR_NAME="infinix"

# Build info
export FOX_VERSION="R11.1_3"
export FOX_BUILD_TYPE="Unofficial"
export OF_MAINTAINER="manusia251"
BUILD_DATE=$(date +%Y%m%d)
BUILD_TIME=$(date +%H%M)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============== Functions ==============
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 could not be found"
        return 1
    fi
}

validate_url() {
    if wget -q --spider "$1" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# ============== Pre-flight Checks ==============
log_info "Starting OrangeFox Recovery Builder"
log_info "Build Date: $BUILD_DATE $BUILD_TIME"
log_info "Device: $DEVICE_CODENAME"
log_info "Target: ${BUILD_TARGET}image"

# Check required commands
for cmd in git repo wget curl; do
    check_command "$cmd" || exit 1
done

# Validate device tree URL
if ! validate_url "$DEVICE_TREE_URL"; then
    log_error "Device tree URL is not accessible: $DEVICE_TREE_URL"
    exit 1
fi

# ============== Setup Environment ==============
WORKDIR=$(pwd)
BUILD_DIR="$WORKDIR/orangefox"
export GITHUB_WORKSPACE="$WORKDIR"

# Git configuration
git config --global user.name "manusia251"
git config --global user.email "darkside@gmail.com"
git config --global advice.detachedHead false
git config --global init.defaultBranch main

# Create build directory
log_info "Creating build directory: $BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# ============== Method Selection ==============
log_info "Detecting best build method..."

# Method 1: Try TWRP 11 first (best compatibility for Android 11)
USE_TWRP_11=false
USE_TWRP_12=false

if wget -q --spider "https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp/tree/twrp-11" 2>/dev/null; then
    log_info "TWRP 11 manifest available - using as base"
    USE_TWRP_11=true
    MANIFEST_URL="https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git"
    MANIFEST_BRANCH="twrp-11"
else
    log_warn "TWRP 11 not available, falling back to TWRP 12.1"
    USE_TWRP_12=true
    MANIFEST_URL="https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git"
    MANIFEST_BRANCH="twrp-12.1"
fi

# ============== Repo Sync ==============
log_info "Initializing repository with $MANIFEST_BRANCH"

if [ ! -d ".repo" ]; then
    repo init -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" \
        --depth=1 \
        --no-repo-verify \
        --git-lfs \
        2>&1 | tee repo_init.log
    
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log_error "Repo init failed. Check repo_init.log"
        exit 1
    fi
fi

# Optimize repo sync for CI
log_info "Syncing repository (this may take a while)..."
repo sync -c \
    --force-sync \
    --no-clone-bundle \
    --no-tags \
    --optimized-fetch \
    --prune \
    -j4 2>&1 | tee repo_sync.log || {
        log_warn "Initial sync failed, retrying with -j1..."
        repo sync -c --force-sync --no-tags -j1
    }

# Verify sync success
if [ ! -f "build/envsetup.sh" ]; then
    log_error "Repository sync incomplete - build/envsetup.sh not found"
    log_info "Attempting manual recovery..."
    
    # Try to manually clone build system
    if [ ! -d "build/make" ]; then
        git clone --depth=1 https://android.googlesource.com/platform/build build/make
    fi
    
    if [ ! -f "build/envsetup.sh" ] && [ -f "build/make/envsetup.sh" ]; then
        ln -sf make/envsetup.sh build/envsetup.sh
    fi
    
    if [ ! -f "build/envsetup.sh" ]; then
        log_error "Cannot recover build system"
        exit 1
    fi
fi

# ============== Clone Additional Vendors ==============
log_info "Setting up vendor repositories..."

# Clone OrangeFox vendor (for OrangeFox features)
if [ ! -d "vendor/recovery" ]; then
    log_info "Cloning OrangeFox vendor..."
    git clone --depth=1 https://gitlab.com/OrangeFox/vendor/recovery.git vendor/recovery || {
        log_warn "GitLab failed, trying GitHub mirror..."
        git clone --depth=1 https://github.com/OrangeFoxRecovery/OrangeFoxVendor.git vendor/recovery
    }
fi

# Clone omni vendor (required for omni products)
if [ ! -d "vendor/omni" ]; then
    log_info "Cloning Omni vendor..."
    if [ "$USE_TWRP_11" = true ]; then
        git clone --depth=1 -b android-11 https://github.com/omnirom/android_vendor_omni.git vendor/omni || {
            log_warn "Android-11 branch not found, using android-9.0"
            git clone --depth=1 -b android-9.0 https://github.com/omnirom/android_vendor_omni.git vendor/omni
        }
    else
        git clone --depth=1 -b android-12.1 https://github.com/omnirom/android_vendor_omni.git vendor/omni
    fi
fi

# ============== Clone Device Tree ==============
log_info "Cloning device tree..."
DEVICE_PATH="device/${VENDOR_NAME}/${DEVICE_CODENAME}"

rm -rf "$DEVICE_PATH"
git clone --depth=1 -b "$DEVICE_TREE_BRANCH" "$DEVICE_TREE_URL" "$DEVICE_PATH"

if [ ! -d "$DEVICE_PATH" ]; then
    log_error "Failed to clone device tree"
    exit 1
fi

# ============== Validate Device Tree ==============
log_info "Validating device tree..."
cd "$DEVICE_PATH"

# Check critical files
MISSING_FILES=()
[ ! -f "AndroidProducts.mk" ] && MISSING_FILES+=("AndroidProducts.mk")
[ ! -f "BoardConfig.mk" ] && MISSING_FILES+=("BoardConfig.mk")
[ ! -f "omni_${DEVICE_CODENAME}.mk" ] && [ ! -f "twrp_${DEVICE_CODENAME}.mk" ] && MISSING_FILES+=("product makefile")
[ ! -f "prebuilt/kernel" ] && MISSING_FILES+=("prebuilt/kernel")

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    log_error "Missing critical files in device tree: ${MISSING_FILES[*]}"
    log_info "Device tree contents:"
    ls -la
    exit 1
fi

# ============== Patch Device Tree ==============
log_info "Patching device tree for OrangeFox..."

# Backup original BoardConfig.mk
cp BoardConfig.mk BoardConfig.mk.original

# Create comprehensive BoardConfig patches
cat >> BoardConfig.mk << 'EOF'

# ========== OrangeFox/TWRP Configuration ==========
# Recovery Type
BOARD_USES_RECOVERY_AS_BOOT := true
AB_OTA_UPDATER := true

# File systems
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs

# Display
TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"
TW_THEME := portrait_hdpi
TW_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"
TW_MAX_BRIGHTNESS := 255
TW_DEFAULT_BRIGHTNESS := 128

# Language & Time
TW_DEFAULT_LANGUAGE := en
TW_EXTRA_LANGUAGES := true
TW_24_HOUR_CLOCK := true

# Crypto
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_CRYPTO_FBE := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true
BOARD_USES_METADATA_PARTITION := true

# Storage
TW_INTERNAL_STORAGE_PATH := "/data/media/0"
TW_INTERNAL_STORAGE_MOUNT_POINT := "data"
TW_EXTERNAL_STORAGE_PATH := "/external_sd"
TW_EXTERNAL_STORAGE_MOUNT_POINT := "external_sd"
RECOVERY_SDCARD_ON_DATA := true

# USB & MTP
TW_HAS_MTP := true
TW_MTP_DEVICE := "/dev/mtp_usb"
TARGET_USE_CUSTOM_LUN_FILE_PATH := "/config/usb_gadget/g1/functions/mass_storage.0/lun.%d/file"

# Features
TW_USE_TOOLBOX := true
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_NTFS_3G := true
TW_INCLUDE_FUSE_EXFAT := true
TW_INCLUDE_FUSE_NTFS := true

# Debug
TWRP_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true

# Navigation without touchscreen
TW_NO_SCREEN_TIMEOUT := true
TW_NO_SCREEN_BLANK := true
TW_INPUT_BLACKLIST := "hbtp_vm"

# Platform specific (MT6761)
TW_CUSTOM_CPU_TEMP_PATH := /sys/class/thermal/thermal_zone0/temp
BOARD_HAS_NO_SELECT_BUTTON := true

# Exclude unnecessary components
TW_EXCLUDE_APEX := true
TW_EXCLUDE_PYTHON := true
TW_EXCLUDE_NANO := true
TW_EXCLUDE_BASH := true

# OrangeFox specific flags (will be used if vendor/recovery exists)
ifeq ($(wildcard vendor/recovery),)
$(warning OrangeFox vendor not found, using TWRP mode)
else
FOX_USE_TWRP_RECOVERY_IMAGE_BUILDER := 1
OF_USE_MAGISKBOOT := 1
OF_USE_MAGISKBOOT_FOR_ALL_PATCHES := 1
OF_DONT_PATCH_ENCRYPTED_DEVICE := 1
OF_NO_TREBLE_COMPATIBILITY_CHECK := 1
OF_PATCH_AVB20 := 1
OF_MAINTAINER := manusia251
OF_FLASHLIGHT_ENABLE := 1
OF_USE_GREEN_LED := 0
endif

# Build optimization
ALLOW_MISSING_DEPENDENCIES := true
BUILD_BROKEN_DUP_RULES := true
BUILD_BROKEN_MISSING_REQUIRED_MODULES := true
EOF

# Create init.recovery.mt6761.rc for touchscreen
log_info "Creating touchscreen initialization script..."
mkdir -p recovery/root
cat > recovery/root/init.recovery.mt6761.rc << 'EOF'
# Touchscreen initialization for MT6761
on early-init
    # Create input devices nodes
    mkdir /dev/input 0755 root root

on init
    # Set permissions for all input devices
    chmod 0666 /dev/input/event0
    chmod 0666 /dev/input/event1
    chmod 0666 /dev/input/event2
    chmod 0666 /dev/input/event3
    chmod 0666 /dev/input/mice
    chmod 0666 /dev/input/mouse0
    
    # Load touchscreen modules if available
    insmod /vendor/lib/modules/omnivision_tcm.ko
    insmod /vendor/lib/modules/touch_driver.ko
    
    # Common touchscreen enable paths
    write /sys/devices/virtual/input/input0/enable 1
    write /sys/devices/virtual/input/input1/enable 1
    write /sys/devices/platform/soc/11010000.spi2/spi_master/spi2/spi2.0/input/input0/enabled 1
    
on boot
    # Additional touchscreen configurations
    write /proc/touchpanel/oppo_tp_direction 0
    write /sys/kernel/touchscreen/enable 1
    write /sys/devices/platform/touch/enable 1
    
    # Attempt to start touch service if exists
    start touch_hal

service touch_hal /vendor/bin/hw/android.hardware.touch@1.0-service
    class hal
    user system
    group system
    disabled

# Fallback touch enabler
service touch_enable /system/bin/sh -c "for i in /sys/devices/virtual/input/input*/enable*; do echo 1 > \$i 2>/dev/null; done"
    oneshot
    disabled
    user root
    group root
    seclabel u:r:recovery:s0

on property:init.svc.recovery=running
    start touch_enable
EOF

# Create vendorsetup.sh for additional exports
cat > vendorsetup.sh << 'EOF'
# OrangeFox environment variables
export FOX_VERSION="R11.1_3"
export FOX_BUILD_TYPE="Unofficial"
export OF_MAINTAINER="manusia251"
export TARGET_DEVICE_ALT="X6512,Infinix-X6512"

# Screen settings
export OF_SCREEN_H=1612
export OF_SCREEN_W=720
export OF_STATUS_H=80
export OF_STATUS_INDENT_LEFT=48
export OF_STATUS_INDENT_RIGHT=48

# Features
export OF_USE_KEY_HANDLER=1
export OF_FLASHLIGHT_ENABLE=1
export OF_QUICK_BACKUP_LIST="/boot;/data;"
export FOX_USE_BASH_SHELL=1
export FOX_ASH_IS_BASH=1
export FOX_USE_TAR_BINARY=1
export FOX_USE_SED_BINARY=1
export FOX_USE_XZ_UTILS=1
export OF_ENABLE_LPTOOLS=1

echo "OrangeFox environment loaded for $TARGET_DEVICE_ALT"
EOF

cd "$BUILD_DIR"

# ============== Setup Build Environment ==============
log_info "Setting up build environment..."

# Java setup (prefer Java 11 for Android 11/12, fallback to Java 8)
if [ -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
elif [ -d "/usr/lib/jvm/java-8-openjdk-amd64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64"
fi
export PATH="$JAVA_HOME/bin:$PATH"

# Python setup
if ! python --version 2>/dev/null | grep -q "Python 3"; then
    ln -sf /usr/bin/python3 /usr/local/bin/python || true
fi

# Ccache setup
export USE_CCACHE=1
export CCACHE_DIR="/tmp/ccache"
export CCACHE_COMPRESS=1
export CCACHE_MAXSIZE="20G"
ccache -M 20G 2>/dev/null || true

# Build environment variables
export ALLOW_MISSING_DEPENDENCIES=true
export BUILD_BROKEN_DUP_RULES=true
export LC_ALL=C

# Source envsetup
log_info "Sourcing build/envsetup.sh..."
source build/envsetup.sh

# ============== Lunch Target ==============
log_info "Selecting lunch target..."

# Try multiple product prefixes
LUNCH_SUCCESS=false
for prefix in "omni" "twrp" "aosp" "lineage"; do
    LUNCH_TARGET="${prefix}_${DEVICE_CODENAME}-eng"
    log_info "Trying lunch: $LUNCH_TARGET"
    
    if lunch "$LUNCH_TARGET" 2>/dev/null; then
        log_info "Lunch successful with $LUNCH_TARGET"
        LUNCH_SUCCESS=true
        break
    fi
done

if [ "$LUNCH_SUCCESS" = false ]; then
    log_error "No valid lunch target found"
    log_info "Available targets:"
    lunch 2>&1 | grep -i "$DEVICE_CODENAME" || true
    exit 1
fi

# ============== Build ==============
log_info "Starting build process..."
log_info "Building ${BUILD_TARGET}image with $(nproc) threads"

# Export additional variables for build
export FOX_VERSION
export FOX_BUILD_TYPE
export OF_MAINTAINER

# Try different build commands
BUILD_SUCCESS=false

# Method 1: mka (recommended)
if ! $BUILD_SUCCESS; then
    log_info "Attempting build with mka..."
    if mka ${BUILD_TARGET}image -j$(nproc) 2>&1 | tee build.log; then
        BUILD_SUCCESS=true
    fi
fi

# Method 2: make (fallback)
if ! $BUILD_SUCCESS; then
    log_warn "mka failed, trying make..."
    if make ${BUILD_TARGET}image -j$(nproc) 2>&1 | tee -a build.log; then
        BUILD_SUCCESS=true
    fi
fi

# Method 3: make with reduced threads
if ! $BUILD_SUCCESS; then
    log_warn "Parallel build failed, trying with 4 threads..."
    if make ${BUILD_TARGET}image -j4 2>&1 | tee -a build.log; then
        BUILD_SUCCESS=true
    fi
fi

if ! $BUILD_SUCCESS; then
    log_error "Build failed. Check build.log for details"
    tail -100 build.log
    exit 1
fi

# ============== Collect Output ==============
log_info "Collecting build output..."

RESULT_DIR="$BUILD_DIR/out/target/product/${DEVICE_CODENAME}"
OUTPUT_DIR="$WORKDIR/output"
mkdir -p "$OUTPUT_DIR"

if [ ! -d "$RESULT_DIR" ]; then
    log_error "Result directory not found: $RESULT_DIR"
    exit 1
fi

log_info "Contents of result directory:"
ls -lah "$RESULT_DIR" | grep -E "\.img|\.zip" || true

# Copy boot.img (primary target for A/B device)
if [ -f "$RESULT_DIR/boot.img" ]; then
    OUTPUT_FILE="$OUTPUT_DIR/OrangeFox-${FOX_VERSION}-${DEVICE_CODENAME}-${BUILD_DATE}.img"
    cp "$RESULT_DIR/boot.img" "$OUTPUT_FILE"
    log_info "Created: $OUTPUT_FILE"
    
    # Create checksum
    sha256sum "$OUTPUT_FILE" > "$OUTPUT_FILE.sha256"
fi

# Copy recovery.img if exists
if [ -f "$RESULT_DIR/recovery.img" ]; then
    cp "$RESULT_DIR/recovery.img" "$OUTPUT_DIR/recovery-${BUILD_DATE}.img"
fi

# Copy any OrangeFox zips
find "$RESULT_DIR" -name "*.zip" -type f 2>/dev/null | while read -r zipfile; do
    cp "$zipfile" "$OUTPUT_DIR/"
    log_info "Copied: $(basename "$zipfile")"
done

# ============== Generate Build Info ==============
cat > "$OUTPUT_DIR/build_info.txt" << EOF
OrangeFox Recovery Build Information
====================================
Device: $DEVICE_CODENAME
Version: $FOX_VERSION
Build Type: $FOX_BUILD_TYPE
Build Date: $BUILD_DATE $BUILD_TIME
Maintainer: $OF_MAINTAINER
Base: $MANIFEST_BRANCH
Target: ${BUILD_TARGET}image

Device Tree: $DEVICE_TREE_URL ($DEVICE_TREE_BRANCH)

Files:
$(ls -lah "$OUTPUT_DIR" | grep -v "^total\|^d")

SHA256 Checksums:
$(sha256sum "$OUTPUT_DIR"/*.img 2>/dev/null || echo "No images found")
EOF

# ============== Final Report ==============
log_info "============================================"
log_info "Build completed successfully!"
log_info "Output directory: $OUTPUT_DIR"
log_info "Files generated:"
ls -lah "$OUTPUT_DIR"
log_info "============================================"

# Cleanup (optional)
if [[ "${CLEANUP:-0}" == "1" ]]; then
    log_info "Cleaning up build directory..."
    rm -rf "$BUILD_DIR"
fi

exit 0
