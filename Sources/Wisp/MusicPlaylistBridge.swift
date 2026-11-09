import Foundation
import AppKit
import CryptoKit
import Carbon
import ImageIO
import OSLog

private let musicPlaylistBridgeLogger = Logger(subsystem: "Wisp", category: "MusicPlaylistBridge")

struct MusicPlaylistBridgeItem: Codable, Equatable, Sendable {
    var id: UUID
    var fingerprint: String
    var title: String
    var artist: String
    var album: String
    var genre: String
    var fileURL: URL
    var artworkURL: URL?

    init(id: UUID, fingerprint: String, title: String, artist: String = "", album: String = "", genre: String = "",
         fileURL: URL, artworkURL: URL? = nil) {
        self.id = id; self.fingerprint = fingerprint; self.title = title; self.artist = artist
        self.album = album; self.genre = genre; self.fileURL = fileURL; self.artworkURL = artworkURL
    }
}

struct MusicPlaylistBridgeRequest: Codable, Equatable, Sendable {
    var items: [MusicPlaylistBridgeItem]
    var playlistName: String
    var playlistArtworkURL: URL?
    init(items: [MusicPlaylistBridgeItem], playlistName: String = "Mixtape", playlistArtworkURL: URL? = nil) {
        self.items = items; self.playlistName = playlistName; self.playlistArtworkURL = playlistArtworkURL
    }
}

struct MusicPlaylistBridgeMapping: Codable, Equatable, Sendable {
    var musicPersistentID: String
    var fingerprint: String
    var metadataSignature: String
    init(musicPersistentID: String, fingerprint: String, metadataSignature: String = "") {
        self.musicPersistentID = musicPersistentID; self.fingerprint = fingerprint; self.metadataSignature = metadataSignature
    }
}

struct MusicPlaylistBridgePendingImport: Codable, Equatable, Sendable {
    var item: MusicPlaylistBridgeItem
    var fileDigest: String
    var previousLibraryIDs: [String]
}

struct MusicPlaylistBridgeState: Codable, Equatable, Sendable {
    var libraryID: String?
    var playlistID: String?
    var mappings: [UUID: MusicPlaylistBridgeMapping]
    // Every audio revision imported by Wisp remains reusable after restoring it.
    // Keys are Music persistent IDs, so ambiguity is preserved rather than hidden.
    var versionMappings: [String: MusicPlaylistBridgeMapping]
    var pendingImport: MusicPlaylistBridgePendingImport?
    var playlistArtworkSignature: String?
    init(libraryID: String? = nil, playlistID: String? = nil,
         mappings: [UUID: MusicPlaylistBridgeMapping] = [:], pendingImport: MusicPlaylistBridgePendingImport? = nil,
         playlistArtworkSignature: String? = nil, versionMappings: [String: MusicPlaylistBridgeMapping] = [:]) {
        self.libraryID = libraryID; self.playlistID = playlistID; self.mappings = mappings; self.pendingImport = pendingImport
        self.playlistArtworkSignature = playlistArtworkSignature
        self.versionMappings = versionMappings
    }

    private enum CodingKeys: String, CodingKey {
        case libraryID, playlistID, mappings, versionMappings, pendingImport, playlistArtworkSignature
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        libraryID = try values.decodeIfPresent(String.self, forKey: .libraryID)
        playlistID = try values.decodeIfPresent(String.self, forKey: .playlistID)
        mappings = try values.decode([UUID: MusicPlaylistBridgeMapping].self, forKey: .mappings)
        versionMappings = try values.decodeIfPresent([String: MusicPlaylistBridgeMapping].self, forKey: .versionMappings) ?? [:]
        pendingImport = try values.decodeIfPresent(MusicPlaylistBridgePendingImport.self, forKey: .pendingImport)
        playlistArtworkSignature = try values.decodeIfPresent(String.self, forKey: .playlistArtworkSignature)
    }

    mutating func remember(_ mapping: MusicPlaylistBridgeMapping, for id: UUID) {
        if let previous = mappings[id] { versionMappings[previous.musicPersistentID] = previous }
        mappings[id] = mapping
        versionMappings[mapping.musicPersistentID] = mapping
    }
}

struct MusicPlaylistBridgeResult: Codable, Equatable, Sendable {
    var state: MusicPlaylistBridgeState
    var trackCount: Int
    var importedCount: Int
    var updatedCount: Int
    var warnings: [String]
    init(state: MusicPlaylistBridgeState, trackCount: Int = 0, importedCount: Int = 0,
         updatedCount: Int = 0, warnings: [String] = []) {
        self.state = state; self.trackCount = trackCount; self.importedCount = importedCount
        self.updatedCount = updatedCount; self.warnings = warnings
    }
}

struct MusicPlaylistBridgePlaylist: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var trackIDs: [String]
    var isEditable: Bool
}

struct MusicPlaylistBridgeInspection: Codable, Equatable, Sendable {
    var libraryID: String
    var playlists: [MusicPlaylistBridgePlaylist]
}

