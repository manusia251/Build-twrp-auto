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
    echo "--- Initializing TWRP 12.1 minimal manifest... ---"
    rm -rf .repo
    
    # Initialize repo with retry mechanism
    MAX_RETRIES=3
    RETRY_COUNT=0
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-12.1 --git-lfs --no-repo-verify; then
            echo "Repo init successful"
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            echo "Repo init failed, retry $RETRY_COUNT/$MAX_RETRIES"
            sleep 10
        fi
    done
    
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo "[ERROR] Failed to initialize repo after $MAX_RETRIES attempts"
        exit 1
    fi
    
    echo "--- Starting repo sync (this will take time)... ---"
    # Sync with retry mechanism
    RETRY_COUNT=0
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if repo sync -c --force-sync --no-tags --no-clone-bundle -j4 --optimized-fetch --prune; then
            echo "Repo sync successful"
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            echo "Repo sync failed, retry $RETRY_COUNT/$MAX_RETRIES"
            sleep 10
        fi
    done
    
    if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
        echo "[ERROR] Failed to sync repo after $MAX_RETRIES attempts"
        exit 1
    fi
    
    # Clone OrangeFox vendor
    if [ ! -d "vendor/recovery" ]; then
        echo "--- Cloning OrangeFox vendor... ---"
        git clone https://gitlab.com/OrangeFox/vendor/recovery.git -b fox_12.1 vendor/recovery --depth=1 || {
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

# Fix device tree makefiles
echo "--- Fixing device tree makefiles... ---"
cd $DEVICE_PATH

# Create twrp makefile if not exists
if [ ! -f "twrp_${DEVICE_CODENAME}.mk" ]; then
    if [ -f "omni_${DEVICE_CODENAME}.mk" ]; then
        debug_log "Creating twrp_${DEVICE_CODENAME}.mk from omni_${DEVICE_CODENAME}.mk"
        cp "omni_${DEVICE_CODENAME}.mk" "twrp_${DEVICE_CODENAME}.mk"
        sed -i "s/omni_/twrp_/g" "twrp_${DEVICE_CODENAME}.mk"
        sed -i "s/vendor\/omni/vendor\/twrp/g" "twrp_${DEVICE_CODENAME}.mk"
        sed -i "s/PRODUCT_NAME := omni_/PRODUCT_NAME := twrp_/g" "twrp_${DEVICE_CODENAME}.mk"
    else
        echo "[WARNING] No omni makefile found, creating basic twrp makefile"
        cat > "twrp_${DEVICE_CODENAME}.mk" << EOF
# Inherit from device
\$(call inherit-product, device/infinix/${DEVICE_CODENAME}/device.mk)

# Inherit TWRP product
\$(call inherit-product, vendor/twrp/config/common.mk)

# Device identifier
PRODUCT_DEVICE := ${DEVICE_CODENAME}
PRODUCT_NAME := twrp_${DEVICE_CODENAME}
PRODUCT_BRAND := Infinix
PRODUCT_MODEL := Infinix ${DEVICE_CODENAME}
PRODUCT_MANUFACTURER := Infinix
EOF
    fi
fi

# Update AndroidProducts.mk
debug_log "Updating AndroidProducts.mk..."
cat > AndroidProducts.mk << EOF
PRODUCT_MAKEFILES := \\
    \$(LOCAL_DIR)/twrp_${DEVICE_CODENAME}.mk

COMMON_LUNCH_CHOICES := \\
    twrp_${DEVICE_CODENAME}-user \\
    twrp_${DEVICE_CODENAME}-userdebug \\
    twrp_${DEVICE_CODENAME}-eng
EOF

cd $WORK_DIR

# Apply touchscreen fixes
echo "--- Applying touchscreen fixes... ---"
debug_log "Fixing touchscreen driver: omnivision_tcm_spi (spi2.0)"

mkdir -p $DEVICE_PATH/recovery/root/sbin
mkdir -p $DEVICE_PATH/recovery/root/vendor/lib/modules

# Create touchscreen fix script
cat > $DEVICE_PATH/recovery/root/sbin/fix_touch.sh << 'TOUCH_EOF'
#!/sbin/sh
# Touchscreen fix for omnivision_tcm_spi

echo "Fixing touchscreen..."

# Load module if exists
if [ -f /vendor/lib/modules/omnivision_tcm_spi.ko ]; then
    insmod /vendor/lib/modules/omnivision_tcm_spi.ko
fi

# Enable touchscreen
if [ -d /sys/bus/spi/devices/spi2.0 ]; then
    echo 1 > /sys/bus/spi/devices/spi2.0/input/input0/enabled 2>/dev/null
fi

# Force enable ADB
setprop persist.sys.usb.config adb
setprop persist.service.adb.enable 1
setprop persist.service.debuggable 1
setprop ro.adb.secure 0
setprop ro.secure 0
start adbd

exit 0
TOUCH_EOF

chmod +x $DEVICE_PATH/recovery/root/sbin/fix_touch.sh

# Create init rc for recovery
cat > $DEVICE_PATH/recovery/root/init.recovery.${DEVICE_CODENAME}.rc << 'INIT_EOF'
on init
    # Enable ADB
    setprop sys.usb.config adb
    setprop persist.sys.usb.config adb
    setprop persist.service.adb.enable 1
    setprop persist.service.debuggable 1
    setprop ro.adb.secure 0
    setprop ro.secure 0
    
on boot
    # Fix touchscreen
    exec u:r:recovery:s0 -- /sbin/fix_touch.sh
    
    # Start ADB daemon
    start adbd

on property:ro.debuggable=0
    setprop ro.debuggable 1
    restart adbd
INIT_EOF

