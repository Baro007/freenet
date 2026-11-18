#!/bin/bash
# freenet build script — swiftc all app sources into .app bundle
set -e

cd "$(dirname "$0")"

APP_NAME="freenet"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
TARGET_ARM="arm64-apple-macosx13.0"
TARGET_X86="x86_64-apple-macosx13.0"

# Collect sources: all .swift in app root except Tests/
SOURCES=()
while IFS= read -r f; do
  SOURCES+=("$f")
done < <(find . -maxdepth 1 -name '*.swift' | sort)

if [ ${#SOURCES[@]} -eq 0 ]; then
  echo "No Swift sources found"
  exit 1
fi

echo "[1/4] swiftc ile derleniyor (${#SOURCES[@]} dosya)..."
mkdir -p "$BUILD_DIR"
swiftc -O \
    -sdk "$SDK_PATH" \
    -target "$TARGET_ARM" \
    -framework Cocoa \
    -framework SwiftUI \
    -framework CryptoKit \
    "${SOURCES[@]}" \
    -o "$BUILD_DIR/${APP_NAME}_arm64"

swiftc -O \
    -sdk "$SDK_PATH" \
    -target "$TARGET_X86" \
    -framework Cocoa \
    -framework SwiftUI \
    -framework CryptoKit \
    "${SOURCES[@]}" \
    -o "$BUILD_DIR/${APP_NAME}_x86_64"

lipo -create -output "$BUILD_DIR/${APP_NAME}" "$BUILD_DIR/${APP_NAME}_arm64" "$BUILD_DIR/${APP_NAME}_x86_64"
rm "$BUILD_DIR/${APP_NAME}_arm64" "$BUILD_DIR/${APP_NAME}_x86_64"

echo "[2/4] .app bundle olusturuluyor..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/bin"
cp "$BUILD_DIR/${APP_NAME}" "$APP_BUNDLE/Contents/MacOS/"
cp Info.plist.template "$APP_BUNDLE/Contents/Info.plist"
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

mkdir -p Resources/bin

# Ensure sing-box present if possible
if [ ! -f "Resources/bin/sing-box" ]; then
    SYS_SINGBOX=""
    if command -v sing-box >/dev/null 2>&1; then
        SYS_SINGBOX="$(command -v sing-box)"
    elif [ -f "/opt/homebrew/bin/sing-box" ]; then
        SYS_SINGBOX="/opt/homebrew/bin/sing-box"
    fi
    if [ -n "$SYS_SINGBOX" ]; then
        cp "$SYS_SINGBOX" Resources/bin/sing-box
        chmod +x Resources/bin/sing-box
    else
        echo "Uyari: sing-box Resources/bin icinde yok (Hizli mod etkilenebilir)."
    fi
fi

# Bundle tor for Maks. Gizlilik (Homebrew or PATH)
if [ ! -f "Resources/bin/tor" ]; then
    SYS_TOR=""
    if command -v tor >/dev/null 2>&1; then
        SYS_TOR="$(command -v tor)"
    elif [ -f "/opt/homebrew/bin/tor" ]; then
        SYS_TOR="/opt/homebrew/bin/tor"
    elif [ -f "/opt/homebrew/opt/tor/bin/tor" ]; then
        SYS_TOR="/opt/homebrew/opt/tor/bin/tor"
    elif [ -f "/usr/local/bin/tor" ]; then
        SYS_TOR="/usr/local/bin/tor"
    fi
    if [ -n "$SYS_TOR" ]; then
        echo "Tor kopyalaniyor: $SYS_TOR"
        # Prefer real binary over symlink for portability
        REAL_TOR="$(python3 -c "import os; print(os.path.realpath('$SYS_TOR'))" 2>/dev/null || readlink -f "$SYS_TOR" 2>/dev/null || echo "$SYS_TOR")"
        cp "$REAL_TOR" Resources/bin/tor
        chmod +x Resources/bin/tor
    else
        echo "Uyari: tor yok. Maks. Gizlilik icin: brew install tor"
    fi
fi

# Refresh tracked checksums (ciadpi + sing-box) in Resources/bin, and full checksums inside bundle
if command -v shasum >/dev/null 2>&1; then
    (
      cd Resources/bin
      : > CHECKSUMS.sha256
      for b in ciadpi sing-box; do
        if [ -f "$b" ]; then shasum -a 256 "$b" >> CHECKSUMS.sha256; fi
      done
    )
fi

if [ -d "Resources" ] && [ "$(ls -A Resources 2>/dev/null)" ]; then
    cp -R Resources/* "$APP_BUNDLE/Contents/Resources/"
fi

if command -v shasum >/dev/null 2>&1; then
    (
      cd "$APP_BUNDLE/Contents/Resources/bin"
      : > CHECKSUMS.sha256
      for b in ciadpi sing-box tor; do
        if [ -f "$b" ]; then shasum -a 256 "$b" >> CHECKSUMS.sha256; fi
      done
    )
fi

chmod -R u+w "$APP_BUNDLE"

echo "[3/4] ad-hoc imzalama..."
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1 | tail -5 || true

echo "[4/4] tamam."
echo "Bundle: $APP_BUNDLE"
echo "Calistir: open $APP_BUNDLE"
