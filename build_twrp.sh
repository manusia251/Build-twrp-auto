#!/bin/bash
set -e

# Arguments
DEVICE_TREE=$1
DEVICE_BRANCH=$2
DEVICE_CODENAME=$3
MANIFEST_BRANCH=${4:-"twrp-11"}
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

# Create empty Android.mk to avoid VTS error
debug "Creating empty Android.mk files to avoid errors..."
mkdir -p test/vts/tools/build
touch test/vts/tools/build/Android.host_config.mk
echo "# Empty file to avoid build error" > test/vts/tools/build/Android.host_config.mk

# Create recovery.fstab in ROOT directory (FIX untuk error ninja)
debug "Creating recovery.fstab in root directory..."
cat > $WORK_DIR/recovery.fstab << 'FSTAB_EOF'
/system                   ext4     system                                                   flags=display=system;logical;slotselect
/system_ext               ext4     system_ext                                               flags=display=system_ext;logical;slotselect
/vendor                   ext4     vendor                                                   flags=display=vendor;logical;slotselect
/product                  ext4     product                                                  flags=display=product;logical;slotselect
/metadata                 ext4     /dev/block/platform/bootdevice/by-name/md_udc            flags=display=metadata
/data                     f2fs     /dev/block/platform/bootdevice/by-name/userdata          flags=display=data
/tranfs                   ext4     /dev/block/platform/bootdevice/by-name/tranfs            flags=display=tranfs
/mnt/vendor/protect_f     ext4     /dev/block/platform/bootdevice/by-name/protect1          flags=display=protect_f
/mnt/vendor/protect_s     ext4     /dev/block/platform/bootdevice/by-name/protect2          flags=display=protect_s
/mnt/vendor/nvdata        ext4     /dev/block/platform/bootdevice/by-name/nvdata            flags=display=nvdata
/mnt/vendor/nvcfg         ext4     /dev/block/platform/bootdevice/by-name/nvcfg             flags=display=nvcfg
/mnt/vendor/persist       ext4     /dev/block/platform/bootdevice/by-name/persist           flags=display=persist
auto                      auto     /devices/platform/externdevice*                          flags=display=auto
auto                      vfat     /devices/platform/mt_usb*                                flags=display=auto
/persistent               emmc     /dev/block/platform/bootdevice/by-name/frp               flags=display=persistent
/nvram                    emmc     /dev/block/platform/bootdevice/by-name/nvram             flags=display=nvram
/proinfo                  emmc     /dev/block/platform/bootdevice/by-name/proinfo           flags=display=proinfo
/bootloader               emmc     /dev/block/platform/bootdevice/by-name/lk                flags=display=bootloader
/bootloader2              emmc     /dev/block/platform/bootdevice/by-name/lk2               flags=display=bootloader2
/misc                     emmc     /dev/block/platform/bootdevice/by-name/para              flags=display=misc
/boot                     emmc     /dev/block/platform/bootdevice/by-name/boot              flags=display=boot;slotselect
/vbmeta_vendor            emmc     /dev/block/platform/bootdevice/by-name/vbmeta_vendor     flags=display=vbmeta_vendor;slotselect
/vbmeta_system            emmc     /dev/block/platform/bootdevice/by-name/vbmeta_system     flags=display=vbmeta_system;slotselect
/logo                     emmc     /dev/block/platform/bootdevice/by-name/logo              flags=display=logo
/expdb                    emmc     /dev/block/platform/bootdevice/by-name/expdb             flags=display=expdb
/seccfg                   emmc     /dev/block/platform/bootdevice/by-name/seccfg            flags=display=seccfg
/tee1                     emmc     /dev/block/platform/bootdevice/by-name/tee1              flags=display=tee1
/tee2                     emmc     /dev/block/platform/bootdevice/by-name/tee2              flags=display=tee2
/scp1                     emmc     /dev/block/platform/bootdevice/by-name/scp1              flags=display=scp1
/scp2                     emmc     /dev/block/platform/bootdevice/by-name/scp2              flags=display=scp2
/sspm_1                   emmc     /dev/block/platform/bootdevice/by-name/sspm_1            flags=display=sspm_1
/sspm_2                   emmc     /dev/block/platform/bootdevice/by-name/sspm_2            flags=display=sspm_2
/md1img                   emmc     /dev/block/platform/bootdevice/by-name/md1img            flags=display=md1img
/md1dsp                   emmc     /dev/block/platform/bootdevice/by-name/md1dsp            flags=display=md1dsp
/md1arm7                  emmc     /dev/block/platform/bootdevice/by-name/md1arm7           flags=display=md1arm7
/md3img                   emmc     /dev/block/platform/bootdevice/by-name/md3img            flags=display=md3img
/gz1                      emmc     /dev/block/platform/bootdevice/by-name/gz1               flags=display=gz1
/gz2                      emmc     /dev/block/platform/bootdevice/by-name/gz2               flags=display=gz2
/spmfw                    emmc     /dev/block/platform/bootdevice/by-name/spmfw             flags=display=spmfw
/boot_para                emmc     /dev/block/platform/bootdevice/by-name/boot_para         flags=display=boot_para
/dtbo1                    emmc     /dev/block/platform/bootdevice/by-name/dtbo1             flags=display=dtbo1
/dtbo2                    emmc     /dev/block/platform/bootdevice/by-name/dtbo2             flags=display=dtbo2
/dtbo                     emmc     /dev/block/platform/bootdevice/by-name/dtbo              flags=display=dtbo
/vbmeta                   emmc     /dev/block/platform/bootdevice/by-name/vbmeta            flags=display=vbmeta
FSTAB_EOF

