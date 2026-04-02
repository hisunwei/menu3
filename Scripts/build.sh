#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "=== Building RightMenu (Universal Binary) ==="
xcodebuild \
    -project RightMenu.xcodeproj \
    -scheme RightMenu \
    -configuration Release \
    -arch arm64 -arch x86_64 \
    ONLY_ACTIVE_ARCH=NO \
    -derivedDataPath ./build \
    clean build

echo ""
echo "✅ Build complete!"
echo "Output: $PROJECT_DIR/build/Build/Products/Release/RightMenu.app"
