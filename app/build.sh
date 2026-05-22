#!/bin/bash
# freenet build script — swiftc ile derle, .app bundle yap
set -e

cd "$(dirname "$0")"

APP_NAME="freenet"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macosx13.0"

echo "[1/4] swiftc ile derleniyor..."
mkdir -p "$BUILD_DIR"
swiftc -O \
    -sdk "$SDK_PATH" \
    -target "$TARGET" \
    -framework Cocoa \
    *.swift \
    -o "$BUILD_DIR/${APP_NAME}"

echo "[2/4] .app bundle olusturuluyor..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_DIR/${APP_NAME}" "$APP_BUNDLE/Contents/MacOS/"
cp Info.plist.template "$APP_BUNDLE/Contents/Info.plist"
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# sing-box binary'sini hazirla
if [ ! -f "Resources/bin/sing-box" ]; then
    echo "sing-box binary'si Resources/bin/ icinde bulunamadi, sistemden araniyor..."
    SYS_SINGBOX=""
    if which sing-box >/dev/null 2>&1; then
        SYS_SINGBOX="$(which sing-box)"
    elif [ -f "/opt/homebrew/bin/sing-box" ]; then
        SYS_SINGBOX="/opt/homebrew/bin/sing-box"
    elif [ -f "/usr/local/bin/sing-box" ]; then
        SYS_SINGBOX="/usr/local/bin/sing-box"
    fi

    if [ -n "$SYS_SINGBOX" ]; then
        echo "sing-box surada bulundu: $SYS_SINGBOX. Kopyalaniyor..."
        mkdir -p Resources/bin
        cp "$SYS_SINGBOX" Resources/bin/sing-box
        chmod +x Resources/bin/sing-box
    else
        echo "Hata: sing-box bulunamadi! Lutfen once 'brew install sing-box' calistirin."
        exit 1
    fi
fi

# Opsiyonel: Resources/ icindeki tum dosyalari kopyala
if [ -d "Resources" ] && [ "$(ls -A Resources)" ]; then
    cp -R Resources/* "$APP_BUNDLE/Contents/Resources/"
fi

# Yazma izinlerini garantile (xattr permission denied hatasini onlemek icin)
chmod -R u+w "$APP_BUNDLE"

echo "[3/4] ad-hoc imzalama..."
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1 | tail -3 || true

echo "[4/4] tamam."
echo ""
echo "Bundle: $APP_BUNDLE"
echo "Calistir: open $APP_BUNDLE"
echo "Yukle:    cp -R $APP_BUNDLE /Applications/ && xattr -dr com.apple.quarantine /Applications/${APP_NAME}.app"
