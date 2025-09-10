Baik, saya akan buat ulang perbaikan yang komplit untuk build OrangeFox Recovery Android 11 dengan target boot.img untuk MT6761. Semua file tambahan akan dibuat melalui script.

## 1. **build_twrp.sh** (Script Lengkap dengan Pembuatan File Otomatis)

```bash
#!/bin/bash
#
# Skrip Build OrangeFox Recovery untuk Android 11 - MT6761
# Target: boot.img (A/B device)
# =======================================================================

set -e

# Parse arguments
DEVICE_TREE_URL="${1:-https://github.com/manusia251/twrp-test.git}"
DEVICE_TREE_BRANCH="${2:-main}"
DEVICE_CODENAME="${3:-X6512}"
MANIFEST_BRANCH="${4:-fox_11.0}"
BUILD_TARGET="${5:-boot}"
VENDOR_NAME="infinix"

# Export OrangeFox variables
export FOX_VERSION="R11.1_1"
export FOX_BUILD_TYPE="Stable"
export OF_MAINTAINER="manusia251"

echo "========================================"
echo "Memulai Build OrangeFox Recovery"
echo "----------------------------------------"
echo "Manifest Branch  : ${MANIFEST_BRANCH}"
echo "Device Tree URL  : ${DEVICE_TREE_URL}"
echo "Device Branch    : ${DEVICE_TREE_BRANCH}"
echo "Device Codename  : ${DEVICE_CODENAME}"
echo "Build Target     : ${BUILD_TARGET}image"
echo "Versi OrangeFox  : ${FOX_VERSION}"
echo "========================================"

# Setup working directory
WORKDIR=$(pwd)
export GITHUB_WORKSPACE=$WORKDIR

echo "--- Membuat dan masuk ke direktori build... ---"
mkdir -p "$WORKDIR/orangefox"
cd "$WORKDIR/orangefox"

# Configure git
git config --global user.name "manusia251"
git config --global user.email "darkside@gmail.com"

# Clone OrangeFox sync script
echo "--- Clone OrangeFox sync script... ---"
git clone https://gitlab.com/OrangeFox/sync.git -b master sync_dir || {
    echo "--- Trying alternative sync method... ---"
    git clone https://gitlab.com/OrangeFox/sync.git sync_dir
}

cd sync_dir

# Sync OrangeFox source
echo "--- Sinkronisasi source code OrangeFox... ---"
if [ -f "orangefox_sync.sh" ]; then
    bash orangefox_sync.sh --branch ${MANIFEST_BRANCH} --path ../
else
    # Fallback to manual sync
    cd ..
    repo init -u https://gitlab.com/OrangeFox/Manifest.git -b ${MANIFEST_BRANCH}
    repo sync -j8 --force-sync
fi

cd "$WORKDIR/orangefox"

# Clone device tree
echo "--- Clone device tree... ---"
git clone ${DEVICE_TREE_URL} -b ${DEVICE_TREE_BRANCH} device/${VENDOR_NAME}/${DEVICE_CODENAME}

# Navigate to device tree
DEVICE_PATH="device/${VENDOR_NAME}/${DEVICE_CODENAME}"
cd "$DEVICE_PATH"

echo "--- Memperbaiki BoardConfig.mk untuk OrangeFox... ---"
# Backup original BoardConfig.mk
cp BoardConfig.mk BoardConfig.mk.bak

# Create updated BoardConfig.mk with OrangeFox configurations
cat > BoardConfig.mk << 'EOF'
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
BOARD_AVB_RECOVERY_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_RECOVERY_ALGORITHM := SHA256_RSA4096
BOARD_AVB_RECOVERY_ROLLBACK_INDEX := 1
BOARD_AVB_RECOVERY_ROLLBACK_INDEX_LOCATION := 1

# Recovery fstab
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery/root/system/etc/recovery.fstab

# TWRP specific build flags
TW_THEME := portrait_hdpi
TW_EXTRA_LANGUAGES := true
TW_SCREEN_BLANK_ON_BOOT := true
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

# Device specific flags for MT6761
TW_CUSTOM_CPU_TEMP_PATH := /sys/class/thermal/thermal_zone0/temp
TARGET_USE_CUSTOM_LUN_FILE_PATH := /config/usb_gadget/g1/functions/mass_storage.0/lun.%d/file
TW_EXCLUDE_APEX := true

# Debug flags
TARGET_USES_LOGD := true
TWRP_INCLUDE_LOGCAT := true
EOF

echo "--- Membuat init.recovery.mt6761.rc untuk touchscreen support... ---"
mkdir -p recovery/root
cat > recovery/root/init.recovery.mt6761.rc << 'EOF'
on init
    # Mount debugfs
    mount debugfs debugfs /sys/kernel/debug
    chmod 0755 /sys/kernel/debug
    
    # Setup touchscreen
    write /sys/devices/platform/soc/11010000.spi2/spi_master/spi2/spi2.0/input/input0/enabled 1
    chmod 0666 /dev/input/event0
    chmod 0666 /dev/input/event1
    chmod 0666 /dev/input/event2
    chmod 0666 /dev/input/event3
    
    # Try to load touchscreen module
    insmod /vendor/lib/modules/omnivision_tcm.ko
    insmod /sbin/omnivision_tcm.ko
    
on boot
    # Enable all input devices
    write /proc/sys/kernel/sysrq 0
    
    # Touchscreen reset sequence
    write /sys/kernel/touchscreen/reset 1
    write /sys/kernel/touchscreen/enable 1
    
    # Alternative touch paths for MT6761
    write /sys/devices/platform/touch/enable 1
    write /proc/touchpanel/oppo_tp_direction 0
    
service touch_fix /sbin/sh -c "echo 1 > /sys/devices/platform/soc/11010000.spi2/spi_master/spi2/spi2.0/input/input0/enabled"
    oneshot
    disabled
    user root
    group root
    seclabel u:r:recovery:s0

on property:recovery.service=main
    start touch_fix
EOF

echo "--- Membuat vendorsetup.sh untuk OrangeFox... ---"
cat > vendorsetup.sh << 'EOF'
#
# OrangeFox Variables for X6512
#

# Maintainer info
export OF_MAINTAINER="manusia251"
export FOX_VERSION="R11.1_1"
export FOX_BUILD_TYPE="Stable"

# Device info
export TARGET_DEVICE_ALT="X6512,Infinix-X6512"
export FOX_AB_DEVICE=1
export FOX_VIRTUAL_AB_DEVICE=0
export OF_AB_DEVICE_WITH_RECOVERY_PARTITION=0

# Build settings
export FOX_USE_TWRP_RECOVERY_IMAGE_BUILDER=1
export OF_USE_MAGISKBOOT=1
export OF_USE_MAGISKBOOT_FOR_ALL_PATCHES=1
export OF_NO_RELOAD_AFTER_DECRYPTION=1
export OF_PATCH_AVB20=1

# Screen settings
export OF_SCREEN_H=1612
export OF_SCREEN_W=720
export OF_STATUS_H=80
export OF_STATUS_INDENT_LEFT=48
export OF_STATUS_INDENT_RIGHT=48
export OF_HIDE_NOTCH=1
export OF_CLOCK_POS=1

# Navigation
export OF_USE_KEY_HANDLER=1
export OF_KEY_NAVIGATION=1

# Features
export OF_FLASHLIGHT_ENABLE=1
export OF_USE_GREEN_LED=0
export OF_QUICK_BACKUP_LIST="/boot;/data;"
export OF_PATCH_VBMETA_FLAG=1
export OF_USE_SYSTEM_FINGERPRINT=1
export OF_SKIP_MULTIUSER_FOLDERS_BACKUP=1
export OF_FBE_METADATA_MOUNT_IGNORE=1

# Display options
export OF_ALLOW_DISABLE_NAVBAR=0
export OF_USE_LOCKSCREEN_BUTTON=1
export OF_NO_SPLASH_CHANGE=1

# Additional tools
export FOX_USE_BASH_SHELL=1
export FOX_ASH_IS_BASH=1
export FOX_USE_NANO_EDITOR=1
export FOX_USE_TAR_BINARY=1
export FOX_USE_SED_BINARY=1
export FOX_USE_XZ_UTILS=1
export OF_ENABLE_LPTOOLS=1
export FOX_DELETE_AROMAFM=1
export FOX_ENABLE_APP_MANAGER=1

# Build type
export FOX_BUILD_TYPE=Stable
export OF_MAINTAINER_AVATAR="$HOME/maintainer.png"

echo "OrangeFox environment variables loaded for X6512"
EOF

echo "--- Kembali ke direktori build root... ---"
cd "$WORKDIR/orangefox"

# Source and export OrangeFox variables
echo "--- Setting up build environment... ---"
source build/envsetup.sh

# Export critical variables for OrangeFox
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL="C"
export FOX_USE_TWRP_RECOVERY_IMAGE_BUILDER=1
export OF_AB_DEVICE=1
export TARGET_DEVICE_ALT="X6512,Infinix-X6512"
export OF_USE_MAGISKBOOT_FOR_ALL_PATCHES=1
export OF_DONT_PATCH_ENCRYPTED_DEVICE=1
export OF_NO_TREBLE_COMPATIBILITY_CHECK=1
export OF_PATCH_AVB20=1
export OF_USE_KEY_HANDLER=1
export OF_KEY_NAVIGATION=1
export OF_FLASHLIGHT_ENABLE=1
export OF_SCREEN_H=1612
export OF_SCREEN_W=720

# Lunch target
echo "--- Running lunch for omni_${DEVICE_CODENAME}-eng... ---"
lunch omni_${DEVICE_CODENAME}-eng || {
    echo "Lunch failed, trying alternative..."
    lunch aosp_${DEVICE_CODENAME}-eng
}

# Build
echo "--- Starting compilation: make ${BUILD_TARGET}image... ---"
mka ${BUILD_TARGET}image -j$(nproc --all) || {
    echo "Build failed with mka, trying make..."
    make ${BUILD_TARGET}image -j$(nproc --all)
}

# Copy output
echo "--- Preparing build output... ---"
RESULT_DIR="$WORKDIR/orangefox/out/target/product/${DEVICE_CODENAME}"
OUTPUT_DIR="$WORKDIR/output"
mkdir -p "$OUTPUT_DIR"

# Find and copy all recovery images and zips
echo "--- Searching for output files... ---"
if [ -d "$RESULT_DIR" ]; then
    # Copy boot.img (primary target for A/B device)
    [ -f "$RESULT_DIR/boot.img" ] && cp "$RESULT_DIR/boot.img" "$OUTPUT_DIR/OrangeFox-${FOX_VERSION}-${DEVICE_CODENAME}-boot.img"
    
    # Copy any OrangeFox zips
    find "$RESULT_DIR" -name "OrangeFox*.zip" -exec cp {} "$OUTPUT_DIR/" \;
    
    # Copy recovery.img if exists
    [ -f "$RESULT_DIR/recovery.img" ] && cp "$RESULT_DIR/recovery.img" "$OUTPUT_DIR/OrangeFox-${FOX_VERSION}-${DEVICE_CODENAME}-recovery.img"
    
    # Copy any other img files
    find "$RESULT_DIR" -maxdepth 1 -name "*.img" -exec cp {} "$OUTPUT_DIR/" \;
fi

echo "--- Build completed! Output files: ---"
ls -lh "$OUTPUT_DIR"
echo "========================================"
```

