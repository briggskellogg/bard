import Foundation
import CryptoKit
import Darwin

public struct DriveLibraryFileStamp: Codable, Equatable, Sendable {
    public let byteCount: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let inode: UInt64
}

public struct DriveLibraryAsset: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case audio, archivedAudio, artwork }
    public let kind: Kind
    public let fileName: String
    public let relativePath: String
    public let byteCount: Int64
    public let sha256: String
    public let sourceStamp: DriveLibraryFileStamp
    public var destinationStamp: DriveLibraryFileStamp?
}

public struct DriveLibraryPlaylist: Codable, Equatable, Sendable {
    public let id: UUID
    public let relativePath: String
    public let sha256: String
}

/// A readable export, not the Mac's live database. Original managed filenames in
/// `document` map to the exported files through `assets`.
public struct DriveLibraryMirrorManifest: Codable, Equatable, Sendable {
    public let formatVersion: Int
    public let sourceLibraryID: UUID
    public let revision: Int64
    public let publishedAt: Date
    public let document: LibraryDocument
    public let assets: [DriveLibraryAsset]
    public let playlists: [DriveLibraryPlaylist]
}

public struct DriveLibraryMirrorResult: Sendable {
    public let manifest: DriveLibraryMirrorManifest
    public let copiedFileCount: Int
    public let reusedFileCount: Int
    public let copiedByteCount: Int64
    public let changed: Bool
    public var songCount: Int { manifest.document.tracks.count }
    public var publishedAt: Date { manifest.publishedAt }
}

public enum DriveLibraryMirrorError: LocalizedError, Equatable {
    case unsafePath, unownedDestination, differentLibrary, invalidManifest, missingAsset(String)
    case changedAsset(String), conflict(String), coordination(String), limit
    public var errorDescription: String? {
        switch self {
        case .unsafePath: return "Choose a separate folder for the drive copy. Linked files and folders are not supported."
        case .unownedDestination: return "This Bard folder already contains files that Bard did not create. Choose an empty folder or your existing Bard drive copy."
        case .differentLibrary: return "This folder belongs to a different Bard library. Choose a separate folder."
        case .invalidManifest: return "The saved drive copy's index could not be verified. Its existing files have been preserved."
        case .missingAsset(let name): return "“\(name)” is unavailable. Bard will retry the drive copy when it is available."
        case .changedAsset(let name): return "“\(name)” changed while being copied. Bard will try again."
        case .conflict(let name): return "“\(name)” was changed outside Bard. The existing file was preserved; choose another copy folder to continue."
        case .coordination(let message): return "The drive folder is unavailable: \(message)"
        case .limit: return "The drive copy has more metadata than this version of Bard supports."
        }
    }
}

/// Blocking work for a serial background queue. Wisp owns metadata updates, but
/// never deletes drive files. Audio and art are immutable; previous versions and
/// removed songs stay available. Proton's app is responsible for cloud upload.
public enum DriveLibraryMirror {
    public static let manifestName = "Library.json"
    public static let ownershipName = ".wisp-drive.json"
    private static let manager = FileManager.default
    private static let lock = NSRecursiveLock()
    private static let maximumJSONBytes = 32 * 1024 * 1024
    private struct Owner: Codable { let formatVersion: Int; let sourceLibraryID: UUID }
    private struct Source {
        let kind: DriveLibraryAsset.Kind
        let name: String
        let url: URL
        let proposedPath: String
        let hash: String
        let bytes: Int64
        let stamp: DriveLibraryFileStamp
    }

