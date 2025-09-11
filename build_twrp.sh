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

# Clone device tree
echo "--- Cloning device tree... ---"
DEVICE_PATH="device/infinix/$DEVICE_CODENAME"
rm -rf $DEVICE_PATH
git clone $DEVICE_TREE -b $DEVICE_BRANCH $DEVICE_PATH

# Setup build environment
echo "--- Setting up build environment... ---"
source build/envsetup.sh

# Export variables
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL=C

# Build
echo "--- Starting build... ---"
lunch twrp_${DEVICE_CODENAME}-eng

# Clean
make clean

# Build boot image
echo "--- Building boot image... ---"
make bootimage -j$(nproc --all) 2>&1 | tee build.log

# Check output
OUTPUT_DIR="out/target/product/$DEVICE_CODENAME"
if [ -f "$OUTPUT_DIR/boot.img" ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Boot image built successfully!"
    mkdir -p /tmp/cirrus-ci-build/output
    cp "$OUTPUT_DIR/boot.img" /tmp/cirrus-ci-build/output/twrp-${DEVICE_CODENAME}-$(date +%Y%m%d).img
    
    # Generate checksums
    cd /tmp/cirrus-ci-build/output
    sha256sum *.img > sha256sums.txt
    
    echo "Output files:"
    ls -lah /tmp/cirrus-ci-build/output/
else
    echo -e "${RED}[ERROR]${NC} Build failed!"
    tail -100 build.log
    exit 1
fi

echo "================================================"
echo "     Build Complete!                            "
echo "================================================"
