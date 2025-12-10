# llMemo

Voice-to-text that archives. Built because every transcription app either loses your recordings or makes you manage files.

## What it does

Press R. Talk. It transcribes in real-time via ElevenLabs Scribe. Press A to archive with auto-generated title and priority tagging. That's it.

Archives persist locally. Search with H. Everything keyboard-driven.

## Setup

1. Get an [ElevenLabs API key](https://elevenlabs.io/app/settings/api-keys)
2. Copy `.env.example` to `.env` and add your keys
3. `pnpm install && pnpm tauri build`

## Keys

R start/stop, P pause, A archive, H history, C copy, D clear, T theme

## Requirements

Node 18+, pnpm, Rust