    @discardableResult
    public static func publish(document: LibraryDocument, libraryDirectory: URL, destination: URL,
                               sourceLibraryID: UUID) throws -> DriveLibraryMirrorResult {
        try Task.checkCancellation()
        try document.validate()
        let library = try directory(libraryDirectory, create: false)
        // Resolve only caller-owned parent aliases such as /tmp. A destination
        // leaf link is rejected before resolving it, as are managed subfolders.
        guard destination.isFileURL else { throw DriveLibraryMirrorError.unsafePath }
        let parent = try directory(destination.deletingLastPathComponent(), create: false)
        let proposed = parent.appendingPathComponent(destination.lastPathComponent, isDirectory: true)
        guard !overlap(library, proposed) else { throw DriveLibraryMirrorError.unsafePath }
        let folder = try directory(proposed, create: true)
        return try coordinate(reading: library, writing: folder) { library, folder in
            guard !overlap(library, folder) else { throw DriveLibraryMirrorError.unsafePath }
            let ownerURL = folder.appendingPathComponent(ownershipName)
            let manifestURL = folder.appendingPathComponent(manifestName)
            let owned = exists(ownerURL)
            if owned {
                let owner: Owner = try decode(Owner.self, from: ownerURL)
                guard owner.formatVersion == 1 else { throw DriveLibraryMirrorError.invalidManifest }
                guard owner.sourceLibraryID == sourceLibraryID else { throw DriveLibraryMirrorError.differentLibrary }
            } else {
                let names = Set(try manager.contentsOfDirectory(atPath: folder.path))
                guard names.isSubset(of: [".DS_Store"]) else { throw DriveLibraryMirrorError.unownedDestination }
            }
            let previous: DriveLibraryMirrorManifest?
            if exists(manifestURL) {
                guard owned else { throw DriveLibraryMirrorError.unownedDestination }
                let saved = try decode(DriveLibraryMirrorManifest.self, from: manifestURL)
                try validate(saved)
                guard saved.sourceLibraryID == sourceLibraryID else { throw DriveLibraryMirrorError.differentLibrary }
                previous = saved
            } else { previous = nil }

            // Preflight every source before admitting any files into the drive.
            var exportedDocument = document
            exportedDocument.phoneFavoriteReceipts = [:]
            let oldAssets = Dictionary(uniqueKeysWithValues: (previous?.assets ?? []).map { (assetKey($0.kind, $0.fileName), $0) })
            let sources = try sources(document: exportedDocument, library: library, previous: oldAssets)
            var assets = sources.map { source -> DriveLibraryAsset in
                // Retain the first readable filename through title/artist edits,
                // avoiding large duplicate uploads for metadata-only changes.
                let old = oldAssets[assetKey(source.kind, source.name)]
                let path = old?.sha256 == source.hash ? old!.relativePath : source.proposedPath
                return DriveLibraryAsset(kind: source.kind, fileName: source.name, relativePath: path,
                                         byteCount: source.bytes, sha256: source.hash, sourceStamp: source.stamp,
                                         destinationStamp: old?.sha256 == source.hash ? old?.destinationStamp : nil)
            }
            guard Set(assets.map(\.relativePath)).count == assets.count else { throw DriveLibraryMirrorError.invalidManifest }
            let byName = Dictionary(uniqueKeysWithValues: assets.filter { $0.kind == .audio }.map { ($0.fileName, $0) })
            let tracks = Dictionary(uniqueKeysWithValues: exportedDocument.tracks.map { ($0.id, $0) })
            let oldPlaylists = Dictionary(uniqueKeysWithValues: (previous?.playlists ?? []).map { ($0.id, $0) })
            var playlists: [DriveLibraryPlaylist] = []
            var playlistContents: [String: Data] = [:]
            for playlist in exportedDocument.playlists {
                var lines = ["#EXTM3U", "#PLAYLIST:\(singleLine(playlist.name))"]
                for id in playlist.trackIDs {
                    guard let track = tracks[id], let asset = byName[track.fileName] else { throw DriveLibraryMirrorError.invalidManifest }
                    let label = track.artist.isEmpty ? track.title : "\(track.artist) — \(track.title)"
                    lines.append("#EXTINF:\(Int(min(track.duration.rounded(), Double(Int.max / 2)))),\(singleLine(label))")
                    lines.append("../" + asset.relativePath)
                }
                let data = Data((lines.joined(separator: "\n") + "\n").utf8)
                let digest = hash(data)
                let path = oldPlaylists[playlist.id]?.sha256 == digest ? oldPlaylists[playlist.id]!.relativePath : "Playlists/\(safeName(playlist.name)) [\(playlist.id.uuidString.prefix(8).lowercased())-\(digest.prefix(10))].m3u8"
                playlists.append(DriveLibraryPlaylist(id: playlist.id, relativePath: path, sha256: digest))
                playlistContents[path] = data
            }
            guard Set(playlists.map(\.relativePath)).count == playlists.count else { throw DriveLibraryMirrorError.invalidManifest }
            // Refuse conflicts before writing any new file. An interrupted first
            // copy can be retried because its ownership marker is durable.
            for asset in assets {
                let target = try child(asset.relativePath, in: folder, createParents: false)
                if exists(target) {
                    let current = try stamp(target)
                    if current != asset.destinationStamp { try verify(target, bytes: asset.byteCount, hash: asset.sha256) }
                }
            }
            for playlist in playlists {
                let target = try child(playlist.relativePath, in: folder, createParents: false)
                if exists(target) {
                    let actual = try measure(target).hash
                    guard actual == playlist.sha256 else {
                        throw DriveLibraryMirrorError.conflict(target.lastPathComponent)
                    }
                }
            }
            if !owned { try encode(Owner(formatVersion: 1, sourceLibraryID: sourceLibraryID)).write(to: ownerURL, options: .atomic) }
            var copied = 0, reused = 0
            var copiedBytes: Int64 = 0
            for (source, asset) in zip(sources, assets) {
                try Task.checkCancellation()
                let target = try child(asset.relativePath, in: folder, createParents: true)
                if exists(target) { reused += 1; continue }
                try copy(source.url, to: target, bytes: asset.byteCount, hash: asset.sha256)
                copied += 1; copiedBytes += asset.byteCount
            }
            for index in assets.indices {
                assets[index].destinationStamp = try stamp(child(assets[index].relativePath, in: folder, createParents: false))
            }
            for playlist in playlists {
                let target = try child(playlist.relativePath, in: folder, createParents: true)
                guard let data = playlistContents[playlist.relativePath] else { throw DriveLibraryMirrorError.invalidManifest }
                if exists(target), try measure(target).hash == playlist.sha256 { continue }
                // Immutable playlist revisions keep the previous manifest valid
                // even if a later write fails or the app closes during copying.
                let temporary = target.deletingLastPathComponent().appendingPathComponent(".wisp-playlist-\(UUID().uuidString)")
                defer { try? manager.removeItem(at: temporary) }
                try data.write(to: temporary, options: .atomic)
                try manager.moveItem(at: temporary, to: target)
            }
            let readme = folder.appendingPathComponent("Read Me.txt")
            if !exists(readme) {
                try Data(readMe.utf8).write(to: readme, options: .withoutOverwriting)
            }
            if let previous, try encode(previous.document) == encode(exportedDocument), previous.assets == assets, previous.playlists == playlists {
                return DriveLibraryMirrorResult(manifest: previous, copiedFileCount: copied, reusedFileCount: reused,
                                                copiedByteCount: copiedBytes, changed: false)
            }
            guard (previous?.revision ?? 0) < Int64.max else { throw DriveLibraryMirrorError.limit }
            let revision = (previous?.revision ?? 0) + 1
            let manifest = DriveLibraryMirrorManifest(formatVersion: 1, sourceLibraryID: sourceLibraryID,
                revision: revision, publishedAt: Date(), document: exportedDocument, assets: assets, playlists: playlists)
            try validate(manifest)
            let data = try encode(manifest)
            guard data.count <= maximumJSONBytes else { throw DriveLibraryMirrorError.limit }
            try Task.checkCancellation()
            // All current audio, art and playlists are durable before this commit.
            try data.write(to: manifestURL, options: .atomic)
            return DriveLibraryMirrorResult(manifest: manifest, copiedFileCount: copied, reusedFileCount: reused,
                                            copiedByteCount: copiedBytes, changed: true)
        }
    }

