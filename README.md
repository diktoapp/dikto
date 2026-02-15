# Dikto

Voice-to-text for macOS. Records speech, transcribes locally. No cloud.

> macOS 14+ (Sonoma) &middot; Apple Silicon

[![Build](https://github.com/diktoapp/dikto/actions/workflows/build.yml/badge.svg)](https://github.com/diktoapp/dikto/actions/workflows/build.yml)
[![Test](https://github.com/diktoapp/dikto/actions/workflows/test.yml/badge.svg)](https://github.com/diktoapp/dikto/actions/workflows/test.yml)
[![Release](https://img.shields.io/github/v/release/diktoapp/dikto)](https://github.com/diktoapp/dikto/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/diktoapp/dikto/total)](https://github.com/diktoapp/dikto/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[Website](https://diktoapp.github.io) · [Download](https://github.com/diktoapp/dikto/releases/latest) · [Install](#quick-install) · [Discussions](https://github.com/diktoapp/dikto/discussions)

## Quick Install

**One-liner** (downloads, verifies, installs, bypasses Gatekeeper):

```bash
curl -fsSL https://diktoapp.github.io/install.sh | bash
```

**Homebrew:**

```bash
brew tap diktoapp/dikto
# GUI app
brew install --cask dikto
# CLI only (builds from source)
brew install diktoapp/dikto/dikto
```

**DMG:** Download from [Releases](https://github.com/diktoapp/dikto/releases/latest).

<details>
<summary><strong>Gatekeeper: "Dikto can't be opened"</strong></summary>

Dikto is ad-hoc signed but not Apple-notarized. The Homebrew and install-script methods bypass Gatekeeper automatically. If you downloaded the DMG directly:

1. **Right-click > Open:** Right-click Dikto.app, choose "Open", click "Open" in the dialog.
2. **Terminal:** `xattr -cr /Applications/Dikto.app`
3. **System Settings:** Privacy & Security > scroll down > "Open Anyway".

</details>

## Privacy

Your voice stays on your device. Dikto never connects to a server. All speech processing happens locally using on-device ML models. No accounts, no telemetry, no cloud APIs.

## Usage

Press **Option+R** to start recording. Speech is transcribed when you stop or silence is detected. The text is copied to your clipboard and pasted into the active app.

On first launch, macOS will prompt for **Microphone** access. Grant **Accessibility** permission in System Settings for auto-paste.

## Models

| Model | Size | Description |
|---|---|---|
| `parakeet-tdt-0.6b-v2` (default) | 2.5 GB | NVIDIA Parakeet TDT — high accuracy English |
| `parakeet-tdt-0.6b-v3` | 2.6 GB | NVIDIA Parakeet TDT — 25 EU languages |
| `whisper-tiny` | 75 MB | Whisper Tiny — fast, 99 languages |
| `whisper-small` | 460 MB | Whisper Small — balanced accuracy & speed |
| `whisper-large-v3-turbo` | 1.6 GB | Whisper Large v3 Turbo — highest accuracy |
| `distil-whisper-large-v3` | 1.5 GB | Distil-Whisper — 6x faster Whisper |

Download a model with the CLI:

```bash
dikto --setup --model whisper-small
```

Then select it in the app's Settings.

## Architecture

- **Rust core** (`dikto-core`) — audio capture, VAD, ASR engine, model management
- **Swift UI** (`DiktoApp`) — SwiftUI menu-bar app with recording overlay
- **CLI** (`dikto-cli`) — headless model setup

Config: `~/.config/dikto/config.json` &middot; Models: `~/.local/share/dikto/models/`

## Build from source

Prerequisites: [Rust](https://rustup.rs/) (1.75+), cmake (`brew install cmake`), macOS 14+.

```bash
git clone https://github.com/diktoapp/dikto.git
cd dikto
make build-app
open build/Dikto.app
```

## License

[MIT](LICENSE)
