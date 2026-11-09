# Building and releasing Bard

Use macOS with a compatible Xcode installation and the required Apple SDKs. The current app was verified with Xcode 27.2. The account owner personally completes Xcode setup and any legal agreements. Never copy a work-machine keychain or signing credentials to another host.

## Local checks

From the repository root:

```sh
swift test
bash scripts/build.sh
bash iOS/scripts/build-simulator.sh
```

`build.sh` creates `build/Bard.app` for the current Mac. `Build.command` runs it and reveals the product; it does not install it. The legacy installer that created a second app under the user's Applications folder is intentionally not included. The existing installed app lives at `/Applications/Developer/Bard.app`; preserve its identity, data, and prior recoverable copy when installing an authorized update.

The simulator script regenerates the Xcode project using XcodeGen 2.44 or newer and compiles the `WispIOS` scheme with signing disabled. It does not launch an app or verify a physical iPhone.

## Mac universal package

```sh
bash scripts/build-universal.sh "$PWD/build/release"
```

This compiles arm64 and x86_64 release products and packages the Swift resource bundle, icon, and Info.plist. The packager validates architecture, signed contents, DMG mounting, and a copy round trip. Existing output destinations are not overwritten. The result is an ad-hoc signed `Bard.app` and `Bard-<version>-universal.dmg`, not a Developer ID notarized release. Do not imply that local signing meets public Gatekeeper distribution requirements.

## iPhone archive and TestFlight

The project is `iOS/WispIOS.xcodeproj`; the shared scheme is `WispIOS`. The visible app name is Bard and the existing bundle is `com.briggskellogg.wisp.ios`. Preserve team and App Store Connect identities in `project-destinations.json`.

`iOS/scripts/archive.sh` requires `WISP_TEAM_ID` and a new archive path. Automatic provisioning updates require the separate opt-in `WISP_ALLOW_PROVISIONING_UPDATES=1`. `export-testflight.sh` creates a local distribution export; `upload-testflight.sh` uploads an authorized frozen archive. They do not assign a tester group or verify Apple processing. See [iPhone development notes](../iOS/README.md).

Build 8 (1.2.4) has already uploaded, processed, and reached Testing in the Personal internal group. Do not re-upload it. Check App Store Connect before choosing the next build number, then validate the archived version, bundle, team, entitlements, icon, privacy manifest, and distribution signature. Retain dSYMs, checksums, source commit, build manifest, and receipt separately from source control.

## Portable assets

The approved vector masters and runtime exports are committed. Normal builds need no graphics tool. To regenerate changed brand assets, install Node.js and librsvg (`rsvg-convert` on PATH), then run:

```sh
node scripts/prepare-bard-assets.cjs
bash iOS/scripts/prepare-icon.sh
```

`BARD_RSVG_CONVERT` can select a specific renderer executable. The Mac asset manifest is written under ignored `build/brand/`; iPhone icons must remain opaque 1024×1024 RGB. Never substitute an approximate maker silhouette or reintroduce handwritten lettering during packaging.

## Release provenance and archiving

Use the reviewed commit as the build source; record versions, commit SHA, archive/export checksums, signature status, Apple processing, and tester availability in a sanitized release receipt. Use an existing authorized macOS CI runner where available. Windows archives signed outputs but cannot replace Xcode as the Apple build host.

PC and Proton archives are not configured yet. Do not copy the Mac checkout, logs, keychain, or personal library into Proton as a workaround. Personal source/release artifacts must originate from the exact approved repository and be staged on an approved PC path. Bard's source is public by the owner's explicit choice; personal songs, artwork, metadata, libraries, exports, and credentials must never be published with it. Follow `RELEASE_PROMPT.txt` before enabling any archive or schedule.
