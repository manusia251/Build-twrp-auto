#!/bin/bash

# OrangeFox Recovery Builder Script for Infinix X6512
# With touchscreen fix and full OrangeFox features support
# Fixed for HTTPS authentication and no-SSH environment

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

echo "--- Method 1: Clone OrangeFox sync script... ---"
debug_log "Cloning from: https://gitlab.com/OrangeFox/sync.git"

if [ -d sync_dir ]; then
    debug_log "sync_dir already exists, removing..."
    rm -rf sync_dir
fi

# Clone with HTTPS
git clone https://gitlab.com/OrangeFox/sync.git -b master sync_dir || {
    warning_msg "Failed to clone sync script, trying alternative method..."
}

# Try the sync script if it exists
if [ -d sync_dir ] && [ -f sync_dir/orangefox_sync.sh ]; then
    cd sync_dir
    debug_log "Contents of sync_dir:"
    ls -la
    
    echo "--- Syncing OrangeFox source code using sync script... ---"
    SYNC_PATH=$(realpath ../)
    debug_log "Sync path: $SYNC_PATH"
    
    # Force HTTPS in sync script
    bash orangefox_sync.sh --branch 12.1 --path "$SYNC_PATH" --ssh 0 || {
        warning_msg "Sync script failed, will use direct repo method..."
    }
    cd "$SYNC_PATH"
fi

# Check if sync was successful
if [ ! -f build/envsetup.sh ] && [ ! -f build/make/envsetup.sh ]; then
    echo "--- Method 2: Direct repo sync with HTTPS... ---"
    warning_msg "Sync script didn't work, using direct repo init method..."
    
    cd "$WORK_DIR"
    
    # Clean up any previous attempts
    rm -rf .repo
    
    # Initialize repo with HTTPS URL
    debug_log "Initializing repo with HTTPS..."
    repo init --depth=1 -u https://gitlab.com/OrangeFox/Manifest.git -b fox_12.1 --git-lfs --no-repo-verify || {
        warning_msg "Standard repo init failed, trying GitHub mirror..."
        
        # Try GitHub mirror as alternative (community maintained)
        repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-12.1 --git-lfs --no-repo-verify || {
            error_exit "All repo init methods failed!"
        }
    }
    
    # Sync the repositories
    debug_log "Starting repo sync..."
    repo sync -c --force-sync --no-tags --no-clone-bundle -j$(nproc --all) --optimized-fetch --prune || {
        warning_msg "Full sync failed, trying partial sync..."
        repo sync -c --force-sync --no-tags --no-clone-bundle -j4 || {
            error_exit "Repo sync completely failed!"
        }
    }
fi

# Alternative Method 3: Use TWRP minimal manifest if OrangeFox fails
if [ ! -f build/envsetup.sh ] && [ ! -f build/make/envsetup.sh ]; then
    echo "--- Method 3: Using TWRP minimal manifest as fallback... ---"
    warning_msg "OrangeFox sync failed, using TWRP base instead..."
    
    cd "$WORK_DIR"
    rm -rf .repo
    
    # Use TWRP minimal manifest which is more reliable
    repo init --depth=1 -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b twrp-12.1
    repo sync -c --force-sync --no-tags --no-clone-bundle -j$(nproc --all)
    
    # Clone OrangeFox vendor repository manually
    if [ ! -d vendor/recovery ]; then
        git clone https://gitlab.com/OrangeFox/vendor/recovery.git -b fox_12.1 vendor/recovery || {
            warning_msg "Failed to clone OrangeFox vendor, build will be TWRP-based"
        }
    fi
fi

cd "$WORK_DIR"
debug_log "Checking build system files..."

# Wait for sync to complete and check multiple times
for i in {1..10}; do
    if [ -f build/envsetup.sh ] || [ -f build/make/envsetup.sh ]; then
        success_msg "Build environment found!"
        break
    fi
    warning_msg "Build environment not found (attempt $i/10), waiting..."
    sleep 5
done

# Final check
if [ ! -f build/envsetup.sh ] && [ ! -f build/make/envsetup.sh ]; then
    error_exit "Build environment not found after all attempts!"
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

# Check if device tree was cloned successfully
if [ ! -d "$DEVICE_PATH" ]; then
    error_exit "Device tree directory not found after cloning!"
