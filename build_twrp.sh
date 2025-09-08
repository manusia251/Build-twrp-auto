#!/bin/bash
#
# Skrip Build TWRP - VERSI OTOMATIS FINAL (Fixed for TWRP)
# =================================================================

set -e

# Parse args dari .cirrus (DEVICE_TREE DEVICE_BRANCH DEVICE_CODENAME MANIFEST_BRANCH TARGET_RECOVERY_IMAGE)
DEVICE_TREE_URL="$1"
DEVICE_TREE_BRANCH="$2"
DEVICE_CODENAME="$3"
MANIFEST_BRANCH="$4"
BUILD_TARGET="$5"  # e.g., boot

# Defaults jika kosong
MANIFEST_BRANCH="${MANIFEST_BRANCH:-twrp-11}"
DEVICE_TREE_URL="${DEVICE_TREE_URL:-https://github.com/manusia251/twrp-test.git}"
DEVICE_TREE_BRANCH="${DEVICE_TREE_BRANCH:-main}"
DEVICE_CODENAME="${DEVICE_CODENAME:-X6512}"
BUILD_TARGET="${BUILD_TARGET:-boot}"
VENDOR_NAME="infinix"

echo "========================================"
echo "Memulai Build TWRP"
echo "----------------------------------------"
echo "Manifest Branch   : ${MANIFEST_BRANCH}"
echo "Device Tree URL   : ${DEVICE_TREE_URL}"
echo "Device Branch     : ${DEVICE_TREE_BRANCH}"
echo "Device Codename   : ${DEVICE_CODENAME}"
echo "Build Target      : ${BUILD_TARGET}image"
echo "========================================"

# Variabel tambahan
WORKDIR=$(pwd)
export GITHUB_WORKSPACE=$WORKDIR

# --- 2. Persiapan Lingkungan Build ---
echo "--- Berada di direktori $(pwd) ---"
echo "--- Membuat dan masuk ke direktori twrp... ---"
cd ..
mkdir -p "$WORKDIR/twrp"
cd "$WORKDIR/twrp"
echo "--- Direktori saat ini: $(pwd) ---"

git config --global user.name "manusia251"
git config --global user.email "darkside@gmail.com"

# --- 3. Inisialisasi dan Konfigurasi Repo ---
echo "--- Langkah 1: Inisialisasi manifest TWRP... ---"
repo init -u https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git -b ${MANIFEST_BRANCH}

echo "--- Langkah 2: Membuat local manifest untuk device tree... ---"
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/twrp_device_tree.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <project name="${DEVICE_TREE_URL#https://github.com/}" path="device/${VENDOR_NAME}/${DEVICE_CODENAME}" remote="github" revision="${DEVICE_TREE_BRANCH}" />
</manifest>
EOF

echo "--- Langkah 3: Memulai sinkronisasi repositori. Mohon tunggu... ---"
repo sync -c -j$(nproc --all) --force-sync --no-clone-bundle --no-tags
echo "--- Sinkronisasi selesai. ---"

# --- 4. Verifikasi Device Tree ---
echo "--- Langkah 4: Memeriksa keberadaan device tree... ---"
if [ -d "device/${VENDOR_NAME}/${DEVICE_CODENAME}" ] && [ -f "device/${VENDOR_NAME}/${DEVICE_CODENAME}/AndroidProducts.mk" ] && [ -f "device/${VENDOR_NAME}/${DEVICE_CODENAME}/vendorsetup.sh" ]; then
    echo "--- Device tree ditemukan dan lengkap. Lokasi: device/${VENDOR_NAME}/${DEVICE_CODENAME} ---"
else
    echo "--- ERROR: Device tree TIDAK DITEMUKAN atau file kunci hilang (AndroidProducts.mk/vendorsetup.sh). Cek repo. ---"
    exit 1
fi

# --- 5. Proses Kompilasi ---
echo "--- Langkah 5: Memulai proses kompilasi... ---"
source build/envsetup.sh
export ALLOW_MISSING_DEPENDENCIES=true
export OF_PATH=${PWD}  # Legacy, tapi OK untuk TWRP
export RECOVERY_VARIANT=twrp

echo "--- Menjalankan lunch... ---"
lunch omni_${DEVICE_CODENAME}-eng  # Kunci: omni_, bukan twrp_
echo "--- Menjalankan make... ---"
mka ${BUILD_TARGET}image  # e.g., bootimage

# --- 6. Persiapan Hasil Build ---
echo "--- Langkah 6: Menyiapkan hasil build... ---"
RESULT_DIR="$WORKDIR/twrp/out/target/product/${DEVICE_CODENAME}"
OUTPUT_DIR="$WORKDIR/output"
mkdir -p "$OUTPUT_DIR"

if [ -f "$RESULT_DIR/boot.img" ] || [ -f "$RESULT_DIR/${BUILD_TARGET}.img" ] || [ -f "$RESULT_DIR/recovery.img" ]; then
    echo "--- File output TWRP ditemukan! Menyalin ke direktori output... ---"
    cp -f "$RESULT_DIR/boot.img" "$OUTPUT_DIR/" 2>/dev/null || true
    cp -f "$RESULT_DIR/${BUILD_TARGET}.img" "$OUTPUT_DIR/" 2>/dev/null || true
    cp -f "$RESULT_DIR/recovery.img" "$OUTPUT_DIR/" 2>/dev/null || true
else
    echo "--- Peringatan: File output build tidak ditemukan di ${RESULT_DIR}. Cek log. ---"
    exit 1
fi

# --- 7. Selesai ---
echo "--- Build selesai! Cek folder output. ---"
ls -lh "$OUTPUT_DIR"
echo "========================================"
