#!/bin/bash
# install.sh - Curl-pipeable installer for Dikto (voice-to-text for macOS)
#
# Usage:
#   curl -fsSL https://diktoapp.github.io/install.sh | bash
#   curl -fsSL https://diktoapp.github.io/install.sh | bash -s -- --cli
#
# Options:
#   --cli    Install only the CLI binary to /usr/local/bin/
#
# Requirements:
#   - macOS 14 (Sonoma) or later
#   - Apple Silicon (M1/M2/M3/M4)

set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
GITHUB_ORG="diktoapp"
GITHUB_REPO="dikto"
API_URL="https://api.github.com/repos/${GITHUB_ORG}/${GITHUB_REPO}/releases/latest"
INSTALL_DIR="/Applications"
CLI_INSTALL_DIR="/usr/local/bin"
MIN_MACOS_VERSION=14

# ---------------------------------------------------------------------------
# Color helpers (disabled when stdout is not a tty)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BOLD=''
    RESET=''
fi

info()    { printf "${BOLD}==> %s${RESET}\n" "$*"; }
success() { printf "${GREEN}==> %s${RESET}\n" "$*"; }
warn()    { printf "${YELLOW}==> %s${RESET}\n" "$*"; }
error()   { printf "${RED}==> ERROR: %s${RESET}\n" "$*" >&2; }
die()     { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Cleanup on exit
# ---------------------------------------------------------------------------
TMPDIR_INSTALL=""

cleanup() {
    if [ -n "${TMPDIR_INSTALL}" ] && [ -d "${TMPDIR_INSTALL}" ]; then
        rm -rf "${TMPDIR_INSTALL}"
    fi
    # Unmount any lingering DMG mounts we may have created
    if [ -n "${MOUNT_POINT:-}" ] && [ -d "${MOUNT_POINT}" ]; then
        hdiutil detach "${MOUNT_POINT}" -quiet 2>/dev/null || true
    fi
}

trap cleanup EXIT

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
CLI_ONLY=false

for arg in "$@"; do
    case "${arg}" in
        --cli)
            CLI_ONLY=true
            ;;
        --help|-h)
            printf "Usage: install.sh [--cli]\n"
            printf "  --cli    Install only the CLI binary to %s\n" "${CLI_INSTALL_DIR}"
            exit 0
            ;;
        *)
            die "Unknown option: ${arg}"
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------

# 1. Architecture --------------------------------------------------------
ARCH="$(uname -m)"
if [ "${ARCH}" != "arm64" ]; then
    die "Dikto requires Apple Silicon (M1/M2/M3/M4). Detected architecture: ${ARCH}"
fi

# 2. macOS version -------------------------------------------------------
if ! command -v sw_vers &>/dev/null; then
    die "This installer only supports macOS."
fi

MACOS_VERSION="$(sw_vers -productVersion)"
MACOS_MAJOR="$(echo "${MACOS_VERSION}" | cut -d. -f1)"

if [ "${MACOS_MAJOR}" -lt "${MIN_MACOS_VERSION}" ]; then
    die "Dikto requires macOS 14 (Sonoma) or later. Detected: macOS ${MACOS_VERSION}"
fi

# 3. Required tools -------------------------------------------------------
for cmd in curl shasum hdiutil; do
    if ! command -v "${cmd}" &>/dev/null; then
        die "Required command not found: ${cmd}"
    fi
done

# ---------------------------------------------------------------------------
# Fetch latest release version from GitHub
# ---------------------------------------------------------------------------
info "Fetching latest Dikto release..."

RELEASE_JSON="$(curl -fsSL "${API_URL}")" \
    || die "Failed to fetch release information from GitHub."

# Extract the tag name (e.g. "v1.0.0") and strip the leading "v"
TAG="$(echo "${RELEASE_JSON}" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
VERSION="${TAG#v}"

if [ -z "${VERSION}" ]; then
    die "Could not determine the latest release version."
fi

success "Latest version: ${VERSION} (${TAG})"

# ---------------------------------------------------------------------------
# Prepare temp directory
# ---------------------------------------------------------------------------
TMPDIR_INSTALL="$(mktemp -d)"

