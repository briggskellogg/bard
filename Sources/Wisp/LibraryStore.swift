import Foundation
import Darwin
import Combine
import AppKit
import WispCore

typealias BulkTrackPatch = TrackMetadataPatch

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var document = LibraryDocument()
    @Published var errorMessage: String?
    @Published private(set) var isImporting = false
    @Published private(set) var replacingAudioID: UUID?
    @Published private(set) var importReview: ImportReview?
    /// New songs with unchanged draft artwork enter this explicit-approval queue,
    /// including imported covers. A cover explicitly saved in review is already approved.
    /// The presentation owner consumes it after any metadata review has closed.
    @Published private(set) var artworkReviewTrackIDs: [UUID] = []
    @Published private(set) var importLabel = ""
    @Published private(set) var notice: String?
    @Published private(set) var canEdit = true
    let directory: URL
    private let repository: LibraryRepository
    private var noticeTask: Task<Void, Never>?
    private struct PendingImport {
        let id = UUID()
        let batch: AudioImportBatch
        let playlistID: UUID?
        let provenance: String?
        let destinationName: String
    }
    private var pendingImport: PendingImport?

    var tracks: [Track] { document.tracks }
    var playlists: [Playlist] { document.playlists }
    var mixtape: Playlist? { playlist(id: MixtapeCollection.id) }
    var mixtapeTracks: [Track] {
        let index = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return (mixtape?.trackIDs ?? []).compactMap { index[$0] }
    }
    var folders: [PlaylistFolder] { document.folders }
    var storageBytes: Int64 {
        tracks.reduce(Int64(0)) { total, track in
            ([track.byteCount] + track.audioVersions.map(\.byteCount)).reduce(total) { subtotal, bytes in
                let (sum, overflow) = subtotal.addingReportingOverflow(bytes)
                return overflow ? Int64.max : sum
            }
        }
    }
    var hasPreviousIndex: Bool { FileManager.default.fileExists(atPath: repository.previousURL.path) }

    init(directory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        self.directory = (directory ?? support.appendingPathComponent("Wisp", isDirectory: true)).standardizedFileURL
        repository = LibraryRepository(directory: self.directory)
        do {
            document = try repository.load()
            var migrated = document
            let needsMigration = MixtapeCollection.ensure(in: &migrated)
            if needsMigration || !FileManager.default.fileExists(atPath: repository.manifestURL.path) {
                try repository.save(migrated)
                document = migrated
            }
        } catch {
            canEdit = false
            errorMessage = error.localizedDescription
        }
    }

    /// A favorite change and its consumed sequence share one atomic index write.
    /// Replayed phone batches cannot undo a later change made on the Mac.
    @discardableResult
    func applyPhoneFavorites(_ batch: PhoneFavoriteBatch, sourceLibraryID: UUID) -> Bool {
        guard canEdit else { errorMessage = LibraryError.notLoaded.localizedDescription; return false }
        do {
            try batch.validate(sourceLibraryID: sourceLibraryID)
            let key = batch.deviceID.uuidString
            let consumed = document.phoneFavoriteReceipts[key] ?? 0
            guard batch.sequence > consumed else { return true }
            var next = document
            let positions = Dictionary(uniqueKeysWithValues: next.tracks.enumerated().map { ($0.element.id, $0.offset) })
            for change in batch.changes where change.sequence > consumed {
                // A removed song stays removed. Its intent is still acknowledged.
                if let index = positions[change.trackID] { next.tracks[index].favorite = change.isFavorite }
            }
            next.phoneFavoriteReceipts[key] = batch.sequence
            return commit(next)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func track(id: UUID) -> Track? { tracks.first { $0.id == id } }
    func playlist(id: UUID) -> Playlist? { playlists.first { $0.id == id } }
    func folder(id: UUID) -> PlaylistFolder? { folders.first { $0.id == id } }
    func consumeArtworkReviewTrackIDs() -> [UUID] {
        let result = artworkReviewTrackIDs.filter { id in
            tracks.contains { $0.id == id }
        }
        artworkReviewTrackIDs = []
        return result
    }
    func audioURL(for track: Track) -> URL { repository.mediaDirectory.appendingPathComponent(track.fileName) }
    func audioURL(for version: TrackAudioVersion) -> URL { repository.mediaDirectory.appendingPathComponent(version.fileName) }
    func artworkURL(for track: Track) -> URL? { existingArtwork(track.artworkFileName) }
    func coverURL(for playlist: Playlist) -> URL? {
        existingArtwork(playlist.coverFileName) ?? (playlist.isMixtape ? WispResources.mixtapeCoverURL : nil)
    }

    private func existingArtwork(_ name: String?) -> URL? {
        guard let name else { return nil }
        let url = repository.artworkDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Downloads remain outside the library until the user approves a cover.
    /// The lookup snapshot prevents a delayed result overwriting newer edits.
    @discardableResult
    func applyArtwork(to expected: Track, data: Data, source: TrackArtworkSource?,
                      replaceExisting: Bool = false) -> Bool {
        guard canEdit else { errorMessage = LibraryError.notLoaded.localizedDescription; return false }
        guard let index = document.tracks.firstIndex(where: { $0.id == expected.id }) else {
            errorMessage = "This song is no longer in your library."
            return false
        }
        let current = document.tracks[index]
        guard current.fingerprint == expected.fingerprint,
              current.title == expected.title, current.artist == expected.artist,
              current.origin == expected.origin, current.genre == expected.genre,
              current.originMediaKind == expected.originMediaKind,
              current.artworkFileName == expected.artworkFileName,
              current.artworkSource == expected.artworkSource else {
            errorMessage = "This song changed while its artwork was being reviewed. Reopen the artwork review to try again."
            return false
        }
        guard replaceExisting || current.artworkFileName == nil else {
            errorMessage = "This song already has a cover. Approve its replacement before changing it."
            return false
        }
        var created: String?
        do {
            try source?.validate()
            let name = try saveCover(data: data)
            created = name
            var next = document
            next.tracks[index].artworkFileName = name
            next.tracks[index].artworkSource = source
            guard commit(next) else {
                discardNewFiles([repository.artworkDirectory.appendingPathComponent(name)])
                return false
            }
            // Keep the previous image. The previous index and a child song may
            // still refer to it, and cover approval must never discard that art.
            artworkReviewTrackIDs.removeAll { $0 == expected.id }
            return true
        } catch {
            if let created { discardNewFiles([repository.artworkDirectory.appendingPathComponent(created)]) }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func importFiles(_ urls: [URL], into playlistID: UUID? = nil, sourceURL: URL? = nil) async {
        guard canEdit else { errorMessage = LibraryError.notLoaded.localizedDescription; return }
        guard !isImporting else { showNotice("An import is already in progress."); return }
        guard pendingImport == nil else { showNotice("Finish reviewing this import before adding more music."); return }
        guard !urls.isEmpty else { return }
        if let playlistID, playlist(id: playlistID) == nil {
            errorMessage = "This playlist is no longer available. Choose an import destination again."
            return
        }
        if let sourceURL, MusicSource.validatedURL(sourceURL.absoluteString) == nil {
            errorMessage = "Use a valid website link for the source."
            return
        }
        let destinationName = playlistID.flatMap { playlist(id: $0)?.name } ?? "Music"
        errorMessage = nil
        isImporting = true
        importLabel = "Preparing"
        defer { isImporting = false; importLabel = "" }
        let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        var expanded: [URL] = []
        var temporary: [URL] = []
        var archiveFailures: [String] = []
        defer { temporary.forEach { try? FileManager.default.removeItem(at: $0) } }
        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                do {
                    importLabel = "Extracting · \(url.lastPathComponent)"
                    let folder = try await AudioArchive.expand(url)
                    temporary.append(folder)
                    expanded.append(folder)
                } catch { archiveFailures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            } else { expanded.append(url) }
        }
        let fingerprints = Dictionary(uniqueKeysWithValues: tracks.map { ($0.fingerprint, $0) })
        let directory = self.directory
        let filesToImport = expanded
        var batch = await Task.detached(priority: .userInitiated) { [weak self] in
            await AudioImporter.prepare(urls: filesToImport, existing: fingerprints, directory: directory) { label in
                Task { @MainActor [weak self] in self?.importLabel = label }
            }
        }.value
        batch.failures.insert(contentsOf: archiveFailures, at: 0)
        let provenance = sourceURL?.absoluteString
        for index in batch.tracks.indices {
            batch.tracks[index].sourceURL = provenance
            let key = OriginMediaKind.originKey(batch.tracks[index].origin)
            if !key.isEmpty {
                batch.tracks[index].originMediaKind = tracks.first(where: {
                    $0.originMediaKind != nil && OriginMediaKind.originKey($0.origin) == key
                })?.originMediaKind ?? batch.tracks[index].originMediaKind
            }
        }
        let pending = PendingImport(batch: batch, playlistID: playlistID, provenance: provenance,
                                    destinationName: destinationName)
        pendingImport = pending
        if batch.needsReview && !batch.tracks.isEmpty {
            presentImportReview(pending)
        } else if !finishImport(pending, tracks: batch.tracks) {
            // Keep prepared copies after a failed save so the user can retry or
            // cancel without re-reading an archive or downloading a second time.
            presentImportReview(pending)
        }
    }

    /// Only the prepared identities and editable metadata may cross the review
    /// boundary. Owned paths, fingerprints, dates, audio versions, and artwork are
    /// always taken from the original preparation result.
    @discardableResult
    func confirmImport(_ reviewedTracks: [Track], artworkEdits: [UUID: TrackArtworkEdit] = [:]) -> Bool {
        guard let pending = pendingImport else {
            errorMessage = "This import is no longer awaiting review."
            return false
        }
        let prepared = Dictionary(uniqueKeysWithValues: pending.batch.tracks.map { ($0.id, $0) })
        guard Set(artworkEdits.keys).isSubset(of: Set(prepared.keys)) else {
            errorMessage = ImportReviewError.changedIdentity.localizedDescription
            return false
        }
        guard Set(reviewedTracks.map(\.id)).count == reviewedTracks.count else {
            errorMessage = "A track appears more than once in this import."
            return false
        }
        do {
            let validated = try reviewedTracks.map { reviewed -> Track in
                guard var original = prepared[reviewed.id] else { throw ImportReviewError.changedIdentity }
                var protected = reviewed
                protected.title = original.title
                protected.artist = original.artist
                protected.genre = original.genre
                protected.origin = original.origin
                protected.remix = original.remix
                protected.originMediaKind = original.originMediaKind
                protected.sourceURL = original.sourceURL
                protected.favorite = original.favorite
                guard protected == original else { throw ImportReviewError.changedIdentity }
                original = try TrackMetadataPatch.allFields(from: reviewed).applying(to: original)
                return original
            }
            return finishImport(pending, tracks: validated, artworkEdits: artworkEdits)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func cancelImportReview() {
        guard let pending = pendingImport else { return }
        discardNewFiles(pending.batch.createdFiles)
        pendingImport = nil
        importReview = nil
        errorMessage = nil
        showNotice("Import cancelled. Your original files are unchanged.")
    }

    private func presentImportReview(_ pending: PendingImport) {
        importReview = ImportReview(id: pending.id, tracks: pending.batch.tracks,
                                    notes: pending.batch.reviewNotes,
                                    duplicateCount: Set(pending.batch.duplicateIDs).count,
                                    failures: pending.batch.failures,
                                    destinationName: pending.destinationName)
    }

    private enum ImportReviewError: LocalizedError {
        case changedIdentity
        var errorDescription: String? {
            "The prepared audio changed unexpectedly. Cancel this import and choose the files again."
        }
    }

    /// Both reviewed and unambiguous imports use the latest document and one
    /// commit, preserving edits made while preparation or review was open.
    private func finishImport(_ pending: PendingImport, tracks reviewedTracks: [Track],
                              artworkEdits: [UUID: TrackArtworkEdit] = [:]) -> Bool {
        guard canEdit else { errorMessage = LibraryError.notLoaded.localizedDescription; return false }
        if let playlistID = pending.playlistID, playlist(id: playlistID) == nil {
            errorMessage = "The destination playlist was deleted while this import was open. Cancel and import again into another collection."
            return false
        }
        let batch = pending.batch
        var stagedArtwork: [URL] = []
        defer { discardNewFiles(stagedArtwork) }
        let acceptedTracks: [Track]
        do {
            // Edits for skipped draft IDs are deliberately ignored. Validate all
            // accepted images before writing the first new artwork file.
            var normalized: [UUID: TrackArtworkEdit] = [:]
            var normalizations: [Data: Data] = [:]
            for track in reviewedTracks {
                let edit = artworkEdits[track.id] ?? .unchanged
                if case .replace(let data, let source) = edit, let cached = normalizations[data] {
                    try source?.validate()
                    normalized[track.id] = .replace(data: cached, source: source)
                } else {
                    let prepared = try edit.normalized()
                    normalized[track.id] = prepared
                    if case .replace(let data, _) = edit, case .replace(let bytes, _) = prepared { normalizations[data] = bytes }
                }
            }
            var sharedFiles: [Data: String] = [:]
            acceptedTracks = try reviewedTracks.map { track in
                try applyingArtwork(normalized[track.id] ?? .unchanged, to: track,
                                    sharedFiles: &sharedFiles, createdFiles: &stagedArtwork)
            }
        } catch { errorMessage = error.localizedDescription; return false }
        var next = document
        let previousIDs = Set(next.tracks.map(\.id))
        let importedIDs = next.mergeTracks(acceptedTracks)
        let known = Set(next.tracks.map(\.id))
        let preparedIDs = Set(batch.tracks.map(\.id))
        // A repeated source inside the batch can refer to a new prepared track;
        // if that track was skipped, its repeated copy must remain skipped too.
        let duplicateIDs = batch.duplicateIDs.filter { known.contains($0) && !preparedIDs.contains($0) }
        if let provenance = pending.provenance {
            next.attachSource(provenance, to: Set(duplicateIDs))
        }
        if let playlistID = pending.playlistID { next.addTracks(importedIDs + duplicateIDs, to: playlistID) }
        if commit(next) {
            // Removes only skipped/redundant new files. Committed tracks and
            // restored copies still referenced by the current library survive.
            discardNewFiles(batch.createdFiles)
            pendingImport = nil
            importReview = nil
            let newTracks = reviewedTracks.filter {
                known.contains($0.id) && !previousIDs.contains($0.id)
                    && !(artworkEdits[$0.id]?.changesArtwork ?? false)
            }.map(\.id)
            for id in newTracks where !artworkReviewTrackIDs.contains(id) { artworkReviewTrackIDs.append(id) }
            let imported = reviewedTracks.filter { known.contains($0.id) && !previousIDs.contains($0.id) }.count
            var message = "Imported \(imported) \(imported == 1 ? "track" : "tracks")."
            if !duplicateIDs.isEmpty { message += " \(duplicateIDs.count) already in your library." }
            let skipped = batch.tracks.count - reviewedTracks.count
            if skipped > 0 { message += " Skipped \(skipped)." }
            let restored = batch.repairedIDs.filter { known.contains($0) }.count
            if restored > 0 { message += " Restored \(restored) missing \(restored == 1 ? "copy" : "copies")." }
            showNotice(message)
            if !batch.failures.isEmpty {
                let shown = batch.failures.prefix(12).joined(separator: "\n")
                let remainder = batch.failures.count > 12 ? "\n…and \(batch.failures.count - 12) more." : ""
                errorMessage = "\(message)\n\nThese files need attention:\n\(shown)\(remainder)"
            }
            return true
        }
        return false
    }

    @discardableResult
    func createPlaylist(name: String, description: String = "", folderID: UUID? = nil,
                        symbol: String = "music.note.list", tint: PaletteColor = .blue, coverURL: URL? = nil) -> UUID? {
        guard canEdit else { errorMessage = LibraryError.notLoaded.localizedDescription; return nil }
        do {
            let name = try validName(name)
            let cover = try coverURL.map { try saveCover(from: $0) }
            let playlist = Playlist(name: name, description: String(description.prefix(2000)),
                                    symbol: String(symbol.prefix(100)), tint: tint, coverFileName: cover,
                                    folderID: folderID.flatMap { folder(id: $0) != nil ? $0 : nil })
            var next = document
            next.playlists.append(playlist)
            guard commit(next) else {
                if let cover { discardNewFiles([repository.artworkDirectory.appendingPathComponent(cover)]) }
                return nil
            }
            return playlist.id
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    @discardableResult
    func updatePlaylist(_ playlist: Playlist, coverURL: URL? = nil, removeCover: Bool = false) -> Bool {
        guard !playlist.isMixtape else { return false }
        guard let index = document.playlists.firstIndex(where: { $0.id == playlist.id }), canEdit else { return false }
        var createdCover: String?
        do {
            var edited = document.playlists[index]
            let oldCover = edited.coverFileName
            edited.name = try validName(playlist.name)
            edited.description = String(playlist.description.prefix(2000))
            edited.symbol = String(playlist.symbol.prefix(100))
            edited.tint = playlist.tint
            edited.folderID = playlist.folderID.flatMap { folder(id: $0) != nil ? $0 : nil }
            if let coverURL {
                createdCover = try saveCover(from: coverURL)
                edited.coverFileName = createdCover
            } else if removeCover { edited.coverFileName = nil }
            var next = document
            next.playlists[index] = edited
            guard commit(next) else {
                if let createdCover { discardNewFiles([repository.artworkDirectory.appendingPathComponent(createdCover)]) }
                return false
            }
            if let oldCover, oldCover != edited.coverFileName {
                trashUnreferenced([repository.artworkDirectory.appendingPathComponent(oldCover)])
            }
            return true
        } catch {
            if let createdCover { discardNewFiles([repository.artworkDirectory.appendingPathComponent(createdCover)]) }
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deletePlaylist(id: UUID) {
        guard id != MixtapeCollection.id else { return }
        let cover = playlist(id: id)?.coverFileName
        var next = document
        next.deletePlaylist(id: id)
        if commit(next), let cover { trashUnreferenced([repository.artworkDirectory.appendingPathComponent(cover)]) }
    }

    @discardableResult
    func createFolder(name: String, tint: PaletteColor = .graphite) -> UUID? {
        do {
            let folder = PlaylistFolder(name: try validName(name), tint: tint)
            var next = document
            next.folders.append(folder)
            return commit(next) ? folder.id : nil
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    func renameFolder(id: UUID, name: String) {
        guard let index = document.folders.firstIndex(where: { $0.id == id }) else { return }
        do {
            var next = document
            next.folders[index].name = try validName(name)
            _ = commit(next)
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteFolder(id: UUID) { var next = document; next.deleteFolder(id: id); _ = commit(next) }
    func movePlaylist(id: UUID, to folderID: UUID?) {
        guard id != MixtapeCollection.id else { return }
        var next = document
        next.movePlaylist(id: id, to: folderID)
        _ = commit(next)
    }

    @discardableResult
    func updateTrack(_ track: Track, genre: String? = nil) -> Bool {
        guard let index = document.tracks.firstIndex(where: { $0.id == track.id }), canEdit else {
            errorMessage = canEdit ? "This track is no longer in your library." : LibraryError.notLoaded.localizedDescription
            return false
        }
        var edited = track
        edited.genre = genre ?? document.tracks[index].genre
        return updateTracks(ids: [track.id], patch: .allFields(from: edited))
    }

    /// One validation contract and one commit for any size selection. No field
    /// spreads to unselected songs, including songs with the same origin.
    @discardableResult
    func updateTracks(ids: Set<UUID>, patch: BulkTrackPatch,
                      artwork: TrackArtworkEdit = .unchanged, expectedTracks: [Track]? = nil) -> Bool {
        guard canEdit else { errorMessage = LibraryError.notLoaded.localizedDescription; return false }
        guard !ids.isEmpty else { errorMessage = "Choose at least one track to edit."; return false }
        guard ids.isSubset(of: Set(tracks.map(\.id))) else {
            errorMessage = "Some selected tracks are no longer in your library. Select the tracks again."
            return false
        }
        guard !patch.isEmpty || artwork.changesArtwork else { errorMessage = nil; return true }
        var stagedArtwork: [URL] = []
        defer { discardNewFiles(stagedArtwork) }
        do {
            if artwork.changesArtwork { try validateArtworkSnapshots(expectedTracks, ids: ids, patch: patch) }
            var next = document
            for index in next.tracks.indices where ids.contains(next.tracks[index].id) {
                next.tracks[index] = try patch.applying(to: next.tracks[index])
            }
            let prepared = try artwork.normalized()
            var sharedFiles: [Data: String] = [:]
            for index in next.tracks.indices where ids.contains(next.tracks[index].id) {
                next.tracks[index] = try applyingArtwork(prepared, to: next.tracks[index],
                    sharedFiles: &sharedFiles, createdFiles: &stagedArtwork)
            }
            guard commit(next) else { return false }
            if artwork.changesArtwork { artworkReviewTrackIDs.removeAll { ids.contains($0) } }
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    /// Edits and an optional audio change commit together. Staging never modifies
    /// the active file, so failed validation or saving keeps the current version.
    @discardableResult
    func saveTrackEdits(trackID: UUID, patch: TrackMetadataPatch,
                        replacementURL: URL? = nil, restoreVersionID: UUID? = nil,
                        expectedFingerprint: String? = nil, artwork: TrackArtworkEdit = .unchanged,
                        expectedTrack: Track? = nil) async -> Bool {
        guard canEdit else { errorMessage = LibraryError.notLoaded.localizedDescription; return false }
        guard replacementURL == nil || restoreVersionID == nil else {
            errorMessage = "Choose a replacement file or a previous version, not both."; return false
        }
        guard let original = track(id: trackID) else {
            errorMessage = "This track is no longer in your library."; return false
        }
        guard expectedFingerprint == nil || original.fingerprint == expectedFingerprint else {
            errorMessage = "This song's audio changed while the Remix station was open. Save your take as a child song instead."; return false
        }
        guard replacementURL != nil || restoreVersionID != nil else {
            return updateTracks(ids: [trackID], patch: patch, artwork: artwork,
                                expectedTracks: expectedTrack.map { [$0] })
        }
        let preparedArtwork: TrackArtworkEdit
        do {
            _ = try patch.applying(to: original)
            if artwork.changesArtwork { try validateArtworkSnapshots(expectedTrack.map { [$0] }, ids: [trackID], patch: patch) }
            preparedArtwork = try artwork.normalized()
        } catch { errorMessage = error.localizedDescription; return false }
        guard replacingAudioID == nil, !isImporting else {
            errorMessage = "Wait for the current audio import to finish, then try again."; return false
        }
        replacingAudioID = trackID
        errorMessage = nil
        defer { replacingAudioID = nil }
        var stagedFiles: [URL] = []
        defer { discardNewFiles(stagedFiles) }
        do {
            // Before promising an archive, verify the existing managed bytes are
            // still present and match the song. A damaged/missing current file
            // must not become a misleading "saved" previous version.
            let currentVersion = TrackAudioVersion(id: original.currentAudioVersionID ?? UUID(),
                fileName: original.fileName, fingerprint: original.fingerprint,
                duration: original.duration, byteCount: original.byteCount,
                originalFileName: original.originalFileName, addedAt: original.currentAudioDate)
            do { try await AudioVersionImporter.validateArchived(currentVersion, at: audioURL(for: original)) }
            catch is CancellationError { throw CancellationError() }
            catch { throw AudioEditError.currentAudioUnavailable }
            let payload: TrackAudioPayload?
            if let replacementURL {
                let media = repository.mediaDirectory
                let prepared = try await AudioVersionImporter.prepare(sourceURL: replacementURL, mediaDirectory: media)
                stagedFiles = prepared.createdFiles
                payload = prepared.payload
            } else {
                guard let version = original.audioVersions.first(where: { $0.id == restoreVersionID }) else {
                    throw AudioEditError.missingVersion
                }
                try await AudioVersionImporter.validateArchived(version, at: audioURL(for: version))
                payload = nil
            }
            try Task.checkCancellation()
            guard let latest = track(id: trackID) else { throw AudioEditError.missingTrack }
            guard latest.fileName == original.fileName, latest.fingerprint == original.fingerprint,
                  latest.currentAudioVersionID == original.currentAudioVersionID else { throw AudioEditError.changedAudio }
            if artwork.changesArtwork { try validateArtworkSnapshots(expectedTrack.map { [$0] }, ids: [trackID], patch: patch) }
            var next = document
            guard let index = next.tracks.firstIndex(where: { $0.id == trackID }) else { throw AudioEditError.missingTrack }
            next.tracks[index] = try patch.applying(to: latest)
            var sharedFiles: [Data: String] = [:]
            next.tracks[index] = try applyingArtwork(preparedArtwork, to: next.tracks[index],
                sharedFiles: &sharedFiles, createdFiles: &stagedFiles)
            if let payload { try next.replaceAudio(trackID: trackID, with: payload) }
            else if let restoreVersionID { try next.restoreAudioVersion(trackID: trackID, versionID: restoreVersionID) }
            guard commit(next) else { return false }
            if artwork.changesArtwork { artworkReviewTrackIDs.removeAll { $0 == trackID } }
            showNotice(payload == nil ? "Previous audio restored. The replaced version is archived with this song." : "Audio replaced. The previous version is archived with this song.")
            return true
        } catch is CancellationError {
            errorMessage = "Audio replacement cancelled. The current track is unchanged."; return false
        } catch { errorMessage = error.localizedDescription; return false }
    }

    /// Takes remain in the station until the caller sees a successful managed copy
    /// and manifest commit. Neither failure nor cancellation loses a recording.
    @discardableResult
    func saveRemixChild(source: Track, takeURL: URL, title: String, artist: String) async -> Bool {
        guard canEdit else { errorMessage = LibraryError.notLoaded.localizedDescription; return false }
        guard !isImporting, replacingAudioID == nil else {
            errorMessage = "Wait for the current audio import to finish, then try again."; return false
        }
        guard track(id: source.id) != nil else {
            errorMessage = "The source song was removed. Your recording is still saved in the Remix station."; return false
        }
        var proposed = source
        proposed.title = title; proposed.artist = artist
        do { _ = try TrackMetadataPatch.allFields(from: proposed).applying(to: proposed) }
        catch { errorMessage = error.localizedDescription; return false }
        replacingAudioID = source.id
        errorMessage = nil
        defer { replacingAudioID = nil }
        var stagedFiles: [URL] = []
        defer { discardNewFiles(stagedFiles) }
        do {
            let prepared = try await AudioVersionImporter.prepare(sourceURL: takeURL, mediaDirectory: repository.mediaDirectory)
            stagedFiles = prepared.createdFiles
            try Task.checkCancellation()
            var next = document
            try next.addRemix(source: source, audio: prepared.payload, title: title, artist: artist)
            guard commit(next) else { return false }
            showNotice("Remix saved as a Classic child song. The original is unchanged.")
            return true
        } catch is CancellationError {
            errorMessage = "Saving cancelled. Your recording is still in the Remix station."; return false
        } catch { errorMessage = error.localizedDescription; return false }
    }

    private enum AudioEditError: LocalizedError {
        case missingTrack, missingVersion, changedAudio, currentAudioUnavailable
        var errorDescription: String? {
            switch self {
            case .missingTrack: return "This track is no longer in your library."
            case .missingVersion: return "This audio version is no longer available. Reopen the editor and try again."
            case .changedAudio: return "The track's audio changed while preparing this update. Reopen the editor and try again."
            case .currentAudioUnavailable: return "The current audio is missing, damaged, or has changed outside Bard. It could not be safely archived, so nothing was replaced."
            }
        }
    }

    func toggleFavorite(id: UUID) {
        guard let index = document.tracks.firstIndex(where: { $0.id == id }) else { return }
        var next = document
        next.tracks[index].favorite.toggle()
        _ = commit(next)
    }

    func addTracks(_ ids: [UUID], to playlistID: UUID) {
        var next = document
        next.addTracks(ids, to: playlistID)
        _ = commit(next)
    }

    func addToMixtape(_ ids: [UUID]) { addTracks(ids, to: MixtapeCollection.id) }
    func removeFromMixtape(_ ids: Set<UUID>) { removeTracks(ids, from: MixtapeCollection.id) }

    func removeTracks(_ ids: Set<UUID>, from playlistID: UUID) {
        var next = document
        next.removeTracks(ids, from: playlistID)
        _ = commit(next)
    }

    func deleteTracks(_ ids: Set<UUID>) {
        guard !isImporting else { showNotice("Wait for the import to finish before deleting tracks."); return }
        let removed = document.tracks.filter { ids.contains($0.id) }
        var next = document
        next.deleteTracks(ids)
        guard commit(next) else { return }
        let files = removed.flatMap { track in
            ([track.fileName] + track.audioVersions.map(\.fileName)).map { repository.mediaDirectory.appendingPathComponent($0) } +
            (track.artworkFileName.map { [repository.artworkDirectory.appendingPathComponent($0)] } ?? [])
        }
        trashUnreferenced(files)
    }

    func moveTrack(id: UUID, in playlistID: UUID, offset: Int) {
        var next = document
        next.moveTrack(id: id, in: playlistID, offset: offset)
        _ = commit(next)
    }

    func moveTracks(fromOffsets offsets: IndexSet, toOffset destination: Int, in playlistID: UUID) {
        var next = document
        next.moveTracks(fromOffsets: offsets, toOffset: destination, in: playlistID)
        _ = commit(next)
    }

    func recoverPrevious() {
        guard !isImporting, pendingImport == nil else {
            showNotice("Finish or cancel the import before restoring the previous library.")
            return
        }
        do {
            document = try repository.recoverPrevious()
            var migrated = document
            if MixtapeCollection.ensure(in: &migrated) {
                try repository.save(migrated)
                document = migrated
            }
            canEdit = true
            errorMessage = nil
            showNotice("The previous index was restored. The replaced index was kept in the library folder.")
        } catch {
            if let libraryError = error as? LibraryError, case .changedExternally = libraryError { canEdit = false }
            errorMessage = error.localizedDescription
        }
    }

    private func commit(_ proposed: LibraryDocument) -> Bool {
        guard canEdit else { errorMessage = LibraryError.notLoaded.localizedDescription; return false }
        var next = proposed
        MixtapeCollection.ensure(in: &next)
        guard next != document else { errorMessage = nil; return true }
        do {
            try repository.save(next)
            document = next
            errorMessage = nil
            return true
        } catch {
            if let libraryError = error as? LibraryError, case .changedExternally = libraryError { canEdit = false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func validName(_ text: String, limit: Int = 80) throws -> String {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw InputError.nameRequired }
        guard name.count <= limit else { throw InputError.nameTooLong(limit) }
        return name
    }

    private enum InputError: LocalizedError {
        case nameRequired, nameTooLong(Int), sourceLink
        var errorDescription: String? {
            switch self {
            case .nameRequired: return "Enter a name before saving."
            case .nameTooLong(let limit): return "Use a name of \(limit) characters or fewer."
            case .sourceLink: return "Use a valid website link for the source."
            }
        }
    }

    private func validateArtworkSnapshots(_ expected: [Track]?, ids: Set<UUID>, patch: TrackMetadataPatch) throws {
        guard let expected, expected.count == ids.count,
              Set(expected.map(\.id)) == ids else { throw TrackArtworkEditError.missingSnapshot }
        for snapshot in expected {
            guard let current = track(id: snapshot.id),
                  current.fileName == snapshot.fileName, current.fingerprint == snapshot.fingerprint,
                  current.currentAudioVersionID == snapshot.currentAudioVersionID,
                  current.title == snapshot.title, current.artist == snapshot.artist,
                  current.genre == snapshot.genre, current.origin == snapshot.origin,
                  current.originMediaKind == snapshot.originMediaKind,
                  current.artworkFileName == snapshot.artworkFileName, current.artworkSource == snapshot.artworkSource,
                  !patch.applySource || current.sourceURL == snapshot.sourceURL,
                  !patch.applyRemix || current.remix == snapshot.remix,
                  !patch.applyFavorite || current.favorite == snapshot.favorite else { throw TrackArtworkEditError.changedTrack }
        }
    }

    /// One newly written image may be referenced by any number of selected songs.
    /// Old images are never deleted; previous indexes and other songs can still use them.
    private func applyingArtwork(_ edit: TrackArtworkEdit, to track: Track,
                                 sharedFiles: inout [Data: String], createdFiles: inout [URL]) throws -> Track {
        var result = track
        switch edit {
        case .unchanged: break
        case .remove:
            result.artworkFileName = nil; result.artworkSource = nil
        case .replace(let data, let source):
            let name: String
            if let shared = sharedFiles[data] { name = shared }
            else {
                name = UUID().uuidString + ".png"
                let url = repository.artworkDirectory.appendingPathComponent(name)
                // Exclusive creation establishes ownership before writing so a
                // partial write can be removed without risking an existing cover.
                let descriptor = url.withUnsafeFileSystemRepresentation { path in
                    Darwin.open(path!, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
                }
                guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                createdFiles.append(url)
                let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                try handle.write(contentsOf: data)
                try handle.close()
                sharedFiles[data] = name
            }
            result.artworkFileName = name; result.artworkSource = source
        }
        return result
    }

    private func saveCover(from source: URL) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 20 * 1_048_576 else { throw AudioImporter.ImportError.invalidCover }
        let data = try Data(contentsOf: source)
        return try saveCover(data: data)
    }

    private func saveCover(data: Data) throws -> String {
        guard !data.isEmpty, data.count <= 20 * 1_048_576 else { throw AudioImporter.ImportError.invalidCover }
        guard let normalized = AudioImporter.normalizedArtwork(data) else { throw AudioImporter.ImportError.invalidCover }
        let name = "\(UUID().uuidString).png"
        try normalized.write(to: repository.artworkDirectory.appendingPathComponent(name), options: .atomic)
        return name
    }

    /// Newly created staging/copies are ours; cleanup is never applied to an original source URL.
    private func discardNewFiles(_ urls: [URL]) {
        // An externally changed index makes our in-memory references stale.
        // Retaining a disposable copy is safer than deleting an unknown reference.
        guard canEdit else { return }
        let media = tracks.flatMap { [$0.fileName] + $0.audioVersions.map(\.fileName) }
            .map { repository.mediaDirectory.appendingPathComponent($0).standardizedFileURL.path }
        let artwork = (tracks.compactMap(\.artworkFileName) + playlists.compactMap(\.coverFileName))
            .map { repository.artworkDirectory.appendingPathComponent($0).standardizedFileURL.path }
        let referenced = Set(media + artwork)
        for url in Set(urls) where isOwned(url) && !referenced.contains(url.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func trashUnreferenced(_ urls: [URL]) {
        let mediaReferences = Set(tracks.flatMap { [$0.fileName] + $0.audioVersions.map(\.fileName) }
            .map { repository.mediaDirectory.appendingPathComponent($0).standardizedFileURL.path })
        let artworkNames = tracks.compactMap(\.artworkFileName) + playlists.compactMap(\.coverFileName)
        let artworkReferences = Set(artworkNames.map { repository.artworkDirectory.appendingPathComponent($0).standardizedFileURL.path })
        var failures = 0
        for url in Set(urls) where isOwned(url) {
            guard !mediaReferences.contains(url.standardizedFileURL.path), !artworkReferences.contains(url.standardizedFileURL.path),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
            catch { failures += 1 }
        }
        if failures > 0 { showNotice("Removed from the library. Some unused copies remain in its folder because Trash was unavailable.") }
    }

    private func isOwned(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().standardizedFileURL
        return parent == repository.mediaDirectory.standardizedFileURL || parent == repository.artworkDirectory.standardizedFileURL
    }

    private func showNotice(_ message: String) {
        noticeTask?.cancel()
        notice = message
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}
