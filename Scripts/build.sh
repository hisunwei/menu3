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
echo "Output: $PROJECT_DIR/build/Build/Products/Release/Menu3.app"
