#!/bin/bash
#
# Skrip Build OrangeFox Recovery - VERSI OTOMATIS FINAL
# =======================================================================
# Dibuat berdasarkan skrip TWRP, dimodifikasi untuk OrangeFox.
# Asumsi: BoardConfig.mk di device tree sudah disesuaikan untuk OrangeFox.
# =======================================================================

set -e

# --- [BAGIAN 1: Konfigurasi Awal] ---
# Parse args dari .cirrus (DEVICE_TREE DEVICE_BRANCH DEVICE_CODENAME MANIFEST_BRANCH TARGET_RECOVERY_IMAGE)
DEVICE_TREE_URL="$1"
DEVICE_TREE_BRANCH="$2"
DEVICE_CODENAME="$3"
MANIFEST_BRANCH="fox_11.0"  # Hardcoded untuk Android 11
BUILD_TARGET="$5"

# --- [DIUBAH] Defaults disesuaikan untuk OrangeFox ---
DEVICE_TREE_URL="${DEVICE_TREE_URL:-https://github.com/manusia251/twrp-test.git}"
DEVICE_TREE_BRANCH="${DEVICE_TREE_BRANCH:-main}"
DEVICE_CODENAME="${DEVICE_CODENAME:-X6512}"
BUILD_TARGET="${BUILD_TARGET:-boot}"  # Diubah ke boot untuk hasil boot.img
VENDOR_NAME="infinix"

# --- [BARU] Variabel untuk info build OrangeFox ---
# Variabel ini akan digunakan di beberapa tempat
export FOX_VERSION="R12.1_1" # Sesuaikan versinya jika perlu
export FOX_BUILD_TYPE="Stable"    # Bisa juga "Beta"

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

# --- [BAGIAN 2: Persiapan Lingkungan] ---
WORKDIR=$(pwd)
export GITHUB_WORKSPACE=$WORKDIR

echo "--- Membuat dan masuk ke direktori build... ---"
# [DIUBAH] Nama folder menjadi 'orangefox' agar lebih jelas
cd ..
mkdir -p "$WORKDIR/orangefox"
cd "$WORKDIR/orangefox"
echo "--- Direktori saat ini: $(pwd) ---"

git config --global user.name "manusia251"
git config --global user.email "darkside@gmail.com"

# --- [BAGIAN 3: Sinkronisasi Source Code] ---
echo "--- Langkah 1: Inisialisasi manifest OrangeFox... ---"
# [DIUBAH] Menggunakan manifest resmi OrangeFox
repo init -u https://gitlab.com/OrangeFox/Manifest.git -b ${MANIFEST_BRANCH}

echo "--- Langkah 2: Membuat local manifest untuk device tree... ---"
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/orangefox_device_tree.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <project name="${DEVICE_TREE_URL#https://github.com/}" path="device/${VENDOR_NAME}/${DEVICE_CODENAME}" remote="github" revision="${DEVICE_TREE_BRANCH}" />
</manifest>
EOF

echo "--- Langkah 3: Memulai sinkronisasi repositori. Ini mungkin butuh waktu lama... ---"
repo sync -c --force-sync --no-clone-bundle --no-tags -j$(nproc --all)
echo "--- Sinkronisasi selesai. ---"

# --- [BAGIAN 4: Proses Kompilasi] ---
echo "--- Langkah 4: Memulai proses kompilasi... ---"
source build/envsetup.sh

# --- [DIUBAH] Variabel khusus untuk build OrangeFox ---
# Variabel dari BoardConfig.mk biasanya sudah cukup, tapi ini untuk memastikan
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL="C"
export OF_MAINTAINER="manusia251" # Pastikan sama dengan di BoardConfig.mk
# Variabel FOX_VERSION dan FOX_BUILD_TYPE sudah di-export di atas

# Variabel tambahan untuk skip komponen yang tidak perlu & atasi error
export BOARD_HAVE_BLUETOOTH=false
export TARGET_SKIP_VTS_BUILD=true
export SKIP_VTS_BUILD=true
export DISABLE_VTS_BUILD=true

echo "--- Menjalankan lunch untuk omni_${DEVICE_CODENAME}-eng... ---"
lunch omni_${DEVICE_CODENAME}-eng

echo "--- Menjalankan make ${BUILD_TARGET}image... ---"
mka ${BUILD_TARGET}image

# --- [BAGIAN 5: Persiapan Hasil Build] ---
echo "--- Langkah 5: Menyiapkan hasil build... ---"
RESULT_DIR="$WORKDIR/orangefox/out/target/product/${DEVICE_CODENAME}"
OUTPUT_DIR="$WORKDIR/output"
mkdir -p "$OUTPUT_DIR"

# --- [DIUBAH] Logika untuk mencari file output OrangeFox ---
# Nama file output OrangeFox biasanya lebih spesifik
ORANGEFOX_IMG_NAME="OrangeFox-${FOX_VERSION}-${FOX_BUILD_TYPE}-${DEVICE_CODENAME}.img"
ORANGEFOX_ZIP_NAME="OrangeFox-${FOX_VERSION}-${FOX_BUILD_TYPE}-${DEVICE_CODENAME}.zip"
GENERIC_RECOVERY_IMG="boot.img"  # Diubah ke boot.img untuk target boot

# Cek file output
if [ -f "$RESULT_DIR/$ORANGEFOX_IMG_NAME" ] || [ -f "$RESULT_DIR/$GENERIC_RECOVERY_IMG" ]; then
    echo "--- File output ditemukan! Menyalin ke direktori output... ---"
    
    # Salin file .img
    cp -f "$RESULT_DIR/$ORANGEFOX_IMG_NAME" "$OUTPUT_DIR/" 2>/dev/null || true
    cp -f "$RESULT_DIR/$GENERIC_RECOVERY_IMG" "$OUTPUT_DIR/" 2>/dev/null || true
    
    # Salin juga file .zip jika ada
    cp -f "$RESULT_DIR/$ORANGEFOX_ZIP_NAME" "$OUTPUT_DIR/" 2>/dev/null || true
else
    echo "--- ERROR: File output build tidak ditemukan di ${RESULT_DIR}. Cek log kompilasi di atas. ---"
    exit 1
fi

# --- [BAGIAN 6: Selesai] ---
echo "--- Build sukses! Cek folder 'output' untuk file recovery. ---"
ls -lh "$OUTPUT_DIR"
echo "============================================================"
echo " Skrip Selesai "
echo "============================================================"
