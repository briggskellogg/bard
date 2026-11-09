# Bard release status

Recorded November 8, 2026 (America/Phoenix).

| Area | State | Evidence and limits |
| --- | --- | --- |
| GitHub source | Verified | Public `briggskellogg/bard` now holds the native music app. Source commit `431939886ea5c6e808b310bea85221bb688d8713` and predecessor branch `archive/legacy-transcription-before-music` were verified remotely. The old transcription history remains intact. Personal library contents are excluded. |
| GitHub app release | Verified | [Mac 1.3.4 / iPhone 1.2.4](https://github.com/briggskellogg/bard/releases/tag/mac-1.3.4-ios-1.2.4) is published with ten assets. GitHub-reported SHA-256 values match the local files, including the universal DMG, distribution IPA, dSYMs, transparent PNG/SVG icons, manifests, notes, and checksums. |
| Branding validation | Passed | Six native Mac and six native iPhone light/dark renders passed. Compiled packages contain no handwritten logo resources; the approved transparent Mac icon and gold maker mark are preserved. The prior 178 shared-core tests passed; unchanged core logic was not retested for this branding-only update. Existing build warnings remain. |
| Mac installed release | Verified | Bard 1.3.4 (54), universal arm64/x86_64, installed at `/Applications/Developer/Bard.app`. Six native main/expanded/Data renders, packaging, startup, and data-preservation checks passed. Ad-hoc signed; not notarized. |
| iPhone TestFlight | Verified | **Bard by Briggs Kellogg 1.2.4 (8)** is processed and **Testing** in the existing Personal internal group. Release notes and app name were saved. App Store Connect app `6829608471`, delivery `b993525d-fa38-4f61-9929-ead1b94e71f0`. No public App Store release. |
| iPhone validation | Passed with limits | Six native home/onboarding/player light/dark renders and 18 distribution checks passed. Physical installation and interaction checks for build 8 remain unverified. |
| Current runtime transfer | Existing Mac-authoritative design | User-selected provider folder, phone listening copies, and two-way favorites. This is not an independent iPhone export or a complete Mac-off backup system. |
| Independent personal iCloud exports | Not configured | No confirmed export allowlist or app-specific CloudKit container. |
| PC archive | Not configured | Approved host, source/archive paths, personal export scope, and retention remain unknown. Follow [the PC handoff](PC-HANDOFF.md). |
| Proton archive | Not configured | Requires an approved PC source and verified remote completion. No work-Mac source mirror was created. Existing Mac-managed music copying is separate from this new archive design. |
| Restore verification and schedules | Not configured | No PC/Proton restore test or new recurring job has run. |

## Artifact provenance

The universal Mac DMG is `Bard-1.3.4-universal.dmg`, SHA-256 `fef834b72bb07dfe60787b43fcc3d543f891d54d958514d912acb41e278d5b9b`. The local iPhone distribution export is 1.2.4 (8), SHA-256 `0ed2fc391670f453031a56f3feb892c974810644151bff29d1ca109c774e8fd4`.

Both builds ran from committed source `431939886ea5c6e808b310bea85221bb688d8713`. All 187 recorded Mac inputs and 60 iPhone inputs match that committed revision and remained unchanged through packaging. Local iPhone export and Apple upload independently signed the same frozen archive.

[RECEIPT.json](RECEIPT.json) and [BUILD-INPUTS.json](BUILD-INPUTS.json) retain sanitized build facts. Raw screenshots, logs, installation backups, and private library checks stay outside this public source tree. App-release artifacts and their checksums belong in the GitHub release; personal music, artwork, playlists, and exports never do.