    /// Read-only ownership check for a folder chooser; absence returns false.
    public static func belongsToLibrary(_ folder: URL, sourceLibraryID: UUID) throws -> Bool {
        let folder = try directory(folder, create: false)
        let file = folder.appendingPathComponent(ownershipName)
        guard exists(file) else { return false }
        let owner = try decode(Owner.self, from: file)
        return owner.formatVersion == 1 && owner.sourceLibraryID == sourceLibraryID
    }

    private static func sources(document: LibraryDocument, library: URL, previous: [String: DriveLibraryAsset]) throws -> [Source] {
        var result: [Source] = []
        let media = document.tracks.isEmpty ? nil : try directory(library.appendingPathComponent("Media"), create: false)
        var artNames = Set(document.playlists.compactMap(\.coverFileName))
        for track in document.tracks {
            guard let media else { throw DriveLibraryMirrorError.invalidManifest }
            let artist = safeName(track.artist.isEmpty ? "Unknown Artist" : track.artist)
            let title = safeName(track.title)
            let source = media.appendingPathComponent(track.fileName)
            let measured = try sourceMeasure(source, previous: previous[assetKey(.audio, track.fileName)], expectedHash: track.fingerprint)
            guard measured.hash == track.fingerprint, measured.bytes == track.byteCount else { throw DriveLibraryMirrorError.changedAsset(track.fileName) }
            let suffix = "[\(track.id.uuidString.prefix(8).lowercased())-\(measured.hash.prefix(10))].\(safeExtension(track.fileName))"
            result.append(Source(kind: .audio, name: track.fileName, url: source,
                proposedPath: "Music/\(artist)/\(title) \(suffix)", hash: measured.hash, bytes: measured.bytes, stamp: measured.stamp))
            for version in track.audioVersions {
                let old = media.appendingPathComponent(version.fileName)
                let measured = try sourceMeasure(old, previous: previous[assetKey(.archivedAudio, version.fileName)], expectedHash: version.fingerprint)
                guard measured.hash == version.fingerprint, measured.bytes == version.byteCount else { throw DriveLibraryMirrorError.changedAsset(version.fileName) }
                result.append(Source(kind: .archivedAudio, name: version.fileName, url: old,
                    proposedPath: "Previous Versions/\(artist)/\(title) [\(version.id.uuidString.prefix(8).lowercased())-\(measured.hash.prefix(10))].\(safeExtension(version.fileName))",
                    hash: measured.hash, bytes: measured.bytes, stamp: measured.stamp))
            }
            if let name = track.artworkFileName { artNames.insert(name) }
        }
        if !artNames.isEmpty {
            let art = try directory(library.appendingPathComponent("Artwork"), create: false)
            for name in artNames.sorted() {
                let source = art.appendingPathComponent(name)
                let measured = try sourceMeasure(source, previous: previous[assetKey(.artwork, name)], expectedHash: nil)
                result.append(Source(kind: .artwork, name: name, url: source,
                    proposedPath: "Artwork/\(safeName(URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent)) [\(measured.hash.prefix(10))].\(safeExtension(name))",
                    hash: measured.hash, bytes: measured.bytes, stamp: measured.stamp))
            }
        }
        guard Set(result.map { assetKey($0.kind, $0.name) }).count == result.count else { throw DriveLibraryMirrorError.invalidManifest }
        return result
    }

