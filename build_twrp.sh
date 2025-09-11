#!/bin/bash
set -e

# Arguments
DEVICE_TREE=$1
DEVICE_BRANCH=$2
DEVICE_CODENAME=$3
MANIFEST_BRANCH=${4:-"twrp-12.1"}
TARGET_RECOVERY_IMAGE=${5:-"boot"}

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
echo "     TWRP Boot Builder for $DEVICE_CODENAME"
echo "     Complete Fix Version"
echo "     Branch: $MANIFEST_BRANCH"
echo "================================================"

# Working directory
WORK_DIR="/tmp/cirrus-ci-build/twrp"
mkdir -p $WORK_DIR
cd $WORK_DIR

# Git config
debug "Configuring git..."
git config --global user.name "manusia"
git config --global user.email "ndktau@gmail.com"

# Install repo
if ! command -v repo &> /dev/null; then
    debug "Installing repo tool..."
    curl https://storage.googleapis.com/git-repo-downloads/repo > /tmp/repo
    chmod a+x /tmp/repo
    mv /tmp/repo /usr/local/bin/repo || true
fi

# Initialize TWRP manifest
debug "Initializing TWRP manifest (branch: $MANIFEST_BRANCH)..."
repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b $MANIFEST_BRANCH --git-lfs || {
    error "Failed to initialize manifest"
    exit 1
}

debug "Syncing source code..."
repo sync -c --force-sync --no-tags --no-clone-bundle -j$(nproc --all) --optimized-fetch --prune || {
    error "Failed to sync source"
    exit 1
}

# Clone device tree
debug "Cloning device tree from $DEVICE_TREE..."
DEVICE_PATH="device/infinix/$DEVICE_CODENAME"
rm -rf $DEVICE_PATH
git clone $DEVICE_TREE -b $DEVICE_BRANCH $DEVICE_PATH || {
    error "Failed to clone device tree"
    exit 1
}

# Create necessary directories
mkdir -p $DEVICE_PATH/recovery/root
mkdir -p $DEVICE_PATH/recovery/root/system/etc
mkdir -p $DEVICE_PATH/recovery/root/first_stage_ramdisk

# BoardConfig.mk - Using exact params from working TWRP
debug "Creating BoardConfig.mk with exact working parameters..."
cat >> $DEVICE_PATH/BoardConfig.mk << 'EOF'

# Platform
TARGET_BOARD_PLATFORM := mt6761
TARGET_BOOTLOADER_BOARD_NAME := mt6761
BOARD_HAS_MTK_HARDWARE := true
BOARD_USES_MTK_HARDWARE := true

# Architecture
TARGET_ARCH := arm
TARGET_ARCH_VARIANT := armv7-a-neon
TARGET_CPU_ABI := armeabi-v7a
TARGET_CPU_ABI2 := armeabi
TARGET_CPU_VARIANT := cortex-a53

# Kernel
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
BOARD_PREBUILT_DTBIMAGE_DIR := $(DEVICE_PATH)/prebuilt
BOARD_INCLUDE_DTB_IN_BOOTIMG := true

