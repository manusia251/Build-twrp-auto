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

# Ensure PATH includes repo
export PATH=/usr/local/bin:$PATH

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

# Double-check repo installation
if ! command -v repo &> /dev/null; then
    echo "--- Installing repo tool (fallback)... ---"
    curl https://storage.googleapis.com/git-repo-downloads/repo > /tmp/repo
    chmod a+x /tmp/repo
    sudo mv /tmp/repo /usr/local/bin/repo || mv /tmp/repo /usr/local/bin/repo
fi

# Verify repo is working
echo "--- Verifying repo tool... ---"
repo version || {
    echo "[ERROR] repo tool not working properly!"
    exit 1
}

echo "--- Starting sync process... ---"

# Check if already synced
if [ -f "build/envsetup.sh" ] || [ -f "build/make/envsetup.sh" ]; then
    echo "--- Source already synced, skipping... ---"
else
    echo "--- Initializing TWRP 11 minimal manifest... ---"  # Changed for Android 11 target
    rm -rf .repo
    
    repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-11 --git-lfs --no-repo-verify || {  # Changed branch to twrp-11 for Android 11
        echo "[ERROR] Failed to initialize repo"
        exit 1
    }
    
    echo "--- Starting repo sync (this will take time)... ---"
    repo sync -c --force-sync --no-tags --no-clone-bundle -j4 --optimized-fetch --prune || {
        echo "[ERROR] Failed to sync repo"
        exit 1
    }
    
    # Clone OrangeFox vendor
    if [ ! -d "vendor/recovery" ]; then
        echo "--- Cloning OrangeFox vendor... ---"
        git clone https://gitlab.com/OrangeFox/vendor/recovery.git -b fox_10.0 vendor/recovery --depth=1 || {  # Changed branch to fox_10.0 for Android 11 compatibility
            echo "[WARNING] Failed to clone OrangeFox vendor, continuing anyway..."
        }
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

git clone $DEVICE_TREE -b $DEVICE_BRANCH $DEVICE_PATH || {
    echo "[ERROR] Failed to clone device tree"
    exit 1
}

if [ ! -d "$DEVICE_PATH" ]; then
    echo "[ERROR] Device tree directory not found after clone"
    exit 1
fi

debug_log "Device tree contents:"
ls -la $DEVICE_PATH

# Create a complete device tree structure
echo "--- Creating complete device tree structure... ---"

# Fix BoardConfig.mk first
echo "--- Fixing BoardConfig.mk... ---"
if [ -f "$DEVICE_PATH/BoardConfig.mk" ]; then
    cp "$DEVICE_PATH/BoardConfig.mk" "$DEVICE_PATH/BoardConfig.mk.bak"
    
    # Remove all problematic lines
    sed -i '/^export /d' "$DEVICE_PATH/BoardConfig.mk"
    sed -i '/TW_THEME/d' "$DEVICE_PATH/BoardConfig.mk"
    
    # Append clean configuration
    cat >> "$DEVICE_PATH/BoardConfig.mk" << 'BOARD_EOF'

# Platform
TARGET_BOARD_PLATFORM := sc9863a  # Changed to correct platform for Unisoc SC9863A

# Architecture
TARGET_ARCH := arm64  # Changed to arm64 for 64-bit architecture
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a55

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := generic
TARGET_2ND_CPU_VARIANT_RUNTIME := cortex-a55

# Kernel
BOARD_KERNEL_CMDLINE := console=ttyS1,115200n8  # Changed for Unisoc typical cmdline
BOARD_KERNEL_BASE := 0x00000000  # Changed for Unisoc
BOARD_KERNEL_PAGESIZE := 2048
BOARD_KERNEL_OFFSET := 0x00008000
BOARD_RAMDISK_OFFSET := 0x05400000  # Adjusted for typical Unisoc
BOARD_KERNEL_TAGS_OFFSET := 0x00000100
BOARD_KERNEL_SECOND_OFFSET := 0x00f00000
BOARD_DTB_OFFSET := 0x01f00000
BOARD_FLASH_BLOCK_SIZE := 512
BOARD_BOOTIMG_HEADER_VERSION := 2
BOARD_KERNEL_IMAGE_NAME := kernel

# Partitions
BOARD_FLASH_BLOCK_SIZE := 512
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432

