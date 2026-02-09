#!/bin/bash
# Notarize Dikto.app for macOS distribution.
#
# Prerequisites:
# 1. Apple Developer ID Application certificate installed in Keychain
# 2. App-specific password stored in Keychain:
#    xcrun notarytool store-credentials "dikto-notarize" \
#      --apple-id "your@email.com" \
#      --team-id "TEAM_ID" \
#      --password "app-specific-password"
# 3. Build with: ./build-app.sh --release
#
# Usage:
#   ./notarize.sh                    # notarize the .app
#   ./notarize.sh --dmg              # notarize the .dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/Dikto.app"
KEYCHAIN_PROFILE="${DIKTO_NOTARIZE_PROFILE:-dikto-notarize}"

# Parse args
TARGET="app"
for arg in "$@"; do
    case "$arg" in
        --dmg) TARGET="dmg" ;;
    esac
done

if [ "$TARGET" = "dmg" ]; then
    VERSION=$(defaults read "$APP_DIR/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "2.0.0")
    SUBMIT_PATH="$BUILD_DIR/Dikto-${VERSION}.dmg"
    if [ ! -f "$SUBMIT_PATH" ]; then
        echo "Error: $SUBMIT_PATH not found. Run './package-dmg.sh' first."
        exit 1
    fi
else
    # Zip the app for notarization
    SUBMIT_PATH="$BUILD_DIR/Dikto-notarize.zip"
    echo "Zipping app for notarization..."
    ditto -c -k --keepParent "$APP_DIR" "$SUBMIT_PATH"
fi

echo "Submitting $SUBMIT_PATH for notarization..."
xcrun notarytool submit "$SUBMIT_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

echo "Stapling notarization ticket..."
if [ "$TARGET" = "dmg" ]; then
    xcrun stapler staple "$SUBMIT_PATH"
else
    xcrun stapler staple "$APP_DIR"
    rm -f "$SUBMIT_PATH"  # Clean up the zip
fi

echo "Notarization complete!"
echo "Verify with: spctl --assess --verbose --type execute $APP_DIR"
