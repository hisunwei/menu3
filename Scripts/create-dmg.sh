#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP_PATH="./build/Build/Products/Release/RightMenu.app"
DMG_NAME="RightMenu.dmg"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH not found. Run build.sh first."
    exit 1
fi

rm -f "$DMG_NAME"

if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "RightMenu" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "RightMenu.app" 150 200 \
        --app-drop-link 450 200 \
        --hide-extension "RightMenu.app" \
        "$DMG_NAME" \
        "$APP_PATH"
else
    echo "create-dmg not found, using hdiutil fallback..."
    TEMP_DIR=$(mktemp -d)
    cp -R "$APP_PATH" "$TEMP_DIR/"
    ln -s /Applications "$TEMP_DIR/Applications"
    hdiutil create -volname "RightMenu" -srcfolder "$TEMP_DIR" -ov -format UDZO "$DMG_NAME"
    rm -rf "$TEMP_DIR"
fi

echo ""
echo "✅ DMG created: $PROJECT_DIR/$DMG_NAME"