    private static func validate(_ manifest: DriveLibraryMirrorManifest) throws {
        guard manifest.formatVersion == 1, manifest.revision > 0,
              manifest.publishedAt.timeIntervalSince1970.isFinite,
              Set(manifest.assets.map { assetKey($0.kind, $0.fileName) }).count == manifest.assets.count,
              Set(manifest.assets.map(\.relativePath)).count == manifest.assets.count,
              Set(manifest.playlists.map(\.id)).count == manifest.playlists.count,
              Set(manifest.playlists.map(\.relativePath)).count == manifest.playlists.count else { throw DriveLibraryMirrorError.invalidManifest }
        try manifest.document.validate()
        guard manifest.document.phoneFavoriteReceipts.isEmpty else { throw DriveLibraryMirrorError.invalidManifest }
        var expected: [String: DriveLibraryAsset.Kind] = [:]
        for track in manifest.document.tracks {
            expected[assetKey(.audio, track.fileName)] = .audio
            for version in track.audioVersions { expected[assetKey(.archivedAudio, version.fileName)] = .archivedAudio }
            if let art = track.artworkFileName { expected[assetKey(.artwork, art)] = .artwork }
        }
        for playlist in manifest.document.playlists { if let art = playlist.coverFileName { expected[assetKey(.artwork, art)] = .artwork } }
        guard expected.count == manifest.assets.count else { throw DriveLibraryMirrorError.invalidManifest }
        for asset in manifest.assets {
            guard expected[assetKey(asset.kind, asset.fileName)] == asset.kind, asset.byteCount > 0,
                  asset.sourceStamp.byteCount == asset.byteCount, asset.destinationStamp?.byteCount == asset.byteCount,
                  validHash(asset.sha256), validRelative(asset.relativePath),
                  ["Music", "Previous Versions", "Artwork"].contains(asset.relativePath.components(separatedBy: "/")[0]) else { throw DriveLibraryMirrorError.invalidManifest }
        }
        guard Set(manifest.document.playlists.map(\.id)) == Set(manifest.playlists.map(\.id)) else { throw DriveLibraryMirrorError.invalidManifest }
        for playlist in manifest.playlists {
            guard validRelative(playlist.relativePath), playlist.relativePath.hasPrefix("Playlists/"),
                  playlist.relativePath.hasSuffix(".m3u8"), validHash(playlist.sha256) else { throw DriveLibraryMirrorError.invalidManifest }
        }
    }

