# ElevenMemo

Voice-to-text that archives. Built because every transcription app either loses your recordings or makes you manage files.

## Download

[![Download ElevenMemo](https://img.shields.io/badge/Download-ElevenMemo%20v0.4-blue?style=for-the-badge)](https://github.com/briggskellogg/elevenmemo/releases/latest/download/ElevenMemo_0.4.0_aarch64.dmg)

1. Download the DMG above
2. Drag ElevenMemo to Applications
3. Open and enter your [ElevenLabs API key](https://elevenlabs.io/app/settings/api-keys)

That's it. You're ready to transcribe.

## What it does

Press R. Talk. It transcribes in real-time via ElevenLabs Scribe. Your transcripts are automatically saved to a local vault. Everything keyboard-driven.

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| R | Start/stop recording |
| P | Pause/resume |
| V | Open vault |
| C | Copy transcript |
| D | Clear transcript |
| T | Toggle theme |

## Development

If you want to build from source:

1. Clone the repo
2. Copy `.env.example` to `.env` and add your keys
3. `pnpm install && pnpm tauri build`

### Requirements

Node 18+, pnpm, Rust

## License

MIT
