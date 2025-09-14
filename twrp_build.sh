#!/bin/bash

###############################################
# TWRP Build Script for Infinix X6512
# Device: MT6761 (Helio A22) 
# Android: 11
# Features: Debug, Validation, Error Handling
###############################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DEVICE="Infinix-X6512"
VENDOR="infinix"
MANIFEST_URL="https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git"
MANIFEST_BRANCH="twrp-11"
DEVICE_TREE_URL="https://github.com/manusia251/twrp-test"
DEVICE_TREE_BRANCH="main"
DEVICE_PATH="device/infinix/Infinix-X6512"
OUT_DIR="out/target/product/${DEVICE}"
WORK_DIR="${HOME}/twrp"
LOG_DIR="${WORK_DIR}/logs"
LOG_FILE="${LOG_DIR}/build_$(date +%Y%m%d_%H%M%S).log"

# Create log directory
mkdir -p "${LOG_DIR}"

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${MAGENTA}[DEBUG]${NC} $*" | tee -a "${LOG_FILE}"
    fi
}

# Error handler
error_handler() {
    local line_no=$1
    local exit_code=$2
    log_error "Build failed at line $line_no with exit code $exit_code"
    log_error "Check log file: ${LOG_FILE}"
    
    # Try to identify the error
    if [ -f "${WORK_DIR}/build.log" ]; then
        log_error "Last 50 lines of build log:"
        tail -n 50 "${WORK_DIR}/build.log" | tee -a "${LOG_FILE}"
    fi
    
    exit $exit_code
}

trap 'error_handler ${LINENO} $?' ERR

# Print banner
print_banner() {
    echo -e "${BLUE}" | tee -a "${LOG_FILE}"
    echo "╔════════════════════════════════════════════════╗" | tee -a "${LOG_FILE}"
    echo "║     TWRP Builder for Infinix X6512            ║" | tee -a "${LOG_FILE}"
    echo "║     Device: MT6761 (Helio A22)                ║" | tee -a "${LOG_FILE}"
    echo "║     Android: 11 | A/B Partitions              ║" | tee -a "${LOG_FILE}"
    echo "║     Features: Touch, Root, Decrypt, Fastbootd ║" | tee -a "${LOG_FILE}"
    echo "╚════════════════════════════════════════════════╝" | tee -a "${LOG_FILE}"
    echo -e "${NC}" | tee -a "${LOG_FILE}"
    log_info "Build started at $(date)"
    log_info "Log file: ${LOG_FILE}"
}

# Check system requirements
check_requirements() {
    log "Checking system requirements..."
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot determine OS version"
        exit 1
    fi
    
    source /etc/os-release
    log_info "OS: $NAME $VERSION"
    
    # Check available memory
    local mem_total=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $mem_total -lt 8 ]]; then
        log_warning "Low memory detected: ${mem_total}GB (minimum 8GB recommended)"
    else
        log_info "Memory: ${mem_total}GB available"
    fi
    
    # Check available disk space
    local disk_free=$(df -BG "${HOME}" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $disk_free -lt 50 ]]; then
        log_error "Insufficient disk space: ${disk_free}GB (minimum 50GB required)"
        exit 1
    else
        log_info "Disk space: ${disk_free}GB available"
    fi
    
    # Check for required commands
    local required_cmds="git repo curl wget make gcc java python3"
    for cmd in $required_cmds; do
        if ! command -v $cmd &> /dev/null; then
            log_warning "Command '$cmd' not found, will install..."
        else
            log_debug "✓ $cmd found: $(which $cmd)"
        fi
    done
    
    log "System requirements check completed"
}

# Install dependencies
install_dependencies() {
    log "Installing build dependencies..."
    
    local packages=(
        bc bison build-essential ccache curl flex
        g++-multilib gcc-multilib git gnupg gperf
        imagemagick lib32ncurses5-dev lib32readline-dev
        lib32z1-dev liblz4-tool libncurses5 libncurses5-dev
        libsdl1.2-dev libssl-dev libxml2 libxml2-utils
        lzop pngcrush rsync schedtool squashfs-tools
        xsltproc zip zlib1g-dev python python3
        wget unzip openjdk-8-jdk file tree dos2unix
    )
    
    log_info "Updating package lists..."
    sudo apt-get update -qq
    
    log_info "Installing packages..."
    for package in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii  $package "; then
            log_debug "✓ $package already installed"
        else
            log_info "Installing $package..."
            sudo apt-get install -y -qq "$package" || log_warning "Failed to install $package"
        fi
    done
    
    # Install repo if not present
    if ! command -v repo &> /dev/null; then
        log_info "Installing repo tool..."
        mkdir -p ~/bin
        curl -s https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
        chmod a+x ~/bin/repo
        export PATH=~/bin:$PATH
        echo 'export PATH=~/bin:$PATH' >> ~/.bashrc
    fi
    
    log "Dependencies installation completed"
}

