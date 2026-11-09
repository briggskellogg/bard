import Foundation
import CryptoKit

/// The Mac publishes a one-way mirror. Original audio versions and all Mac-only
/// receipts/preferences stay on the Mac; the phone receives current songs only.
public struct PhoneLibraryAsset: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case audio, artwork }
    public var kind: Kind
    public var fileName: String
    public var relativePath: String
    public var byteCount: Int64
    public var sha256: String

    public init(kind: Kind, fileName: String, relativePath: String, byteCount: Int64, sha256: String) {
        self.kind = kind; self.fileName = fileName; self.relativePath = relativePath
        self.byteCount = byteCount; self.sha256 = sha256
    }
}

public struct PhoneLibraryManifest: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var sourceLibraryID: UUID
    public var revision: Int64
    public var publishedAt: Date
    public var document: LibraryDocument
    public var assets: [PhoneLibraryAsset]

    public init(formatVersion: Int = 1, sourceLibraryID: UUID, revision: Int64, publishedAt: Date,
                document: LibraryDocument, assets: [PhoneLibraryAsset]) {
        self.formatVersion = formatVersion; self.sourceLibraryID = sourceLibraryID
        self.revision = revision; self.publishedAt = publishedAt; self.document = document; self.assets = assets
    }
}

public struct PhoneLibrarySnapshot: Sendable {
    public let document: LibraryDocument
    public let mediaDirectory: URL
    public let artworkDirectory: URL
    public let sourceLibraryID: UUID
    public let revision: Int64
}

public enum PhoneLibrarySyncError: LocalizedError, Equatable {
    case unsupportedVersion, invalidManifest, unsafePath, missingAsset(String), changedAsset(String)
    case differentLibrary, olderRevision, conflictingRevision, invalidCache, unownedDestination, limit
    case coordination(String), waitingForDownload(String), missingLibraryManifest
    /// A selected cloud folder can remain pending while its files arrive. Format,
    /// ownership and integrity errors require user action, not endless retries.
    public var isRetryable: Bool {
        switch self {
        case .waitingForDownload, .missingAsset, .coordination: return true
        default: return false
        }
    }
    public var errorDescription: String? {
        switch self {
        case .missingLibraryManifest: return "No Bard library was found here. In iCloud Drive, select the folder connected on your Mac, then tap Open. An existing connection may still be named Wisp or Wisp Phone Sync. Select the whole folder, not Assets inside it. If this is the correct folder, let the Mac finish publishing, then try again."
        case .unsupportedVersion: return "This phone library requires a newer version of Bard."
        case .invalidManifest: return "The phone library has invalid or inconsistent song information."
        case .unsafePath: return "The phone library contains an unsafe file or link."
        case .waitingForDownload(let name): return "Downloading “\(name)” from iCloud. Bard will retry automatically; your current phone library is unchanged."
        case .missingAsset(let name): return "“\(name)” has not finished transferring. Your current phone library is unchanged."
        case .changedAsset(let name): return "“\(name)” did not match the published copy. Your current phone library is unchanged."
        case .differentLibrary: return "This folder belongs to a different Bard library. Choose a separate folder."
        case .olderRevision: return "An older library update arrived. Your newer phone library was kept."
        case .conflictingRevision: return "Two different updates have the same revision. Your current phone library was kept."
        case .invalidCache: return "The saved phone library could not be verified. Its files have been preserved."
        case .unownedDestination: return "Choose an empty folder or the folder already linked to this Bard library."
        case .limit: return "This transfer exceeds the supported phone-library limits."
        case .coordination(let message): return "The library folder is unavailable: \(message)"
        }
    }
}

