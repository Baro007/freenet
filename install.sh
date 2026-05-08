#!/bin/bash
set -e

echo "=========================================="
echo "🛡️  Freenet macOS Kurulumuna Hosgeldiniz"
echo "=========================================="
echo ""

# Repo URL
REPO_URL="https://github.com/Baro007/freenet.git"
INSTALL_DIR="/tmp/freenet_install"

# Temizlik
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

echo "📦 Proje indiriliyor..."
git clone --quiet "$REPO_URL" "$INSTALL_DIR"

echo "🔨 Uygulama derleniyor..."
cd "$INSTALL_DIR/app"
chmod +x build.sh
./build.sh > /dev/null

echo "🚀 Uygulama /Applications klasorune yukleniyor..."
rm -rf /Applications/freenet.app
cp -R build/freenet.app /Applications/
xattr -dr com.apple.quarantine /Applications/freenet.app

echo "🧹 Gecici dosyalar temizleniyor..."
cd ~
rm -rf "$INSTALL_DIR"

echo ""
echo "✅ Kurulum Tamamlandi!"
echo "Uygulama baslatiliyor..."
open /Applications/freenet.app