enum MusicPlaylistBridgeError: LocalizedError, Equatable, Sendable {
    case automationDenied, musicUnavailable, libraryChanged, playlistMissing, unsafePlaylist
    case playlistConflict(String), missingFile(String), interruptedImport(String), verificationFailed(String)
    case scriptFailure(Int, String), invalidRequest(String)

    var isAutomationDenied: Bool { self == .automationDenied }
    var errorDescription: String? {
        switch self {
        case .automationDenied: return "Allow Bard to control Music in System Settings → Privacy & Security → Automation, then try again."
        case .musicUnavailable: return "Music is unavailable. Open Music and try again."
        case .libraryChanged: return "Music is using a different library. The linked library has not been changed."
        case .playlistMissing: return "The linked playlist disappeared during sync. Try again to reconnect safely."
        case .unsafePlaylist: return "Bard can only manage a regular, private playlist. No playlist was changed."
        case .playlistConflict(let message): return message
        case .missingFile(let title): return "The publishing copy for “\(title)” is missing or unreadable."
        case .interruptedImport(let title): return "Music may already contain “\(title)” from an interrupted sync. Bard stopped rather than add a second copy."
        case .verificationFailed(let message): return "Music has not confirmed the update. \(message)"
        case .scriptFailure(_, let message): return "Music could not finish this sync. \(message)"
        case .invalidRequest(let message): return message
        }
    }
}

// The backend permits deterministic failure/recovery checks without touching Music.
struct MusicPlaylistBridgeNativeTrack: Equatable {
    var id: String
    var fileURL: URL?
}

protocol MusicPlaylistBridgeBackend {
    func libraryID() throws -> String
    func playlists(named: String) throws -> [MusicPlaylistBridgePlaylist]
    func playlist(id: String) throws -> MusicPlaylistBridgePlaylist?
    func createPlaylist(named: String) throws -> MusicPlaylistBridgePlaylist
    func allTrackIDs() throws -> [String]
    func track(id: String) throws -> MusicPlaylistBridgeNativeTrack?
    func importFile(_ url: URL) throws -> String
    func updateMetadata(id: String, item: MusicPlaylistBridgeItem) throws -> [String]
    func setPlaylistArtwork(playlistID: String, fileURL: URL) throws
    func removeMembership(at index: Int, playlistID: String, expectedTrackID: String) throws
    func appendMembership(trackID: String, playlistID: String) throws
}

/// Runs on the coordinator's serial worker. Only Music's application-data API
/// is used; no GUI scripting, playback commands, or library deletion exists.
enum MusicPlaylistBridge {
    static func synchronize(request: MusicPlaylistBridgeRequest, state: MusicPlaylistBridgeState,
                            checkpoint: (MusicPlaylistBridgeState) throws -> Void) throws -> MusicPlaylistBridgeResult {
        try synchronize(request: request, state: state, checkpoint: checkpoint, backend: MusicPlaylistScriptBackend())
    }

    static func inspect(playlistName: String = "Mixtape") throws -> MusicPlaylistBridgeInspection {
        let backend = try MusicPlaylistScriptBackend()
        return MusicPlaylistBridgeInspection(libraryID: try backend.libraryID(), playlists: try backend.playlists(named: playlistName))
    }

    /// Compiles static handlers without sending an event to Music.
    static func validateScriptCompilation() throws { _ = try MusicPlaylistScriptBackend() }