# ---------------------------------------------------------------------------
# Install: CLI-only mode
# ---------------------------------------------------------------------------
if [ "${CLI_ONLY}" = true ]; then
    CLI_TARBALL="dikto-cli-${VERSION}-aarch64-apple-darwin.tar.gz"
    CLI_CHECKSUM="${CLI_TARBALL}.sha256"
    DOWNLOAD_BASE="https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/releases/download/${TAG}"

    # Download tarball
    info "Downloading ${CLI_TARBALL}..."
    curl -fSL --progress-bar \
        "${DOWNLOAD_BASE}/${CLI_TARBALL}" \
        -o "${TMPDIR_INSTALL}/${CLI_TARBALL}" \
        || die "Failed to download CLI tarball."

    # Download checksum
    info "Downloading checksum..."
    curl -fsSL \
        "${DOWNLOAD_BASE}/${CLI_CHECKSUM}" \
        -o "${TMPDIR_INSTALL}/${CLI_CHECKSUM}" \
        || die "Failed to download checksum file."

    # Verify SHA256
    info "Verifying checksum..."
    (cd "${TMPDIR_INSTALL}" && shasum -a 256 -c "${CLI_CHECKSUM}") \
        || die "Checksum verification failed! The download may be corrupted."
    success "Checksum OK"

    # Extract to install directory
    info "Installing CLI to ${CLI_INSTALL_DIR}..."
    if [ ! -d "${CLI_INSTALL_DIR}" ]; then
        sudo mkdir -p "${CLI_INSTALL_DIR}"
    fi

    # Extract into temp dir first, then move the binary
    tar -xzf "${TMPDIR_INSTALL}/${CLI_TARBALL}" -C "${TMPDIR_INSTALL}" \
        || die "Failed to extract CLI tarball."

    # Move the binary (may require sudo for /usr/local/bin)
    if [ -w "${CLI_INSTALL_DIR}" ]; then
        mv "${TMPDIR_INSTALL}/dikto" "${CLI_INSTALL_DIR}/dikto"
    else
        sudo mv "${TMPDIR_INSTALL}/dikto" "${CLI_INSTALL_DIR}/dikto"
    fi

    sudo chmod +x "${CLI_INSTALL_DIR}/dikto" 2>/dev/null \
        || chmod +x "${CLI_INSTALL_DIR}/dikto"

    success "Dikto CLI ${VERSION} installed to ${CLI_INSTALL_DIR}/dikto"

    # Summary
    printf "\n"
    printf "${BOLD}-------------------------------------------------------${RESET}\n"
    printf "${BOLD}  Dikto CLI ${VERSION} installed successfully!${RESET}\n"
    printf "${BOLD}-------------------------------------------------------${RESET}\n"
    printf "\n"
    printf "  Run ${BOLD}dikto --help${RESET} to get started.\n"
    printf "\n"
    printf "${BOLD}  First-run permissions:${RESET}\n"
    printf "    1. ${YELLOW}Microphone${RESET}  - Grant access when prompted, or enable in\n"
    printf "       System Settings > Privacy & Security > Microphone\n"
    printf "    2. ${YELLOW}Accessibility${RESET} - Required for global keyboard shortcuts.\n"
    printf "       System Settings > Privacy & Security > Accessibility\n"
    printf "\n"

    exit 0
fi

# ---------------------------------------------------------------------------
# Install: Full app (DMG) mode — default
# ---------------------------------------------------------------------------
DMG_FILE="Dikto-${VERSION}.dmg"
DMG_CHECKSUM="${DMG_FILE}.sha256"
DOWNLOAD_BASE="https://github.com/${GITHUB_ORG}/${GITHUB_REPO}/releases/download/${TAG}"

# Download DMG
info "Downloading ${DMG_FILE}..."
curl -fSL --progress-bar \
    "${DOWNLOAD_BASE}/${DMG_FILE}" \
    -o "${TMPDIR_INSTALL}/${DMG_FILE}" \
    || die "Failed to download DMG."

# Download checksum
info "Downloading checksum..."
curl -fsSL \
    "${DOWNLOAD_BASE}/${DMG_CHECKSUM}" \
    -o "${TMPDIR_INSTALL}/${DMG_CHECKSUM}" \
    || die "Failed to download checksum file."

# Verify SHA256
info "Verifying checksum..."
(cd "${TMPDIR_INSTALL}" && shasum -a 256 -c "${DMG_CHECKSUM}") \
    || die "Checksum verification failed! The download may be corrupted."
success "Checksum OK"

# Mount DMG
info "Mounting disk image..."
MOUNT_OUTPUT="$(hdiutil attach -nobrowse -quiet "${TMPDIR_INSTALL}/${DMG_FILE}" 2>&1)" \
    || die "Failed to mount DMG: ${MOUNT_OUTPUT}"

# Find the mount point (last column of the last line from hdiutil output)
MOUNT_POINT="$(echo "${MOUNT_OUTPUT}" | tail -1 | awk -F'\t' '{print $NF}' | xargs)"

if [ ! -d "${MOUNT_POINT}" ]; then
    die "Could not determine DMG mount point."
fi

# Locate the app bundle
APP_PATH="${MOUNT_POINT}/Dikto.app"
if [ ! -d "${APP_PATH}" ]; then
    die "Dikto.app not found in mounted DMG at ${MOUNT_POINT}"
fi

# Copy to /Applications (remove old version if present)
info "Installing Dikto.app to ${INSTALL_DIR}..."
if [ -d "${INSTALL_DIR}/Dikto.app" ]; then
    warn "Removing existing Dikto.app..."
    rm -rf "${INSTALL_DIR}/Dikto.app"
fi

cp -R "${APP_PATH}" "${INSTALL_DIR}/Dikto.app" \
    || die "Failed to copy Dikto.app to ${INSTALL_DIR}."

# Clear Gatekeeper quarantine attribute
info "Clearing Gatekeeper quarantine flags..."
xattr -cr "${INSTALL_DIR}/Dikto.app" 2>/dev/null || true

# Unmount DMG
info "Unmounting disk image..."
hdiutil detach "${MOUNT_POINT}" -quiet 2>/dev/null || true
unset MOUNT_POINT  # prevent double-detach in cleanup trap

success "Dikto ${VERSION} installed to ${INSTALL_DIR}/Dikto.app"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf "\n"
printf "${BOLD}-------------------------------------------------------${RESET}\n"
printf "${BOLD}  Dikto ${VERSION} installed successfully!${RESET}\n"
printf "${BOLD}-------------------------------------------------------${RESET}\n"
printf "\n"
printf "  Open Dikto from your Applications folder or Spotlight.\n"
printf "\n"
printf "${BOLD}  First-run permissions (macOS will prompt you):${RESET}\n"
printf "    1. ${YELLOW}Microphone${RESET}  - Required for voice-to-text.\n"
printf "       System Settings > Privacy & Security > Microphone\n"
printf "    2. ${YELLOW}Accessibility${RESET} - Required for global keyboard shortcuts\n"
printf "       and text insertion.\n"
printf "       System Settings > Privacy & Security > Accessibility\n"
printf "\n"
printf "  To uninstall, simply drag Dikto.app to the Trash.\n"
printf "\n"
