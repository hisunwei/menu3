#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

TARGET_BUILD_DIR="$(xcodebuild -project menu3.xcodeproj -scheme menu3 -configuration Release -showBuildSettings 2>/dev/null | awk -F ' = ' '/^[[:space:]]*TARGET_BUILD_DIR = / {print $2; exit}')"
FULL_PRODUCT_NAME="$(xcodebuild -project menu3.xcodeproj -scheme menu3 -configuration Release -showBuildSettings 2>/dev/null | awk -F ' = ' '/^[[:space:]]*FULL_PRODUCT_NAME = / {print $2; exit}')"
APP_PATH="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"

if [ -z "$APP_VERSION" ]; then
    APP_VERSION="latest"
fi

DMG_NAME="Menu3-${APP_VERSION}.dmg"
LATEST_DMG="Menu3.dmg"

if [ ! -d "$APP_PATH" ]; then
    APP_PATH="./build/Build/Products/Release/Menu3.app"
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Error: Release app not found. Run build.sh first."
    exit 1
fi

rm -f "$DMG_NAME" "$LATEST_DMG"

if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "Menu3" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "Menu3.app" 150 200 \
        --app-drop-link 450 200 \
        --hide-extension "Menu3.app" \
        "$DMG_NAME" \
        "$APP_PATH"
else
    echo "create-dmg not found, using hdiutil fallback..."
    TEMP_DIR=$(mktemp -d)
    cp -R "$APP_PATH" "$TEMP_DIR/"
    ln -s /Applications "$TEMP_DIR/Applications"
    hdiutil create -volname "Menu3" -srcfolder "$TEMP_DIR" -ov -format UDZO "$DMG_NAME"
    rm -rf "$TEMP_DIR"
fi

cp -f "$DMG_NAME" "$LATEST_DMG"

echo ""
echo "✅ DMG created: $PROJECT_DIR/$DMG_NAME"
echo "✅ DMG latest alias: $PROJECT_DIR/$LATEST_DMG"
