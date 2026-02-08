# sotto

Voice-to-text for macOS. A menu-bar app that records speech and transcribes it locally using NVIDIA Parakeet TDT. Everything runs on your machine — no cloud APIs.

> **macOS 14+ only.** Apple Silicon recommended.

## Architecture

- **Rust core** (`sotto-core`) — audio capture, VAD, ASR engine, model management
- **Swift UI** (`SottoApp`) — SwiftUI menu-bar app with recording overlay
- **CLI** (`sotto-cli`) — headless model setup

## Prerequisites

- macOS 14+ (Sonoma or later)
- [Rust toolchain](https://rustup.rs/) (1.75+)
- cmake (`brew install cmake`)

## Install

```bash
# Build the CLI and download a model
cargo build --release --bin sotto
./target/release/sotto --setup

# Build the app
make build-app
```

The setup command downloads the default model (~2.5 GB) to `~/.local/share/sotto/models/` and creates a config at `~/.config/sotto/config.json`.

## Usage

```bash
open build/Sotto.app
```

Press **Option+R** to start recording. Speech is transcribed when you stop or silence is detected. The transcribed text is copied to your clipboard.

On first use, macOS will prompt you to grant microphone access in **System Settings > Privacy & Security > Microphone**.

## Models

| Model | Size | Description |
|---|---|---|
| `parakeet-tdt-0.6b-v2` (default) | 2.5 GB | NVIDIA Parakeet TDT — high accuracy English (1.69% WER) |
| `parakeet-tdt-0.6b-v3` | 2.6 GB | NVIDIA Parakeet TDT — 25 EU languages |
| `whisper-tiny` | 75 MB | Whisper Tiny — fast, 99 languages |
| `whisper-small` | 460 MB | Whisper Small — balanced accuracy & speed |
| `whisper-large-v3-turbo` | 1.6 GB | Whisper Large v3 Turbo — highest accuracy |
| `distil-whisper-large-v3` | 1.5 GB | Distil-Whisper — 6x faster Whisper |

To use a different model:

```bash
sotto --setup --model whisper-small
```

Then select it in the app's Settings.

## License

MIT
