#!/bin/bash
#
# Skrip Build OrangeFox Recovery untuk Android 11 - MT6761
# Target: boot.img (A/B device)
# =======================================================================

set -e

# Enable debugging
set -x

# Parse arguments
DEVICE_TREE_URL="${1:-https://github.com/manusia251/twrp-test.git}"
DEVICE_TREE_BRANCH="${2:-main}"
DEVICE_CODENAME="${3:-X6512}"
MANIFEST_BRANCH="${4:-fox_11.0}"  # Will be converted to correct format
BUILD_TARGET="${5:-boot}"
VENDOR_NAME="infinix"

# Fix manifest branch name for OrangeFox
echo "[DEBUG] Original MANIFEST_BRANCH: $MANIFEST_BRANCH"
if [[ "$MANIFEST_BRANCH" == "fox_11.0" ]] || [[ "$MANIFEST_BRANCH" == "11.0" ]]; then
    ORANGEFOX_BRANCH="11.0"
elif [[ "$MANIFEST_BRANCH" == "fox_12.1" ]] || [[ "$MANIFEST_BRANCH" == "12.1" ]]; then
    ORANGEFOX_BRANCH="12.1"
else
    ORANGEFOX_BRANCH="11.0"  # Default to Android 11
fi
echo "[DEBUG] Using OrangeFox branch: $ORANGEFOX_BRANCH"

# Export OrangeFox variables
export FOX_VERSION="R11.1_1"
export FOX_BUILD_TYPE="Stable"
export OF_MAINTAINER="manusia251"

echo "========================================"
echo "Memulai Build OrangeFox Recovery"
echo "----------------------------------------"
echo "Manifest Branch  : ${ORANGEFOX_BRANCH}"
echo "Device Tree URL  : ${DEVICE_TREE_URL}"
echo "Device Branch    : ${DEVICE_TREE_BRANCH}"
echo "Device Codename  : ${DEVICE_CODENAME}"
echo "Build Target     : ${BUILD_TARGET}image"
echo "Versi OrangeFox  : ${FOX_VERSION}"
echo "========================================"

# Setup working directory
WORKDIR=$(pwd)
export GITHUB_WORKSPACE=$WORKDIR

echo "[DEBUG] Current working directory: $WORKDIR"
echo "[DEBUG] Creating build directory..."

mkdir -p "$WORKDIR/orangefox"
cd "$WORKDIR/orangefox"

echo "[DEBUG] Now in directory: $(pwd)"

# Configure git
git config --global user.name "manusia251"
git config --global user.email "darkside@gmail.com"

# Clone OrangeFox sync script
echo "--- Clone OrangeFox sync script... ---"
echo "[DEBUG] Cloning from: https://gitlab.com/OrangeFox/sync.git"

if [ -d "sync_dir" ]; then
    echo "[DEBUG] sync_dir already exists, removing..."
    rm -rf sync_dir
fi

git clone https://gitlab.com/OrangeFox/sync.git -b master sync_dir || {
    echo "[DEBUG] Failed to clone with master branch, trying without branch..."
    git clone https://gitlab.com/OrangeFox/sync.git sync_dir
}

if [ ! -d "sync_dir" ]; then
    echo "[ERROR] Failed to clone sync repository!"
    exit 1
fi

cd sync_dir
echo "[DEBUG] Contents of sync_dir:"
ls -la

# Check available branches in orangefox_sync.sh
echo "[DEBUG] Checking supported branches in orangefox_sync.sh..."
if [ -f "orangefox_sync.sh" ]; then
    grep -E "14\.1|12\.1|11\.0|10\.0" orangefox_sync.sh || true
fi

# Sync OrangeFox source
echo "--- Sinkronisasi source code OrangeFox... ---"

# Get absolute path for sync
SYNC_PATH=$(realpath ../)
echo "[DEBUG] Sync path: $SYNC_PATH"

if [ -f "orangefox_sync.sh" ]; then
    echo "[DEBUG] Found orangefox_sync.sh, checking if branch $ORANGEFOX_BRANCH is supported..."
    
    # Check if the branch is supported
    if grep -q "$ORANGEFOX_BRANCH" orangefox_sync.sh; then
        echo "[DEBUG] Branch $ORANGEFOX_BRANCH is supported, syncing..."
        bash orangefox_sync.sh --branch ${ORANGEFOX_BRANCH} --path ${SYNC_PATH}
    else
        echo "[WARNING] Branch $ORANGEFOX_BRANCH not found in orangefox_sync.sh"
        echo "[DEBUG] Trying with branch 12.1 (closest to Android 11)..."
        bash orangefox_sync.sh --branch 12.1 --path ${SYNC_PATH} || {
            echo "[ERROR] orangefox_sync.sh failed with branch 12.1"
            echo "[DEBUG] Available options in orangefox_sync.sh:"
            bash orangefox_sync.sh --help || true
        }
    fi
