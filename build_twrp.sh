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

echo "================================================"
echo "     TWRP Recovery Builder for $DEVICE_CODENAME"
echo "================================================"

# Working directory
WORK_DIR="/tmp/cirrus-ci-build/twrp"
mkdir -p $WORK_DIR
cd $WORK_DIR

# Git config
git config --global user.name "manusia"
git config --global user.email "ndktau@gmail.com"
git config --global url.https://github.com/.insteadOf git@github.com:
git config --global url.https://.insteadOf git://

# Install repo if not exists
if ! command -v repo &> /dev/null; then
    echo "--- Installing repo tool... ---"
    curl https://storage.googleapis.com/git-repo-downloads/repo > /tmp/repo
    chmod a+x /tmp/repo
    sudo mv /tmp/repo /usr/local/bin/repo || mv /tmp/repo /usr/local/bin/repo
fi

# Initialize TWRP manifest
echo "--- Initializing TWRP manifest... ---"
repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-11 --git-lfs

echo "--- Syncing source... ---"
repo sync -c --force-sync --no-tags --no-clone-bundle -j$(nproc --all) --optimized-fetch --prune

# Fix missing VTS files
echo "--- Fixing missing VTS files... ---"
mkdir -p test/vts/tools/build
touch test/vts/tools/build/Android.host_config.mk

# Create a dummy Android.host_config.mk to prevent build errors
cat > test/vts/tools/build/Android.host_config.mk << 'VTS_EOF'
# Dummy VTS config file for TWRP build
LOCAL_PATH := $(call my-dir)
VTS_EOF

# Clone device tree
echo "--- Cloning device tree... ---"
DEVICE_PATH="device/infinix/$DEVICE_CODENAME"
rm -rf $DEVICE_PATH
git clone $DEVICE_TREE -b $DEVICE_BRANCH $DEVICE_PATH

# Create recovery directory structure
echo "--- Creating recovery directory structure... ---"
mkdir -p $DEVICE_PATH/recovery/root

# Create init.recovery.X6512.rc for ADB and touchscreen
echo "--- Creating init.recovery.${DEVICE_CODENAME}.rc... ---"
cat > $DEVICE_PATH/recovery/root/init.recovery.${DEVICE_CODENAME}.rc << 'INIT_EOF'
on init
    # Create mount points
    mkdir /mnt/vendor/persist 0700 root root
    mount ext4 /dev/block/by-name/persist /mnt/vendor/persist rw
    
    # Enable ADB
    setprop sys.usb.config adb
    setprop persist.sys.usb.config adb
    setprop persist.service.adb.enable 1
    setprop persist.service.debuggable 1
    setprop ro.adb.secure 0
    setprop service.adb.root 1
    
    # Load touchscreen module
    insmod /vendor/lib/modules/omnivision_touch.ko

on boot
    # Start adbd
    start adbd
    
    # Set touchscreen permissions
    chmod 0666 /dev/input/event0
    chmod 0666 /dev/input/event1
    chmod 0666 /dev/input/event2
    chmod 0666 /dev/input/event3
    chmod 0666 /dev/input/event4
    
    # Enable touchscreen
    write /sys/class/input/input0/enabled 1
    write /sys/class/input/input1/enabled 1
    write /sys/class/input/input2/enabled 1

on property:ro.debuggable=0
    setprop ro.debuggable 1

on property:ro.secure=1
    setprop ro.secure 0

on property:persist.sys.usb.config=none
    setprop persist.sys.usb.config adb

service adbd /system/bin/adbd --root_seclabel=u:r:su:s0
    disabled
    socket adbd stream 660 system system
    seclabel u:r:adbd:s0

on property:sys.usb.config=adb
    start adbd
INIT_EOF

# Create default.prop for additional ADB settings
echo "--- Creating default.prop... ---"
cat > $DEVICE_PATH/recovery/root/default.prop << 'PROP_EOF'
ro.secure=0
ro.adb.secure=0
ro.debuggable=1
persist.sys.usb.config=adb
persist.service.adb.enable=1
persist.service.debuggable=1
service.adb.root=1
PROP_EOF

# Create prop.default as backup
cp $DEVICE_PATH/recovery/root/default.prop $DEVICE_PATH/recovery/root/prop.default

# Create recovery.fstab if not exists
if [ ! -f "$DEVICE_PATH/recovery.fstab" ]; then
    echo "--- Creating recovery.fstab... ---"
    cat > $DEVICE_PATH/recovery.fstab << 'FSTAB_EOF'
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
fi

# Create vendorsetup.sh for additional build flags
echo "--- Creating vendorsetup.sh... ---"
cat > $DEVICE_PATH/vendorsetup.sh << 'VENDOR_EOF'
# Force ADB to be enabled
export TW_FORCE_DEFAULT_USB_INIT=0
export TW_EXCLUDE_DEFAULT_USB_INIT=true
export TW_USE_TOOLBOX=true

# Touchscreen modules
export TW_LOAD_VENDOR_MODULES="omnivision_touch.ko"

