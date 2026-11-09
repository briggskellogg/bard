# Bard release status

Recorded November 8, 2026. This file distinguishes existing release evidence from work still being prepared.

| Area | State | Evidence and limits |
| --- | --- | --- |
| Clean source checkout | Prepared | Reviewed app-source allowlist now replaces the old tracked transcription source locally. `SOURCE-SNAPSHOT.json` records copied-file hashes and the two packaging portability adjustments. The old main commit is retained by `archive/legacy-transcription-before-music`. Mac and iPhone final source freezes have been reconciled byte-for-byte. |
| Clean checkout validation | Passed | 178 shared-core tests passed with zero failures. Mac debug target compiled during that run. Nine asset exports reproduced byte-for-byte in an isolated portability check. Existing deprecation and Swift 6 concurrency warnings remain; this is not a strict Swift 6 build. |
| GitHub | Pending push | The owner authorized replacing the old transcription source at `briggskellogg/bard` with this music project and explicitly keeping source code public. Preserve history and the old main commit under an archival ref; use an ordinary new commit. Personal app contents remain excluded. No replacement commit has been pushed yet. |
| Mac installed release | Verified | Bard 1.3.3 (53), `/Applications/Developer/Bard.app`, universal arm64/x86_64. Four native main-screen renders, packaging checks, startup, and Command-F search passed. Existing library files and preferences were preserved; only normal Music sync runtime metadata changed. Personal library contents and detailed preservation evidence are excluded from this repository. Ad-hoc signed; not notarized. |
| iPhone TestFlight | Verified existing availability | Bard 1.2.2 (6) uploaded November 8 at 17:25 Phoenix, delivery receipt `171d025f-0e98-425c-86ec-dbdc3a2bd459`; processed build was assigned to the existing Personal internal group. App Store Connect app `6829608471`. No public App Store release. |
| Physical iPhone build 6 | Unverified | Earlier phone transfers worked; build 6 installation and new runtime checks are not independently confirmed. |
| iPhone next candidate | Signed export verified; upload in progress | 1.2.3 (7), 62 frozen build inputs unchanged, 16 distribution checks passed. Main light/dark screens and nine native view cases, including compact accessibility sizing, were checked. Not yet claimed available to testers. |
| Current runtime transfer | Existing Mac-authoritative design | User-selected provider folder; iPhone cached listening copies and two-way favorites. This does not meet the new independent iPhone export / Mac-off archive requirement. |
| Independent personal iCloud exports | Not configured | No confirmed export allowlist or app-specific CloudKit container. Do not invent container IDs or migrate personal data without scoped authorization. |
| PC archive | Not configured | Host, exact approved source/archive paths, credentials, and retention remain unknown. |
| Proton archive | Not configured | Must upload from the approved PC with verified completion. Existing Mac-managed music copying is not evidence of the new archive design. No source mirror was created from this work Mac. |
| Restore verification and schedules | Not configured | No PC/Proton restoration test or new recurring job has run. |

The previous Mac DMG was `Bard-1.3.2-universal.dmg`, 9,471,090 bytes, SHA-256 `70e7e7f188c8c05f52b4736e17a8baa6fc190eba1f5bf2417673a98615ee4f45`. It was built before a canonical Git commit existed; do not retroactively claim that it was built from a later commit.

The verified 1.3.3 package is `Bard-1.3.3-universal.dmg`, SHA-256 `acf27f4f33229f84c94eda2827e80b3ed13d3e0bda33bde163532c14339d7255`; executable SHA-256 `4b6c4307faff144a539920129286e7216256cad9e0f37ad1955d51a74d7d0c55`. This build predates the canonical source commit. Its original build commit remains unknown; exact source-byte equivalence may be recorded against the eventual reviewed commit after comparing the input manifest. Do not claim that the build itself ran from that later Git commit.

Raw historical validation logs, screenshots, archives, installation backups, and personal library checks remain outside this clean repository. Sanitized verification facts above come from the existing release evidence. New builds must be linked to their actual source commit and retain appropriate artifacts in an approved destination.
