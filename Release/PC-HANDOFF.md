# Bard handoff for the personal Windows PC

This is a scoped setup guide for the next PC session, not a running backup job. PC and Proton destinations, personal export scope, retention, and schedules are still unknown or unapproved. Keep backup execution disabled until those values and approvals are recorded.

## Established identities and current state

| Item | Verified identity or state |
| --- | --- |
| Personal source repository | `https://github.com/briggskellogg/bard`, repository ID `1112021879`, branch `main`. The owner explicitly chose public **source code**. |
| Native music source baseline | Commit `1ad267cc9b9642e2faff7e11c3b9d15870be6e8d`. Fetch and review subsequent commits before using a newer revision. |
| Preserved predecessor | Branch `archive/legacy-transcription-before-music`, retaining commit `5d9d3bd87fff69b092bd4227f8f80fe0cd02f01b`. This is the old transcription application, not the current music app. |
| Mac app | Bard 1.3.3 (53); universal Mac package, ad-hoc signed and not notarized. |
| iPhone app | **Bard by Briggs Kellogg**, App Store Connect ID `6829608471`; version 1.2.3 (7) is Testing in the Personal internal TestFlight group. Physical installation/testing of build 7 has not been verified. |
| Runtime data transfer | The current music library remains Mac-authoritative, using a user-selected shared provider folder, downloaded phone copies, and favorite changes that can return to the Mac. |
| PC archive / Proton backup | Not configured or tested. Exact host, account, resolved paths, retention, and approved scope are unknown. |

Read `AGENTS.md`, `RELEASE_PROMPT.txt`, `project-destinations.json`, and the latest `Release/STATUS.md` before proceeding. A later release receipt may supersede the build numbers above.

## Keep the roles separate

- **GitHub:** app source, reviewed brand resources, synthetic tests, release automation, and specifically approved app-release artifacts. Never store personal songs, user artwork, track metadata, playlists, libraries, exports, or credentials in commits, issues, logs, Actions artifacts, or releases.
- **iCloud:** the shared runtime transfer and future complete personal app exports. It is not a historical backup. The current implementation has no app-specific CloudKit container and no independently verified complete iPhone export.
- **Personal PC:** durable local archive outside cloud-managed/source folders. It receives only exact approved personal exports and repository/release identities, verifies complete files, then writes dated snapshots.
- **Proton Drive:** off-site copies uploaded from that PC using official supported tooling, with remote completion checked independently.
- **Mac:** app development and current music creation/import/remix. Do not back up its filesystem or copy its checkout, keychain, credentials, or private library into the archive as a shortcut.

Windows is the archive host, not an Xcode build host. Apple builds still require an authorized macOS runner and signing setup; never migrate a work-machine keychain to make that portable.

## First PC session: establish scope before copying

1. Confirm this is the user's personal Windows PC and record its exact host identity. Verify the intended personal iCloud and Proton accounts without reading unrelated account contents. Do not enumerate all accessible repositories, cloud drives, or local profiles.
2. Ask the owner to choose exact personal-only source folders and an archive destination. Present each resolved source, its account/dataset identity, and its destination for confirmation. A folder called Bard, Wisp, Music, or Projects is not sufficient proof that its contents are personal. Mixed or unknown folders remain excluded.
3. Record the confirmed allowlist and scope approval in non-secret configuration. Keep personal path/account details and dataset inventories outside the public repository. The public `project-destinations.json` can record sanitized status; personal archive configuration belongs in approved private PC storage.
4. Choose separate approved PC locations for source checkout/staging, downloaded release artifacts, personal data snapshots, and restore tests. The durable archive must be outside iCloud, Proton, every source tree, and backup temporary folders. Do not choose an entire disk, user profile, Documents, Desktop, Downloads, iCloud root, corporate share, or work-machine folder.
5. Leave execution disabled if any source, account, resolved path, destination, or approval remains empty or ambiguous. Denials override allowances. Reject symlinks and junctions by default and unknown reparse behavior; validate paths again immediately before reading or writing.

## Retrieve only this project's source and releases

After the exact personal repository identity and PC staging/archive locations are confirmed:

