# Echo

Voice-to-text that archives. Built because every transcription app either loses your recordings or makes you manage files.

## Download

[Download the latest release](https://github.com/briggskellogg/echo/releases/latest)

1. Download `Echo.dmg` from the releases page
2. Drag Echo to Applications
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
