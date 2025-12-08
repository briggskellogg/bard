# ElevenMemo

A sleek desktop application for real-time voice transcription powered by [ElevenLabs Scribe v2](https://elevenlabs.io/docs/capabilities/speech-to-text).

## ⬇️ Build & Install

This app requires your own [ElevenLabs API key](https://elevenlabs.io/app/settings/api-keys) to function. See the [Setup](#setup-for-developers) section below for instructions.

## Features

- **Real-time transcription** — Watch your words appear as you speak
- **Multi-language support** — English, French, German, Italian, Spanish, Portuguese, Hindi, Japanese, Thai
- **Live waveform visualization** — See your audio input in real-time
- **Archive system** — Save and search through past transcriptions
- **Keyboard-first design** — Full hotkey support for power users
- **Dark & Light themes** — Easy on the eyes, day or night
- **Privacy-focused** — All data stored locally on your device

## Setup (For Developers)

To use ElevenMemo, you need to add your own ElevenLabs API key:

1. Get an API key from [ElevenLabs](https://elevenlabs.io/app/settings/api-keys)
2. Open `src/hooks/useApiKey.ts`
3. Add your API key to the `EMBEDDED_API_KEY` constant:
   ```typescript
   const EMBEDDED_API_KEY = 'your_api_key_here'
   ```
4. Build the app with `pnpm tauri build`
5. Install and start recording!

## Hotkeys

| Action | Key |
|--------|-----|
| Start/Stop Recording | `R` |
| Pause/Resume | `P` |
| Copy Transcript | `C` |
| Delete Transcript | `D` |
| Archive Transcript | `A` |
| Open Archive | `H` |
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
