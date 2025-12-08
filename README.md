# ElevenMemo

A sleek desktop application for real-time voice transcription powered by [ElevenLabs Scribe v2](https://elevenlabs.io/docs/capabilities/speech-to-text).

## ⬇️ Download

**[Download ElevenMemo for macOS](https://github.com/briggskellogg/elevenmemo/releases/latest/download/ElevenMemo_0.1.0_aarch64.dmg)** (Apple Silicon)

> After downloading, open the `.dmg` file and drag ElevenMemo to your Applications folder.

## Features

- **Real-time transcription** — Watch your words appear as you speak
- **Multi-language support** — English, French, German, Italian, Spanish, Portuguese, Hindi, Japanese, Thai
- **Live waveform visualization** — See your audio input in real-time
- **Archive system** — Save and search through past transcriptions
- **Keyboard-first design** — Full hotkey support for power users
- **Dark & Light themes** — Easy on the eyes, day or night
- **Privacy-focused** — All data stored locally on your device

## Setup

1. Download and install ElevenMemo
2. Open the app and click on **Settings** (gear icon) or press `S`
3. Enter your [ElevenLabs API key](https://elevenlabs.io/app/settings/api-keys)
4. Start recording!

## Hotkeys

| Action | Key |
|--------|-----|
| Start/Stop Recording | `R` |
| Pause/Resume | `P` |
| Copy Transcript | `C` |
| Delete Transcript | `D` |
| Archive Transcript | `A` |
| Open Archive | `H` |
| Open Settings | `S` |
| Toggle Theme | `T` |
| Discard Recording | `Esc` |

## Tech Stack

- **[Tauri v2](https://tauri.app)** — Lightweight, secure desktop framework
- **[React 19](https://react.dev)** — UI library
- **[TypeScript](https://typescriptlang.org)** — Type safety
- **[Tailwind CSS](https://tailwindcss.com)** — Styling
- **[shadcn/ui](https://ui.shadcn.com)** — Component library
- **[ElevenLabs Scribe v2](https://elevenlabs.io)** — Speech-to-text API

## Development

### Prerequisites

- [Node.js](https://nodejs.org) (v18+)
- [pnpm](https://pnpm.io)
- [Rust](https://rustup.rs)

### Setup

```bash
# Clone the repository
git clone https://github.com/briggskellogg/elevenmemo.git
cd elevenmemo

# Install dependencies
pnpm install

# Run in development mode
pnpm tauri dev

# Build for production
pnpm tauri build
```

## Privacy & Security

- 🔒 **Local storage only** — Archives and settings are stored on your device
- 🎙️ **Audio processing** — Audio is streamed to ElevenLabs for real-time transcription
- 🔑 **API key security** — Your API key is stored securely in Tauri's encrypted store

## License

MIT

---

<p align="center">
  <em>"An agent can carry out tasks, but the final responsibility should always remain with a human."</em><br>
  <small>Policy based on <a href="https://linear.app/developers/aig">Linear's framework</a></small>
</p>
