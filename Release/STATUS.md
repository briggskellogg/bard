# Bard release status

Recorded November 8, 2026 (America/Phoenix).

| Area | State | Evidence and limits |
| --- | --- | --- |
| GitHub source | Verified | Public `briggskellogg/bard` now holds the native music app. Source commit `1ad267cc9b9642e2faff7e11c3b9d15870be6e8d` and predecessor branch `archive/legacy-transcription-before-music` were verified remotely. The old transcription history remains intact. Personal library contents are excluded. |
| GitHub app release | Verified | [Mac 1.3.3 / iPhone 1.2.3](https://github.com/briggskellogg/bard/releases/tag/mac-1.3.3-ios-1.2.3) is published with eight assets. GitHub-reported SHA-256 values match the local files, including the universal DMG, distribution IPA, dSYMs, manifests, notes, and checksums. |
| Clean checkout validation | Passed | 178 shared-core tests passed with zero failures; the Mac debug target compiled. Nine brand exports reproduced byte-for-byte. Existing deprecation and Swift 6 concurrency warnings remain; this is not a strict Swift 6 build. |
| Mac installed release | Verified | Bard 1.3.3 (53), universal arm64/x86_64, installed at `/Applications/Developer/Bard.app`. Four native main-screen renders, packaging, startup, Command-F search, and data-preservation checks passed. Ad-hoc signed; not notarized. |
| iPhone TestFlight | Verified | **Bard by Briggs Kellogg 1.2.3 (7)** is processed and **Testing** in the existing Personal internal group. Release notes and app name were saved. App Store Connect app `6829608471`, delivery `7e9320e4-fa0a-4174-b0a2-1e235b8398ff`. No public App Store release. |
| iPhone validation | Passed with limits | Nine native view cases, compact accessibility sizing, main light/dark renders, 53 continuity checks, and 16 distribution checks passed. Physical installation and interaction checks for build 7 remain unverified. |
| Current runtime transfer | Existing Mac-authoritative design | User-selected provider folder, phone listening copies, and two-way favorites. This is not an independent iPhone export or a complete Mac-off backup system. |
| Independent personal iCloud exports | Not configured | No confirmed export allowlist or app-specific CloudKit container. |
| PC archive | Not configured | Approved host, source/archive paths, personal export scope, and retention remain unknown. Follow [the PC handoff](PC-HANDOFF.md). |
| Proton archive | Not configured | Requires an approved PC source and verified remote completion. No work-Mac source mirror was created. Existing Mac-managed music copying is separate from this new archive design. |
| Restore verification and schedules | Not configured | No PC/Proton restore test or new recurring job has run. |

## Artifact provenance

The universal Mac DMG is `Bard-1.3.3-universal.dmg`, SHA-256 `acf27f4f33229f84c94eda2827e80b3ed13d3e0bda33bde163532c14339d7255`. The local iPhone distribution export is 1.2.3 (7), SHA-256 `da55a0ed83a62359e079e69e1ad83ff18686bb8ca6d0853f47e413abf4f8dd12`.

Both builds predate the canonical source commit. All 189 recorded Mac inputs and 62 iPhone inputs were compared with the committed blobs at `1ad267cc9b9642e2faff7e11c3b9d15870be6e8d` and match byte-for-byte. This establishes source equivalence; it does not claim that the builds originally ran from that Git checkout. Local iPhone export and Apple upload independently signed the same frozen archive.

[RECEIPT.json](RECEIPT.json) and [BUILD-INPUTS.json](BUILD-INPUTS.json) retain sanitized build facts. Raw screenshots, logs, installation backups, and private library checks stay outside this public source tree. App-release artifacts and their checksums belong in the GitHub release; personal music, artwork, playlists, and exports never do.
