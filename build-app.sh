#!/bin/bash
# Build the Dikto macOS menu bar app
# Compiles Swift sources + links against libdikto_core.a
# ONNX Runtime is statically linked into libdikto_core.a (no dylib needed)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/Dikto.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"

GENERATED="$ROOT/DiktoApp/Generated"
SOURCES="$ROOT/DiktoApp/Sources"
RUST_LIB="$ROOT/target/release/libdikto_core.a"

# Ensure bindings exist
if [ ! -f "$GENERATED/dikto_core.swift" ]; then
    echo "Error: Swift bindings not found. Run: make generate-bindings"
    exit 1
fi

if [ ! -f "$RUST_LIB" ]; then
    echo "Error: Rust library not found. Run: make build-rust"
    exit 1
fi

# Create app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$CONTENTS/Resources"

# Copy Info.plist
cp "$ROOT/DiktoApp/Resources/Info.plist" "$CONTENTS/Info.plist"

echo "Compiling Swift sources..."

# Collect all swift source files
SWIFT_FILES=(
    "$GENERATED/dikto_core.swift"
    "$SOURCES/DiktoApp.swift"
    "$SOURCES/AppState.swift"
    "$SOURCES/KeyCodes.swift"
    "$SOURCES/MenuBarView.swift"
    "$SOURCES/OnboardingView.swift"
    "$SOURCES/PermissionView.swift"
    "$SOURCES/RecordingOverlay.swift"
    "$SOURCES/SettingsView.swift"
)

# The modulemap for the FFI C header
MODULEMAP="$GENERATED/dikto_coreFFI.modulemap"

SDK="$(xcrun --sdk macosx --show-sdk-path)"

swiftc \
    -swift-version 5 \
    -target arm64-apple-macosx14.0 \
    -sdk "$SDK" \
    -Xcc -fmodule-map-file="$MODULEMAP" \
    -I "$GENERATED" \
    "$RUST_LIB" \
    -Xlinker -lc++ \
    -Xlinker -framework -Xlinker Accelerate \
    -Xlinker -framework -Xlinker CoreAudio \
    -Xlinker -framework -Xlinker AudioToolbox \
    -Xlinker -framework -Xlinker Security \
    -Xlinker -framework -Xlinker SystemConfiguration \
    -Xlinker -framework -Xlinker CoreFoundation \
    -Xlinker -framework -Xlinker IOKit \
    -Xlinker -framework -Xlinker ServiceManagement \
    -Xlinker -framework -Xlinker Carbon \
    -framework AppKit \
    -framework SwiftUI \
    -o "$MACOS_DIR/DiktoApp" \
    "${SWIFT_FILES[@]}"

# Parse --release flag
RELEASE_BUILD=false
for arg in "$@"; do
    if [ "$arg" = "--release" ]; then
        RELEASE_BUILD=true
    fi
done

# Try to find a stable signing identity (keeps CDHash consistent across rebuilds,
# so accessibility permissions don't go stale)
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | { grep "Developer ID Application" || true; } | head -1 | awk -F'"' '{print $2}')

if [ -z "$IDENTITY" ]; then
    # Fall back to Apple Development identity
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | { grep "Apple Development" || true; } | head -1 | awk -F'"' '{print $2}')
fi

if [ -z "$IDENTITY" ]; then
    if [ "$RELEASE_BUILD" = true ]; then
        echo "ERROR: --release build requires a valid Developer ID signing identity"
        echo "No valid signing identity found. Install a Developer ID certificate first."
        exit 1
    fi
    IDENTITY="-"   # ad-hoc fallback
    echo "WARNING: No developer identity found, using ad-hoc signing"
    echo "  This is fine for development but NOT suitable for distribution."
    echo "  Use --release flag to enforce proper signing."
else
    echo "Signing with: $IDENTITY"
fi

# Remove extended attributes (must be immediately before codesign to avoid
# macOS re-adding provenance/FinderInfo attrs after compilation)
xattr -cr "$APP_DIR"

codesign --force --sign "$IDENTITY" \
    --options runtime \
    --timestamp \
    --deep \
    --entitlements "$ROOT/DiktoApp/DiktoApp.entitlements" \
    "$APP_DIR"

# Strip any xattrs macOS may have re-added between sign and verify
xattr -cr "$APP_DIR"

# Verify the signature
echo "Verifying signature..."
if codesign --verify --deep --strict "$APP_DIR" 2>&1; then
    echo "Signature verified successfully"
else
    echo "WARNING: Signature verification failed"
    if [ "$RELEASE_BUILD" = true ]; then
        exit 1
    fi
fi

echo "Created: $APP_DIR"
echo "Run with: open $APP_DIR"