    static func synchronize(request: MusicPlaylistBridgeRequest, state initial: MusicPlaylistBridgeState,
                            checkpoint: (MusicPlaylistBridgeState) throws -> Void,
                            backend: MusicPlaylistBridgeBackend) throws -> MusicPlaylistBridgeResult {
        guard !request.playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Set(request.items.map(\.id)).count == request.items.count,
              Set(request.items.map(\.fingerprint)).count == request.items.count,
              request.items.allSatisfy({ !$0.fingerprint.isEmpty && !$0.title.isEmpty }) else {
            throw MusicPlaylistBridgeError.invalidRequest("Mixtape contains an invalid or repeated track.")
        }
        for item in request.items { try validateFile(item.fileURL, title: item.title) }
        let identity = try backend.libraryID()
        guard !identity.isEmpty else { throw MusicPlaylistBridgeError.musicUnavailable }
        var state = initial
        if let expected = state.libraryID, expected != identity { throw MusicPlaylistBridgeError.libraryChanged }
        if state.libraryID == nil && (state.playlistID != nil || !state.mappings.isEmpty || !state.versionMappings.isEmpty || state.pendingImport != nil) {
            throw MusicPlaylistBridgeError.libraryChanged
        }
        state.libraryID = identity
        for mapping in state.mappings.values { state.versionMappings[mapping.musicPersistentID] = mapping }
        // Confirm durable storage before the first possible external mutation.
        try checkpoint(state)
        let linked: MusicPlaylistBridgePlaylist
        if let id = state.playlistID, let existing = try backend.playlist(id: id) {
            guard existing.isEditable else { throw MusicPlaylistBridgeError.unsafePlaylist }
            linked = existing
        } else {
            let candidates = try backend.playlists(named: request.playlistName)
            guard candidates.count <= 1 else {
                throw MusicPlaylistBridgeError.playlistConflict("Music has more than one playlist named “\(request.playlistName)”. Rename the unrelated playlists, then try again.")
            }
            if let candidate = candidates.first {
                guard candidate.isEditable else { throw MusicPlaylistBridgeError.unsafePlaylist }
                guard candidate.trackIDs.isEmpty else {
                    throw MusicPlaylistBridgeError.playlistConflict("Music already has a playlist named “\(request.playlistName)” with songs in it. Rename that playlist to keep it, then try again. Bard has not changed it.")
                }
                linked = candidate
            } else {
                // The native handler repeats the name/emptiness check to close
                // the gap between inspection and creation.
                linked = try backend.createPlaylist(named: request.playlistName)
            }
            guard linked.isEditable, linked.trackIDs.isEmpty else { throw MusicPlaylistBridgeError.unsafePlaylist }
            state.playlistID = linked.id
            // An old cover receipt belongs to the old playlist, even when the
            // replacement has the same display name.
            state.playlistArtworkSignature = nil
            try checkpoint(state)
        }
        var imported = 0
        var updated = 0
        var warnings: [String] = []
        if let pending = state.pendingImport {
            let previous = Set(pending.previousLibraryIDs)
            let appeared = try backend.allTrackIDs().filter { !previous.contains($0) }
            var matches: [String] = []
            for id in appeared {
                guard let location = try backend.track(id: id)?.fileURL,
                      let digest = try? fileDigest(location), digest == pending.fileDigest else { continue }
                matches.append(id)
            }
            if matches.count == 1, let id = matches.first {
                state.remember(MusicPlaylistBridgeMapping(musicPersistentID: id, fingerprint: pending.item.fingerprint), for: pending.item.id)
                state.pendingImport = nil
                try checkpoint(state)
            } else {
                // An add can outlive an Apple-event timeout. Even no visible
                // addition is ambiguous, so never issue a second add merely
                // because the first one has not appeared yet.
                throw MusicPlaylistBridgeError.interruptedImport(pending.item.title)
            }
        }
        var desiredIDs: [String] = []
        for item in request.items {
            try Task.checkCancellation()
            let existing = state.mappings[item.id]
            var reusable = false
            if let existing, existing.fingerprint == item.fingerprint {
                reusable = try backend.track(id: existing.musicPersistentID) != nil
            }
            if !reusable {
                // A restored revision or reimported Wisp song can reuse any
                // previously published audio that still belongs to this library.
                let candidates = Set(state.versionMappings.values.filter { $0.fingerprint == item.fingerprint }.map(\.musicPersistentID))
                var surviving: [String] = []
                for id in candidates where try backend.track(id: id) != nil { surviving.append(id) }
                if surviving.count == 1, let id = surviving.first {
                    state.remember(MusicPlaylistBridgeMapping(musicPersistentID: id, fingerprint: item.fingerprint), for: item.id)
                    try checkpoint(state)
                    reusable = true
                } else if surviving.count > 1 {
                    throw MusicPlaylistBridgeError.playlistConflict("Music has multiple Bard copies of “\(item.title)”. Bard stopped rather than choose or import another copy.")
                }
            }
            if !reusable {
                let before = try backend.allTrackIDs()
                state.pendingImport = MusicPlaylistBridgePendingImport(item: item, fileDigest: try fileDigest(item.fileURL), previousLibraryIDs: before)
                try checkpoint(state)
                let id = try backend.importFile(item.fileURL)
                guard !id.isEmpty, !before.contains(id) else {
                    if !id.isEmpty {
                        // Music explicitly returned an existing item. This is
                        // a known no-new-item result, not an uncertain import.
                        state.pendingImport = nil
                        try checkpoint(state)
                    }
                    throw MusicPlaylistBridgeError.playlistConflict("Music reused an existing copy of “\(item.title)”. Its metadata was left unchanged; Bard will not take ownership of another library track.")
                }
                state.remember(MusicPlaylistBridgeMapping(musicPersistentID: id, fingerprint: item.fingerprint), for: item.id)
                state.pendingImport = nil
                // Save identity immediately after add, before any later metadata
                // write or playlist operation can fail.
                try checkpoint(state)
                imported += 1
            }
            guard var mapping = state.mappings[item.id] else { throw MusicPlaylistBridgeError.verificationFailed("A track reference is missing.") }
            let signature = try metadataSignature(item)
            if mapping.metadataSignature != signature {
                let metadataWarnings = try backend.updateMetadata(id: mapping.musicPersistentID, item: item)
                warnings.append(contentsOf: metadataWarnings)
                // A cover rejected by Music remains retryable on the next sync.
                if metadataWarnings.isEmpty { mapping.metadataSignature = signature }
                state.remember(mapping, for: item.id)
                try checkpoint(state)
                updated += 1
            }
            desiredIDs.append(mapping.musicPersistentID)
        }
        guard Set(desiredIDs).count == desiredIDs.count else {
            throw MusicPlaylistBridgeError.verificationFailed("Two Bard tracks point to the same Music item.")
        }
        guard let latest = try backend.playlist(id: linked.id), latest.isEditable else { throw MusicPlaylistBridgeError.playlistMissing }
        var sharedPrefix = 0
        while sharedPrefix < min(latest.trackIDs.count, desiredIDs.count), latest.trackIDs[sharedPrefix] == desiredIDs[sharedPrefix] {
            sharedPrefix += 1
        }
        // Retain the common prefix. Remove only suffix memberships, from the
        // end, and append the requested remainder. No library track is deleted.
        if latest.trackIDs.count > sharedPrefix {
            for index in stride(from: latest.trackIDs.count - 1, through: sharedPrefix, by: -1) {
                try Task.checkCancellation()
                try backend.removeMembership(at: index, playlistID: linked.id, expectedTrackID: latest.trackIDs[index])
                try checkpoint(state)
            }
        }
        for id in desiredIDs.dropFirst(sharedPrefix) {
            try Task.checkCancellation()
            try backend.appendMembership(trackID: id, playlistID: linked.id)
            try checkpoint(state)
        }
        guard let verified = try backend.playlist(id: linked.id), verified.isEditable, verified.trackIDs == desiredIDs else {
            throw MusicPlaylistBridgeError.verificationFailed("Mixtape's order has not settled yet. It will be checked again.")
        }
        // Read back all formerly present tracks to assert the membership-only
        // deletion boundary. This is never used as an excuse for cleanup.
        for id in Set(latest.trackIDs) where try backend.track(id: id) == nil {
            throw MusicPlaylistBridgeError.verificationFailed("A Music library track disappeared during sync. No further changes were made.")
        }
        var confirmedArtworkSignature: String?
        if let artworkURL = request.playlistArtworkURL {
            do {
                let signature = try playlistArtworkSignature(artworkURL)
                if state.playlistArtworkSignature != signature {
                    try backend.setPlaylistArtwork(playlistID: linked.id, fileURL: artworkURL)
                    confirmedArtworkSignature = signature
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as MusicPlaylistBridgeError where error == .automationDenied || error == .musicUnavailable || error == .unsafePlaylist || error == .playlistMissing || error == .libraryChanged {
                throw error
            } catch {
                // Music versions may advertise playlist artwork without
                // accepting it. Never substitute individual track artwork.
                musicPlaylistBridgeLogger.error("Mixtape cover was not confirmed: \(String(describing: error), privacy: .private)")
                warnings.append("Mixtape's songs are synced, but Music could not update its playlist cover. Bard will retry the cover on the next sync.")
            }
        }
        if let signature = confirmedArtworkSignature {
            state.playlistArtworkSignature = signature
            // A storage failure must remain a sync failure, not a cover warning.
            try checkpoint(state)
        }
        return MusicPlaylistBridgeResult(state: state, trackCount: desiredIDs.count, importedCount: imported,
                                         updatedCount: updated, warnings: Array(Set(warnings)).sorted())
    }

    private static func validateFile(_ url: URL, title: String) throws {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard url.isFileURL, values?.isRegularFile == true, values?.isSymbolicLink != true,
              FileManager.default.isReadableFile(atPath: url.path) else { throw MusicPlaylistBridgeError.missingFile(title) }
    }

    static func fileDigest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 256 * 1024), !data.isEmpty {
            try Task.checkCancellation(); hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func metadataSignature(_ item: MusicPlaylistBridgeItem) throws -> String {
        let artwork = try item.artworkURL.map(fileDigest) ?? ""
        let data = try JSONEncoder().encode([item.title, item.artist, item.album, item.genre, artwork])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func playlistArtworkSignature(_ url: URL) throws -> String {
        try validateFile(url, title: "Mixtape cover")
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size > 0, size <= 20 * 1024 * 1024 else {
            throw MusicPlaylistBridgeError.invalidRequest("Mixtape's cover must be an image smaller than 20 MB.")
        }
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw MusicPlaylistBridgeError.invalidRequest("Mixtape's cover is not a supported image.")
        }
        try Task.checkCancellation()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// Music may resize or JPEG-encode a playlist cover. Compare its rendered image,
// not the encoded bytes, and retain contrast checks so a dark placeholder or an
// unchanged older cover cannot be mistaken for a successful write.
enum MusicPlaylistArtworkComparison {
    private struct Sample {
        let pixels: [UInt8]
        let aspectRatio: Double
    }

    static func matches(expected: Data, returned: Data) -> Bool {
        guard let reference = sample(expected), let actual = sample(returned),
              abs(reference.aspectRatio / actual.aspectRatio - 1) <= 0.02 else { return false }
        let count = 64 * 64
        var absoluteError = 0.0, squaredError = 0.0
        var referenceMeans = [Double](repeating: 0, count: 3)
        var actualMeans = [Double](repeating: 0, count: 3)
        for pixel in 0..<count {
            for channel in 0..<3 {
                let lhs = Double(reference.pixels[pixel * 4 + channel]) / 255
                let rhs = Double(actual.pixels[pixel * 4 + channel]) / 255
                referenceMeans[channel] += lhs / Double(count)
                actualMeans[channel] += rhs / Double(count)
                absoluteError += abs(lhs - rhs)
                squaredError += (lhs - rhs) * (lhs - rhs)
            }
        }
        let meanError = absoluteError / Double(count * 3)
        let rootMeanSquareError = sqrt(squaredError / Double(count * 3))
        guard meanError <= 0.035, rootMeanSquareError <= 0.065 else { return false }
        var referenceVariance = 0.0, actualVariance = 0.0
        for pixel in 0..<count {
            for channel in 0..<3 {
                let lhs = Double(reference.pixels[pixel * 4 + channel]) / 255 - referenceMeans[channel]
                let rhs = Double(actual.pixels[pixel * 4 + channel]) / 255 - actualMeans[channel]
                referenceVariance += lhs * lhs
                actualVariance += rhs * rhs
            }
        }
        let referenceContrast = sqrt(referenceVariance / Double(count * 3))
        let actualContrast = sqrt(actualVariance / Double(count * 3))
        // Flat, intentional covers still compare by color above. For artwork,
        // require its structure to survive as well as its overall dark palette.
        return referenceContrast <= 0.02 ||
            (rootMeanSquareError <= referenceContrast * 0.35 && actualContrast >= referenceContrast * 0.65)
    }

    private static func sample(_ data: Data) -> Sample? {
        guard !data.isEmpty, data.count <= 20 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 64
              ] as CFDictionary),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 64, height: 64,
                bitsPerComponent: 8, bytesPerRow: 64 * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            return true
        }
        return rendered ? Sample(pixels: pixels, aspectRatio: Double(width) / Double(height)) : nil
    }
}

/// Music can report error 1 after accepting an image. A successful setter alone
/// is not a receipt; the intended image must be readable from the owned song.
enum MusicTrackArtworkVerification {
    static func isConfirmed(expected: Data, returned: Data?, setterError: Int32) -> Bool {
        guard setterError == 0 || setterError == 1, let returned, !returned.isEmpty else { return false }
        return MusicPlaylistArtworkComparison.matches(expected: expected, returned: returned)
    }
}

private final class MusicPlaylistScriptBackend: MusicPlaylistBridgeBackend {
    private let script: NSAppleScript