1. Clone or update **only** `briggskellogg/bard` in its approved PC source folder. Confirm the remote URL and repository ID; preserve local edits and reconcile normally. Do not force-push or substitute a similarly named repository.
2. Retain the selected commit and its manifest. Preserve the predecessor archive branch if repository history is being archived. Do not archive every repository the account can access.
3. Retrieve only explicitly selected Bard release assets from their verified release or authorized artifact locations. Verify release/tag identity, asset names, hashes, and completeness against the sanitized receipt. A source ZIP is not an installable app; TestFlight availability is not proof that the PC holds an IPA or archive.
4. Keep signed products, dSYMs, build-input manifests, checksums, and release receipts together where available. Do not collect signing keys, provisioning credentials, account cookies, or keychains. Current pre-commit builds have recorded input-hash equivalence; do not claim they originally ran from a later Git commit.
5. Record exactly which source commit and artifacts reached the PC archive. If an artifact was never uploaded to the verified location, report it missing instead of retrieving it from the work Mac filesystem.

## Establish a complete personal-data export

Select and confirm the exact personal iCloud library/export scope separately from source-code staging. Do not guess a path from a screenshot or a historical Wisp folder name.

Before treating it as a backup source, verify that an export has a versioned manifest, referenced audio/artwork, metadata, playlists, and checksums sufficient to reconstruct the approved dataset. Record the source-data timestamp separately from the time the backup runs. Hydrate cloud-provider placeholders completely, read and hash every approved file, and reject incomplete or inconsistent manifests. Never follow external references into work or unapproved folders.

The current Mac-authoritative transfer does **not** establish that new iPhone changes will produce a complete export while the Mac is off. Favorites moving between devices are not proof of a complete independent phone export. That capability needs implementation and a real cross-device test before claiming the Mac can be absent from the data-protection path. Do not perform a personal-data migration merely to bypass this gap.

CloudKit data, if introduced later, is not an ordinary iCloud Drive folder. Implement an explicit complete export; do not infer coverage from an iCloud account being signed in.

## Snapshot, upload, and prove restoration

Once the exact personal-data source is approved and a complete export is available:

1. Write a dated PC snapshot outside all source/cloud folders. Keep source-data and backup-job timestamps distinct. Validate the copied manifest and checksums before marking the snapshot complete. Preserve earlier snapshots when files are deleted upstream; do not turn cloud deletions into historical archive deletions.
2. Upload only the approved snapshot and selected source/release archives to the confirmed Proton destination using the PC's supported Proton tooling. Keep personal data, repository history, and release artifacts organized separately. A local copy or a successful process exit is not proof of a completed remote upload.
3. Verify the remote object set and completion, then download a snapshot from Proton into an isolated restore location. Test restoration from both a PC snapshot and the Proton download without relying on the Mac. Compare manifests, hashes, and the restored app dataset; do not overwrite a live library.
4. Record missing files, stale exports, partial hydration, failed uploads, and restore failures explicitly. Never label an old complete snapshot as fresh merely because today's backup job ran successfully.

## Schedules stay off until configured

The proposed cadence is hourly PC snapshots, nightly Proton uploads, and a daily TestFlight-expiration check, displayed in America/Phoenix. These are proposals, not active tasks. Establish exact times, retention, credentials, destinations, scope approval, and an approved notification channel before activation. Do not prune snapshots until retention is explicitly configured, and do not attach essential jobs to the work Mac.

For TestFlight renewal, inspect Apple's actual build expiration and the last successfully released revision. An approximate 60-day renewal target does not authorize publishing an App Store release or inventing signing access. Keep unchanged healthy checks quiet and surface failures, stale data, or required user action through the approved channel only.

## Required completion report

Report **GitHub**, **TestFlight**, **iCloud runtime/export**, **PC archive**, and **Proton backup** separately as VERIFIED, PENDING, BLOCKED, or NOT CONFIGURED. Include the exact approved destinations, source commit/build, source-data and snapshot timestamps, remote-upload result, and both restore-test outcomes. Keep detailed personal paths and dataset inventories in the approved private PC record, not the public repository. A guide or saved configuration is not an activated scheduler or a completed backup.