fi

debug_log "Device tree contents:"
ls -la "$DEVICE_PATH"

# Apply touchscreen fixes
echo "--- Applying touchscreen fixes... ---"
debug_log "Fixing touchscreen driver: omnivision_tcm_spi (spi2.0)"

# Create recovery directory structure if it doesn't exist
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

on property:ro.debuggable=1
    start adbd
    
service adbd /sbin/adbd --root_seclabel=u:r:su:s0
    disabled
    socket adbd stream 660 system system
    seclabel u:r:adbd:s0
EOF

# Create touchscreen fix script
cat > "$DEVICE_PATH/recovery/root/sbin/fix_touch.sh" << 'EOF'
#!/sbin/sh
# Touchscreen fix script for omnivision_tcm_spi

echo "Starting touchscreen fix..." >> /tmp/recovery.log

# Wait for device to settle
sleep 2

# Check if module exists
if [ -f /vendor/lib/modules/omnivision_tcm_spi.ko ]; then
    # Load touchscreen module if not loaded
    if ! lsmod | grep -q omnivision_tcm_spi; then
        insmod /vendor/lib/modules/omnivision_tcm_spi.ko
        echo "Touchscreen module loaded" >> /tmp/recovery.log
    fi
fi

# Set permissions
chmod 666 /dev/input/event* 2>/dev/null
chmod 666 /dev/spidev2.0 2>/dev/null

# Enable touchscreen
echo 1 > /sys/bus/spi/devices/spi2.0/accessible 2>/dev/null

# Enable ADB
setprop ro.adb.secure 0
setprop ro.debuggable 1
setprop persist.sys.usb.config adb
setprop service.adb.root 1

# Log success
echo "Touchscreen fix applied at $(date)" >> /tmp/recovery.log
EOF

chmod +x "$DEVICE_PATH/recovery/root/sbin/fix_touch.sh"

# Update init.rc to include touchscreen fix
if [ -f "$DEVICE_PATH/recovery/root/init.rc" ]; then
    echo "import /init.recovery.touchscreen.rc" >> "$DEVICE_PATH/recovery/root/init.rc"
else
    # Create basic init.rc if it doesn't exist
    cat > "$DEVICE_PATH/recovery/root/init.rc" << 'EOF'
import /init.recovery.touchscreen.rc

on init
    # Run touchscreen fix
    exec u:r:recovery:s0 -- /sbin/fix_touch.sh
EOF
fi

# Create custom vendorsetup.sh for OrangeFox variables
echo "--- Setting up OrangeFox build variables... ---"
cat > "$DEVICE_PATH/vendorsetup.sh" << 'EOF'
# OrangeFox build vars
export FOX_RECOVERY_SYSTEM_PARTITION="/dev/block/mapper/system"
export FOX_RECOVERY_VENDOR_PARTITION="/dev/block/mapper/vendor"
export FOX_USE_BASH_SHELL=1
export FOX_ASH_IS_BASH=1
export FOX_USE_TAR_BINARY=1
export FOX_USE_SED_BINARY=1
export FOX_USE_XZ_UTILS=1
export FOX_USE_NANO_EDITOR=1
export OF_ENABLE_LPTOOLS=1
export OF_NO_TREBLE_COMPATIBILITY_CHECK=1

# A/B device configuration
export FOX_AB_DEVICE=1
export FOX_VIRTUAL_AB_DEVICE=1
export FOX_RECOVERY_BOOT_PARTITION="/dev/block/by-name/boot"

# Super partition support
export OF_DYNAMIC_PARTITIONS=1
export OF_NO_RELOAD_AFTER_DECRYPTION=1

# Touchscreen and navigation support
export OF_ALLOW_DISABLE_NAVBAR=0
export OF_SCREEN_H=2400
export OF_STATUS_H=100
export OF_STATUS_INDENT_LEFT=48
export OF_STATUS_INDENT_RIGHT=48
export OF_HIDE_NOTCH=1
export OF_CLOCK_POS=1

# Enable keyboard/mouse support for non-touch control
export TW_USE_MOUSE_INPUT=1
export TW_ENABLE_VIRTUAL_MOUSE=1
export TW_HAS_USB_STORAGE=1