    init() throws {
        guard let script = NSAppleScript(source: Self.source) else { throw MusicPlaylistBridgeError.musicUnavailable }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else { throw Self.failure(error) }
        self.script = script
    }

    func libraryID() throws -> String {
        let result = try call("libraryidentity")
        let parts = try strings(result)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { throw MusicPlaylistBridgeError.musicUnavailable }
        return parts.joined(separator: ":")
    }

    func playlists(named name: String) throws -> [MusicPlaylistBridgePlaylist] {
        let result = try call("matchingplaylists", [.init(string: name)])
        return try (1...max(1, result.numberOfItems)).compactMap { index in
            guard index <= result.numberOfItems, let entry = result.atIndex(index) else { return nil }
            return try playlistValue(entry)
        }
    }

    func playlist(id: String) throws -> MusicPlaylistBridgePlaylist? {
        let value = try call("playlistwithid", [.init(string: id)])
        return value.numberOfItems == 0 ? nil : try playlistValue(value)
    }

    func createPlaylist(named name: String) throws -> MusicPlaylistBridgePlaylist {
        try playlistValue(call("createemptyplaylist", [.init(string: name)]))
    }

    func allTrackIDs() throws -> [String] { try strings(call("librarytrackids")) }

    func track(id: String) throws -> MusicPlaylistBridgeNativeTrack? {
        let value = try call("trackwithid", [.init(string: id)])
        guard value.numberOfItems > 0 else { return nil }
        let record = try strings(value)
        guard record.count == 2, record[0] == id else { throw MusicPlaylistBridgeError.verificationFailed("Music returned an unexpected track reference.") }
        return MusicPlaylistBridgeNativeTrack(id: record[0], fileURL: record[1].isEmpty ? nil : URL(fileURLWithPath: record[1]))
    }

