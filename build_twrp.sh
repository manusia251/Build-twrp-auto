#!/usr/bin/env bash
# Build OrangeFox for MT6761 (X6512) - Android 11 target boot.img
# Base: TWRP minimal manifest twrp-12.1 + vendor/recovery (OrangeFox) + vendor/omni
set -euo pipefail
set -x

# Args dari .cirrus
DEVICE_TREE_URL="${1:-https://github.com/manusia251/twrp-test.git}"
DEVICE_TREE_BRANCH="${2:-main}"
DEVICE_CODENAME="${3:-X6512}"
_IGNORED_MANIFEST="${4:-fox_11.0}"      # diabaikan (OFOX 11.0 deprecated)
BUILD_TARGET="${5:-boot}"               # boot -> bootimage
VENDOR_NAME="infinix"

# Base branch
TWRP_BRANCH="twrp-12.1"                 # stabil, kecil
OF_VENDOR_BRANCH="master"               # vendor/recovery
OMNI_VENDOR_BRANCH_PRIMARY="android-11" # prefer 11
OMNI_VENDOR_BRANCH_FALLBACK="android-12.1" # fallback 12.1 jika 11 tak ada

# Variabel OrangeFox
export FOX_VERSION="R11.1_1"
export FOX_BUILD_TYPE="Stable"
export OF_MAINTAINER="manusia251"

echo "======== Build OrangeFox ========"
echo "Base manifest   : $TWRP_BRANCH"
echo "Device tree URL : $DEVICE_TREE_URL ($DEVICE_TREE_BRANCH)"
echo "Codename        : $DEVICE_CODENAME"
echo "Build target    : ${BUILD_TARGET}image"
echo "================================="

WORKDIR="$(pwd)"
export GITHUB_WORKSPACE="$WORKDIR"

# Git settings ringan
git config --global user.name "manusia251" || true
git config --global user.email "darkside@gmail.com" || true
git config --global core.compression 1 || true
git config --global advice.detachedHead false || true

# Workspace
mkdir -p "$WORKDIR/ofx"
cd "$WORKDIR/ofx"

# Repo tool sudah terinstall dari .cirrus.yaml
# Init & sync minimal manifest (cepat)
if [ ! -d ".repo" ]; then
  repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b "$TWRP_BRANCH" --depth=1
fi

# Sync hemat resource
repo sync -c --force-sync --no-clone-bundle --no-tags -j2 || {
  echo "[WARN] repo sync failed once, retrying with -j1"
  repo sync -c --force-sync --no-clone-bundle --no-tags -j1
}

# Pastikan envsetup ada
if [ ! -f "build/envsetup.sh" ]; then
  echo "[ERROR] build/envsetup.sh not found after repo sync!"
  find . -maxdepth 3 -type f -name envsetup.sh
  exit 1
fi

# Clone vendor OrangeFox
if [ ! -d "vendor/recovery" ]; then
  git clone --depth=1 -b "$OF_VENDOR_BRANCH" https://gitlab.com/OrangeFox/vendor/recovery.git vendor/recovery
fi

# Clone vendor/omni (try android-11, fallback android-12.1)
if [ ! -d "vendor/omni" ]; then
  git clone --depth=1 -b "$OMNI_VENDOR_BRANCH_PRIMARY" https://github.com/omnirom/android_vendor_omni.git vendor/omni || {
    echo "[WARN] vendor/omni $OMNI_VENDOR_BRANCH_PRIMARY not found, trying $OMNI_VENDOR_BRANCH_FALLBACK"
    git clone --depth=1 -b "$OMNI_VENDOR_BRANCH_FALLBACK" https://github.com/omnirom/android_vendor_omni.git vendor/omni
  }
fi

# Clone device tree kamu (cepat)
DEVICE_TREE_PATH="device/${VENDOR_NAME}/${DEVICE_CODENAME}"
rm -rf "$DEVICE_TREE_PATH"
git clone --depth=1 -b "$DEVICE_TREE_BRANCH" "$DEVICE_TREE_URL" "$DEVICE_TREE_PATH"

echo "[DEBUG] Device tree contents:"
ls -la "$DEVICE_TREE_PATH" || true

# Patch dinamis BoardConfig + init.rc touch
pushd "$DEVICE_TREE_PATH"

# 1) Perbaiki BOARD_INCLUDE_DTB_IN_BOOTIMG yang kosong di blok prebuilt (jika ada)
if grep -q "BOARD_INCLUDE_DTB_IN_BOOTIMG :=" BoardConfig.mk 2>/dev/null; then
  sed -i 's/BOARD_INCLUDE_DTB_IN_BOOTIMG[[:space:]]*:=.*/BOARD_INCLUDE_DTB_IN_BOOTIMG := true/g' BoardConfig.mk
fi