# Also create in /recovery/root/system/etc/ path jika ada yang butuh
debug "Creating recovery directories if needed..."
mkdir -p $WORK_DIR/recovery/root/system/etc
cp $WORK_DIR/recovery.fstab $WORK_DIR/recovery/root/system/etc/recovery.fstab

# Verify files exist
debug "Verifying created files..."
ls -la $WORK_DIR/recovery.fstab || error "recovery.fstab not created in root!"
ls -la $DEVICE_PATH/recovery.fstab || echo "recovery.fstab exists in device tree"

# Setup build environment
debug "Setting up build environment..."
source build/envsetup.sh

# Export build variables with more flags
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL=C
export BUILD_BROKEN_USES_BUILD_COPY_HEADERS=true
export BUILD_BROKEN_VINTF_PRODUCT_COPY_FILES=true
export BUILD_BROKEN_DUP_RULES=true
export BUILD_BROKEN_MISSING_REQUIRED_MODULES=true
export BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES=true

# Build configuration
debug "Setting up build configuration..."
lunch twrp_${DEVICE_CODENAME}-eng || {
    error "Failed to setup build configuration"
    exit 1
}

# Clean build
debug "Cleaning previous builds..."
make clean

# Build boot image with specific target
debug "Building boot image..."
make bootimage -j$(nproc --all) 2>&1 | tee build.log || {
    # Try alternative if failed
    debug "Trying alternative build method..."
    mka bootimage -j$(nproc --all) 2>&1 | tee build_alt.log || {
        error "Boot image build failed"
        exit 1
    }
}

# Check output
OUTPUT_DIR="out/target/product/$DEVICE_CODENAME"
if [ -f "$OUTPUT_DIR/boot.img" ]; then
    success "Build completed!"
    mkdir -p /tmp/cirrus-ci-build/output
    cp "$OUTPUT_DIR/boot.img" /tmp/cirrus-ci-build/output/
    cp build.log /tmp/cirrus-ci-build/output/ || true
    
    echo ""
    echo "================================================"
    echo "TWRP Build Complete!"
    echo "================================================"
    echo "Output: /tmp/cirrus-ci-build/output/boot.img"
    echo "================================================"
    
    # Show boot.img info
    echo "Boot image info:"
    ls -lh "$OUTPUT_DIR/boot.img"
    file "$OUTPUT_DIR/boot.img"
else
    error "Build failed! No boot.img found"
    
    # Debug info
    echo "Checking output directory:"
    ls -la $OUTPUT_DIR/ || echo "Output directory not found"
    
    echo "Last 100 lines of build log:"
    tail -n 100 build.log || true
    
    exit 1
fi
