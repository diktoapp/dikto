# sotto

[![npm version](https://img.shields.io/npm/v/sotto)](https://www.npmjs.com/package/sotto)
[![license](https://img.shields.io/npm/l/sotto)](./LICENSE)

Voice input for Claude Code. Speak instead of typing.

A local, open-source MCP server that streams your voice to [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for real-time transcription and sends the text to Claude Code. Everything runs on your machine — no cloud APIs, no network calls.

> **macOS only.** Sotto uses `osascript` and the Cocoa framework for its floating status indicator. Linux and Windows are not supported.

## How It Works

```
You speak → sotto streams audio to whisper-stream for live transcription
→ a floating indicator shows status and live text
→ silence detected or you click stop → text returned to Claude
→ Claude treats it as your message and responds
```

## Prerequisites

- **macOS** (Apple Silicon recommended, Intel works too)
- **Node.js** >= 18
- **whisper-cpp** — local speech-to-text with live streaming

Install system dependencies:

```bash
brew install whisper-cpp
```

## Installation

```bash
npm install -g sotto
sotto-setup
```

The setup command will:
1. Verify `whisper-stream` is installed (ships with whisper-cpp)
2. Download the Whisper Base English model (~150MB) to `~/.local/share/sotto/models/`
3. Create a default config at `~/.config/sotto/config.json`

Then register with Claude Code:

```bash
claude mcp add sotto -- sotto
```

On first use, macOS will prompt you to grant microphone access to your terminal app (Terminal, iTerm2, etc.) in **System Settings > Privacy & Security > Microphone**.

## Usage

In Claude Code, type:

```
/sotto:listen
```

A floating indicator appears at the bottom of your screen showing:
- Recording status (listening / transcribing)
- Live transcription text as you speak
- A stop button to end recording early

Recording stops automatically after silence is detected, or when you click the stop button. Your speech is transcribed and sent to Claude as text.

## Configuration

Edit `~/.config/sotto/config.json`:

| Setting | Default | Env Var | Description |
|---|---|---|---|
| `modelPath` | `~/.local/share/sotto/models/ggml-base.en.bin` | `WHISPER_MODEL_PATH` | Path to GGML model |
| `language` | `en` | `WHISPER_LANGUAGE` | Language code |
| `maxDuration` | `30` | `WHISPER_MAX_DURATION` | Max recording seconds |

Environment variables take precedence over the config file.

## Troubleshooting

| Problem | Solution |
|---|---|
| "whisper-stream is not installed" | `brew install whisper-cpp` |
| "Model not found" | Run `sotto-setup` |
| "Microphone access denied" | Grant mic access to your terminal in System Settings > Privacy & Security > Microphone |
| No speech detected | Make sure your microphone is working and you're speaking loudly enough |
| Transcription is slow | The base model is ~3s for a 5s clip on Apple Silicon. Try the tiny model for faster results. |

## Development

```bash
git clone https://github.com/sourabhbgp/sotto.git
cd sotto
npm install
npm run build
npm test
```

## License

MIT