/// Synchronous, blocking file work: call from a dedicated background task/queue.
/// Assets are written first and never overwritten or removed. The final manifest
/// is the only publication point, allowing a file provider to transport any order.
public enum PhoneLibraryPublisher {
    @discardableResult
    public static func publish(document: LibraryDocument, libraryDirectory: URL, destination: URL,
                               sourceLibraryID: UUID) throws -> PhoneLibraryManifest {
        try Task.checkCancellation()
        let library = try PhoneSyncFiles.directory(libraryDirectory, create: false)
        let folder = try PhoneSyncFiles.directory(destination, create: true)
        guard !PhoneSyncFiles.overlap(library, folder) else { throw PhoneLibrarySyncError.unsafePath }
        return try PhoneSyncFiles.coordinate(reading: library, writing: folder) { library, folder in
            let manifestURL = folder.appendingPathComponent("Library.json")
            let previous: PhoneLibraryManifest?
            if PhoneSyncFiles.exists(manifestURL) {
                previous = try PhoneSyncFiles.manifest(at: manifestURL).manifest
                guard previous?.sourceLibraryID == sourceLibraryID else { throw PhoneLibrarySyncError.differentLibrary }
            } else {
                // An unfinished first publish may contain only our immutable Assets.
                try PhoneSyncFiles.requireNames(in: folder, allowed: ["Assets", ".DS_Store"])
                previous = nil
            }
            var phone = document
            phone.phoneFavoriteReceipts = [:]
            for index in phone.tracks.indices {
                phone.tracks[index].audioVersions = []
                phone.tracks[index].currentAudioAddedAt = nil
                phone.tracks[index].currentAudioVersionID = nil
            }
            try phone.validate()
            let references = try PhoneSyncFiles.references(phone)
            let assetsFolder = try PhoneSyncFiles.directory(folder.appendingPathComponent("Assets"), create: true)
            var inventory: [PhoneLibraryAsset] = []
            for reference in references {
                let parent = try PhoneSyncFiles.directory(library.appendingPathComponent(reference.kind == .audio ? "Media" : "Artwork"), create: false)
                let source = parent.appendingPathComponent(reference.fileName)
                let measured = try PhoneSyncFiles.measure(source)
                if (reference.fingerprint != nil && measured.hash != reference.fingerprint)
                    || (reference.byteCount != nil && measured.bytes != reference.byteCount) {
                    throw PhoneLibrarySyncError.changedAsset(reference.fileName)
                }
                let asset = PhoneLibraryAsset(kind: reference.kind, fileName: reference.fileName,
                    relativePath: PhoneSyncFiles.assetPath(hash: measured.hash, name: reference.fileName),
                    byteCount: measured.bytes, sha256: measured.hash)
                try PhoneSyncFiles.ensureCopy(from: source, to: assetsFolder.appendingPathComponent(URL(fileURLWithPath: asset.relativePath).lastPathComponent), asset: asset)
                inventory.append(asset)
            }
            // Do not create another revision for an unchanged view of this library.
            if let previous, try PhoneSyncFiles.encode(previous.document) == PhoneSyncFiles.encode(phone), previous.assets == inventory {
                return previous
            }
            let clock = Int64(Date().timeIntervalSince1970 * 1000)
            guard (previous?.revision ?? 0) < Int64.max else { throw PhoneLibrarySyncError.limit }
            let revision = max(clock, (previous?.revision ?? 0) + 1)
            let manifest = PhoneLibraryManifest(sourceLibraryID: sourceLibraryID, revision: revision,
                publishedAt: Date(timeIntervalSince1970: Double(revision) / 1000), document: phone, assets: inventory)
            try PhoneSyncFiles.validate(manifest)
            let data = try PhoneSyncFiles.encode(manifest)
            guard data.count <= PhoneSyncFiles.maximumManifestBytes else { throw PhoneLibrarySyncError.limit }
            // This is the first moment readers can see the new snapshot.
            try Task.checkCancellation()
            try data.write(to: manifestURL, options: .atomic)
            return manifest
        }
    }
}

/// The receiver is a mirror, never a merge editor. It keeps every old snapshot
/// and cached asset so a player can safely finish using its existing file URLs.
public enum PhoneLibraryReceiver {
    @discardableResult
    public static func receive(source: URL, cacheDirectory: URL) throws -> PhoneLibrarySnapshot {
        try receive(source: source, cacheDirectory: cacheDirectory, downloads: .live)
    }