    private static func assetKey(_ kind: DriveLibraryAsset.Kind, _ name: String) -> String { (kind == .artwork ? "art:" : "audio:") + name }
    private static func sourceMeasure(_ url: URL, previous: DriveLibraryAsset?, expectedHash: String?) throws -> (bytes: Int64, hash: String, stamp: DriveLibraryFileStamp) {
        let current = try stamp(url)
        if let previous, previous.sourceStamp == current, expectedHash == nil || expectedHash == previous.sha256 {
            return (current.byteCount, previous.sha256, current)
        }
        let measured = try measure(url)
        let after = try stamp(url)
        guard current == after else { throw DriveLibraryMirrorError.changedAsset(url.lastPathComponent) }
        return (measured.bytes, measured.hash, after)
    }
    private static func stamp(_ url: URL) throws -> DriveLibraryFileStamp {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw DriveLibraryMirrorError.missingAsset(url.lastPathComponent) }
        guard value.st_mode & S_IFMT == S_IFREG else { throw DriveLibraryMirrorError.unsafePath }
        return DriveLibraryFileStamp(byteCount: value.st_size, modifiedSeconds: Int64(value.st_mtimespec.tv_sec),
            modifiedNanoseconds: Int64(value.st_mtimespec.tv_nsec), inode: value.st_ino)
    }

    private static func validHash(_ value: String) -> Bool { value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) } }
    private static func validRelative(_ value: String) -> Bool {
        let parts = value.components(separatedBy: "/")
        return parts.count >= 2 && parts.count <= 3 && parts.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.contains(":") && $0.utf8.count <= 240 &&
            $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
        }
    }
    private static func child(_ relative: String, in root: URL, createParents: Bool) throws -> URL {
        guard validRelative(relative) else { throw DriveLibraryMirrorError.unsafePath }
        let parts = relative.components(separatedBy: "/")
        var parent = root
        for part in parts.dropLast() {
            let next = parent.appendingPathComponent(part, isDirectory: true)
            if exists(next) || createParents { parent = try directory(next, create: createParents) }
            else { parent = next }
            guard parent.path.hasPrefix(root.path + "/") else { throw DriveLibraryMirrorError.unsafePath }
        }
        let result = parent.appendingPathComponent(parts.last!)
        if exists(result), try regularSize(result) < 0 { throw DriveLibraryMirrorError.unsafePath }
        return result
    }
    private static func exists(_ url: URL) -> Bool { (try? manager.attributesOfItem(atPath: url.path)) != nil }
    private static func overlap(_ a: URL, _ b: URL) -> Bool { a.path == b.path || a.path.hasPrefix(b.path + "/") || b.path.hasPrefix(a.path + "/") }
    private static func directory(_ url: URL, create: Bool) throws -> URL {
        guard url.isFileURL, url.lastPathComponent != ".", url.lastPathComponent != ".." else { throw DriveLibraryMirrorError.unsafePath }
        if !exists(url), create { try manager.createDirectory(at: url, withIntermediateDirectories: false) }
        guard let attributes = try? manager.attributesOfItem(atPath: url.path) else { throw DriveLibraryMirrorError.missingAsset(url.lastPathComponent) }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw DriveLibraryMirrorError.unsafePath }
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }
    private static func regularSize(_ url: URL) throws -> Int64 {
        guard let attrs = try? manager.attributesOfItem(atPath: url.path) else { throw DriveLibraryMirrorError.missingAsset(url.lastPathComponent) }
        guard attrs[.type] as? FileAttributeType == .typeRegular, let size = attrs[.size] as? NSNumber else { throw DriveLibraryMirrorError.unsafePath }
        return size.int64Value
    }
    private static func measure(_ url: URL) throws -> (bytes: Int64, hash: String) {
        _ = try regularSize(url)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw DriveLibraryMirrorError.missingAsset(url.lastPathComponent) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat(); guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG else { throw DriveLibraryMirrorError.unsafePath }
        var digest = SHA256(), count: Int64 = 0
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            try Task.checkCancellation(); count += Int64(chunk.count); digest.update(data: chunk)
        }
        var after = stat()
        guard fstat(fd, &after) == 0, count == before.st_size, after.st_size == before.st_size,
              after.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec, after.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec else { throw DriveLibraryMirrorError.changedAsset(url.lastPathComponent) }
        guard count > 0 else { throw DriveLibraryMirrorError.changedAsset(url.lastPathComponent) }
        return (count, digest.finalize().map { String(format: "%02x", $0) }.joined())
    }
    private static func verify(_ url: URL, bytes: Int64, hash: String) throws {
        let actual = try measure(url)
        guard actual.bytes == bytes, actual.hash == hash else { throw DriveLibraryMirrorError.conflict(url.lastPathComponent) }
    }
    private static func copy(_ source: URL, to destination: URL, bytes: Int64, hash: String) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".wisp-copy-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: temporary) }
        try manager.copyItem(at: source, to: temporary)
        try verify(temporary, bytes: bytes, hash: hash)
        try Task.checkCancellation()
        // moveItem refuses an existing final name, including provider/user races.
        try manager.moveItem(at: temporary, to: destination)
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }
    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let size = try regularSize(url)
        guard size > 0, size <= maximumJSONBytes else { throw DriveLibraryMirrorError.invalidManifest }
        let data = try Data(contentsOf: url)
        guard data.count == size else { throw DriveLibraryMirrorError.invalidManifest }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        do { return try decoder.decode(type, from: data) }
        catch { throw DriveLibraryMirrorError.invalidManifest }
    }
    private static func coordinate<T>(reading: URL, writing: URL, body: (URL, URL) throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        var error: NSError?, result: Result<T, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: reading, options: .withoutChanges,
            writingItemAt: writing, options: .forMerging, error: &error) { source, destination in
                result = Result { try body(source, destination) }
            }
        if let result { return try result.get() }
        throw DriveLibraryMirrorError.coordination(error?.localizedDescription ?? "File coordination did not complete.")
    }
    private static func safeName(_ text: String) -> String {
        let cleaned = text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) || "/\\:".unicodeScalars.contains($0) ? " " : String($0) }
            .joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var result = ""
        for character in cleaned {
            guard result.utf8.count + String(character).utf8.count <= 100 else { break }
            result.append(character)
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return result.isEmpty ? "Untitled" : result
    }
    private static func safeExtension(_ name: String) -> String {
        let value = URL(fileURLWithPath: name).pathExtension.lowercased()
        return !value.isEmpty && value.count <= 16 && value.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains) ? value : "audio"
    }
    private static func singleLine(_ value: String) -> String { value.split(whereSeparator: \.isNewline).joined(separator: " ") }
    private static let readMe = """
    Wisp

    This is an automatic copy of your Wisp music library. Open Music to find your original audio files, organized by artist. Playlists contains playable M3U playlists. Artwork contains the original covers. Previous Versions contains archived audio first copied after its replacement.

    Library.json records the current songs, titles, artists, origins, sources, favorites, playlists, and exact locations of your files. It identifies the current playlist files. Earlier playlist revisions are retained when their songs or order change; retained files can stay in their original folders after a replacement or restore. Audio and artwork are copied without conversion. Their readable filenames stay stable through metadata edits to avoid unnecessary uploads.

    Wisp updates this copy while it is open on your Mac. Proton Drive handles uploading it to your account. A completed local copy does not confirm that Proton's upload has finished.

    Wisp never deletes files from this folder. Removed songs, earlier versions, and files you add yourself are retained. Please manage music in Wisp; changing managed audio or playlist files here pauses copying rather than overwriting your changes.
    """
}
