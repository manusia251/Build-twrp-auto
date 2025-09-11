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
echo "     Target: boot.img (Simplified)"
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

# Install repo if not exists
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

# Check for kernel and dtb
debug "Checking prebuilt kernel and dtb..."
if [ ! -f "$DEVICE_PATH/prebuilt/kernel" ]; then
    error "Kernel not found at $DEVICE_PATH/prebuilt/kernel"
    exit 1
fi
if [ ! -f "$DEVICE_PATH/prebuilt/dtb.img" ]; then
    error "DTB not found at $DEVICE_PATH/prebuilt/dtb.img"
    exit 1
fi
success "Kernel and DTB found!"

# Create minimal recovery directories
mkdir -p $DEVICE_PATH/recovery/root

# Minimal BoardConfig.mk append
debug "Adding minimal boot configuration..."
cat >> $DEVICE_PATH/BoardConfig.mk << 'EOF'

# Kernel
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
BOARD_PREBUILT_DTBIMAGE_DIR := $(DEVICE_PATH)/prebuilt

# Boot header (try version 2 for MTK)
BOARD_BOOT_HEADER_VERSION := 2
BOARD_KERNEL_BASE := 0x40000000
BOARD_KERNEL_CMDLINE := bootopt=64S3,32S1,32S1 buildvariant=user
BOARD_KERNEL_PAGESIZE := 2048
BOARD_RAMDISK_OFFSET := 0x11b00000
BOARD_KERNEL_TAGS_OFFSET := 0x07880000
BOARD_DTB_OFFSET := 0x07880000
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset $(BOARD_RAMDISK_OFFSET)
BOARD_MKBOOTIMG_ARGS += --tags_offset $(BOARD_KERNEL_TAGS_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb_offset $(BOARD_DTB_OFFSET)
BOARD_MKBOOTIMG_ARGS += --dtb $(DEVICE_PATH)/prebuilt/dtb.img

# Partitions
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432

# Recovery
BOARD_HAS_LARGE_FILESYSTEM := true
BOARD_USES_RECOVERY_AS_BOOT := true
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true

# A/B
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += boot

# TWRP Basic
TW_THEME := portrait_hdpi
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_REPACKTOOLS := true
EOF

# Minimal init.recovery.rc (TANPA clear misc agresif)
debug "Creating minimal init.recovery.${DEVICE_CODENAME}.rc..."
cat > $DEVICE_PATH/recovery/root/init.recovery.${DEVICE_CODENAME}.rc << 'INIT_EOF'
on init
    # Basic ADB setup
    setprop sys.usb.config adb
    setprop ro.adb.secure 0
    setprop service.adb.root 1

on boot
    start adbd

service adbd /system/bin/adbd
    disabled
    seclabel u:r:adbd:s0
INIT_EOF

# Minimal recovery.fstab
debug "Creating minimal recovery.fstab..."
cat > $DEVICE_PATH/recovery.fstab << 'FSTAB_EOF'
# mount point    fstype    device                                        flags
/boot            emmc      /dev/block/by-name/boot                      flags=slotselect
/system          ext4      /dev/block/mapper/system                     flags=logical;slotselect
/vendor          ext4      /dev/block/mapper/vendor                     flags=logical;slotselect
/product         ext4      /dev/block/mapper/product                    flags=logical;slotselect
/data            f2fs      /dev/block/by-name/userdata
/misc            emmc      /dev/block/by-name/misc
/super           emmc      /dev/block/by-name/super
FSTAB_EOF

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

# Check for output
OUTPUT_DIR="out/target/product/$DEVICE_CODENAME"
if [ -f "$OUTPUT_DIR/boot.img" ]; then
    success "Build completed!"
    mkdir -p /tmp/cirrus-ci-build/output
    cp "$OUTPUT_DIR/boot.img" /tmp/cirrus-ci-build/output/
    cp build.log /tmp/cirrus-ci-build/output/
    echo "Output: boot.img"
else
    error "Build failed! No boot.img found"
    exit 1
fi