else
    echo "[DEBUG] orangefox_sync.sh not found, using manual repo sync..."
    cd ..
    
    # Install repo if not available
    if ! command -v repo &> /dev/null; then
        echo "[DEBUG] Installing repo tool..."
        curl https://storage.googleapis.com/git-repo-downloads/repo > /usr/local/bin/repo
        chmod +x /usr/local/bin/repo
    fi
    
    echo "[DEBUG] Trying different manifest URLs..."
    
    # Try different manifest URLs
    MANIFEST_URLS=(
        "https://gitlab.com/OrangeFox/Manifest.git"
        "https://github.com/OrangeFoxRecovery/OrangeFox-Manifest.git"
        "https://gitlab.com/OrangeFox/fox_manifest.git"
    )
    
    SYNC_SUCCESS=0
    for MANIFEST_URL in "${MANIFEST_URLS[@]}"; do
        echo "[DEBUG] Trying manifest: $MANIFEST_URL with branch $ORANGEFOX_BRANCH"
        
        # Remove existing .repo if exists
        rm -rf .repo
        
        if repo init -u "$MANIFEST_URL" -b "$ORANGEFOX_BRANCH" --depth=1 2>/dev/null; then
            echo "[DEBUG] Repo init successful with $MANIFEST_URL"
            
            echo "[DEBUG] Starting repo sync..."
            if repo sync -c --force-sync --no-tags --no-clone-bundle -j4; then
                echo "[DEBUG] Sync successful!"
                SYNC_SUCCESS=1
                break
            else
                echo "[WARNING] Sync failed with $MANIFEST_URL"
            fi
        else
            echo "[WARNING] Init failed with $MANIFEST_URL branch $ORANGEFOX_BRANCH"
        fi
    done
    
    if [ $SYNC_SUCCESS -eq 0 ]; then
        echo "[ERROR] All manifest sync attempts failed!"
        echo "[DEBUG] Trying alternative: TWRP minimal manifest for Android 11..."
        
        rm -rf .repo
        repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-11 --depth=1
        repo sync -c --force-sync --no-tags --no-clone-bundle -j4 || {
            echo "[ERROR] TWRP manifest sync also failed!"
            exit 1
        }
        
        echo "[DEBUG] Cloning OrangeFox vendor..."
        git clone https://gitlab.com/OrangeFox/vendor/recovery.git -b master vendor/recovery || {
            echo "[WARNING] Failed to clone OrangeFox vendor"
        }
    fi
fi

cd "$WORKDIR/orangefox"

echo "[DEBUG] Checking build system files..."
echo "[DEBUG] Looking for build/envsetup.sh..."

# Check multiple possible locations
ENVSETUP_LOCATIONS=(
    "build/envsetup.sh"
    "build/make/envsetup.sh"
    "build/soong/envsetup.sh"
)

ENVSETUP_FOUND=""
for LOCATION in "${ENVSETUP_LOCATIONS[@]}"; do
    if [ -f "$LOCATION" ]; then
        ENVSETUP_FOUND="$LOCATION"
        echo "[DEBUG] Found envsetup.sh at: $LOCATION"
        break
    fi
done

if [ -z "$ENVSETUP_FOUND" ]; then
    echo "[ERROR] envsetup.sh not found!"
    echo "[DEBUG] Current directory structure:"
    ls -la
    echo "[DEBUG] Contents of subdirectories:"
    for dir in */; do
        echo "[DEBUG] Directory: $dir"
        ls -la "$dir" 2>/dev/null | head -5
    done
    
    echo "[DEBUG] Searching for any envsetup.sh file..."
    find . -name "envsetup.sh" -type f 2>/dev/null | head -10
    
    echo "[ERROR] Build environment not properly synced. Exiting."
    exit 1
fi

# Clone device tree
echo "--- Clone device tree... ---"
DEVICE_TREE_PATH="device/${VENDOR_NAME}/${DEVICE_CODENAME}"

if [ -d "$DEVICE_TREE_PATH" ]; then
    echo "[DEBUG] Device tree already exists, removing..."
    rm -rf "$DEVICE_TREE_PATH"
fi