# Setup ccache
setup_ccache() {
    log "Setting up ccache..."
    
    export USE_CCACHE=1
    export CCACHE_SIZE=50G
    export CCACHE_DIR="${HOME}/.ccache"
    export CCACHE_COMPRESS=1
    
    ccache -M $CCACHE_SIZE
    ccache -z
    
    log_info "Ccache configuration:"
    ccache -s | tee -a "${LOG_FILE}"
    
    log "Ccache setup completed"
}

# Sync TWRP sources
sync_sources() {
    log "Syncing TWRP sources..."
    
    mkdir -p "${WORK_DIR}"
    cd "${WORK_DIR}"
    
    # Initialize repo
    if [ ! -d .repo ]; then
        log_info "Initializing repo..."
        repo init --depth=1 -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" 2>&1 | tee -a "${LOG_FILE}"
    else
        log_info "Repo already initialized"
    fi
    
    # Sync with retry mechanism
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        log_info "Sync attempt $((retry + 1))/$max_retries..."
        
        if repo sync -c --no-clone-bundle --no-tags --optimized-fetch --prune --force-sync -j$(nproc) 2>&1 | tee -a "${LOG_FILE}"; then
            log "Source sync completed successfully"
            return 0
        else
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                log_warning "Sync failed, retrying in 10 seconds..."
                sleep 10
            fi
        fi
    done
    
    log_error "Failed to sync sources after $max_retries attempts"
    exit 1
}

# Clone and validate device tree
clone_device_tree() {
    log "Cloning device tree..."
    
    cd "${WORK_DIR}"
    
    # Remove old device tree if exists
    if [ -d "$DEVICE_PATH" ]; then
        log_info "Removing old device tree..."
        rm -rf "$DEVICE_PATH"
    fi
    
    # Clone device tree
    log_info "Cloning from $DEVICE_TREE_URL..."
    git clone "$DEVICE_TREE_URL" -b "$DEVICE_TREE_BRANCH" "$DEVICE_PATH" 2>&1 | tee -a "${LOG_FILE}"
    
    log "Device tree cloned, validating files..."
    validate_device_tree
}

