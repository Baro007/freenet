#!/bin/bash
# Build Universal Binary release archive + SHA-256 checksum for GitHub Releases & In-App Self-Updater.
set -e

cd "$(dirname "$0")"
VER="$(tr -d '[:space:]' < ../VERSION)"
OUT_DIR="build/release"
ZIP_NAME="freenet-v${VER}-macos-universal.zip"

echo "=== Building Freenet v${VER} Universal Binary ==="
./Tests/run_tests.sh
./build.sh

echo "=== Packaging ${ZIP_NAME} ==="
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/$ZIP_NAME" "$OUT_DIR/$ZIP_NAME.sha256"
# Use ditto to preserve macOS bundle permissions, symlinks, and code signature
ditto -c -k --sequesterRsrc --keepParent build/freenet.app "$OUT_DIR/$ZIP_NAME"

(
  cd "$OUT_DIR"
  shasum -a 256 "$ZIP_NAME" > "${ZIP_NAME}.sha256"
  cat "${ZIP_NAME}.sha256"
)

echo "=== Release artifacts ready ==="
ls -lh "$OUT_DIR/$ZIP_NAME" "$OUT_DIR/$ZIP_NAME.sha256"