echo "[DEBUG] Cloning device tree to: $DEVICE_TREE_PATH"
git clone ${DEVICE_TREE_URL} -b ${DEVICE_TREE_BRANCH} ${DEVICE_TREE_PATH}

if [ ! -d "$DEVICE_TREE_PATH" ]; then
    echo "[ERROR] Failed to clone device tree!"
    exit 1
fi

# Navigate to device tree
cd "$DEVICE_TREE_PATH"
echo "[DEBUG] Device tree contents:"
ls -la

echo "--- Memperbaiki BoardConfig.mk untuk OrangeFox... ---"
if [ -f "BoardConfig.mk" ]; then
    echo "[DEBUG] Backing up original BoardConfig.mk..."
    cp BoardConfig.mk BoardConfig.mk.bak
fi

# Create updated BoardConfig.mk with OrangeFox configurations
cat > BoardConfig.mk << 'BOARDCONFIG_EOF'
#
# Copyright (C) 2025 The Android Open Source Project
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/infinix/X6512

# For building with minimal manifest
ALLOW_MISSING_DEPENDENCIES := true

# A/B
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \
    vbmeta_system \
    vbmeta_vendor \
    boot \
    system \
    product \
    system_ext \
    vendor
BOARD_USES_RECOVERY_AS_BOOT := true

# Architecture
TARGET_ARCH := arm
TARGET_ARCH_VARIANT := armv7-a-neon
TARGET_CPU_ABI := armeabi-v7a
TARGET_CPU_ABI2 := armeabi
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a53

TARGET_USES_64_BIT_BINDER := true

# APEX
OVERRIDE_TARGET_FLATTEN_APEX := true

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := mt6761
TARGET_NO_BOOTLOADER := true

# Display
TARGET_SCREEN_DENSITY := 320

# Kernel
BOARD_BOOTIMG_HEADER_VERSION := 2
BOARD_KERNEL_BASE := 0x40000000
BOARD_KERNEL_CMDLINE := bootopt=64S3,32S1,32S1 buildvariant=user
BOARD_KERNEL_PAGESIZE := 2048
BOARD_RAMDISK_OFFSET := 0x11b00000
BOARD_KERNEL_TAGS_OFFSET := 0x07880000
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_KERNEL_IMAGE_NAME := Image
BOARD_INCLUDE_DTB_IN_BOOTIMG := true

# Kernel - prebuilt
TARGET_FORCE_PREBUILT_KERNEL := true
ifeq ($(TARGET_FORCE_PREBUILT_KERNEL),true)
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
TARGET_PREBUILT_DTB := $(DEVICE_PATH)/prebuilt/dtb.img
BOARD_MKBOOTIMG_ARGS += --dtb $(TARGET_PREBUILT_DTB)
BOARD_INCLUDE_DTB_IN_BOOTIMG := 
endif

# Partitions
BOARD_FLASH_BLOCK_SIZE := 131072
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_SYSTEMIMAGE_PARTITION_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
TARGET_COPY_OUT_VENDOR := vendor
BOARD_SUPER_PARTITION_SIZE := 9126805504
BOARD_SUPER_PARTITION_GROUPS := infinix_dynamic_partitions
BOARD_INFINIX_DYNAMIC_PARTITIONS_PARTITION_LIST := system system_ext vendor product
BOARD_INFINIX_DYNAMIC_PARTITIONS_SIZE := 9122611200

# Platform
TARGET_BOARD_PLATFORM := mt6761

# Recovery
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"

# Security patch level
VENDOR_SECURITY_PATCH := 2099-12-31
PLATFORM_SECURITY_PATCH := 2099-12-31
PLATFORM_VERSION := 16.1.0

# Verified Boot
BOARD_AVB_ENABLE := true
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 3

# Recovery fstab
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery/root/system/etc/recovery.fstab

# TWRP/OrangeFox Configuration
TW_THEME := portrait_hdpi
TW_EXTRA_LANGUAGES := true
TW_SCREEN_BLANK_ON_BOOT := false
TW_INPUT_BLACKLIST := "hbtp_vm"
RECOVERY_SDCARD_ON_DATA := true
TW_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"
TW_MAX_BRIGHTNESS := 255
TW_DEFAULT_BRIGHTNESS := 120
TW_INCLUDE_NTFS_3G := true
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_REPACKTOOLS := true
TW_HAS_MTP := true
TW_USE_TOOLBOX := true

# Navigation without touchscreen
BOARD_HAS_NO_SELECT_BUTTON := true
TW_NO_SCREEN_TIMEOUT := true
TW_NO_SCREEN_BLANK := true

