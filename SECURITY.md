# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x     | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

If you discover a security vulnerability in Dikto, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, please [open a private security advisory](https://github.com/diktoapp/dikto/security/advisories/new) on GitHub.

### What to include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response timeline

- **Acknowledgment:** We aim to respond within 48 hours
- **Initial assessment:** Typically within 1 week
- **Fix timeline:** Depends on severity; we prioritize critical issues

### Scope

The following are in scope:

- The Dikto macOS application (`Dikto.app`)
- The `dikto-core` Rust library
- The `dikto` CLI tool
- Build and distribution scripts
- Model download and verification

The following are out of scope:

- Third-party model files hosted on Hugging Face
- Upstream dependencies (report to their maintainers)
- Social engineering attacks

## Security Design

- All models are downloaded over HTTPS
- Config files are stored with 0600 permissions (user-only read/write)
- No network communication except model downloads (no telemetry, no analytics)
- Audio data is processed locally and never transmitted
- Model integrity can be verified via SHA-256 checksums