# Dynamic Partitions
BOARD_SUPER_PARTITION_SIZE := 9126805504
BOARD_SUPER_PARTITION_GROUPS := infinix_dynamic_partitions
BOARD_INFINIX_DYNAMIC_PARTITIONS_PARTITION_LIST := system vendor product system_ext
BOARD_INFINIX_DYNAMIC_PARTITIONS_SIZE := 9122611200

# File systems
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_SYSTEMIMAGE_PARTITION_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
TARGET_COPY_OUT_VENDOR := vendor

# A/B
AB_OTA_UPDATER := true
BOARD_USES_RECOVERY_AS_BOOT := true
BOARD_BUILD_SYSTEM_ROOT_IMAGE := false

# TWRP Configuration
TW_THEME := portrait_hdpi
RECOVERY_SDCARD_ON_DATA := true
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_EXTRA_LANGUAGES := false  # Changed to false to reduce size
TW_SCREEN_BLANK_ON_BOOT := true
TW_INPUT_BLACKLIST := "hbtp_vm"
TW_USE_TOOLBOX := true
TW_INCLUDE_REPACKTOOLS := false  # Changed to false to reduce size
TW_INCLUDE_RESETPROP := false  # Changed to false to reduce size
TW_INCLUDE_LIBRESETPROP := false  # Changed to false to reduce size
TW_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"
TW_MAX_BRIGHTNESS := 2047
TW_DEFAULT_BRIGHTNESS := 1200

# Debug flags
TWRP_INCLUDE_LOGCAT := false  # Changed to false to reduce size
TARGET_USES_LOGD := false  # Changed to false to reduce size

# Crypto
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_CRYPTO_FBE := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := 2099-12-31
PLATFORM_VERSION := 11.0.0  # Changed to 11.0.0 for Android 11
TW_USE_FSCRYPT_POLICY := 1

# Additional flags
TW_NO_SCREEN_BLANK := true
TW_EXCLUDE_APEX := true
BOARD_EOF
fi

# Create proper makefiles
echo "--- Creating makefiles... ---"
cd $DEVICE_PATH

# Create twrp makefile - REMOVING the duplicate ro.build.date.utc
cat > "twrp_${DEVICE_CODENAME}.mk" << EOF
# Inherit from those products. Most specific first.
\$(call inherit-product, \$(SRC_TARGET_DIR)/product/core_64_bit.mk)
\$(call inherit-product, \$(SRC_TARGET_DIR)/product/aosp_base.mk)

# Inherit from our custom product configuration
\$(call inherit-product, vendor/twrp/config/common.mk)

# Device identifier
PRODUCT_DEVICE := ${DEVICE_CODENAME}
PRODUCT_NAME := twrp_${DEVICE_CODENAME}
PRODUCT_BRAND := Infinix
PRODUCT_MODEL := Infinix ${DEVICE_CODENAME}
PRODUCT_MANUFACTURER := Infinix

# Remove duplicate date properties - let the build system handle it
PRODUCT_PROPERTY_OVERRIDES += \\
    ro.vendor.build.security_patch=2099-12-31
EOF

# Create omni makefile - REMOVING the duplicate ro.build.date.utc
cat > "omni_${DEVICE_CODENAME}.mk" << EOF
# Inherit from those products. Most specific first.
\$(call inherit-product, \$(SRC_TARGET_DIR)/product/core_64_bit.mk)
\$(call inherit-product, \$(SRC_TARGET_DIR)/product/aosp_base.mk)

# Inherit from our custom product configuration
\$(call inherit-product, vendor/twrp/config/common.mk)

# Device identifier
PRODUCT_DEVICE := ${DEVICE_CODENAME}
PRODUCT_NAME := omni_${DEVICE_CODENAME}
PRODUCT_BRAND := Infinix
PRODUCT_MODEL := Infinix ${DEVICE_CODENAME}
PRODUCT_MANUFACTURER := Infinix

# Remove duplicate date properties
PRODUCT_PROPERTY_OVERRIDES += \\
    ro.vendor.build.security_patch=2099-12-31
EOF

# Create AndroidProducts.mk
cat > AndroidProducts.mk << EOF
PRODUCT_MAKEFILES := \\
    \$(LOCAL_DIR)/twrp_${DEVICE_CODENAME}.mk \\
    \$(LOCAL_DIR)/omni_${DEVICE_CODENAME}.mk

