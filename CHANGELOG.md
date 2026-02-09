# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-02-09

### Added
- Complete rewrite: Rust core with UniFFI bindings to Swift macOS app
- NVIDIA Parakeet TDT models (v2 English, v3 multilingual) as default ASR backend
- Whisper.cpp models (tiny, small, large-v3-turbo, distil-large-v3)
- Push-to-talk (hold) and toggle activation modes
- Global hotkey with configurable shortcut (Carbon RegisterEventHotKey)
- Voice Activity Detection (VAD) for automatic speech endpoint detection
- Floating overlay showing recording status and partial transcription
- Auto-copy to clipboard and auto-paste into active app
- Model download manager with progress reporting
- Idle model unloading (5-minute timeout) and memory pressure handling
- Launch at login support via SMAppService
- Accessibility permission probing with stale-cache detection
- Settings UI with General, Models, and Permissions tabs
- SHA-256 hash verification for model downloads
- Config file permissions set to 0600
- Language code validation
- CI/CD workflows (test, build, release, security audit)
- DMG packaging and notarization scripts
- Homebrew formula
- cargo-deny configuration for license and advisory checking

### Changed
- Renamed from "Sotto" to "Dikto"
- Bundle ID: `dev.dikto.app`
- Config location: `~/.config/dikto/config.json`
- Models location: `~/.local/share/dikto/models/`
- Default model: Parakeet TDT 0.6B v2 (was Whisper tiny.en)
- Automatic migration from v1 Whisper model names to Parakeet default

### Fixed
- Removed `expect()` panics in config path resolution
- Proper error propagation for missing home directory
- UTF-8 path validation for Whisper model loading
- Lock poisoning now logged with warnings instead of silent fallback
- Atomic ordering upgraded from Relaxed to Acquire/Release for thread safety
- Carbon event handler cleanup on hotkey registration failure
- Settings window lifecycle with NSWindowDelegate
- Download button disabled during active downloads
- Temp download files cleaned up on all error paths

### Security
- Config file written with 0600 permissions
- SHA-256 verification infrastructure for model downloads
- Model file validation uses specific filenames instead of any `.bin`
- NSAccessibilityUsageDescription added to Info.plist

## [1.0.0] - 2025-01-01

### Added
- Initial release as "Sotto" — Python-based voice-to-text using Whisper