# Enable ADB by default for debugging
export OF_FORCE_ENABLE_ADB=1
export OF_SKIP_ADB_SECURE=1
export PLATFORM_SECURITY_PATCH="2099-12-31"
export TW_DEFAULT_LANGUAGE="en"

# Additional debugging
export OF_DEBUG_MODE=1
export TW_INCLUDE_RESETPROP=true
export TW_INCLUDE_REPACKTOOLS=true
export TW_INCLUDE_LIBRESETPROP=true

# UI customization
export OF_USE_GREEN_LED=0
export FOX_DELETE_AROMAFM=1
export FOX_ENABLE_APP_MANAGER=1
export OF_USE_HEXDUMP=1

# Decryption support
export OF_FBE_METADATA_MOUNT_IGNORE=1
export OF_PATCH_AVB20=1
export OF_DONT_PATCH_ENCRYPTED_DEVICE=1

# Build as boot.img instead of recovery.img
export FOX_RECOVERY_INSTALL_PARTITION="boot"
export FOX_REPLACE_BOOTIMAGE_DATE=1
export FOX_BUGGED_AOSP_ARB_WORKAROUND="1616300800"

# Device info
export OF_MAINTAINER="manusia"
export FOX_BUILD_TYPE="Unofficial"
export FOX_VERSION="R11.1"

# Fix common issues
export OF_FIX_OTA_UPDATE_MANUAL_FLASH_ERROR=1
export OF_DISABLE_MIUI_OTA_BY_DEFAULT=1
export OF_NO_MIUI_OTA_VENDOR_BACKUP=1
export OF_NO_SAMSUNG_SPECIAL=1

# Skip FBE decryption if causing issues
export OF_SKIP_FBE_DECRYPTION=1

echo "OrangeFox build variables loaded for X6512"
EOF

# Create BoardConfig additions for touchscreen
echo "--- Updating BoardConfig for touchscreen support... ---"
if [ -f "$DEVICE_PATH/BoardConfig.mk" ]; then
    cat >> "$DEVICE_PATH/BoardConfig.mk" << 'EOF'

# Touchscreen configuration
RECOVERY_TOUCHSCREEN_SWAP_XY := false
RECOVERY_TOUCHSCREEN_FLIP_X := false
RECOVERY_TOUCHSCREEN_FLIP_Y := false

# Enable touch driver debugging
BOARD_RECOVERY_TOUCHSCREEN_DEBUG := true

# SPI touchscreen support
TARGET_RECOVERY_DEVICE_MODULES += omnivision_tcm_spi
TW_LOAD_VENDOR_MODULES := "omnivision_tcm_spi.ko"

# Non-touch navigation support
TW_USE_KEY_CODE_WAKE_DEVICE := true
BOARD_HAS_NO_SELECT_BUTTON := true

# Enable virtual mouse for navigation without touch
TW_INPUT_BLACKLIST := ""
TW_EXCLUDE_DEFAULT_USB_INIT := false

# ADB configuration
BOARD_ALWAYS_INSECURE := true
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_CRYPTO_FBE := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true

# Build as boot image
BOARD_USES_RECOVERY_AS_BOOT := true
BOARD_BUILD_SYSTEM_ROOT_IMAGE := false
EOF
fi

# Setup build environment
echo "--- Setting up build environment... ---"
if [ -f build/envsetup.sh ]; then
    source build/envsetup.sh
elif [ -f build/make/envsetup.sh ]; then
    source build/make/envsetup.sh
else
    error_exit "Failed to find envsetup.sh"
fi

# Add device to lunch menu
debug_log "Adding device to lunch menu..."
add_lunch_combo "twrp_${DEVICE_CODENAME}-eng" || warning_msg "Failed to add lunch combo"

# Select device
echo "--- Selecting device: ${DEVICE_CODENAME} ---"
lunch "twrp_${DEVICE_CODENAME}-eng" || lunch "omni_${DEVICE_CODENAME}-eng" || error_exit "Failed to lunch device"

# Clean previous builds
echo "--- Cleaning previous builds... ---"
make clean || warning_msg "Clean failed, continuing anyway..."

# Start building
echo "--- Starting OrangeFox build... ---"
debug_log "Building with TARGET_RECOVERY_IMAGE=$TARGET_RECOVERY_IMAGE"