# MT6761 specific
TW_CUSTOM_CPU_TEMP_PATH := /sys/class/thermal/thermal_zone0/temp
TARGET_USE_CUSTOM_LUN_FILE_PATH := /config/usb_gadget/g1/functions/mass_storage.0/lun.%d/file
TW_EXCLUDE_APEX := true

# Debug
TARGET_USES_LOGD := true
TWRP_INCLUDE_LOGCAT := true
BOARDCONFIG_EOF

echo "[DEBUG] BoardConfig.mk updated"

echo "--- Creating touchscreen init file... ---"
mkdir -p recovery/root
cat > recovery/root/init.recovery.mt6761.rc << 'INIT_EOF'
on init
    # Touchscreen setup for Omnivision TCM SPI
    write /sys/devices/platform/soc/11010000.spi2/spi_master/spi2/spi2.0/input/input0/enabled 1
    chmod 0666 /dev/input/event0
    chmod 0666 /dev/input/event1
    chmod 0666 /dev/input/event2
    
on boot
    write /sys/kernel/touchscreen/enable 1
    write /proc/touchpanel/oppo_tp_direction 0
INIT_EOF

echo "[DEBUG] init.recovery.mt6761.rc created"

# Return to build root
cd "$WORKDIR/orangefox"
echo "[DEBUG] Back to build root: $(pwd)"

# Source build environment
echo "--- Setting up build environment... ---"
if [ -n "$ENVSETUP_FOUND" ]; then
    echo "[DEBUG] Sourcing $ENVSETUP_FOUND"
    source "$ENVSETUP_FOUND"
else
    echo "[DEBUG] Trying default location build/envsetup.sh"
    source build/envsetup.sh
fi

echo "[DEBUG] Checking available lunch targets..."
lunch 2>&1 | grep -E "${DEVICE_CODENAME}" | head -5 || true

# Export OrangeFox variables
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL="C"
export FOX_USE_TWRP_RECOVERY_IMAGE_BUILDER=1
export OF_AB_DEVICE=1
export OF_USE_MAGISKBOOT_FOR_ALL_PATCHES=1
export OF_USE_KEY_HANDLER=1
export OF_KEY_NAVIGATION=1

# Try lunch
echo "--- Running lunch... ---"
LUNCH_TARGET="omni_${DEVICE_CODENAME}-eng"
echo "[DEBUG] Trying: $LUNCH_TARGET"

lunch $LUNCH_TARGET || {
    echo "[WARNING] $LUNCH_TARGET failed, trying alternatives..."
    
    # Try other variants
    for variant in "aosp_${DEVICE_CODENAME}-eng" "twrp_${DEVICE_CODENAME}-eng" "lineage_${DEVICE_CODENAME}-eng"; do
        echo "[DEBUG] Trying: $variant"
        if lunch $variant 2>/dev/null; then
            echo "[DEBUG] Lunch successful with $variant"
            break
        fi
    done
}

# Build
echo "--- Starting build... ---"
echo "[DEBUG] Building ${BUILD_TARGET}image with $(nproc) cores"

mka ${BUILD_TARGET}image -j$(nproc) || {
    echo "[WARNING] mka failed, trying make..."
    make ${BUILD_TARGET}image -j$(nproc) || {
        echo "[ERROR] Build failed!"
        exit 1
    }
}

# Copy output
echo "--- Copying output files... ---"
RESULT_DIR="$WORKDIR/orangefox/out/target/product/${DEVICE_CODENAME}"
OUTPUT_DIR="$WORKDIR/output"
mkdir -p "$OUTPUT_DIR"

echo "[DEBUG] Looking for files in: $RESULT_DIR"
if [ -d "$RESULT_DIR" ]; then
    ls -la "$RESULT_DIR" | grep -E "\.img|\.zip" || true
    
    # Copy boot.img
    [ -f "$RESULT_DIR/boot.img" ] && cp "$RESULT_DIR/boot.img" "$OUTPUT_DIR/"
    
    # Copy other images
    find "$RESULT_DIR" -maxdepth 1 -name "*.img" -o -name "*.zip" 2>/dev/null | while read file; do
        echo "[DEBUG] Copying: $(basename $file)"
        cp "$file" "$OUTPUT_DIR/"
    done
fi

echo "--- Build completed! ---"
ls -lh "$OUTPUT_DIR" 2>/dev/null || echo "[WARNING] No output files"
echo "========================================"

set +x