    func importFile(_ url: URL) throws -> String {
        guard let id = try call("importaudiofile", [.init(string: url.path)]).stringValue, !id.isEmpty else {
            throw MusicPlaylistBridgeError.verificationFailed("Music did not return the imported track.")
        }
        return id
    }

    func updateMetadata(id: String, item: MusicPlaylistBridgeItem) throws -> [String] {
        var artwork = NSAppleEventDescriptor.null()
        var artworkMode: Int32 = 2 // Clear old artwork when Wisp has none.
        var expectedArtwork: Data?
        var warnings: [String] = []
        if let url = item.artworkURL {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int.max
            if size <= 20 * 1024 * 1024, let data = try? Data(contentsOf: url), !data.isEmpty,
               let descriptor = NSAppleEventDescriptor(descriptorType: DescType(typePict), data: data) {
                // Use Music's picture setter, as for playlist covers. Generic
                // raw data cannot reliably create a song's first artwork.
                artwork = descriptor
                artworkMode = 1
                expectedArtwork = data
            } else {
                artworkMode = 0
                warnings.append("The cover for “\(item.title)” could not be sent to Music.")
            }
        }
        let result = try call("applytrackmetadata", [.init(string: id), .init(string: item.title),
            .init(string: item.artist), .init(string: item.album), .init(string: item.genre),
            .init(int32: artworkMode), artwork])
        let values = (1...5).compactMap { result.atIndex($0)?.stringValue }
        guard result.numberOfItems == 7, values.count == 5,
              Array(values.prefix(4)) == [item.title, item.artist, item.album, item.genre] else {
            throw MusicPlaylistBridgeError.verificationFailed("The song details did not match the requested edit.")
        }
        let setterError = result.atIndex(7)?.int32Value ?? -1
        if setterError != 0 {
            musicPlaylistBridgeLogger.info("Music song artwork setter reported code \(setterError, privacy: .public); detail: \(values[4], privacy: .private)")
        }
        if let expectedArtwork {
            if !MusicTrackArtworkVerification.isConfirmed(expected: expectedArtwork,
                returned: result.atIndex(6)?.data, setterError: setterError) {
                warnings.append("Music could not update the cover for “\(item.title)”. Bard will retry it.")
            }
        } else if !values[4].isEmpty { warnings.append("Music could not update the cover for “\(item.title)”.") }
        return warnings
    }