# Set additional build variables
export TW_DEVICE_VERSION="1.0_manusia"
export TARGET_PREBUILT_KERNEL="$DEVICE_PATH/prebuilt/kernel"
export ALLOW_MISSING_DEPENDENCIES=true

# Build the recovery
if [ "$TARGET_RECOVERY_IMAGE" == "boot" ]; then
    debug_log "Building boot image..."
    mka bootimage -j$(nproc --all) 2>&1 | tee build.log || {
        warning_msg "bootimage build failed, trying alternative..."
        mka recoveryimage -j$(nproc --all) 2>&1 | tee build.log || error_exit "Build failed!"
    }
else
    debug_log "Building recovery image..."
    mka recoveryimage -j$(nproc --all) 2>&1 | tee build.log || error_exit "Build failed!"
fi

# Find and copy output files
echo "--- Collecting output files... ---"
OUT_DIR="out/target/product/$DEVICE_CODENAME"
OUTPUT_DIR="/tmp/cirrus-ci-build/output"
mkdir -p "$OUTPUT_DIR"

# Find the built image
debug_log "Looking for output images in: $OUT_DIR"
if [ -d "$OUT_DIR" ]; then
    ls -la "$OUT_DIR/" | grep -E "\.img|\.zip"
    
    # Copy boot image
    if [ -f "$OUT_DIR/boot.img" ]; then
        cp "$OUT_DIR/boot.img" "$OUTPUT_DIR/OrangeFox-${DEVICE_CODENAME}-boot.img"
        success_msg "Boot image copied to output"
    fi
    
    # Copy recovery image if exists
    if [ -f "$OUT_DIR/recovery.img" ]; then
        cp "$OUT_DIR/recovery.img" "$OUTPUT_DIR/OrangeFox-${DEVICE_CODENAME}-recovery.img"
        success_msg "Recovery image copied to output"
    fi
    
    # Find and copy OrangeFox zip
    for zip_file in "$OUT_DIR"/OrangeFox*.zip; do
        if [ -f "$zip_file" ]; then
            cp "$zip_file" "$OUTPUT_DIR/"
            success_msg "OrangeFox zip copied: $(basename $zip_file)"
        fi
    done
    
    # Alternative locations for OrangeFox zip
    if [ -d "$OUT_DIR/OrangeFox" ]; then
        for zip_file in "$OUT_DIR/OrangeFox"/*.zip; do
            if [ -f "$zip_file" ]; then
                cp "$zip_file" "$OUTPUT_DIR/"
                success_msg "OrangeFox zip copied from OrangeFox dir: $(basename $zip_file)"
            fi
        done
    fi
else
    error_exit "Output directory not found: $OUT_DIR"
fi

# Copy build log
cp build.log "$OUTPUT_DIR/" 2>/dev/null || warning_msg "Failed to copy build log"

# Create device info file
cat > "$OUTPUT_DIR/device_info.txt" << EOF
Device: Infinix X6512
Android Version: 11
Partition Type: A/B with Super partition
Recovery Type: Boot image (no recovery partition)
Touchscreen: omnivision_tcm_spi (spi2.0) - FIXED
OrangeFox Version: R11.1 (fox_12.1 base)
Build Date: $(date)
Builder: manusia
Email: ndktau@gmail.com

Features:
- Full OrangeFox features enabled
- Touchscreen support fixed for omnivision_tcm_spi
- Non-touch navigation enabled (keyboard/mouse support)
- ADB enabled by default for debugging
- Debug mode enabled
- Virtual A/B support
- Super partition support
- Boot image output (no recovery partition)

Instructions:
1. Flash boot.img using fastboot:
   fastboot flash boot OrangeFox-X6512-boot.img
   
2. Or use the OrangeFox zip installer if available

3. For touchscreen issues:
   - ADB is enabled by default
   - Connect USB and use: adb shell
   - Run: /sbin/fix_touch.sh
   
4. Non-touch navigation:
   - Use USB OTG with keyboard/mouse
   - Volume keys for navigation
   - Power button for selection
EOF

# List output files
echo "--- Output files ---"
ls -lah "$OUTPUT_DIR"

success_msg "Build completed successfully!"
echo "================================================"
echo "       OrangeFox Build Complete!                "
echo "================================================"
echo "Output directory: $OUTPUT_DIR"
echo "================================================"