# Additional debug flags
export TARGET_USES_LOGD=true
export TWRP_INCLUDE_LOGCAT=true

echo "TWRP build variables loaded for X6512"
VENDOR_EOF

# Make vendorsetup.sh executable
chmod +x $DEVICE_PATH/vendorsetup.sh

# Setup build environment
echo "--- Setting up build environment... ---"
source build/envsetup.sh

# Export variables to fix build issues
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL=C
export TW_EXCLUDE_DEFAULT_USB_INIT=true
export TW_USE_TOOLBOX=true
export BUILD_BROKEN_DUP_RULES=true
export BUILD_BROKEN_MISSING_REQUIRED_MODULES=true

# Disable VTS modules that cause issues
export BOARD_VNDK_VERSION=current
export PRODUCT_FULL_TREBLE_OVERRIDE=false

# Build
echo "--- Starting build... ---"
lunch twrp_${DEVICE_CODENAME}-eng

# Clean
echo "--- Cleaning previous builds... ---"
make clean

# Remove problematic Android.mk files if they exist
echo "--- Removing problematic makefiles... ---"
if [ -f "frameworks/base/core/xsd/vts/Android.mk" ]; then
    echo "Removing frameworks/base/core/xsd/vts/Android.mk"
    rm -f frameworks/base/core/xsd/vts/Android.mk
fi

# Build boot image with error handling
echo "--- Building boot image... ---"
make bootimage -j$(nproc --all) 2>&1 | tee build.log || {
    echo "Build encountered errors, checking for partial output..."
}

# Check output in multiple locations
OUTPUT_DIR="out/target/product/$DEVICE_CODENAME"
OUTPUT_FOUND=""

# List of possible output locations
POSSIBLE_OUTPUTS=(
    "$OUTPUT_DIR/boot.img"
    "$OUTPUT_DIR/recovery.img"
    "$OUTPUT_DIR/obj/PACKAGING/target_files_intermediates/*/IMAGES/boot.img"
    "$OUTPUT_DIR/ramdisk-recovery.img"
)

echo "--- Checking for output files... ---"
for OUTPUT in "${POSSIBLE_OUTPUTS[@]}"; do
    if [ -f "$OUTPUT" ] || ls $OUTPUT 2>/dev/null; then
        OUTPUT_FOUND=$(ls $OUTPUT 2>/dev/null | head -1)
        echo "Found output: $OUTPUT_FOUND"
        break
    fi
done

# If no boot.img found, try to create it manually
if [ -z "$OUTPUT_FOUND" ] && [ -f "$OUTPUT_DIR/ramdisk-recovery.img" ]; then
    echo "--- Attempting to create boot.img manually... ---"
    if [ -f "$DEVICE_PATH/prebuilt/kernel" ] && [ -f "$DEVICE_PATH/prebuilt/dtb.img" ]; then
        mkbootimg \
            --kernel $DEVICE_PATH/prebuilt/kernel \
            --ramdisk $OUTPUT_DIR/ramdisk-recovery.img \
            --dtb $DEVICE_PATH/prebuilt/dtb.img \
            --cmdline "bootopt=64S3,32S1,32S1 buildvariant=user" \
            --base 0x40000000 \
            --pagesize 2048 \
            --ramdisk_offset 0x11b00000 \
            --tags_offset 0x07880000 \
            --header_version 2 \
            --output $OUTPUT_DIR/boot.img
        
        if [ -f "$OUTPUT_DIR/boot.img" ]; then
            OUTPUT_FOUND="$OUTPUT_DIR/boot.img"
            echo "Successfully created boot.img manually"
        fi
    fi
fi

if [ -n "$OUTPUT_FOUND" ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Image built successfully!"
    echo "Location: $OUTPUT_FOUND"
    
    # Create output directory
    mkdir -p /tmp/cirrus-ci-build/output
    cp "$OUTPUT_FOUND" /tmp/cirrus-ci-build/output/twrp-${DEVICE_CODENAME}-$(date +%Y%m%d).img
    
    # Copy build log for debugging
    cp build.log /tmp/cirrus-ci-build/output/build.log
    
    # Generate checksums
    cd /tmp/cirrus-ci-build/output
    sha256sum *.img > sha256sums.txt
    
    echo "Output files:"
    ls -lah /tmp/cirrus-ci-build/output/
    
    echo ""
    echo "================================================"
    echo "TWRP Features enabled:"
    echo "- ADB enabled by default"
    echo "- Root ADB access"
    echo "- Touchscreen support (omnivision)"
    echo "================================================"
else
    echo -e "${RED}[ERROR]${NC} Build failed! No output image found"
    echo "Checking for errors in build log..."
    grep -i "error\|failed" build.log | tail -20 || true
    
    # List all img files in out directory for debugging
    echo ""
    echo "All .img files in out directory:"
    find out/ -name "*.img" -type f 2>/dev/null || true
    
    exit 1
fi

echo "================================================"
echo "     Build Complete!                            "
echo "================================================"
