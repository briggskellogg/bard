# Bard

Bard is a native personal music library for Mac and iPhone. Import, organize, edit, and remix on the Mac; listen offline, browse the library, use Smart Shuffle, and change favorites on the iPhone.

This is the music application formerly named Wisp. The owner has chosen it to replace the older voice-transcription source at `briggskellogg/bard`, preserving that predecessor in Git history. The visible brand is Bard; existing `Wisp` module names, bundle identifiers, storage keys, and sync formats remain intentionally stable so updates preserve the user's music library.

## Project state

The current installed Mac app is Bard 1.3.4 (54), with six native light/dark renders, packaging, startup, and data-preservation checks passed. The logo is symbol-only; app headers use the standard interface font. **Bard by Briggs Kellogg 1.2.4 (8)** is processed and Testing in the existing Personal internal TestFlight group. Physical installation and interaction checks for build 8 remain unverified. See [release status](Release/STATUS.md) for the exact evidence and remaining work.

[Download the current Mac release and view its verification records](https://github.com/briggskellogg/bard/releases/tag/mac-1.3.4-ios-1.2.4). Update the iPhone app through TestFlight.

The app requires macOS 14 or later, or iOS 17 or later. The Mac package supports Apple Silicon and Intel. The current personal Mac distribution has an ad-hoc integrity signature and is not notarized. iPhone delivery uses TestFlight, not the unsigned device build.

## Development

- `Sources/WispCore`: shared library models, import rules, queues, Smart Shuffle, listening data, and transfer formats.
- `Sources/Wisp`: native Mac library, player, artwork editor, and Remix alpha.
- `iOS/Sources/WispIOS`: native iPhone listening experience.
- `Support/Brand/Bard`: approved vector masters; resources keep their internal compatibility names.
- `Tests/WispCoreTests`: isolated core tests using synthetic fixtures.

See [build and release instructions](Release/BUILD.md) and [the asset notes](Release/ASSETS.md). The repository preserves approved app assets; source publication does not grant additional redistribution rights to third-party fonts or icons.

## Data and release boundaries

The existing runtime transfer uses a user-selected shared provider folder. The Mac is still the authoritative music library; iPhone favorites can flow back. This is not yet an independent iPhone export or a complete Mac-off backup system. No CloudKit container is configured in this release.

The newer personal app system in [RELEASE_PROMPT.txt](RELEASE_PROMPT.txt) governs future release and backup work. The owner explicitly chose to keep Bard's source code public, overriding the earlier generic preference for private repositories. **Personal app contents must never enter GitHub:** songs, user artwork, metadata, libraries, exports, and credentials stay outside source control. Personal data exports may be archived only from confirmed, exact personal iCloud and Windows folders; the PC is the archive host and Proton is the off-site destination. Do not back up the work Mac filesystem or use its source checkout as a Proton backup source.

[project-destinations.json](project-destinations.json) records verified destinations and leaves unknown or unapproved values null. PC archiving, Proton uploads, restore tests, and schedules remain disabled until their scope and destinations are confirmed. A successful build, local copy, or upload receipt does not establish TestFlight availability, physical phone testing, cross-device sync, or a completed cloud backup.
