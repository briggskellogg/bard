import Foundation

public struct PhoneFavoriteChange: Codable, Equatable, Sendable {
    public var sequence: Int64
    public var trackID: UUID
    public var isFavorite: Bool
    public init(sequence: Int64, trackID: UUID, isFavorite: Bool) {
        self.sequence = sequence; self.trackID = trackID; self.isFavorite = isFavorite
    }
}

public struct PhoneFavoriteBatch: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var sourceLibraryID: UUID
    public var deviceID: UUID
    public var sequence: Int64
    public var changes: [PhoneFavoriteChange]
    public init(formatVersion: Int = 1, sourceLibraryID: UUID, deviceID: UUID,
                sequence: Int64, changes: [PhoneFavoriteChange]) {
        self.formatVersion = formatVersion; self.sourceLibraryID = sourceLibraryID
        self.deviceID = deviceID; self.sequence = sequence; self.changes = changes
    }
    public func validate(sourceLibraryID expected: UUID) throws {
        guard sourceLibraryID == expected else { throw PhoneFavoriteError.differentLibrary }
        guard formatVersion == 1, sequence > 0, !changes.isEmpty, changes.count <= 10_000,
              Set(changes.map(\.trackID)).count == changes.count,
              Set(changes.map(\.sequence)).count == changes.count,
              changes.allSatisfy({ $0.sequence > 0 && $0.sequence <= sequence }),
              changes.map(\.sequence).max() == sequence else { throw PhoneFavoriteError.invalidData }
    }
}

public struct PhoneFavoriteAcknowledgement: Codable, Equatable, Sendable {
    public var formatVersion: Int = 1
    public var sourceLibraryID: UUID
    public var deviceID: UUID
    public var sequence: Int64
    public var publishedRevision: Int64
    public init(sourceLibraryID: UUID, deviceID: UUID, sequence: Int64, publishedRevision: Int64) {
        self.sourceLibraryID = sourceLibraryID; self.deviceID = deviceID
        self.sequence = sequence; self.publishedRevision = publishedRevision
    }
}

public enum PhoneFavoriteError: LocalizedError {
    case invalidData, differentLibrary, staleOutbox, limit
    public var errorDescription: String? {
        switch self {
        case .invalidData: return "The favorite update could not be verified. Your songs are unchanged."
        case .differentLibrary: return "These favorites belong to a different Bard library."
        case .staleOutbox: return "A newer favorite update is already shared by this device. Your downloaded library is unchanged."
        case .limit: return "There are too many pending favorite changes. Connect to your Mac before adding more."
        }
    }
}

/// Durable local intent. Cleared only after an acknowledgement and its published
/// library revision have both arrived, so transport order never flickers hearts.
public struct PhoneFavoriteOutbox: Codable, Equatable, Sendable {
    public var sourceLibraryID: UUID
    public var deviceID: UUID
    public private(set) var sequence: Int64 = 0
    public private(set) var changes: [PhoneFavoriteChange] = []
    public init(sourceLibraryID: UUID, deviceID: UUID) {
        self.sourceLibraryID = sourceLibraryID; self.deviceID = deviceID
    }
    public var batch: PhoneFavoriteBatch? {
        guard !changes.isEmpty else { return nil }
        return PhoneFavoriteBatch(sourceLibraryID: sourceLibraryID, deviceID: deviceID,
                                  sequence: sequence, changes: changes)
    }
    public func validate() throws {
        guard sequence >= 0 else { throw PhoneFavoriteError.invalidData }
        if let batch { try batch.validate(sourceLibraryID: sourceLibraryID) }
    }
    public mutating func set(_ favorite: Bool, for trackID: UUID) throws {
        guard sequence < Int64.max,
              changes.count < 10_000 || changes.contains(where: { $0.trackID == trackID }) else { throw PhoneFavoriteError.limit }
        sequence += 1
        changes.removeAll { $0.trackID == trackID }
        changes.append(PhoneFavoriteChange(sequence: sequence, trackID: trackID, isFavorite: favorite))
    }
    public mutating func acknowledge(_ receipt: PhoneFavoriteAcknowledgement, snapshot: PhoneLibrarySnapshot) throws {
        guard receipt.formatVersion == 1, receipt.sourceLibraryID == sourceLibraryID,
              receipt.deviceID == deviceID, receipt.sequence > 0, receipt.sequence <= sequence,
              receipt.publishedRevision > 0, snapshot.sourceLibraryID == sourceLibraryID else { throw PhoneFavoriteError.invalidData }
        guard snapshot.revision >= receipt.publishedRevision else { return }
        changes.removeAll { $0.sequence <= receipt.sequence }
    }
    public func applying(to document: LibraryDocument) -> LibraryDocument {
        var copy = document
        let selected = Dictionary(uniqueKeysWithValues: changes.map { ($0.trackID, $0.isFavorite) })
        for index in copy.tracks.indices {
            if let value = selected[copy.tracks[index].id] { copy.tracks[index].favorite = value }
        }
        return copy
    }
}