# Validate device tree files
validate_device_tree() {
    log "Validating device tree structure..."
    
    cd "${WORK_DIR}/${DEVICE_PATH}"
    
    # Show tree structure
    log_info "Device tree structure:"
    tree -L 3 . | tee -a "${LOG_FILE}"
    
    # Check required files
    local required_files=(
        "Android.mk"
        "AndroidProducts.mk"
        "BoardConfig.mk"
        "device.mk"
        "omni_${DEVICE}.mk"
        "recovery.fstab"
        "prebuilt/kernel"
        "prebuilt/dtb.img"
        "recovery/root/init.recovery.mt6761.rc"
    )
    
    local missing_files=()
    local invalid_files=()
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Missing: $file"
            missing_files+=("$file")
        else
            log_debug "✓ Found: $file"
            
            # Check file validity
            if [ -s "$file" ]; then
                # Check for DOS line endings
                if file "$file" | grep -q "CRLF"; then
                    log_warning "$file has DOS line endings, converting..."
                    dos2unix "$file" 2>/dev/null || true
                fi
                
                # Validate makefiles syntax
                if [[ "$file" == *.mk ]]; then
                    if grep -q "LOCAL_PATH" "$file" || grep -q "PRODUCT_" "$file" || grep -q "BOARD_" "$file" || grep -q "TARGET_" "$file"; then
                        log_debug "  $file syntax looks valid"
                    else
                        log_warning "  $file might have syntax issues"
                        invalid_files+=("$file")
                    fi
                fi
            else
                log_error "$file is empty!"
                invalid_files+=("$file")
            fi
        fi
    done
    
    # Check prebuilt kernel
    if [ -f "prebuilt/kernel" ]; then
        local kernel_info=$(file "prebuilt/kernel")
        log_info "Kernel info: $kernel_info"
        
        if [[ ! "$kernel_info" == *"Linux kernel"* ]] && [[ ! "$kernel_info" == *"data"* ]]; then
            log_warning "Prebuilt kernel might be invalid"
        fi
    fi
    
    # Check DTB
    if [ -f "prebuilt/dtb.img" ]; then
        local dtb_info=$(file "prebuilt/dtb.img")
        log_info "DTB info: $dtb_info"
    fi
    
    # Report validation results
    if [ ${#missing_files[@]} -gt 0 ]; then
        log_error "Missing files: ${missing_files[*]}"
        log_error "Device tree validation failed!"
        exit 1
    fi
    
    if [ ${#invalid_files[@]} -gt 0 ]; then
        log_warning "Files with potential issues: ${invalid_files[*]}"
    fi
    
    log "Device tree validation completed"
}

# Apply patches and fixes
apply_patches() {
    log "Applying patches and fixes..."
    
    cd "${WORK_DIR}/${DEVICE_PATH}"
    
    # Backup original files
    cp BoardConfig.mk BoardConfig.mk.bak
    cp device.mk device.mk.bak
    
    # Add configurations to BoardConfig.mk
    log_info "Updating BoardConfig.mk..."
    cat >> BoardConfig.mk << 'EOF'

# === Additional Configurations (Added by build script) ===

# Fastbootd support for super partition
TW_INCLUDE_FASTBOOTD := true
TW_FASTBOOTD_MODE := true

# Magisk support
TW_INCLUDE_RESETPROP := true
TW_EXCLUDE_MAGISK_PREBUILT := false

# Decryption support
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_CRYPTO_FBE := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true
BOARD_USES_METADATA_PARTITION := true

# Root access
BOARD_BUILD_SYSTEM_ROOT_IMAGE := false
TW_USE_NEW_MINADBD := true

# Debugging features
TARGET_USES_LOGD := true
TWRP_INCLUDE_LOGCAT := true
TARGET_RECOVERY_DEVICE_MODULES += debuggerd
TW_RECOVERY_ADDITIONAL_RELINK_FILES += $(TARGET_OUT_EXECUTABLES)/debuggerd
TW_CRYPTO_SYSTEM_VOLD_DEBUG := true

# Screen configuration
TW_NO_SCREEN_BLANK := true
RECOVERY_SDCARD_ON_DATA := true
TW_DEFAULT_BRIGHTNESS := 120
TW_MAX_BRIGHTNESS := 255
TW_BRIGHTNESS_PATH := "/sys/class/leds/lcd-backlight/brightness"

# Touchscreen fix
BOARD_USE_LEGACY_TOUCHSCREEN := false
TW_USE_MODEL_HARDWARE_ID_FOR_DEVICE_ID := true
EOF
    
    # Create comprehensive touchscreen init script
    log_info "Creating touchscreen init script..."
    mkdir -p recovery/root
    cat > recovery/root/init.recovery.touchscreen.rc << 'EOF'
# Touchscreen and Debug Configuration for Infinix X6512

on early-init
    # Mount necessary filesystems for debugging
    mount debugfs debugfs /sys/kernel/debug
    chmod 0755 /sys/kernel/debug
    
    # Enable kernel messages
    write /proc/sys/kernel/printk 8
    write /proc/sys/kernel/dmesg_restrict 0

on init
    # Create directories for touch firmware if needed
    mkdir /vendor/firmware 0755 system system
    
    # Set up logging
    setprop persist.debug.trace 1
    setprop debug.atrace.tags.enableflags 0xffffffff

on fs
    # Wait for sysfs
    wait /sys/class/input 5
    wait /sys/bus/spi/devices 5

on boot
    # Omnivision TCM SPI touchscreen initialization
    write /sys/bus/spi/drivers/omnivision_tcm_spi/bind "spi2.0"
    
    # Alternative binding methods (if first fails)
    write /sys/bus/spi/drivers_probe "omnivision_tcm_spi"
    
    # Set input device permissions
    chmod 0660 /dev/input/event0
    chmod 0660 /dev/input/event1
    chmod 0660 /dev/input/event2
    chmod 0660 /dev/input/event3
    chmod 0660 /dev/input/mice
    chown system input /dev/input/event0
    chown system input /dev/input/event1
    chown system input /dev/input/event2
    chown system input /dev/input/event3
    
    # Enable touchscreen controller (Omnivision specific)
    write /sys/class/omnivision_tcm/tcm0/enable 1
    write /sys/class/omnivision_tcm/tcm0/wake_gesture 0
    
    # MediaTek platform specific
    write /sys/devices/platform/11012000.spi2/spi_master/spi2/spi2.0/enable 1
    
    # Touch panel settings (MTK TPD)
    write /proc/tpd_em_log 1
    
    # Enable ADB with root
    setprop ro.adb.secure 0
    setprop ro.secure 0
    setprop ro.debuggable 1
    setprop persist.sys.usb.config adb
    setprop persist.service.adb.enable 1
    setprop persist.service.debuggable 1
    setprop service.adb.root 1
    
    # Start ADB daemon
    start adbd

on property:sys.usb.config=adb
    start adbd

on property:sys.usb.config=mtp,adb
    start adbd

# Service for touch debugging
service touch_debug /system/bin/sh -c "while true; do cat /proc/bus/input/devices > /tmp/input_devices.txt; sleep 5; done"
    user root
    group root
    disabled
    oneshot

on property:debug.touch=1
    start touch_debug
EOF
    
    # Update device.mk
    log_info "Updating device.mk..."
    cat >> device.mk << 'EOF'

# Touchscreen and debugging additions
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/recovery/root/init.recovery.touchscreen.rc:root/init.recovery.touchscreen.rc

# Additional properties for debugging
PRODUCT_PROPERTY_OVERRIDES += \
    ro.adb.secure=0 \
    ro.secure=0 \
    ro.debuggable=1 \
    persist.service.adb.enable=1 \
    persist.service.debuggable=1 \
    persist.sys.usb.config=adb
EOF
    
    log "Patches applied successfully"
}

# Build TWRP
build_twrp() {
    log "Starting TWRP build..."
    
    cd "${WORK_DIR}"
    
    # Set environment variables
    export ALLOW_MISSING_DEPENDENCIES=true
    export LC_ALL=C
    export BUILD_USERNAME=$(whoami)
    export BUILD_HOSTNAME=$(hostname)
    
    # Source build environment
    log_info "Setting up build environment..."
    source build/envsetup.sh
    
    # Show available lunch choices
    log_info "Available lunch choices:"
    lunch 2>&1 | tee -a "${LOG_FILE}"
    
    # Select device
    log_info "Selecting device: omni_${DEVICE}-eng"
    lunch omni_${DEVICE}-eng 2>&1 | tee -a "${LOG_FILE}" || {
        log_warning "omni lunch failed, trying alternatives..."
        lunch aosp_${DEVICE}-eng 2>&1 | tee -a "${LOG_FILE}" || \
        lunch twrp_${DEVICE}-eng 2>&1 | tee -a "${LOG_FILE}" || {
            log_error "Failed to lunch device!"
            exit 1
        }
    }
    
    # Display build configuration
    log_info "Build configuration:"
    echo "Device: $TARGET_DEVICE" | tee -a "${LOG_FILE}"
    echo "Product: $TARGET_PRODUCT" | tee -a "${LOG_FILE}"
    echo "Variant: $TARGET_BUILD_VARIANT" | tee -a "${LOG_FILE}"
    echo "Architecture: $TARGET_ARCH" | tee -a "${LOG_FILE}"
    echo "CPU ABI: $TARGET_CPU_ABI" | tee -a "${LOG_FILE}"
    
    # Clean build directory
    log_info "Cleaning build directory..."
    make clean 2>&1 | tee -a "${LOG_FILE}"
    
    # Start build
    log_info "Building recovery image..."
    local build_start=$(date +%s)
    
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        make -j$(nproc) recoveryimage showcommands 2>&1 | tee "${WORK_DIR}/build.log"
    else
        make -j$(nproc) recoveryimage 2>&1 | tee "${WORK_DIR}/build.log"
    fi
    
    local build_end=$(date +%s)
    local build_time=$((build_end - build_start))
    
    log_info "Build completed in $((build_time / 60)) minutes and $((build_time % 60)) seconds"
}

# Validate build output
validate_output() {
    log "Validating build output..."
    
    cd "${WORK_DIR}"
    
    # Check for boot.img (A/B device uses boot as recovery)
    if [ -f "${OUT_DIR}/boot.img" ]; then
        log "✓ boot.img found!"
        
        local img_size=$(stat -c%s "${OUT_DIR}/boot.img")
        local img_size_mb=$((img_size / 1024 / 1024))
        
        log_info "Image size: ${img_size_mb}MB"
        log_info "Image info: $(file ${OUT_DIR}/boot.img)"
        
        # Calculate checksums
        local md5=$(md5sum "${OUT_DIR}/boot.img" | cut -d' ' -f1)
        local sha256=$(sha256sum "${OUT_DIR}/boot.img" | cut -d' ' -f1)
        
        log_info "MD5: $md5"
        log_info "SHA256: $sha256"
        
        # Copy to home with timestamp
        local output_name="twrp-${DEVICE}-$(date +%Y%m%d-%H%M).img"
        cp "${OUT_DIR}/boot.img" "${HOME}/${output_name}"
        
        # Create info file
        cat > "${HOME}/${output_name}.txt" << EOF
TWRP Build Information
======================
Device: ${DEVICE}
Vendor: ${VENDOR}
Build Date: $(date)
Build Host: $(hostname)
Build User: $(whoami)

Image Details:
- Filename: ${output_name}
- Size: ${img_size_mb}MB
- MD5: ${md5}
- SHA256: ${sha256}

Features:
- Touchscreen support (Omnivision TCM SPI)
- ADB Root enabled
- Fastbootd support
- Magisk support
- FBE Decryption support
- A/B partition support

Flash Instructions:
1. Reboot to bootloader:
   adb reboot bootloader

2. Flash TWRP:
   fastboot flash boot ${output_name}

3. Reboot to recovery:
   fastboot reboot recovery

Troubleshooting:
- If touchscreen doesn't work, use 'adb shell' to debug
- Check /tmp/recovery.log for errors
- Use 'adb shell dmesg | grep -i touch' to check touchscreen driver

EOF
        
        log "Build output saved to: ${HOME}/${output_name}"
        log "Build info saved to: ${HOME}/${output_name}.txt"
        
    else
        log_error "boot.img not found!"
        
        # Check for recovery.img as fallback
        if [ -f "${OUT_DIR}/recovery.img" ]; then
            log_warning "Found recovery.img instead (non-A/B behavior)"
            ls -lh "${OUT_DIR}/recovery.img"
        else
            log_error "No recovery image found!"
            log_error "Output directory contents:"
            ls -la "${OUT_DIR}/" | tee -a "${LOG_FILE}"
            exit 1
        fi
    fi
    
    # Show ccache stats
    log_info "Ccache statistics:"
    ccache -s | tee -a "${LOG_FILE}"
    
    log "Output validation completed"
}

# Main function
main() {
    print_banner
    
    case "${1:-}" in
        "check")
            check_requirements
            ;;
        "deps")
            check_requirements
            install_dependencies
            ;;
        "setup")
            check_requirements
            install_dependencies
            setup_ccache
            ;;
        "sync")
            sync_sources
            ;;
        "clone")
            clone_device_tree
            ;;
        "patch")
            apply_patches
            ;;
        "build")
            build_twrp
            validate_output
            ;;
        "clean")
            log "Cleaning build directory..."
            cd "${WORK_DIR}" && make clean
            log "Clean completed"
            ;;
        "all")
            check_requirements
            install_dependencies
            setup_ccache
            sync_sources
            clone_device_tree
            apply_patches
            build_twrp
            validate_output
            ;;
        *)
            echo "Usage: $0 {check|deps|setup|sync|clone|patch|build|clean|all}"
            echo ""
            echo "Commands:"
            echo "  check  - Check system requirements"
            echo "  deps   - Install build dependencies"
            echo "  setup  - Install deps and setup ccache"
            echo "  sync   - Sync TWRP sources"
            echo "  clone  - Clone and validate device tree"
            echo "  patch  - Apply patches and fixes"
            echo "  build  - Build TWRP"
            echo "  clean  - Clean build directory"
            echo "  all    - Run all steps"
            echo ""
            echo "Environment variables:"
            echo "  DEBUG=true    - Enable debug output"
            echo "  VERBOSE=true  - Enable verbose build output"
            exit 1
            ;;
    esac
    
    log "Operation completed successfully!"
}

# Run main function
main "$@"