# Update vendorsetup.sh
echo "--- Setting up OrangeFox build variables... ---"
cat > $DEVICE_PATH/vendorsetup.sh << VENDOR_EOF
# OrangeFox Configuration
export FOX_USE_BASH_SHELL=1
export FOX_ASH_IS_BASH=1
export FOX_USE_NANO_EDITOR=1
export OF_ENABLE_LPTOOLS=1

# A/B device configuration
export FOX_AB_DEVICE=1
export FOX_VIRTUAL_AB_DEVICE=1
export FOX_RECOVERY_BOOT_PARTITION="/dev/block/by-name/boot"

# Dynamic partitions
export OF_DYNAMIC_PARTITIONS=1

# UI Configuration
export OF_ALLOW_DISABLE_NAVBAR=0
export OF_STATUS_INDENT_LEFT=48
export OF_STATUS_INDENT_RIGHT=48
export OF_HIDE_NOTCH=1
export OF_CLOCK_POS=1
export OF_SCREEN_H=2400

# Enable navigation without touchscreen
export TW_USE_MOUSE_INPUT=1
export TW_ENABLE_VIRTUAL_MOUSE=1
export TW_HAS_USB_STORAGE=1

# Force enable ADB
export OF_FORCE_ENABLE_ADB=1
export OF_SKIP_ADB_SECURE=1

# Build configuration
export FOX_RECOVERY_INSTALL_PARTITION="boot"
export OF_MAINTAINER="manusia"
export FOX_BUILD_TYPE="Unofficial"
export FOX_VERSION="R11.1"

# Features
export OF_USE_GREEN_LED=0
export FOX_DELETE_AROMAFM=1
export FOX_ENABLE_APP_MANAGER=1
export OF_FBE_METADATA_MOUNT_IGNORE=1
export OF_PATCH_AVB20=1

# Debug mode
export OF_DEBUG_MODE=1

echo "OrangeFox build variables loaded for ${DEVICE_CODENAME}"
VENDOR_EOF

# Update BoardConfig.mk
echo "--- Updating BoardConfig.mk... ---"
if [ -f "$DEVICE_PATH/BoardConfig.mk" ]; then
    # Check if touchscreen configs already exist
    if ! grep -q "RECOVERY_TOUCHSCREEN" "$DEVICE_PATH/BoardConfig.mk"; then
        cat >> $DEVICE_PATH/BoardConfig.mk << 'BOARD_EOF'

# Touchscreen Configuration
RECOVERY_TOUCHSCREEN_SWAP_XY := false
RECOVERY_TOUCHSCREEN_FLIP_X := false
RECOVERY_TOUCHSCREEN_FLIP_Y := false
TW_INPUT_BLACKLIST := "hbtp_vm"

# Navigation support
BOARD_HAS_NO_SELECT_BUTTON := true
TW_HAS_USB_STORAGE := true

# ADB Configuration
TW_EXCLUDE_DEFAULT_USB_INIT := true

# Debug
TW_INCLUDE_LOGCAT := true
TARGET_USES_LOGD := true
BOARD_EOF
    fi
fi

# Build recovery
echo "--- Setting up build environment... ---"
cd $WORK_DIR

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

# Disable roomservice
export DISABLE_ROOMSERVICE=1

echo "--- Starting build process... ---"
echo "Lunch target: twrp_${DEVICE_CODENAME}-eng"

# Try lunch with error handling
lunch twrp_${DEVICE_CODENAME}-eng || {
    echo "[WARNING] twrp lunch failed, trying with omni..."
    lunch omni_${DEVICE_CODENAME}-eng || {
        echo "[ERROR] Lunch failed for both twrp and omni targets"
        echo "Available lunch choices:"
        lunch
        exit 1
    }
}

# Clean previous builds
echo "--- Cleaning old builds... ---"
make clean || true

# Build recovery/boot image
echo "--- Building $TARGET_RECOVERY_IMAGE image (this will take time)... ---"
if [ "$TARGET_RECOVERY_IMAGE" = "boot" ]; then
    echo "Building boot image..."
    mka bootimage -j$(nproc --all) 2>&1 | tee build.log
else
    echo "Building recovery image..."
    mka recoveryimage -j$(nproc --all) 2>&1 | tee build.log
fi

# Check build output
echo "--- Checking build output... ---"
OUTPUT_DIR="out/target/product/$DEVICE_CODENAME"

if [ -f "$OUTPUT_DIR/boot.img" ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Boot image built successfully!"
    echo "Location: $OUTPUT_DIR/boot.img"
    
    # Create output directory
    mkdir -p /tmp/cirrus-ci-build/output
    cp $OUTPUT_DIR/boot.img /tmp/cirrus-ci-build/output/OrangeFox-${FOX_VERSION:-R11.1}-${DEVICE_CODENAME}-$(date +%Y%m%d).img
    
    # Generate checksums
    cd /tmp/cirrus-ci-build/output
    sha256sum *.img > sha256sums.txt
    md5sum *.img > md5sums.txt
    
    echo "Output files:"
    ls -lah /tmp/cirrus-ci-build/output/
elif [ -f "$OUTPUT_DIR/recovery.img" ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Recovery image built successfully!"
    echo "Location: $OUTPUT_DIR/recovery.img"
    
    # Create output directory
    mkdir -p /tmp/cirrus-ci-build/output
    cp $OUTPUT_DIR/recovery.img /tmp/cirrus-ci-build/output/OrangeFox-${FOX_VERSION:-R11.1}-${DEVICE_CODENAME}-$(date +%Y%m%d).img
    
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
    exit 1
fi

echo "================================================"
echo "     Build Complete!                            "
echo "================================================"
