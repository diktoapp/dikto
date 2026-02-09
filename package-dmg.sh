#!/bin/bash
# Create a distributable DMG from the built Dikto.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/Dikto.app"
DMG_NAME="Dikto"
DMG_PATH="$BUILD_DIR/$DMG_NAME.dmg"
STAGING="$BUILD_DIR/dmg-staging"

# Check that the app exists
if [ ! -d "$APP_DIR" ]; then
    echo "Error: $APP_DIR not found. Run 'make build-app' first."
    exit 1
fi

# Extract version from Info.plist
VERSION=$(defaults read "$APP_DIR/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "2.0.0")
DMG_FINAL="$BUILD_DIR/Dikto-${VERSION}.dmg"

echo "Creating DMG for Dikto v${VERSION}..."

# Clean up any previous staging
rm -rf "$STAGING"
rm -f "$DMG_PATH" "$DMG_FINAL"

# Create staging directory
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Create the DMG
hdiutil create \
    -volname "$DMG_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_FINAL"

# Clean up staging
rm -rf "$STAGING"

echo "Created: $DMG_FINAL"
echo "Size: $(du -h "$DMG_FINAL" | cut -f1)"