COMMON_LUNCH_CHOICES := \\
    twrp_${DEVICE_CODENAME}-eng \\
    omni_${DEVICE_CODENAME}-eng
EOF

# Create device.mk (empty for now)
touch device.mk

# Create Android.mk
cat > Android.mk << 'EOF'
LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),X6512)
include $(call all-subdir-makefiles,$(LOCAL_PATH))
endif
EOF

# Create Android.bp
cat > Android.bp << 'EOF'
soong_namespace {
}
EOF

# Fix recovery.fstab issue
echo "--- Setting up recovery filesystem structure... ---"
mkdir -p recovery/root/{system/etc,etc,sbin,vendor/lib/modules}

# Create recovery.fstab in all required locations
cat > recovery.fstab << 'FSTAB_EOF'
# mount point    fstype    device                                        flags
/system          ext4      /dev/block/mapper/system                     flags=display="System";logical
/vendor          ext4      /dev/block/mapper/vendor                     flags=display="Vendor";logical
/product         ext4      /dev/block/mapper/product                    flags=display="Product";logical
/system_ext      ext4      /dev/block/mapper/system_ext                 flags=display="System_ext";logical
/boot            emmc      /dev/block/by-name/boot                      flags=display="Boot";backup=1;flashimg=1
/recovery        emmc      /dev/block/by-name/recovery                  flags=display="Recovery";backup=1;flashimg=1
/data            f2fs      /dev/block/by-name/userdata                  flags=fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized
/cache           ext4      /dev/block/by-name/cache                     flags=display="Cache"
/metadata        ext4      /dev/block/by-name/metadata                  flags=display="Metadata"
/persist         ext4      /dev/block/by-name/persist                   flags=display="Persist"
/misc            emmc      /dev/block/by-name/misc                      flags=display="Misc"

# Removable storage
/external_sd     auto      /dev/block/mmcblk1p1                         flags=display="MicroSD";storage;wipeingui;removable
/usb_otg         auto      /dev/block/sda1                              flags=display="USB Storage";storage;wipeingui;removable
FSTAB_EOF

# Copy to all locations
cp recovery.fstab recovery/root/system/etc/recovery.fstab
cp recovery.fstab recovery/root/etc/recovery.fstab
cp recovery.fstab recovery/root/etc/twrp.fstab

# Create init files
cat > recovery/root/init.recovery.${DEVICE_CODENAME}.rc << 'INIT_EOF'
on init
    setprop sys.usb.config adb
    setprop persist.sys.usb.config adb
    setprop persist.service.adb.enable 1
    setprop persist.service.debuggable 1
    setprop ro.adb.secure 0

on boot
    start adbd
INIT_EOF

# Create vendorsetup.sh - WITHOUT setting ro.build.date.utc
cat > vendorsetup.sh << VENDOR_EOF
export FOX_USE_BASH_SHELL=1
export FOX_ASH_IS_BASH=1
export FOX_USE_NANO_EDITOR=1
export OF_ENABLE_LPTOOLS=1
export FOX_AB_DEVICE=1
export FOX_VIRTUAL_AB_DEVICE=1
export FOX_RECOVERY_BOOT_PARTITION="/dev/block/by-name/boot"
export OF_DYNAMIC_PARTITIONS=1
export OF_ALLOW_DISABLE_NAVBAR=0
export OF_STATUS_INDENT_LEFT=48
export OF_STATUS_INDENT_RIGHT=48
export OF_HIDE_NOTCH=1
export OF_CLOCK_POS=1
export OF_FORCE_ENABLE_ADB=1
export OF_SKIP_ADB_SECURE=1
export FOX_RECOVERY_INSTALL_PARTITION="boot"
export OF_MAINTAINER="manusia"
export FOX_BUILD_TYPE="Unofficial"
export FOX_VERSION="R11.1"
export OF_USE_GREEN_LED=0
export FOX_DELETE_AROMAFM=1
export FOX_ENABLE_APP_MANAGER=0  # Changed to 0 to reduce size
export OF_FBE_METADATA_MOUNT_IGNORE=1
export OF_PATCH_AVB20=1
export OF_DEBUG_MODE=1

