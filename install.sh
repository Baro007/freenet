#!/bin/bash
set -e

echo "=========================================="
echo "  Freenet macOS kurulum (kaynak derleme)"
echo "=========================================="
echo ""
echo "UYARI (tedarik zinciri): Uzak betikleri dogrudan"
echo "  curl ... | bash"
echo "ile calistirmak risklidir. Bu scripti once okuyun,"
echo "mumkunse git clone + app/build.sh + checksum dogrulayin."
echo "Dokuman: docs/BUILD.md"
echo ""

REPO_URL="https://github.com/Baro007/freenet.git"
INSTALL_DIR="/tmp/freenet_install_$$"

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

echo "Proje indiriliyor..."
git clone --quiet "$REPO_URL" "$INSTALL_DIR"

echo "Uygulama derleniyor..."
cd "$INSTALL_DIR/app"
chmod +x build.sh
./build.sh

# Optional checksum verification for bundled bins
if [ -f "Resources/bin/CHECKSUMS.sha256" ]; then
  echo "Checksum dogrulaniyor..."
  (cd Resources/bin && shasum -a 256 -c CHECKSUMS.sha256) || {
    echo "HATA: CHECKSUMS.sha256 dogrulamasi basarisiz."
    exit 1
  }
fi

echo "Uygulama /Applications klasorune yukleniyor..."
rm -rf /Applications/freenet.app
cp -R build/freenet.app /Applications/
xattr -dr com.apple.quarantine /Applications/freenet.app 2>/dev/null || true

echo "Gecici dosyalar temizleniyor..."
rm -rf "$INSTALL_DIR"

echo ""
echo "Kurulum tamamlandi."
echo "Niyetler: Hizli | Dengeli (WARP/Cloudflare) | Maks. Gizlilik (Tor)"
echo "Gercek anonimlik yalnizca Maks. Gizlilik (Tor)."
open /Applications/freenet.app
