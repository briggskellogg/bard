import Foundation
import Combine
import AppKit
import Darwin
import WispCore

struct LibraryDownloadItem: Sendable {
    let track: Track
    let audioURL: URL
    let artworkURL: URL?
}

struct LibraryDownloadRequest: Sendable {
    enum Kind: Sendable, Equatable { case song, collection }
    let kind: Kind
    let title: String
    var description = ""
    let items: [LibraryDownloadItem]
    var coverURL: URL? = nil
    // Only validation supplies a directory. The app always uses Downloads/Wisp.
    var directory: URL? = nil
}

enum LibraryDownloadError: LocalizedError {
    case empty, unavailable(String), changed(String), archive, destination
    var errorDescription: String? {
        switch self {
        case .empty: return "There are no tracks to download."
        case .unavailable(let name): return "“\(name)” is unavailable. No download was saved."
        case .changed(let name): return "“\(name)” changed while it was being copied. Try downloading again."
        case .archive: return "The collection could not be packaged. No download was saved."
        case .destination: return "Bard could not create a new file in Downloads/Wisp."
        }
    }
}

/// Reads one file at a time in 256 KiB chunks. The final file is published by an
/// exclusive same-volume rename, so repeated or concurrent exports never replace
/// an existing download. All intermediate files live in a disposable directory.
enum LibraryDownloadExporter {
    static func downloadsDirectory() throws -> URL {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw LibraryDownloadError.destination
        }
        let directory = downloads.appendingPathComponent("Wisp", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func export(_ request: LibraryDownloadRequest,
                       progress: @Sendable (String) -> Void = { _ in }) throws -> URL {
        guard !request.items.isEmpty else { throw LibraryDownloadError.empty }
        guard request.kind != .song || request.items.count == 1 else { throw LibraryDownloadError.empty }
        try Task.checkCancellation()
        let manager = FileManager.default
        let directory = try request.directory ?? downloadsDirectory()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(".Wisp-download-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        if request.kind == .song, let item = request.items.first {
            progress("Saving \(item.track.displayTitle)…")
            let temporary = staging.appendingPathComponent("Audio")
            try copy(item.audioURL, to: temporary, label: item.track.displayTitle)
            try Task.checkCancellation()
            return try publish(temporary, in: directory, name: safeName(item.track.displayTitle),
                               extension: audioExtension(item.audioURL))
        }

        let collectionName = safeName(request.title)
        let collection = staging.appendingPathComponent(collectionName, isDirectory: true)
        let audioDirectory = collection.appendingPathComponent("Audio", isDirectory: true)
        try manager.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        var entries: [ExportedTrack] = []
        var playlist = ["#EXTM3U", "#PLAYLIST:\(singleLine(request.title))"]
        let digits = max(3, String(request.items.count).count)
        for (index, item) in request.items.enumerated() {
            try Task.checkCancellation()
            progress("Saving \(index + 1) of \(request.items.count)…")
            let number = String(repeating: "0", count: max(0, digits - String(index + 1).count)) + String(index + 1)
            let audioName = "\(number) - \(safeName(item.track.displayTitle)).\(audioExtension(item.audioURL))"
            let relativeAudio = "Audio/\(audioName)"
            try copy(item.audioURL, to: audioDirectory.appendingPathComponent(audioName), label: item.track.displayTitle)
            var relativeArtwork: String?
            if let artwork = item.artworkURL {
                let artworkDirectory = collection.appendingPathComponent("Artwork", isDirectory: true)
                try manager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
                let name = "\(number).\(audioExtension(artwork))"
                try copy(artwork, to: artworkDirectory.appendingPathComponent(name), label: "\(item.track.displayTitle) artwork")
                relativeArtwork = "Artwork/\(name)"
            }
            entries.append(ExportedTrack(order: index + 1, audioFile: relativeAudio,
                                         artworkFile: relativeArtwork, track: item.track))
            let artist = item.track.artist.isEmpty ? "" : "\(item.track.artist) — "
            playlist.append("#EXTINF:\(Int(item.track.duration.rounded())),\(singleLine(artist + item.track.displayTitle))")
            playlist.append(relativeAudio)
        }
        var coverName: String?
        if let cover = request.coverURL {
            let name = "Cover.\(audioExtension(cover))"
            try copy(cover, to: collection.appendingPathComponent(name), label: "Collection cover")
            coverName = name
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let metadata = ExportedCollection(title: request.title, description: request.description,
                                          coverFile: coverName, tracks: entries)
        try encoder.encode(metadata).write(to: collection.appendingPathComponent("Metadata.json"), options: .atomic)
        try (playlist.joined(separator: "\n") + "\n").write(to: collection.appendingPathComponent("Playlist.m3u8"), atomically: true, encoding: .utf8)
        let readme = "\(request.title)\n\n\(request.description)\n\nOpen Playlist.m3u8 after extracting this ZIP to play the tracks in their exported order. Audio files are unchanged originals. Metadata.json preserves Bard's titles, artists, origins, source links, genres, and Basic/Classic attribution. This is a collection of separate tracks; Make Mixtape in Bard creates cassette-ready audio sides.\n"
        try readme.write(to: collection.appendingPathComponent("Read Me.txt"), atomically: true, encoding: .utf8)
        try Task.checkCancellation()
        progress("Packaging collection…")
        let archive = staging.appendingPathComponent("Collection.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--keepParent", collection.path, archive.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationStatus == 0, manager.fileExists(atPath: archive.path) else {
            throw LibraryDownloadError.archive
        }
        return try publish(archive, in: directory, name: collectionName, extension: "zip")
    }

    static func safeName(_ value: String) -> String {
        let clean = value.unicodeScalars.map { scalar -> String in
            CharacterSet.controlCharacters.contains(scalar) || "/\\:".unicodeScalars.contains(scalar) ? " " : String(scalar)
        }.joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var result = ""
        for character in clean {
            guard result.utf8.count + String(character).utf8.count <= 120 else { break }
            result.append(character)
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return result.isEmpty ? "Music" : result
    }

    private static func audioExtension(_ url: URL) -> String {
        let suffix = url.pathExtension.lowercased()
        return !suffix.isEmpty && suffix.utf8.count <= 16 && suffix.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
            ? suffix : "audio"
    }

    private static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    private static func copy(_ source: URL, to destination: URL, label: String) throws {
        let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
            throw LibraryDownloadError.unavailable(label)
        }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var before = stat()
        guard fstat(input.fileDescriptor, &before) == 0,
              before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw LibraryDownloadError.unavailable(label) }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw LibraryDownloadError.destination }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var count = 0
        while true {
            try Task.checkCancellation()
            guard let data = try input.read(upToCount: 256 * 1024), !data.isEmpty else { break }
            try output.write(contentsOf: data)
            count += data.count
        }
        var after = stat()
        guard fstat(input.fileDescriptor, &after) == 0, Int64(count) == before.st_size,
              after.st_size == before.st_size,
              after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
              after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec else {
            throw LibraryDownloadError.changed(label)
        }
        try output.synchronize()
    }

    private static func publish(_ source: URL, in directory: URL, name: String, extension suffix: String) throws -> URL {
        for index in 1...10_000 {
            try Task.checkCancellation()
            let number = index == 1 ? "" : " (\(index))"
            let destination = directory.appendingPathComponent("\(name)\(number).\(suffix)")
            if renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 { return destination }
            let code = errno
            guard code == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        }
        throw LibraryDownloadError.destination
    }

    private struct ExportedCollection: Encodable {
        let formatVersion = 1
        let title: String
        let description: String
        let coverFile: String?
        let tracks: [ExportedTrack]
    }

    private struct ExportedTrack: Encodable {
        let order: Int
        let audioFile: String
        let artworkFile: String?
        let track: Track
    }
}

@MainActor
final class LibraryDownloadController: ObservableObject {
    static let shared = LibraryDownloadController()
    @Published private(set) var isWorking = false
    @Published private(set) var status: String?
    @Published private(set) var resultURL: URL?
    @Published private(set) var failed = false

    func start(_ request: LibraryDownloadRequest) {
        guard !isWorking else { return }
        isWorking = true
        failed = false
        resultURL = nil
        status = "Preparing download…"
        Task { [self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try LibraryDownloadExporter.export(request) { label in
                        Task { @MainActor in if self.isWorking { self.status = label } }
                    }
                }.value
                resultURL = result
                status = "Saved to Downloads/Wisp"
            } catch {
                failed = true
                status = error.localizedDescription
            }
            isWorking = false
        }
    }

    func dismiss() { guard !isWorking else { return }; status = nil; resultURL = nil }
    func reveal() { if let resultURL { NSWorkspace.shared.activateFileViewerSelecting([resultURL]) } }
}