    // Download status is injectable for isolated placeholder/retry tests. The
    // public entry point always uses the real OS provider and unchanged admission checks.
    static func receive(source: URL, cacheDirectory: URL,
                        downloads: PhoneLibraryDownloadAccess) throws -> PhoneLibrarySnapshot {
        try Task.checkCancellation()
        let remote = try PhoneSyncFiles.directory(source, create: false)
        let cache = try PhoneSyncFiles.directory(cacheDirectory, create: true)
        guard !PhoneSyncFiles.overlap(remote, cache) else { throw PhoneLibrarySyncError.unsafePath }
        return try PhoneSyncFiles.coordinate(reading: remote, writing: cache) { remote, cache in
            let incoming: PhoneSyncFiles.ManifestRead
            do {
                incoming = try PhoneSyncFiles.manifest(at: remote.appendingPathComponent("Library.json"), downloads: downloads)
            } catch PhoneLibrarySyncError.missingAsset {
                // Known iCloud placeholders already report waitingForDownload.
                // A genuinely absent manifest must not leave a wrong folder
                // silently retrying forever; valid custom folder names still work.
                throw PhoneLibrarySyncError.missingLibraryManifest
            }
            let active = try PhoneSyncFiles.active(in: cache)
            if let active {
                guard active.pointer.sourceLibraryID == incoming.manifest.sourceLibraryID else { throw PhoneLibrarySyncError.differentLibrary }
                guard incoming.manifest.revision >= active.pointer.revision else { throw PhoneLibrarySyncError.olderRevision }
                if incoming.manifest.revision == active.pointer.revision {
                    guard incoming.digest == active.pointer.manifestDigest else { throw PhoneLibrarySyncError.conflictingRevision }
                    return active.snapshot
                }
            } else {
                try PhoneSyncFiles.requireNames(in: cache, allowed: ["Assets", "Snapshots", ".DS_Store"])
            }
            let assetsFolder = try PhoneSyncFiles.directory(cache.appendingPathComponent("Assets"), create: true)
            var missing: [PhoneLibraryAsset] = []
            for asset in incoming.manifest.assets {
                let cached = assetsFolder.appendingPathComponent(URL(fileURLWithPath: asset.relativePath).lastPathComponent)
                if PhoneSyncFiles.exists(cached) { try PhoneSyncFiles.verifySize(cached, asset: asset) }
                else { missing.append(asset) }
            }
            if !missing.isEmpty {
                let remoteAssets = try PhoneSyncFiles.directory(remote.appendingPathComponent("Assets"), create: false)
                // Start every missing iCloud asset in one pass. Returning after
                // the first placeholder would otherwise cost one retry per song.
                try PhoneSyncFiles.prepareDownloads(missing.map {
                    remoteAssets.appendingPathComponent(URL(fileURLWithPath: $0.relativePath).lastPathComponent)
                }, downloads: downloads)
            }
            for asset in incoming.manifest.assets {
                let name = URL(fileURLWithPath: asset.relativePath).lastPathComponent
                let cached = assetsFolder.appendingPathComponent(name)
                if PhoneSyncFiles.exists(cached) { try PhoneSyncFiles.verifySize(cached, asset: asset) }
                else {
                    let remoteAssets = try PhoneSyncFiles.directory(remote.appendingPathComponent("Assets"), create: false)
                    try PhoneSyncFiles.ensureCopy(from: remoteAssets.appendingPathComponent(name), to: cached, asset: asset, downloads: downloads)
                }
            }
            let snapshots = try PhoneSyncFiles.directory(cache.appendingPathComponent("Snapshots"), create: true)
            let name = "\(incoming.manifest.sourceLibraryID.uuidString)-\(incoming.manifest.revision)-\(incoming.digest)"
            let target = snapshots.appendingPathComponent(name, isDirectory: true)
            if PhoneSyncFiles.exists(target) {
                _ = try PhoneSyncFiles.snapshot(at: target, manifest: incoming.manifest, digest: incoming.digest)
            } else {
                let stage = snapshots.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: stage) }
                let media = try PhoneSyncFiles.directory(stage.appendingPathComponent("Media"), create: true)
                let artwork = try PhoneSyncFiles.directory(stage.appendingPathComponent("Artwork"), create: true)
                for asset in incoming.manifest.assets {
                    let source = assetsFolder.appendingPathComponent(URL(fileURLWithPath: asset.relativePath).lastPathComponent)
                    let destination = (asset.kind == .audio ? media : artwork).appendingPathComponent(asset.fileName)
                    // A separate immutable snapshot preserves old file paths even
                    // when a Mac edit keeps the same managed filename.
                    do { try FileManager.default.linkItem(at: source, to: destination) }
                    catch { try FileManager.default.copyItem(at: source, to: destination) }
                    try PhoneSyncFiles.verifySize(destination, asset: asset)
                }
                try PhoneSyncFiles.encode(incoming.manifest.document).write(to: stage.appendingPathComponent("Library.json"), options: .atomic)
                try incoming.data.write(to: stage.appendingPathComponent("Transfer.json"), options: .atomic)
                try FileManager.default.moveItem(at: stage, to: target)
            }
            let pointer = PhoneSyncFiles.Pointer(sourceLibraryID: incoming.manifest.sourceLibraryID,
                revision: incoming.manifest.revision, manifestDigest: incoming.digest, snapshotName: name,
                previousSnapshotName: active?.pointer.snapshotName)
            // No active state changes until every referenced file is verified.
            let ready = try PhoneSyncFiles.snapshot(at: target, manifest: incoming.manifest, digest: incoming.digest)
            try Task.checkCancellation()
            try PhoneSyncFiles.encode(pointer).write(to: cache.appendingPathComponent("Current.json"), options: .atomic)
            return ready
        }
    }

    public static func current(cacheDirectory: URL) throws -> PhoneLibrarySnapshot? {
        guard PhoneSyncFiles.exists(cacheDirectory) else { return nil }
        let cache = try PhoneSyncFiles.directory(cacheDirectory, create: false)
        return try PhoneSyncFiles.coordinate(reading: cache) { try PhoneSyncFiles.active(in: $0)?.snapshot }
    }
}

