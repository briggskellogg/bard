# Bard

**Real-time voice transcription for macOS** — powered by [ElevenLabs Scribe v2](https://elevenlabs.io/scribe).

Talk. It transcribes. It saves.

---

## What is Bard?

Bard is a lightweight macOS app that turns your spoken words into text in real-time. Whether you're taking meeting notes, dictating ideas, or capturing thoughts on the fly — just hit record and let Bard handle the rest.

**Features:**
- 🎙️ **Real-time transcription** — See your words appear as you speak
- 💾 **Auto-archive** — Transcripts are automatically saved and organized
- 🏷️ **Smart tagging** — Claude AI categorizes and titles your notes
- 🌙 **Dark & Light mode** — Easy on your eyes, day or night
- ⌨️ **Keyboard shortcuts** — Power-user friendly (⌘+Enter to record, ⌘+C to copy)
- 📱 **iOS support** — Coming soon

---

## Getting Started

### Step 1: Download

[![Download Bard](https://img.shields.io/badge/Download-Bard-EAB308?style=for-the-badge)](https://github.com/briggskellogg/bard/releases/latest/download/Bard.dmg)

1. Click the button above to download `Bard.dmg`
2. Open the DMG file
3. Drag **Bard** into your **Applications** folder
4. Open Bard from Applications (you may need to right-click → Open the first time)

### Step 2: Get an ElevenLabs API Key

Bard uses [ElevenLabs](https://elevenlabs.io) for transcription. You'll need a free API key:

1. Go to [elevenlabs.io](https://elevenlabs.io) and create an account
2. Navigate to **Settings → API Keys** ([direct link](https://elevenlabs.io/app/settings/api-keys))
3. Click **Create API Key** and copy it
4. Paste it into Bard when prompted

> 💡 **Tip:** ElevenLabs offers free credits to get started. The Scribe API is pay-per-use and very affordable.

### Step 3: Start Recording

1. Click the **Record** button (or press `⌘+Enter`)
2. Speak into your microphone
3. Watch your words appear in real-time
4. Click **Stop** when done — your transcript is auto-saved!

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘ + Enter` | Start/Stop recording |
| `⌘ + P` | Pause/Resume recording |
| `⌘ + C` | Copy transcript |
| `⌘ + V` | Open archive |
| `⌘ + T` | Toggle dark/light mode |
| `Esc` | Discard current recording |

---

## Building from Source

Want to run the latest development version or contribute? Here's how:

### Prerequisites

- **macOS** 10.15 or later
- **Node.js** 18+ ([download](https://nodejs.org))
- **pnpm** (`npm install -g pnpm`)
- **Rust** ([install via rustup](https://rustup.rs))
- **Xcode Command Line Tools** (`xcode-select --install`)

### Build Steps

```bash
# Clone the repository
git clone https://github.com/briggskellogg/bard.git
cd bard

# Install dependencies
pnpm install

# Run in development mode
pnpm tauri dev

# Or build for production
pnpm tauri build
```

The built app will be in `src-tauri/target/release/bundle/`.

---

## FAQ

**Q: Is my audio sent to the cloud?**  
A: Yes, audio is streamed to ElevenLabs for transcription. Your transcripts are stored locally on your device.

**Q: Does it work offline?**  
A: No, Bard requires an internet connection for transcription.

**Q: What languages are supported?**  
A: Bard supports 100+ languages with varying accuracy levels (Excellent, High, Good, Moderate). Top languages include English, Spanish, French, German, Japanese, Hindi, Portuguese, and many more. Select your language from the dropdown before recording — each language shows its accuracy tier.

**Q: How much does it cost?**  
A: Bard itself is free. You pay ElevenLabs directly for API usage (they offer free credits to start).

---

## License

MIT — do whatever you want with it.

---

<p align="center">
  Made with ❤️ by <a href="https://briggskellogg.com">Briggs Kellogg</a>
</p>