# 2) Pastikan flag penting untuk A/B + RAB + include recovery/root
{
  echo ""
  echo "# --- Appended by CI: OrangeFox/TWRP flags ---"
  echo "ALLOW_MISSING_DEPENDENCIES := true"
  echo "BOARD_USES_RECOVERY_AS_BOOT := true"
  echo "TARGET_USERIMAGES_USE_EXT4 := true"
  echo "TARGET_USERIMAGES_USE_F2FS := true"
  echo "TARGET_RECOVERY_PIXEL_FORMAT := \"RGBX_8888\""
  echo "TARGET_RECOVERY_DEVICE_DIRS := \$(DEVICE_PATH)/recovery"
  echo "TWRP_INCLUDE_LOGCAT := true"
  echo "TARGET_USES_LOGD := true"
  echo "TW_USE_TOOLBOX := true"
  echo "TW_INCLUDE_REPACKTOOLS := true"
  echo "TW_EXCLUDE_APEX := true"
  echo "TW_NO_SCREEN_TIMEOUT := true"
  echo "TW_NO_SCREEN_BLANK := true"
  echo "TW_CUSTOM_CPU_TEMP_PATH := /sys/class/thermal/thermal_zone0/temp"
  echo "TW_BRIGHTNESS_PATH := \"/sys/class/leds/lcd-backlight/brightness\""
  echo "TW_MAX_BRIGHTNESS := 255"
  echo "TW_DEFAULT_BRIGHTNESS := 120"
  echo "FOX_USE_TWRP_RECOVERY_IMAGE_BUILDER := 1"
  echo "OF_PATCH_AVB20 := 1"
  echo "OF_AB_DEVICE := 1"
  echo "OF_USE_KEY_HANDLER := 1"
  echo "OF_FLASHLIGHT_ENABLE := 1"
  echo "OF_SCREEN_H := 1612"
  echo "OF_SCREEN_W := 720"
  echo "OF_STATUS_H := 80"
  echo "OF_STATUS_INDENT_LEFT := 48"
  echo "OF_STATUS_INDENT_RIGHT := 48"
  echo "TW_LOAD_VENDOR_MODULES := \"omnivision_tcm.ko\""
} >> BoardConfig.mk

# 3) Jika ada prebuilt dtbo, aktifkan include dtbo untuk recovery-as-boot device (beberapa MTK butuh)
if [ -f "prebuilt/dtbo.img" ]; then
  echo "TARGET_PREBUILT_DTBO := \$(DEVICE_PATH)/prebuilt/dtbo.img" >> BoardConfig.mk
  echo "BOARD_INCLUDE_RECOVERY_DTBO := true" >> BoardConfig.mk
fi

# 4) Tambahkan init.recovery.mt6761.rc (touch attempt)
mkdir -p recovery/root
cat > recovery/root/init.recovery.mt6761.rc <<'EOF'
on init
    # Longgarin permission input biar key/touch kebaca
    chmod 0666 /dev/input/event0
    chmod 0666 /dev/input/event1
    chmod 0666 /dev/input/event2
    chmod 0666 /dev/input/event3
    # Enable touchscreen (generic)
    write /sys/kernel/touchscreen/enable 1
    # Omnivision TCM SPI (alamat bisa beda per DTB)
    write /sys/devices/platform/soc/11010000.spi2/spi_master/spi2/spi2.0/input/input0/enabled 1
    # coba load modul dari vendor kalau ada
    insmod /vendor/lib/modules/omnivision_tcm.ko
on boot
    # Contoh path lain yang kadang ada, tidak fatal kalau gagal
    write /proc/touchpanel/oppo_tp_direction 0
EOF

popd

# JDK dan Python
if command -v javac >/dev/null 2>&1; then javac -version || true; fi
# Pastikan JDK 11 dipakai
if [ -x /usr/lib/jvm/java-11-openjdk-amd64/bin/java ]; then
  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
  export PATH="$JAVA_HOME/bin:$PATH"
fi
# Pastikan python mengarah ke python3
if ! python --version 2>/dev/null | grep -q "Python 3"; then
  ln -sf /usr/bin/python3 /usr/bin/python || true
fi

# Ccache
export USE_CCACHE=1
export CCACHE_DIR="/tmp/ccache"
ccache -M 20G || true

# Build env
source build/envsetup.sh

# Debug: tampilkan target lunch yang tersedia
lunch 2>&1 | grep -E "omni_|twrp_|aosp_" | head -20 || true

# Lunch omni_X6512
LUNCH_TARGET="omni_${DEVICE_CODENAME}-eng"
lunch "$LUNCH_TARGET" || {
  echo "[ERROR] lunch $LUNCH_TARGET gagal. Periksa file omni_${DEVICE_CODENAME}.mk dan androidproducts.mk"
  find device -maxdepth 3 -name "omni_${DEVICE_CODENAME}.mk" -o -name "*${DEVICE_CODENAME}*.mk" || true
  exit 1
}

# Build bootimage (A/B + recovery-as-boot -> output boot.img)
mka ${BUILD_TARGET}image -j"$(nproc)" || {
  echo "[WARN] mka gagal, coba make..."
  make ${BUILD_TARGET}image -j"$(nproc)"
}

# Output
RESULT_DIR="out/target/product/${DEVICE_CODENAME}"
OUTPUT_DIR="$WORKDIR/output"
mkdir -p "$OUTPUT_DIR"

echo "[DEBUG] Hasil build di: $RESULT_DIR"
ls -la "$RESULT_DIR" | grep -E "\.img|\.zip" || true

if [ -f "$RESULT_DIR/boot.img" ]; then
  cp -f "$RESULT_DIR/boot.img" "$OUTPUT_DIR/OrangeFox-${FOX_VERSION}-${DEVICE_CODENAME}-boot.img"
fi
[ -f "$RESULT_DIR/recovery.img" ] && cp -f "$RESULT_DIR/recovery.img" "$OUTPUT_DIR/"

echo "[INFO] Files in output:"
ls -lh "$OUTPUT_DIR" || true
echo "=== DONE ==="