    func removeMembership(at index: Int, playlistID: String, expectedTrackID: String) throws {
        _ = try call("removemembership", [.init(string: playlistID), .init(int32: Int32(index + 1)), .init(string: expectedTrackID)])
    }

    func setPlaylistArtwork(playlistID: String, fileURL: URL) throws {
        let expectedImage = try Data(contentsOf: fileURL)
        // Both ID and path remain event data; neither is interpolated into code.
        let result = try call("applyplaylistartwork", [.init(string: playlistID), .init(string: fileURL.path)])
        if result.numberOfItems == 4, result.atIndex(3)?.int32Value == 1 {
            let detail = result.atIndex(4)?.stringValue ?? ""
            musicPlaylistBridgeLogger.info("Music handler applyplaylistartwork reported code 1; verifying readback: \(detail, privacy: .private)")
        }
        guard result.numberOfItems == 4, result.atIndex(1)?.stringValue == playlistID,
              let imageData = result.atIndex(2)?.data, !imageData.isEmpty,
              MusicPlaylistArtworkComparison.matches(expected: expectedImage, returned: imageData) else {
            throw MusicPlaylistBridgeError.verificationFailed("Music did not confirm Mixtape's playlist cover.")
        }
    }

    func appendMembership(trackID: String, playlistID: String) throws {
        _ = try call("appendmembership", [.init(string: playlistID), .init(string: trackID)])
    }

    private func playlistValue(_ value: NSAppleEventDescriptor) throws -> MusicPlaylistBridgePlaylist {
        guard value.numberOfItems == 4, let id = value.atIndex(1)?.stringValue,
              let name = value.atIndex(2)?.stringValue, let ids = value.atIndex(3), let editable = value.atIndex(4) else {
            throw MusicPlaylistBridgeError.verificationFailed("Music returned an invalid playlist record.")
        }
        return MusicPlaylistBridgePlaylist(id: id, name: name, trackIDs: try strings(ids), isEditable: editable.booleanValue)
    }

    private func strings(_ descriptor: NSAppleEventDescriptor) throws -> [String] {
        guard descriptor.descriptorType == typeAEList else { throw MusicPlaylistBridgeError.verificationFailed("Music returned an invalid response.") }
        if descriptor.numberOfItems == 0 { return [] }
        return try (1...descriptor.numberOfItems).map { index in
            guard let value = descriptor.atIndex(index)?.stringValue else { throw MusicPlaylistBridgeError.verificationFailed("Music returned an invalid identifier.") }
            return value
        }
    }

