#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "=== Building Menu3 (Universal Binary: arm64 + x86_64) ==="
xcodebuild \
    -project menu3.xcodeproj \
    -scheme menu3 \
    -configuration Release \
    -arch arm64 -arch x86_64 \
    ONLY_ACTIVE_ARCH=NO \
    -derivedDataPath ./build \
    clean build

echo ""
echo "✅ Build complete!"
TARGET_BUILD_DIR="$(xcodebuild -project menu3.xcodeproj -scheme menu3 -configuration Release -showBuildSettings 2>/dev/null | awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / {print $2; exit}')"
FULL_PRODUCT_NAME="$(xcodebuild -project menu3.xcodeproj -scheme menu3 -configuration Release -showBuildSettings 2>/dev/null | awk -F ' = ' '/^[[:space:]]*FULL_PRODUCT_NAME = / {print $2; exit}')"
echo "Output: $TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"

if [ "${SKIP_DMG:-0}" != "1" ]; then
    echo ""
    echo "=== Auto packaging DMG after build ==="
    bash "$PROJECT_DIR/Scripts/create-dmg.sh"
fi