/// Internal test seam: production reads native resource values and only asks the
/// OS to download known iCloud items. A stale local copy is not the current copy.
struct PhoneLibraryDownloadAccess {
    enum State: Equatable { case local, current, stale, notDownloaded }
    var state: (URL) throws -> State
    var start: (URL) throws -> Void

    static var live: Self {
        Self(state: { url in
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                return .local // Truly absent; normal file validation supplies the missing-file error.
            }
            // Other provider metadata failures propagate as retryable coordination
            // errors rather than mislabeling an unavailable cloud file as absent.
            guard values.isUbiquitousItem == true else { return .local }
            switch values.ubiquitousItemDownloadingStatus {
            case .current: return .current
            case .downloaded: return .stale
            default: return .notDownloaded
            }
        }, start: { try FileManager.default.startDownloadingUbiquitousItem(at: $0) })
    }
}

enum PhoneSyncFiles {
    static let maximumManifestBytes = 16 * 1024 * 1024
    static let maximumAssetBytes: Int64 = 2 * 1024 * 1024 * 1024
    static let maximumTotalBytes: Int64 = 64 * 1024 * 1024 * 1024
    static let manager = FileManager.default
    static let operationLock = NSRecursiveLock()
    struct Reference { let kind: PhoneLibraryAsset.Kind; let fileName: String; let fingerprint: String?; let byteCount: Int64? }
    struct Pointer: Codable {
        let sourceLibraryID: UUID
        let revision: Int64
        let manifestDigest: String
        let snapshotName: String
        let previousSnapshotName: String?
    }
    struct ManifestRead { let manifest: PhoneLibraryManifest; let data: Data; let digest: String }
    struct Active { let pointer: Pointer; let snapshot: PhoneLibrarySnapshot }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }
    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func exists(_ url: URL) -> Bool { (try? manager.attributesOfItem(atPath: url.path)) != nil }
    static func overlap(_ a: URL, _ b: URL) -> Bool {
        a.path == b.path || a.path.hasPrefix(b.path + "/") || b.path.hasPrefix(a.path + "/")
    }
    static func directory(_ url: URL, create: Bool) throws -> URL {
        guard url.isFileURL else { throw PhoneLibrarySyncError.unsafePath }
        if !exists(url), create { try manager.createDirectory(at: url, withIntermediateDirectories: true) }
        guard let attributes = try? manager.attributesOfItem(atPath: url.path) else { throw PhoneLibrarySyncError.missingAsset(url.lastPathComponent) }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw PhoneLibrarySyncError.unsafePath }
        // Resolve caller-owned parent aliases (e.g. /tmp), never an asset/link.
        return url.standardizedFileURL.resolvingSymlinksInPath()
    }
    static func requireNames(in directory: URL, allowed: Set<String>) throws {
        let names = try manager.contentsOfDirectory(atPath: directory.path)
        guard Set(names).isSubset(of: allowed) else { throw PhoneLibrarySyncError.unownedDestination }
    }
    static func regularSize(_ url: URL) throws -> Int64 {
        guard let attributes = try? manager.attributesOfItem(atPath: url.path) else { throw PhoneLibrarySyncError.missingAsset(url.lastPathComponent) }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber else { throw PhoneLibrarySyncError.unsafePath }
        return size.int64Value
    }
    static func read(_ url: URL, maximum: Int, downloads: PhoneLibraryDownloadAccess = .live) throws -> Data {
        try coordinatedFileRead(url, downloads: downloads) { coordinated in
            let size = try regularSize(coordinated)
            guard size >= 0, size <= maximum else { throw PhoneLibrarySyncError.limit }
            let handle = try FileHandle(forReadingFrom: coordinated); defer { try? handle.close() }
            let data = try handle.read(upToCount: maximum + 1) ?? Data()
            guard data.count == size, data.count <= maximum else { throw PhoneLibrarySyncError.changedAsset(url.lastPathComponent) }
            return data
        }
    }
    static func measure(_ url: URL) throws -> (bytes: Int64, hash: String) {
        let expected = try regularSize(url)
        guard expected > 0, expected <= maximumAssetBytes else { throw PhoneLibrarySyncError.limit }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var digest = SHA256(), total: Int64 = 0
        while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            total += Int64(chunk.count)
            guard total <= expected else { throw PhoneLibrarySyncError.changedAsset(url.lastPathComponent) }
            digest.update(data: chunk)
        }
        guard total == expected, try regularSize(url) == expected else { throw PhoneLibrarySyncError.changedAsset(url.lastPathComponent) }
        return (total, digest.finalize().map { String(format: "%02x", $0) }.joined())
    }
    static func verify(_ url: URL, asset: PhoneLibraryAsset) throws {
        let actual = try measure(url)
        guard actual.bytes == asset.byteCount, actual.hash == asset.sha256 else { throw PhoneLibrarySyncError.changedAsset(asset.fileName) }
    }
    static func verifySize(_ url: URL, asset: PhoneLibraryAsset) throws {
        guard try regularSize(url) == asset.byteCount else { throw PhoneLibrarySyncError.changedAsset(asset.fileName) }
    }
    static func ensureCopy(from source: URL, to destination: URL, asset: PhoneLibraryAsset,
                           downloads: PhoneLibraryDownloadAccess = .live) throws {
        if exists(destination) { try verify(destination, asset: asset); return }
        try coordinatedFileRead(source, downloads: downloads) { coordinated in
            try verifySize(coordinated, asset: asset)
            let temporary = destination.deletingLastPathComponent().appendingPathComponent(".copy-\(UUID().uuidString)")
            try manager.copyItem(at: coordinated, to: temporary)
            defer { try? manager.removeItem(at: temporary) }
            // Hash the exact bytes admitted to the immutable local cache.
            try verify(temporary, asset: asset)
            try manager.moveItem(at: temporary, to: destination)
        }
    }
    /// A placeholder can expose cloud metadata before a normal data file exists.
    /// Reject any existing link/type first, then request its download before asking
    /// for a regular file. Each eventual read remains individually coordinated.
    static func prepareDownloads(_ urls: [URL], downloads: PhoneLibraryDownloadAccess) throws {
        var pending: PhoneLibrarySyncError?
        var seen = Set<URL>()
        for url in urls where seen.insert(url).inserted {
            try Task.checkCancellation()
            do {
                if let attributes = try? manager.attributesOfItem(atPath: url.path),
                   attributes[.type] as? FileAttributeType != .typeRegular {
                    throw PhoneLibrarySyncError.unsafePath
                }
                let state: PhoneLibraryDownloadAccess.State
                do { state = try downloads.state(url) }
                catch is CancellationError { throw CancellationError() }
                catch let error as PhoneLibrarySyncError { throw error }
                catch { throw PhoneLibrarySyncError.coordination(error.localizedDescription) }
                if state == .notDownloaded || state == .stale {
                    do { try downloads.start(url) }
                    catch is CancellationError { throw CancellationError() }
                    catch { throw PhoneLibrarySyncError.coordination(error.localizedDescription) }
                    pending = pending ?? .waitingForDownload(url.lastPathComponent)
                } else {
                    _ = try regularSize(url)
                }
            } catch let error as PhoneLibrarySyncError where error.isRetryable {
                // One absent/busy asset must not prevent requesting all the others.
                pending = pending ?? error
            }
        }
        if let pending { throw pending }
    }
    static func coordinatedFileRead<T>(_ url: URL, downloads: PhoneLibraryDownloadAccess = .live,
                                       body: (URL) throws -> T) throws -> T {
        try prepareDownloads([url], downloads: downloads)
        var result: Result<T, Error>?, error: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { coordinated in
            result = Result { try body(coordinated) }
        }
        if let result {
            do { return try result.get() }
            catch is CancellationError { throw CancellationError() }
            catch let error as PhoneLibrarySyncError { throw error }
            catch { throw PhoneLibrarySyncError.coordination(error.localizedDescription) }
        }
        throw PhoneLibrarySyncError.coordination(error?.localizedDescription ?? "A file has not finished transferring.")
    }
    static func assetPath(hash: String, name: String) -> String {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        let safe = ext.utf8.count <= 16 && ext.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains) ? ext : ""
        return "Assets/\(hash)\(safe.isEmpty ? "" : "." + safe)"
    }
    static func references(_ document: LibraryDocument) throws -> [Reference] {
        guard document.tracks.count <= 10_000, document.playlists.count <= 5_000 else { throw PhoneLibrarySyncError.limit }
        var result = document.tracks.map { Reference(kind: .audio, fileName: $0.fileName, fingerprint: $0.fingerprint, byteCount: $0.byteCount) }
        let artwork = Set(document.tracks.compactMap(\.artworkFileName) + document.playlists.compactMap(\.coverFileName))
        result += artwork.map { Reference(kind: .artwork, fileName: $0, fingerprint: nil, byteCount: nil) }
        guard result.count <= 20_000 else { throw PhoneLibrarySyncError.limit }
        var names = Set<String>()
        for item in result {
            try LibraryDocument.validateFileName(item.fileName)
            guard names.insert(item.kind.rawValue + "/" + ZIPPreflight.canonicalPath(item.fileName)).inserted else { throw PhoneLibrarySyncError.unsafePath }
        }
        return result.sorted { $0.kind.rawValue + "/" + $0.fileName < $1.kind.rawValue + "/" + $1.fileName }
    }
    static func validate(_ manifest: PhoneLibraryManifest) throws {
        guard manifest.formatVersion == 1 else { throw PhoneLibrarySyncError.unsupportedVersion }
        guard manifest.revision > 0, manifest.publishedAt.timeIntervalSince1970.isFinite,
              manifest.document.phoneFavoriteReceipts.isEmpty,
              manifest.document.tracks.allSatisfy({ $0.audioVersions.isEmpty && $0.currentAudioAddedAt == nil && $0.currentAudioVersionID == nil }) else { throw PhoneLibrarySyncError.invalidManifest }
        try manifest.document.validate()
        let refs = try references(manifest.document)
        guard refs.count == manifest.assets.count else { throw PhoneLibrarySyncError.invalidManifest }
        var inventory: [String: PhoneLibraryAsset] = [:], total: Int64 = 0
        var locations: [String: String] = [:]
        for asset in manifest.assets {
            try LibraryDocument.validateFileName(asset.fileName)
            guard asset.sha256.utf8.count == 64,
                  asset.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  asset.relativePath == assetPath(hash: asset.sha256, name: asset.fileName),
                  asset.byteCount > 0, asset.byteCount <= maximumAssetBytes else { throw PhoneLibrarySyncError.unsafePath }
            let key = asset.kind.rawValue + "/" + ZIPPreflight.canonicalPath(asset.fileName)
            guard inventory.updateValue(asset, forKey: key) == nil else { throw PhoneLibrarySyncError.invalidManifest }
            if let existing = locations[asset.relativePath], existing != "\(asset.sha256):\(asset.byteCount)" { throw PhoneLibrarySyncError.invalidManifest }
            locations[asset.relativePath] = "\(asset.sha256):\(asset.byteCount)"
            guard total <= maximumTotalBytes - asset.byteCount else { throw PhoneLibrarySyncError.limit }
            total += asset.byteCount
        }
        for ref in refs {
            guard let asset = inventory[ref.kind.rawValue + "/" + ZIPPreflight.canonicalPath(ref.fileName)],
                  asset.fileName == ref.fileName,
                  ref.fingerprint == nil || ref.fingerprint == asset.sha256,
                  ref.byteCount == nil || ref.byteCount == asset.byteCount else { throw PhoneLibrarySyncError.invalidManifest }
        }
    }
    static func manifest(at url: URL, downloads: PhoneLibraryDownloadAccess = .live) throws -> ManifestRead {
        let data = try read(url, maximum: maximumManifestBytes, downloads: downloads)
        let value: PhoneLibraryManifest
        do { value = try decode(PhoneLibraryManifest.self, data) }
        catch { throw PhoneLibrarySyncError.invalidManifest }
        try validate(value)
        return ManifestRead(manifest: value, data: data, digest: hash(data))
    }
    static func snapshot(at directory: URL, manifest: PhoneLibraryManifest, digest: String) throws -> PhoneLibrarySnapshot {
        let root = try self.directory(directory, create: false)
        let saved = try self.manifest(at: root.appendingPathComponent("Transfer.json"))
        guard saved.digest == digest else { throw PhoneLibrarySyncError.invalidCache }
        let document = try decode(LibraryDocument.self, read(root.appendingPathComponent("Library.json"), maximum: maximumManifestBytes))
        guard try encode(document) == encode(manifest.document) else { throw PhoneLibrarySyncError.invalidCache }
        let media = try self.directory(root.appendingPathComponent("Media"), create: false)
        let artwork = try self.directory(root.appendingPathComponent("Artwork"), create: false)
        for asset in manifest.assets { try verifySize((asset.kind == .audio ? media : artwork).appendingPathComponent(asset.fileName), asset: asset) }
        return PhoneLibrarySnapshot(document: document, mediaDirectory: media, artworkDirectory: artwork,
                                    sourceLibraryID: manifest.sourceLibraryID, revision: manifest.revision)
    }
    static func active(in cache: URL) throws -> Active? {
        let url = cache.appendingPathComponent("Current.json")
        guard exists(url) else { return nil }
        let pointer = try decode(Pointer.self, read(url, maximum: 4096))
        try LibraryDocument.validateFileName(pointer.snapshotName)
        let snapshots = try directory(cache.appendingPathComponent("Snapshots"), create: false)
        let root = try directory(snapshots.appendingPathComponent(pointer.snapshotName), create: false)
        let saved = try manifest(at: root.appendingPathComponent("Transfer.json"))
        guard saved.manifest.sourceLibraryID == pointer.sourceLibraryID, saved.manifest.revision == pointer.revision,
              saved.digest == pointer.manifestDigest,
              pointer.snapshotName == "\(pointer.sourceLibraryID.uuidString)-\(pointer.revision)-\(pointer.manifestDigest)" else { throw PhoneLibrarySyncError.invalidCache }
        return Active(pointer: pointer, snapshot: try snapshot(at: root, manifest: saved.manifest, digest: saved.digest))
    }
    static func coordinate<T>(reading: URL, writing: URL? = nil, body: (URL, URL) throws -> T) throws -> T {
        operationLock.lock(); defer { operationLock.unlock() }
        var result: Result<T, Error>?, error: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        if let writing {
            coordinator.coordinate(readingItemAt: reading, options: .withoutChanges,
                                   writingItemAt: writing, options: .forMerging, error: &error) { source, destination in
                result = Result { try body(source, destination) }
            }
        } else {
            coordinator.coordinate(readingItemAt: reading, options: .withoutChanges, error: &error) { source in
                result = Result { try body(source, source) }
            }
        }
        if let result { return try result.get() }
        throw PhoneLibrarySyncError.coordination(error?.localizedDescription ?? "File coordination did not complete.")
    }
    static func coordinate<T>(reading: URL, body: (URL) throws -> T) throws -> T {
        try coordinate(reading: reading, writing: nil) { source, _ in try body(source) }
    }
}