    private func call(_ handler: String, _ arguments: [NSAppleEventDescriptor] = []) throws -> NSAppleEventDescriptor {
        try Task.checkCancellation()
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: handler), forKeyword: AEKeyword(keyASSubroutineName))
        let parameters = NSAppleEventDescriptor.list()
        for (index, argument) in arguments.enumerated() { parameters.insert(argument, at: index + 1) }
        event.setParam(parameters, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
            musicPlaylistBridgeLogger.error("Music handler \(handler, privacy: .public) failed with code \(code, privacy: .public); detail: \(error.description, privacy: .private)")
            throw Self.failure(error)
        }
        return result
    }

    private static func failure(_ error: NSDictionary?) -> MusicPlaylistBridgeError {
        let code = (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
        let detail = error?[NSAppleScript.errorMessage] as? String ?? "Try again after opening Music."
        switch code {
        case -1743: return .automationDenied
        case -600, -609, -10814: return .musicUnavailable
        case 9101: return .unsafePlaylist
        case 9102: return .playlistMissing
        case 9103: return .playlistConflict(detail)
        case 9104: return .verificationFailed("The playlist changed during sync. Try again.")
        default: return .scriptFailure(code, detail)
        }
    }

    // All variable input is passed as Apple-event descriptors. These handlers
    // deliberately omit activate/play and never delete from a library playlist.
    private static let source = #"""
    on libraryidentity()
        with timeout of 30 seconds
            tell application "/System/Applications/Music.app"
                set mainLibrary to library playlist 1
                return {(persistent ID of container of mainLibrary) as text, (persistent ID of mainLibrary) as text}
            end tell
        end timeout
    end libraryidentity

    on playlistrecord(targetPlaylist)
        tell application "/System/Applications/Music.app"
            set editableValue to false
            if class of targetPlaylist is user playlist then
                set editableValue to not (smart of targetPlaylist) and not (genius of targetPlaylist) and not (shared of targetPlaylist)
            end if
            set memberIDsValue to {}
            if (count of tracks of targetPlaylist) is greater than 0 then
                set memberIDsValue to persistent ID of every track of targetPlaylist
            end if
            return {(persistent ID of targetPlaylist) as text, (name of targetPlaylist) as text, memberIDsValue, editableValue}
        end tell
    end playlistrecord

    on matchingplaylists(targetName)
        with timeout of 30 seconds
            tell application "/System/Applications/Music.app" to set candidates to every user playlist whose name is targetName
            set playlistRecords to {}
            repeat with candidate in candidates
                set end of playlistRecords to my playlistrecord(contents of candidate)
            end repeat
            return playlistRecords
        end timeout
    end matchingplaylists

    on playlistwithid(targetID)
        with timeout of 30 seconds
            tell application "/System/Applications/Music.app"
                set candidates to every user playlist whose persistent ID is targetID
                if (count of candidates) is 0 then return {}
                if (count of candidates) is not 1 then error "Ambiguous playlist reference." number 9101
                set targetPlaylist to item 1 of candidates
            end tell
            return my playlistrecord(targetPlaylist)
        end timeout
    end playlistwithid

    on editableplaylist(targetID)
        tell application "/System/Applications/Music.app"
            set candidates to every user playlist whose persistent ID is targetID
            if (count of candidates) is not 1 then error "The linked playlist is missing." number 9102
            set targetPlaylist to item 1 of candidates
            if class of targetPlaylist is not user playlist then error "Only a normal user playlist can be managed." number 9101
            if smart of targetPlaylist or genius of targetPlaylist or shared of targetPlaylist then error "Only a private, normal playlist can be managed." number 9101
            if (persistent ID of targetPlaylist) is (persistent ID of library playlist 1) then error "The library cannot be managed as a playlist." number 9101
            return targetPlaylist
        end tell
    end editableplaylist

    on createemptyplaylist(targetName)
        with timeout of 60 seconds
            tell application "/System/Applications/Music.app"
                set candidates to every user playlist whose name is targetName
                if (count of candidates) is greater than 1 then error "Multiple playlists have this name. Rename the unrelated playlists before syncing." number 9103
                if (count of candidates) is 1 then
                    set targetPlaylist to item 1 of candidates
                    set targetID to persistent ID of targetPlaylist
                else
                    set targetPlaylist to make new user playlist with properties {name:targetName}
                    set targetID to persistent ID of targetPlaylist
                end if
            end tell
            set targetPlaylist to my editableplaylist(targetID)
            tell application "/System/Applications/Music.app"
                if (count of tracks of targetPlaylist) is not 0 then error "The existing playlist contains songs and was left unchanged." number 9103
            end tell
            return my playlistrecord(targetPlaylist)
        end timeout
    end createemptyplaylist

    on librarytrackids()
        with timeout of 60 seconds
            tell application "/System/Applications/Music.app"
                if (count of tracks of library playlist 1) is 0 then return {}
                return persistent ID of every track of library playlist 1
            end tell
        end timeout
    end librarytrackids

    on trackwithid(targetID)
        with timeout of 30 seconds
            tell application "/System/Applications/Music.app"
                set candidates to every track of library playlist 1 whose persistent ID is targetID
                if (count of candidates) is 0 then return {}
                if (count of candidates) is not 1 then error "Ambiguous track reference." number 9104
                set targetTrack to item 1 of candidates
                set filePath to ""
                try
                    set trackLocation to location of targetTrack
                    if trackLocation is not missing value then set filePath to POSIX path of trackLocation
                end try
                return {(persistent ID of targetTrack) as text, filePath}
            end tell
        end timeout
    end trackwithid

    on importaudiofile(filePath)
        with timeout of 120 seconds
            tell application "/System/Applications/Music.app"
                set addedTrack to add (POSIX file filePath) to library playlist 1
                if class of addedTrack is list then
                    if (count of addedTrack) is not 1 then error "Music did not return one imported track." number 9104
                    set addedTrack to item 1 of addedTrack
                end if
                return (persistent ID of addedTrack) as text
            end tell
        end timeout
    end importaudiofile

    on applytrackmetadata(targetID, titleValue, artistValue, albumValue, genreValue, artworkMode, artworkValue)
        with timeout of 60 seconds
            tell application "/System/Applications/Music.app"
                set candidates to every track of library playlist 1 whose persistent ID is targetID
                if (count of candidates) is not 1 then error "The imported track disappeared." number 9104
                set targetTrack to item 1 of candidates
                set name of targetTrack to titleValue
                set artist of targetTrack to artistValue
                set album of targetTrack to albumValue
                set genre of targetTrack to genreValue
                set artworkWarning to ""
                set artworkErrorNumber to 0
                set confirmedArtwork to missing value
                try
                    if artworkMode is 1 then
                        set data of artwork 1 of targetTrack to artworkValue
                    else if artworkMode is 2 then
                        if (count of artworks of targetTrack) is greater than 0 then delete every artwork of targetTrack
                    end if
                on error errorMessage number errorNumber
                    if errorNumber is in {-1743, -600, -609, -10814} then error errorMessage number errorNumber
                    set artworkErrorNumber to errorNumber
                    set artworkWarning to errorMessage
                end try
                if artworkMode is 1 then
                    -- Re-read the owned song, never another track or playlist.
                    set candidates to every track of library playlist 1 whose persistent ID is targetID
                    if (count of candidates) is not 1 then error "The imported track disappeared." number 9104
                    set targetTrack to item 1 of candidates
                    try
                        set confirmedArtwork to raw data of artwork 1 of targetTrack
                    on error errorMessage number errorNumber
                        if errorNumber is in {-1743, -600, -609, -10814} then error errorMessage number errorNumber
                        try
                            set confirmedArtwork to data of artwork 1 of targetTrack
                        on error errorMessage number errorNumber
                            if errorNumber is in {-1743, -600, -609, -10814} then error errorMessage number errorNumber
                            set artworkWarning to errorMessage
                        end try
                    end try
                end if
                return {(name of targetTrack) as text, (artist of targetTrack) as text, (album of targetTrack) as text, (genre of targetTrack) as text, artworkWarning, confirmedArtwork, artworkErrorNumber}
            end tell
        end timeout
    end applytrackmetadata

    on applyplaylistartwork(targetID, artworkPath)
        with timeout of 30 seconds
            set targetPlaylist to my editableplaylist(targetID)
            set artworkValue to read (POSIX file artworkPath) as «class PICT»
            set setterErrorNumber to 0
            set setterErrorMessage to ""
            tell application "/System/Applications/Music.app"
                -- Artwork is scoped to the owned playlist itself. Never write
                -- artwork of its tracks or of the library as a fallback.
                try
                    set data of artwork 1 of targetPlaylist to artworkValue
                on error errorMessage number errorNumber
                    -- Some Music releases apply the image but report error 1.
                    -- Swift must still verify the returned image before saving
                    -- a receipt. All other setter errors remain failures.
                    if errorNumber is not 1 then error errorMessage number errorNumber
                    set setterErrorNumber to errorNumber
                    set setterErrorMessage to errorMessage
                end try
            end tell
            set targetPlaylist to my editableplaylist(targetID)
            tell application "/System/Applications/Music.app"
                -- Playlist artwork enumeration can differ from indexed data
                -- access. Verify the image itself, never a fabricated count.
                try
                    set confirmedArtwork to raw data of artwork 1 of targetPlaylist
                on error errorMessage number errorNumber
                    if errorNumber is in {-1743, -600, -609, -10814} then error errorMessage number errorNumber
                    set confirmedArtwork to data of artwork 1 of targetPlaylist
                end try
                return {(persistent ID of targetPlaylist) as text, confirmedArtwork, setterErrorNumber, setterErrorMessage}
            end tell
        end timeout
    end applyplaylistartwork

    on removemembership(targetID, memberIndex, expectedID)
        with timeout of 60 seconds
            set targetPlaylist to my editableplaylist(targetID)
            tell application "/System/Applications/Music.app"
                if memberIndex is less than 1 or memberIndex is greater than (count of tracks of targetPlaylist) then error "The playlist changed during sync." number 9104
                if (persistent ID of track memberIndex of targetPlaylist) is not expectedID then error "The playlist changed during sync." number 9104
                -- This exact scoped object is a membership in the managed user
                -- playlist. It is never a track of the library playlist.
                delete track memberIndex of targetPlaylist
            end tell
            return true
        end timeout
    end removemembership

    on appendmembership(targetID, trackID)
        with timeout of 60 seconds
            set targetPlaylist to my editableplaylist(targetID)
            tell application "/System/Applications/Music.app"
                set candidates to every track of library playlist 1 whose persistent ID is trackID
                if (count of candidates) is not 1 then error "The imported track disappeared." number 9104
                if (count of (every track of targetPlaylist whose persistent ID is trackID)) is not 0 then error "The playlist changed during sync." number 9104
                duplicate (item 1 of candidates) to targetPlaylist
            end tell
            return true
        end timeout
    end appendmembership
    """#
}
