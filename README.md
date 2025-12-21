# Bard

Voice-to-text that archives. Built because every transcription app either loses your recordings or makes you manage files.

## Download

[![Download Bard](https://img.shields.io/badge/Download-Bard%20v0.8.1-EAB308?style=for-the-badge)](https://github.com/briggskellogg/bard/releases/latest/download/Bard.dmg)

1. Download the DMG above
2. Drag Bard to Applications
3. Open and enter your [ElevenLabs API key](https://elevenlabs.io/app/settings/api-keys)

That's it. You're ready to transcribe.

## What it does

Press Record. Talk. It transcribes in real-time via ElevenLabs Scribe. Your transcripts are automatically saved to a local vault.

## Development

If you want to build from source:

1. Clone the repo
2. Copy `.env.example` to `.env` and add your keys
3. `pnpm install && pnpm tauri build`

### Requirements

Node 18+, pnpm, Rust

## License

MIT