# Boot header - EXACT from working TWRP
BOARD_BOOT_HEADER_VERSION := 2
BOARD_KERNEL_BASE := 0x40000000
BOARD_KERNEL_CMDLINE := bootopt=64S3,32S1,32S twrpfastboot=1 buildvariant=eng
BOARD_KERNEL_PAGESIZE := 2048
BOARD_RAMDISK_OFFSET := 0x11b00000
BOARD_KERNEL_TAGS_OFFSET := 0x07880000
BOARD_DTB_OFFSET := 0x01f00000  # Different from tags offset!
BOARD_KERNEL_OFFSET := 0x00008000
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb_offset $(BOARD_DTB_OFFSET)
BOARD_MKBOOTIMG_ARGS += --kernel_offset $(BOARD_KERNEL_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb $(DEVICE_PATH)/prebuilt/dtb.img

# Partitions
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_USES_METADATA_PARTITION := true
BOARD_ROOT_EXTRA_FOLDERS += metadata

# Dynamic Partitions
BOARD_SUPER_PARTITION_SIZE := 4722786304
BOARD_SUPER_PARTITION_GROUPS := infinix_dynamic_partitions
BOARD_INFINIX_DYNAMIC_PARTITIONS_SIZE := 4720689152
BOARD_INFINIX_DYNAMIC_PARTITIONS_PARTITION_LIST := system system_ext vendor product

# File systems
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

# Recovery
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_USES_RECOVERY_AS_BOOT := true
TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery/root/system/etc/recovery.fstab

# IMPORTANT: No system as root!
BOARD_BUILD_SYSTEM_ROOT_IMAGE := false

# Virtual A/B
ENABLE_VIRTUAL_AB := true
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += boot system system_ext vendor product

# TWRP Configuration
TW_THEME := portrait_hdpi
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_REPACKTOOLS := true
TW_EXTRA_LANGUAGES := false
TW_DEFAULT_LANGUAGE := en

# Fix mount issues
TARGET_RECOVERY_DEVICE_DIRS += $(DEVICE_PATH)
TW_INCLUDE_LOGICAL := true
TW_EXCLUDE_APEX := true

# Paths
TARGET_USE_CUSTOM_LUN_FILE_PATH := /config/usb_gadget/g1/functions/mass_storage.usb0/lun.%d/file
TW_EXCLUDE_DEFAULT_USB_INIT := true
RECOVERY_SDCARD_ON_DATA := true

# Storage
TW_INTERNAL_STORAGE_PATH := "/data/media/0"
TW_INTERNAL_STORAGE_MOUNT_POINT := "data"
TW_EXTERNAL_STORAGE_PATH := "/external_sd"
TW_EXTERNAL_STORAGE_MOUNT_POINT := "external_sd"

# Crypto
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true
TW_USE_FSCRYPT_POLICY := 2
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := 2099-12-31

# Trustonic TEE
TRUSTONIC_TEE_SUPPORT := true
MTK_HARDWARE := true

# Debug
TWRP_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true

# MediaTek specific
TW_BRIGHTNESS_PATH := /sys/class/leds/lcd-backlight/brightness
TW_MAX_BRIGHTNESS := 2047
TW_DEFAULT_BRIGHTNESS := 1200
TW_NO_SCREEN_BLANK := true
EOF

# Create first_stage_ramdisk fstab (from extract)
debug "Creating first_stage_ramdisk fstab..."
cat > $DEVICE_PATH/recovery/root/first_stage_ramdisk/fstab.mt6761 << 'FSTAB_EOF'
system /system ext4 ro wait,avb=vbmeta_system,logical,first_stage_mount,avb_keys=/avb/q-gsi.avbpubkey:/avb/r-gsi.avbpubkey:/avb/s-gsi.avbpubkey,slotselect
system_ext /system_ext ext4 ro wait,avb,logical,first_stage_mount,slotselect
vendor /vendor ext4 ro wait,avb,logical,first_stage_mount,slotselect
product /product ext4 ro wait,avb,logical,first_stage_mount,slotselect

/dev/block/platform/bootdevice/by-name/md_udc /metadata ext4 noatime,nosuid,nodev,discard wait,check,formattable,first_stage_mount
/dev/block/platform/bootdevice/by-name/userdata /data f2fs noatime,nosuid,nodev,discard,noflush_merge,reserve_root=134217,resgid=1065,inlinecrypt,tran_gc latemount,wait,check,quota,reservedsize=128M,formattable,resize,checkpoint=fs,fileencryption=aes-256-xts:aes-256-cts:v2,keydirectory=/metadata/vold/metadata_encryption,
/dev/block/platform/bootdevice/by-name/tranfs /tranfs ext4 noatime,nosuid,nodev,noauto_da_alloc,discard wait,check,formattable,nofail,first_stage_mount
/dev/block/platform/bootdevice/by-name/protect1 /mnt/vendor/protect_f ext4 noatime,nosuid,nodev,noauto_da_alloc,commit=1,nodelalloc wait,check,formattable
/dev/block/platform/bootdevice/by-name/protect2 /mnt/vendor/protect_s ext4 noatime,nosuid,nodev,noauto_da_alloc,commit=1,nodelalloc wait,check,formattable
/dev/block/platform/bootdevice/by-name/nvdata /mnt/vendor/nvdata ext4 noatime,nosuid,nodev,noauto_da_alloc,commit=1,nodelalloc wait,check,formattable
/dev/block/platform/bootdevice/by-name/nvcfg /mnt/vendor/nvcfg ext4 noatime,nosuid,nodev,noauto_da_alloc,commit=1,nodelalloc wait,check,formattable
/dev/block/platform/bootdevice/by-name/persist /mnt/vendor/persist ext4 noatime,nosuid,nodev,noauto_da_alloc,commit=1,nodelalloc wait,check,formattable

/devices/platform/externdevice* auto auto defaults voldmanaged=sdcard1:auto,encryptable=userdata
/devices/platform/mt_usb* auto vfat defaults voldmanaged=usbotg:auto,encryptable=userdata

/dev/block/platform/bootdevice/by-name/frp /persistent emmc defaults defaults
/dev/block/platform/bootdevice/by-name/nvram /nvram emmc defaults defaults
/dev/block/platform/bootdevice/by-name/proinfo /proinfo emmc defaults defaults
/dev/block/platform/bootdevice/by-name/lk /bootloader emmc defaults defaults
/dev/block/platform/bootdevice/by-name/lk2 /bootloader2 emmc defaults defaults
/dev/block/platform/bootdevice/by-name/para /misc emmc defaults defaults
/dev/block/platform/bootdevice/by-name/boot /boot emmc defaults first_stage_mount,nofail,slotselect
/dev/block/platform/bootdevice/by-name/vbmeta_vendor /vbmeta_vendor emmc defaults first_stage_mount,nofail,slotselect
/dev/block/platform/bootdevice/by-name/vbmeta_system /vbmeta_system emmc defaults first_stage_mount,nofail,slotselect,avb=vbmeta
/dev/block/platform/bootdevice/by-name/logo /logo emmc defaults defaults
/dev/block/platform/bootdevice/by-name/expdb /expdb emmc defaults defaults
/dev/block/platform/bootdevice/by-name/seccfg /seccfg emmc defaults defaults
/dev/block/platform/bootdevice/by-name/tee1 /tee1 emmc defaults defaults
/dev/block/platform/bootdevice/by-name/tee2 /tee2 emmc defaults defaults
/dev/block/platform/bootdevice/by-name/scp1 /scp1 emmc defaults defaults
/dev/block/platform/bootdevice/by-name/scp2 /scp2 emmc defaults defaults
/dev/block/platform/bootdevice/by-name/sspm_1 /sspm_1 emmc defaults defaults
/dev/block/platform/bootdevice/by-name/sspm_2 /sspm_2 emmc defaults defaults
/dev/block/platform/bootdevice/by-name/md1img /md1img emmc defaults defaults
/dev/block/platform/bootdevice/by-name/md1dsp /md1dsp emmc defaults defaults
/dev/block/platform/bootdevice/by-name/gz1 /gz1 emmc defaults defaults
/dev/block/platform/bootdevice/by-name/gz2 /gz2 emmc defaults defaults
/dev/block/platform/bootdevice/by-name/spmfw /spmfw emmc defaults defaults
/dev/block/platform/bootdevice/by-name/boot_para /boot_para emmc defaults defaults
/dev/block/platform/bootdevice/by-name/dtbo1 /dtbo1 emmc defaults defaults
/dev/block/platform/bootdevice/by-name/dtbo2 /dtbo2 emmc defaults defaults
/dev/block/platform/bootdevice/by-name/dtbo /dtbo emmc defaults defaults
/dev/block/platform/bootdevice/by-name/vbmeta /vbmeta emmc defaults defaults
FSTAB_EOF

# Create recovery.fstab with PROPER mount points (fix system_root issue)
debug "Creating recovery.fstab with fixed mount points..."
cat > $DEVICE_PATH/recovery/root/system/etc/recovery.fstab << 'FSTAB_EOF'
# mount point    fstype    device                                                flags
/system          ext4      system                                                flags=display="System";logical;slotselect
/system_ext      ext4      system_ext                                            flags=display="System_ext";logical;slotselect
/vendor          ext4      vendor                                                flags=display="Vendor";logical;slotselect
/product         ext4      product                                               flags=display="Product";logical;slotselect

/metadata        ext4      /dev/block/platform/bootdevice/by-name/md_udc        flags=display="Metadata";backup=1
/data            f2fs      /dev/block/platform/bootdevice/by-name/userdata      flags=fileencryption=aes-256-xts:aes-256-cts:v2+inlinecrypt_optimized,keydirectory=/metadata/vold/metadata_encryption
/tranfs          ext4      /dev/block/platform/bootdevice/by-name/tranfs        flags=display="Tranfs"
/boot            emmc      /dev/block/platform/bootdevice/by-name/boot          flags=display="Boot";backup=1;flashimg=1;slotselect
/misc            emmc      /dev/block/platform/bootdevice/by-name/para          flags=display="Misc"
/cache           ext4      /dev/block/platform/bootdevice/by-name/cache         flags=display="Cache"
FSTAB_EOF

# Create twrp.flags (copy from working)
debug "Creating twrp.flags..."
cat > $DEVICE_PATH/recovery/root/system/etc/twrp.flags << 'FLAGS_EOF'
# Main partitions
/protect_f       ext4      /dev/block/platform/bootdevice/by-name/protect1      flags=display="Protect_f";backup=1
/protect_s       ext4      /dev/block/platform/bootdevice/by-name/protect2      flags=display="Protect_s";backup=1
/nvdata          ext4      /dev/block/platform/bootdevice/by-name/nvdata        flags=display="Nvdata";backup=1
/nvcfg           ext4      /dev/block/platform/bootdevice/by-name/nvcfg         flags=display="Nvcfg";backup=1
/persist         ext4      /dev/block/platform/bootdevice/by-name/persist       flags=display="Persist";backup=1
/persistent      emmc      /dev/block/platform/bootdevice/by-name/frp           flags=display="Persistent";backup=1
/nvram           emmc      /dev/block/platform/bootdevice/by-name/nvram         flags=display="Nvram";backup=1

# Boot partitions
/lk              emmc      /dev/block/platform/bootdevice/by-name/bootloader    flags=display="Bootloader";backup=1
/lk2             emmc      /dev/block/platform/bootdevice/by-name/bootloader2   flags=display="Bootloader2";backup=1
/logo            emmc      /dev/block/platform/bootdevice/by-name/logo          flags=display="Logo";backup=1;slotselect
/dtbo            emmc      /dev/block/platform/bootdevice/by-name/dtbo          flags=display="Dtbo";backup=1

# Trustonic
/tee1            emmc      /dev/block/platform/bootdevice/by-name/tee1          flags=display="Tee1";backup=1
/tee2            emmc      /dev/block/platform/bootdevice/by-name/tee2          flags=display="Tee2";backup=1

# Super partition
/super           emmc      /dev/block/platform/bootdevice/by-name/super         flags=display="Super";backup=1;flashimg=1

# AVB
/vbmeta          emmc      /dev/block/platform/bootdevice/by-name/vbmeta        flags=display="VBMeta";backup=1;flashimg=1;slotselect
/vbmeta_system   emmc      /dev/block/platform/bootdevice/by-name/vbmeta_system flags=display="VBMeta System";backup=1;flashimg=1;slotselect  
/vbmeta_vendor   emmc      /dev/block/platform/bootdevice/by-name/vbmeta_vendor flags=display="VBMeta Vendor";backup=1;flashimg=1;slotselect

# External Storage
/external_sd     auto      /dev/block/mmcblk1p1                                 flags=display="MicroSD Card";storage;wipeingui;removable
/usb-otg         auto      /dev/block/sda1                                      flags=display="USB OTG";storage;wipeingui;removable
FLAGS_EOF

# Create init.recovery.mt6761.rc (copy from working but add mount fixes)
debug "Creating init.recovery.mt6761.rc with mount fixes..."
cat > $DEVICE_PATH/recovery/root/init.recovery.mt6761.rc << 'INIT_EOF'
import /init.recovery.trustonic.rc

on init
    export LD_LIBRARY_PATH /system/lib:/vendor/lib:/vendor/lib/hw:/system/lib/hw
    
    # Create mount directories
    mkdir /system
    mkdir /system_ext
    mkdir /vendor
    mkdir /product

on post-fs
    # Support A/B feature for EMMC boot region
    symlink /dev/block/mmcblk0boot0 /dev/block/platform/bootdevice/by-name/preloader_a
    symlink /dev/block/mmcblk0boot1 /dev/block/platform/bootdevice/by-name/preloader_b

    # Fix OF installer
    symlink /dev/block/platform/bootdevice /dev/block/bootdevice

    # Support A/B feature for combo emmc OTA update
    symlink /dev/block/platform/bootdevice/by-name/preloader_a /dev/block/platform/bootdevice/by-name/preloader_emmc_a
    symlink /dev/block/platform/bootdevice/by-name/preloader_b /dev/block/platform/bootdevice/by-name/preloader_emmc_b
    symlink /dev/block/platform/bootdevice/by-name/preloader_a /dev/block/by-name/preloader_emmc_a
    symlink /dev/block/platform/bootdevice/by-name/preloader_b /dev/block/by-name/preloader_emmc_b

    exec u:r:update_engine:s0 root root -- /system/bin/mtk_plpath_utils
    start mtk.plpath.utils.link

on fs
    install_keyring

    # Wait for logical partitions to be ready
    wait /dev/block/mapper/system${ro.boot.slot_suffix}
    wait /dev/block/mapper/vendor${ro.boot.slot_suffix}
    wait /dev/block/mapper/system_ext${ro.boot.slot_suffix}
    wait /dev/block/mapper/product${ro.boot.slot_suffix}
    
    # Mount logical partitions - FIX: direct to proper mount points
    mount ext4 /dev/block/mapper/system${ro.boot.slot_suffix} /system ro noatime
    mount ext4 /dev/block/mapper/vendor${ro.boot.slot_suffix} /vendor ro noatime
    mount ext4 /dev/block/mapper/system_ext${ro.boot.slot_suffix} /system_ext ro noatime
    mount ext4 /dev/block/mapper/product${ro.boot.slot_suffix} /product ro noatime

    # Symlinks for compatibility
    symlink /system/bin /bin
    symlink /system/etc /etc
    symlink /system/lib /lib

service mtk.plpath.utils.link /system/bin/mtk_plpath_utils
    class main
    user root
    group root system
    disabled
    oneshot
    seclabel u:r:recovery:s0

service keystore_auth /system/bin/keystore_auth
    oneshot
    user system
    group root
    disabled
    seclabel u:r:recovery:s0

service keystore /system/bin/keystore /tmp/misc/keystore
    user root
    group root drmrpc readproc log
    disabled
    seclabel u:r:recovery:s0

on boot
    start boot-hal-1-1
    start health-hal-2-1
INIT_EOF

# Create prop.default with key properties
debug "Creating prop.default..."
cat > $DEVICE_PATH/recovery/root/prop.default << 'PROP_EOF'
ro.secure=0
ro.adb.secure=0
ro.debuggable=1
ro.build.system_root_image=false
persist.sys.usb.config=adb
ro.crypto.metadata.enabled=true
ro.crypto.support_metadata_encrypt=true
ro.crypto.uses_fs_ioc_add_encryption_key=true
PROP_EOF

# Setup build environment
debug "Setting up build environment..."
source build/envsetup.sh

# Minimal exports
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL=C

# Build configuration
debug "Setting up build configuration..."
lunch twrp_${DEVICE_CODENAME}-eng || {
    error "Failed to setup build configuration"
    exit 1
}

# Clean build
debug "Cleaning previous builds..."
make clean

# Build boot image
debug "Building boot image..."
make bootimage -j$(nproc --all) 2>&1 | tee build.log || {
    error "Boot image build failed"
    exit 1
}

# Check output
OUTPUT_DIR="out/target/product/$DEVICE_CODENAME"
if [ -f "$OUTPUT_DIR/boot.img" ]; then
    success "Build completed!"
    mkdir -p /tmp/cirrus-ci-build/output
    cp "$OUTPUT_DIR/boot.img" /tmp/cirrus-ci-build/output/
    cp build.log /tmp/cirrus-ci-build/output/
    
    echo ""
    echo "================================================"
    echo "TWRP Build Complete!"
    echo "Fixed mount issues + exact working parameters"
    echo "================================================"
    echo "Features:"
    echo "- Proper system mount (not system_root)"
    echo "- Virtual A/B support"
    echo "- Trustonic TEE for decrypt"
    echo "- MediaTek optimizations"
    echo "================================================"
else
    error "Build failed!"
    exit 1
fi