## 2. **.cirrus.yml** (Tetap sama, tidak perlu diubah)

File .cirrus.yml yang kamu berikan sudah benar dan tidak perlu diubah. Script build_twrp.sh akan menangani semua perubahan yang diperlukan.

## Penjelasan Perbaikan:

1. **Script Otomatis**: Semua file yang diperlukan (BoardConfig.mk yang diperbaiki, init.recovery.mt6761.rc, vendorsetup.sh) dibuat otomatis oleh script.

2. **Touchscreen Support**: 
   - Menambahkan init script untuk MT6761 yang akan mencoba mengaktifkan touchscreen Omnivision TCM SPI
   - Multiple fallback paths untuk berbagai kemungkinan lokasi driver

3. **Non-Touch Navigation**:
   - Volume Up/Down: Navigasi
   - Power Button: Select
   - Diaktifkan melalui OF_USE_KEY_HANDLER dan OF_KEY_NAVIGATION

4. **A/B Device Support**:
   - Target boot.img (bukan recovery.img)
   - Flag FOX_AB_DEVICE=1
   - BOARD_USES_RECOVERY_AS_BOOT := true

5. **MT6761 Specific**:
   - Platform settings yang tepat
   - CPU temp path yang benar
   - USB gadget configuration

Script ini akan otomatis:
- Clone OrangeFox source
- Setup device tree
- Patch semua file yang diperlukan
- Build boot.img dengan OrangeFox
- Copy hasil ke folder output

Navigasi tanpa touchscreen akan otomatis aktif, dan touchscreen akan dicoba untuk diaktifkan saat boot recovery.
