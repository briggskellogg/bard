import Foundation
import AVFoundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import WispCore

struct AudioImportBatch: Sendable {
    var tracks: [Track] = []
    var duplicateIDs: [UUID] = []
    var repairedIDs: [UUID] = []
    var failures: [String] = []
    var createdFiles: [URL] = []
    var reviewNotes: [UUID: [String]] = [:]
    var needsReview = false
}

enum AudioImporter {
    static let extensions: Set<String> = ["mp3", "m4a", "aac", "wav", "wave", "aif", "aiff", "aifc", "caf", "flac", "ogg", "opus", "mp4"]

    /// Called from a detached task. Only progress messages cross back to the UI actor.
    static func prepare(urls: [URL], existing: [String: Track], directory: URL,
                        progress: @escaping @Sendable (String) -> Void) async -> AudioImportBatch {
        let manager = FileManager.default
        var result = AudioImportBatch()
        let scopes = urls.filter { $0.startAccessingSecurityScopedResource() }
        defer { scopes.forEach { $0.stopAccessingSecurityScopedResource() } }
        let files = collectFiles(urls, failures: &result.failures)
        let media = directory.appendingPathComponent("Media", isDirectory: true)
        let artwork = directory.appendingPathComponent("Artwork", isDirectory: true)
        var known = existing

        for (index, source) in files.enumerated() {
            if Task.isCancelled { result.failures.append("Import stopped before all files were copied."); break }
            progress("\(index + 1) of \(files.count) · \(source.lastPathComponent)")
            let id = UUID()
            let temporary = media.appendingPathComponent(".import-\(id.uuidString).\(source.pathExtension.lowercased())")
            var created: [URL] = []
            do {
                let (fingerprint, byteCount) = try copyAndHash(source, to: temporary)
                if let duplicate = known[fingerprint] {
                    let owned = media.appendingPathComponent(duplicate.fileName)
                    if !manager.fileExists(atPath: owned.path) {
                        // Identical bytes can restore a missing copy without losing its edited metadata.
                        try manager.moveItem(at: temporary, to: owned)
                        result.createdFiles.append(owned)
                        result.repairedIDs.append(duplicate.id)
                    } else {
                        try manager.removeItem(at: temporary)
                    }
                    if !result.duplicateIDs.contains(duplicate.id) { result.duplicateIDs.append(duplicate.id) }
                    continue
                }
                // Check with the same decoder used for playback, before adding a library record.
                let probe = try AVAudioPlayer(contentsOf: temporary)
                let duration = probe.duration
                guard duration.isFinite, duration > 0 else { throw ImportError.unreadable }
                let metadata = await readMetadata(temporary)
                let fileName = "\(id.uuidString).\(source.pathExtension.lowercased())"
                let destination = media.appendingPathComponent(fileName)
                let artworkData = metadata.artwork ?? sidecarArtwork(beside: source)
                let preparedArtwork = artworkData.flatMap(normalizedArtwork)
                try Task.checkCancellation()
                try manager.moveItem(at: temporary, to: destination)
                created.append(destination)
                var artworkName: String?
                if let png = preparedArtwork {
                    let name = "\(UUID().uuidString).png"
                    let url = artwork.appendingPathComponent(name)
                    try png.write(to: url, options: .atomic)
                    created.append(url)
                    artworkName = name
                }
                let proposal = ImportSuggestion.propose(filename: source.lastPathComponent,
                    title: metadata.title, artist: metadata.artist, album: metadata.album, genre: metadata.genre)
                let track = Track(id: id, title: proposal.title,
                                  artist: proposal.artist, album: proposal.album,
                                  fileName: fileName, fingerprint: fingerprint,
                                  artworkFileName: artworkName, duration: duration, byteCount: byteCount,
                                  origin: proposal.origin, remix: proposal.remix,
                                  originalFileName: source.lastPathComponent,
                                  originMediaKind: proposal.originMediaKind, genre: proposal.genre)
                result.tracks.append(track)
                result.reviewNotes[id] = proposal.notes
                result.needsReview = result.needsReview || proposal.needsReview
                result.createdFiles.append(contentsOf: created)
                known[fingerprint] = track
            } catch {
                try? manager.removeItem(at: temporary)
                created.forEach { try? manager.removeItem(at: $0) }
                result.failures.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result
    }

    private static func collectFiles(_ roots: [URL], failures: inout [String]) -> [URL] {
        let manager = FileManager.default
        var found: [URL] = []
        var seen = Set<String>()
        for root in roots {
            guard root.isFileURL else { failures.append("Only local audio files can be imported."); continue }
            do {
                let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                if values.isDirectory == true {
                    guard let iterator = manager.enumerator(at: root,
                        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                        failures.append("\(root.lastPathComponent): This folder could not be opened.")
                        continue
                    }
                    for case let file as URL in iterator {
                        let details = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                        guard details?.isRegularFile == true, details?.isSymbolicLink != true,
                              extensions.contains(file.pathExtension.lowercased()) else { continue }
                        if seen.insert(file.standardizedFileURL.path).inserted { found.append(file) }
                    }
                } else if values.isRegularFile == true, extensions.contains(root.pathExtension.lowercased()) {
                    if seen.insert(root.standardizedFileURL.path).inserted { found.append(root) }
                } else {
                    failures.append("\(root.lastPathComponent): Choose an audio file or a folder of audio files.")
                }
            } catch { failures.append("\(root.lastPathComponent): \(error.localizedDescription)") }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static func copyAndHash(_ source: URL, to destination: URL) throws -> (String, Int64) {
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw ImportError.writeFailed }
        let writer = try FileHandle(forWritingTo: destination)
        defer { try? writer.close() }
        var hasher = SHA256()
        var count: Int64 = 0
        while let data = try reader.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            try writer.write(contentsOf: data)
            hasher.update(data: data)
            count += Int64(data.count)
        }
        try writer.synchronize()
        guard count > 0 else { throw ImportError.empty }
        let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return (hash, count)
    }

    private struct AudioMetadata {
        var title: String?
        var artist: String?
        var album: String?
        var genre: String?
        var artwork: Data?
    }

    private static func readMetadata(_ url: URL) async -> AudioMetadata {
        var result = AudioMetadata()
        let asset = AVURLAsset(url: url)
        let items = (try? await asset.load(.commonMetadata)) ?? []
        for item in items {
            switch item.commonKey {
            case .commonKeyTitle:
                if result.title == nil { result.title = try? await item.load(.stringValue) }
            case .commonKeyArtist:
                if result.artist == nil { result.artist = try? await item.load(.stringValue) }
            case .commonKeyAlbumName:
                if result.album == nil { result.album = try? await item.load(.stringValue) }
            case .commonKeyArtwork:
                if result.artwork == nil, let data = try? await item.load(.dataValue), data.count <= 20 * 1_048_576 {
                    result.artwork = data
                }
            default: break
            }
        }
        // Genre is format-specific rather than a common metadata key. Read the
        // explicit tag, without guessing a genre from the filename or artist.
        let genreIdentifiers: Set<AVMetadataIdentifier> = [
            .id3MetadataContentType,
            .iTunesMetadataUserGenre,
            .iTunesMetadataPredefinedGenre,
            .quickTimeMetadataGenre,
            .quickTimeUserDataGenre
        ]
        for format in (try? await asset.load(.availableMetadataFormats)) ?? [] {
            guard result.genre == nil, let metadata = try? await asset.loadMetadata(for: format) else { continue }
            for item in metadata where item.identifier.map(genreIdentifiers.contains) == true {
                if let value = try? await item.load(.stringValue), let genre = clean(value) {
                    result.genre = genre
                    break
                }
            }
        }
        return result
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : String(clean.prefix(500))
    }

    /// Optional artwork must not enumerate a File Provider directory: asking for
    /// sibling resource values can wait indefinitely for cloud-only items.
    /// This is a lexical path check, so deciding to skip it never contacts the provider.
    static func canInspectSidecarArtwork(beside source: URL) -> Bool {
        guard source.isFileURL else { return false }
        let components = source.pathComponents.map { $0.lowercased() }
        return !zip(components, components.dropFirst()).contains { parent, child in
            parent == "library" && (child == "cloudstorage" || child == "mobile documents")
        }
    }

    private static func sidecarArtwork(beside source: URL) -> Data? {
        guard canInspectSidecarArtwork(beside: source) else { return nil }
        let folder = source.deletingLastPathComponent()
        guard let siblings = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        let images = siblings.filter { ["jpg", "jpeg", "png", "webp", "heic"].contains($0.pathExtension.lowercased()) }
        let preferred = ["cover", "folder", "front", "album"]
        let selected = preferred.lazy.compactMap { name in images.first { $0.deletingPathExtension().lastPathComponent.lowercased() == name } }.first
            ?? (images.count == 1 ? images[0] : nil)
        guard let selected, let attributes = try? selected.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              attributes.isRegularFile == true, (attributes.fileSize ?? Int.max) <= 20 * 1_048_576 else { return nil }
        return try? Data(contentsOf: selected)
    }

    /// Small PNGs preserve transparency and avoid keeping giant embedded images in the library.
    static func normalizedArtwork(_ data: Data) -> Data? {
        guard data.count <= 20 * 1_048_576,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 900,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    enum ImportError: LocalizedError {
        case unreadable, empty, writeFailed, invalidCover
        var errorDescription: String? {
            switch self {
            case .unreadable: return "macOS could not read playable audio from this file."
            case .empty: return "This file is empty."
            case .writeFailed: return "The file could not be copied into Bard."
            case .invalidCover: return "Choose a readable image smaller than 20 MB."
            }
        }
    }
}