/// Separate device files avoid competing phone writers. Only the Mac writes
/// acknowledgements, after both its durable receipt and published revision exist.
public enum PhoneFavoritesSync {
    public static let directoryName = "Favorites"
    private static let maximumBytes = 2 * 1024 * 1024

    private static func ownedFolder(_ folder: URL, identity: UUID) throws -> URL {
        let root = try PhoneSyncFiles.directory(folder, create: false)
        let manifest = try PhoneSyncFiles.manifest(at: root.appendingPathComponent("Library.json")).manifest
        guard manifest.sourceLibraryID == identity else { throw PhoneFavoriteError.differentLibrary }
        return root
    }
    private static func batchURL(_ directory: URL, device: UUID) -> URL {
        directory.appendingPathComponent(device.uuidString + ".json")
    }
    private static func acknowledgementURL(_ directory: URL, device: UUID) -> URL {
        directory.appendingPathComponent(device.uuidString + ".ack.json")
    }
    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let bytes = try PhoneSyncFiles.encode(value)
        guard bytes.count <= maximumBytes else { throw PhoneFavoriteError.limit }
        return bytes
    }
    private static func knownFile(_ url: URL) throws -> Bool {
        if PhoneSyncFiles.exists(url) { return true }
        return try PhoneLibraryDownloadAccess.live.state(url) != .local
    }
    private static func mutate<T>(_ root: URL, body: (URL) throws -> T) throws -> T {
        try Task.checkCancellation()
        PhoneSyncFiles.operationLock.lock(); defer { PhoneSyncFiles.operationLock.unlock() }
        var result: Result<T, Error>?, error: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: root, options: .forMerging, error: &error) { folder in
            result = Result { try body(folder) }
        }
        if let result { return try result.get() }
        throw PhoneLibrarySyncError.coordination(error?.localizedDescription ?? "Favorite updates are unavailable.")
    }

    public static func publish(_ batch: PhoneFavoriteBatch, to folder: URL) throws {
        try batch.validate(sourceLibraryID: batch.sourceLibraryID)
        let root = try PhoneSyncFiles.directory(folder, create: false)
        try mutate(root) { root in
            let owned = try ownedFolder(root, identity: batch.sourceLibraryID)
            let directory = try PhoneSyncFiles.directory(owned.appendingPathComponent(directoryName), create: true)
            let destination = batchURL(directory, device: batch.deviceID)
            if try knownFile(destination) {
                let previous = try PhoneSyncFiles.decode(PhoneFavoriteBatch.self, PhoneSyncFiles.read(destination, maximum: maximumBytes))
                try previous.validate(sourceLibraryID: batch.sourceLibraryID)
                guard previous.deviceID == batch.deviceID else { throw PhoneFavoriteError.invalidData }
                if previous == batch { return }
                // A partial acknowledgement can trim older entries locally
                // without changing the latest sequence. Keep the full shared
                // file intact; retrying that exact subset is idempotent.
                if previous.sequence == batch.sequence,
                   batch.changes.allSatisfy({ previous.changes.contains($0) }) { return }
                guard previous.sequence < batch.sequence else { throw PhoneFavoriteError.staleOutbox }
            }
            try Task.checkCancellation()
            try encoded(batch).write(to: destination, options: .atomic)
        }
    }

    public static func batches(in folder: URL, sourceLibraryID: UUID) throws -> [PhoneFavoriteBatch] {
        let root = try ownedFolder(folder, identity: sourceLibraryID)
        let child = root.appendingPathComponent(directoryName)
        guard PhoneSyncFiles.exists(child) else { return [] }
        let directory = try PhoneSyncFiles.directory(child, create: false)
        return try PhoneSyncFiles.coordinate(reading: directory) { directory in
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            guard files.count <= 2_049 else { throw PhoneFavoriteError.limit }
            var result: [PhoneFavoriteBatch] = []
            var totalBytes = 0
            var seen = Set<UUID>()
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                var name = file.lastPathComponent
                if name.hasPrefix("."), name.hasSuffix(".icloud") { name = String(name.dropFirst().dropLast(7)) }
                guard name.hasSuffix(".json"), !name.hasSuffix(".ack.json") else { continue }
                let stem = String(name.dropLast(5))
                guard let device = UUID(uuidString: stem), device.uuidString == stem else { throw PhoneFavoriteError.invalidData }
                guard seen.insert(device).inserted else { continue }
                let bytes = try PhoneSyncFiles.read(directory.appendingPathComponent(name), maximum: maximumBytes)
                totalBytes += bytes.count
                guard totalBytes <= 16 * 1024 * 1024 else { throw PhoneFavoriteError.limit }
                let batch = try PhoneSyncFiles.decode(PhoneFavoriteBatch.self, bytes)
                try batch.validate(sourceLibraryID: sourceLibraryID)
                guard batch.deviceID == device else { throw PhoneFavoriteError.invalidData }
                result.append(batch)
            }
            return result
        }
    }

    public static func acknowledge(_ receipt: PhoneFavoriteAcknowledgement, in folder: URL) throws {
        guard receipt.formatVersion == 1, receipt.sequence > 0, receipt.publishedRevision > 0 else { throw PhoneFavoriteError.invalidData }
        let root = try PhoneSyncFiles.directory(folder, create: false)
        try mutate(root) { root in
            let owned = try ownedFolder(root, identity: receipt.sourceLibraryID)
            let manifest = try PhoneSyncFiles.manifest(at: owned.appendingPathComponent("Library.json")).manifest
            guard manifest.revision >= receipt.publishedRevision else { throw PhoneFavoriteError.invalidData }
            let directory = try PhoneSyncFiles.directory(owned.appendingPathComponent(directoryName), create: true)
            let destination = acknowledgementURL(directory, device: receipt.deviceID)
            if try knownFile(destination) {
                let previous = try readAcknowledgement(destination, identity: receipt.sourceLibraryID, device: receipt.deviceID)
                guard previous.sequence <= receipt.sequence else { return }
                if previous.sequence == receipt.sequence { return }
            }
            try Task.checkCancellation()
            try encoded(receipt).write(to: destination, options: .atomic)
        }
    }

    public static func acknowledgement(in folder: URL, sourceLibraryID: UUID, deviceID: UUID) throws -> PhoneFavoriteAcknowledgement? {
        let root = try ownedFolder(folder, identity: sourceLibraryID)
        let child = root.appendingPathComponent(directoryName)
        guard PhoneSyncFiles.exists(child) else { return nil }
        let directory = try PhoneSyncFiles.directory(child, create: false)
        let file = acknowledgementURL(directory, device: deviceID)
        guard try knownFile(file) else { return nil }
        return try readAcknowledgement(file, identity: sourceLibraryID, device: deviceID)
    }

    private static func readAcknowledgement(_ file: URL, identity: UUID, device: UUID) throws -> PhoneFavoriteAcknowledgement {
        let value = try PhoneSyncFiles.decode(PhoneFavoriteAcknowledgement.self, PhoneSyncFiles.read(file, maximum: maximumBytes))
        guard value.formatVersion == 1, value.sourceLibraryID == identity, value.deviceID == device,
              value.sequence > 0, value.publishedRevision > 0 else { throw PhoneFavoriteError.invalidData }
        return value
    }
}
