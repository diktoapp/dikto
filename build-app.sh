#!/bin/bash
# Build the Sotto macOS menu bar app
# Compiles Swift sources + links against libsotto_core.a
# ONNX Runtime is statically linked into libsotto_core.a (no dylib needed)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/Sotto.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"

GENERATED="$ROOT/SottoApp/Generated"
SOURCES="$ROOT/SottoApp/Sources"
RUST_LIB="$ROOT/target/release/libsotto_core.a"

# Ensure bindings exist
if [ ! -f "$GENERATED/sotto_core.swift" ]; then
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
cp "$ROOT/SottoApp/Resources/Info.plist" "$CONTENTS/Info.plist"

echo "Compiling Swift sources..."

# Collect all swift source files
SWIFT_FILES=(
    "$GENERATED/sotto_core.swift"
    "$SOURCES/SottoApp.swift"
    "$SOURCES/AppState.swift"
    "$SOURCES/MenuBarView.swift"
    "$SOURCES/RecordingOverlay.swift"
    "$SOURCES/SettingsView.swift"
)

# The modulemap for the FFI C header
MODULEMAP="$GENERATED/sotto_coreFFI.modulemap"

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
    -o "$MACOS_DIR/SottoApp" \
    "${SWIFT_FILES[@]}"

# Remove extended attributes and ad-hoc code sign with hardened runtime
xattr -cr "$APP_DIR"
codesign --force --sign - \
    --options runtime \
    --entitlements "$ROOT/SottoApp/SottoApp.entitlements" \
    "$APP_DIR"

echo "Created: $APP_DIR"
echo "Run with: open $APP_DIR"