# Don't override build date - let the system handle it
export FOX_REPLACE_BOOTIMAGE_DATE=0
export FOX_BUGGED_AOSP_ARB_WORKAROUND=""

echo "OrangeFox build variables loaded for ${DEVICE_CODENAME}"
VENDOR_EOF

cd $WORK_DIR

# Build recovery
echo "--- Setting up build environment... ---"

# Source build environment
if [ -f "build/envsetup.sh" ]; then
    debug_log "Sourcing build/envsetup.sh..."
    source build/envsetup.sh
elif [ -f "build/make/envsetup.sh" ]; then
    debug_log "Sourcing build/make/envsetup.sh..."
    source build/make/envsetup.sh
else
    echo "[ERROR] envsetup.sh not found!"
    exit 1
fi

# Export additional variables - REMOVE duplicate date settings
export DISABLE_ROOMSERVICE=1
export ALLOW_MISSING_DEPENDENCIES=true
export FOX_USE_TWRP_RECOVERY_IMAGE_BUILDER=1
export LC_ALL=C

# Unset any date override variables that might cause duplicates
unset PRODUCT_BUILD_PROP_OVERRIDES
unset ADDITIONAL_BUILD_PROPERTIES

echo "--- Starting build process... ---"
echo "Lunch target: twrp_${DEVICE_CODENAME}-eng"

# Try lunch
lunch twrp_${DEVICE_CODENAME}-eng || lunch omni_${DEVICE_CODENAME}-eng || {
    echo "[ERROR] Lunch failed!"
    exit 1
}

# Clean previous builds
echo "--- Cleaning old builds... ---"
make clean || true

# Build recovery/boot image
echo "--- Building $TARGET_RECOVERY_IMAGE image... ---"
if [ "$TARGET_RECOVERY_IMAGE" = "boot" ]; then
    echo "Building boot image..."
    # Use make instead of mka to avoid property conflicts
    make bootimage -j$(nproc --all) 2>&1 | tee build.log || {
        echo "Build failed, checking for partial outputs..."
    }
else
    echo "Building recovery image..."
    make recoveryimage -j$(nproc --all) 2>&1 | tee build.log || {
        echo "Build failed, checking for partial outputs..."
    }
fi

# Check build output
echo "--- Checking build output... ---"
OUTPUT_DIR="out/target/product/$DEVICE_CODENAME"

# Check multiple possible locations
POSSIBLE_OUTPUTS=(
    "$OUTPUT_DIR/boot.img"
    "$OUTPUT_DIR/recovery.img"
    "$OUTPUT_DIR/recovery/root/boot.img"
    "$OUTPUT_DIR/obj/PACKAGING/target_files_intermediates/*/IMAGES/boot.img"
    "$OUTPUT_DIR/obj/PACKAGING/target_files_intermediates/*/IMAGES/recovery.img"
)

OUTPUT_FOUND=""
for OUTPUT in "${POSSIBLE_OUTPUTS[@]}"; do
    if [ -f "$OUTPUT" ] || ls $OUTPUT 2>/dev/null; then
        OUTPUT_FOUND=$(ls $OUTPUT 2>/dev/null | head -1)
        break
    fi
done

if [ -n "$OUTPUT_FOUND" ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Image built successfully!"
    echo "Location: $OUTPUT_FOUND"
    
    # Create output directory
    mkdir -p /tmp/cirrus-ci-build/output
    cp "$OUTPUT_FOUND" /tmp/cirrus-ci-build/output/OrangeFox-${FOX_VERSION:-R11.1}-${DEVICE_CODENAME}-$(date +%Y%m%d).img
    
    # Generate checksums
    cd /tmp/cirrus-ci-build/output
    sha256sum *.img > sha256sums.txt
    md5sum *.img > md5sums.txt
    
    echo "Output files:"
    ls -lah /tmp/cirrus-ci-build/output/
else
    echo -e "${RED}[ERROR]${NC} Build failed! No output image found"
    echo "Checking for partial outputs..."
    find out/ -name "*.img" -type f 2>/dev/null || true
    echo ""
    echo "Last 100 lines of build.log:"
    tail -100 build.log
    
    # Show actual error
    echo ""
    echo "Searching for actual error in log:"
    grep -i "error\|failed" build.log | tail -20
    exit 1
fi

echo "================================================"
echo "     Build Complete!                            "
echo "================================================"
