import Foundation

/// The bytes and technical details of one immutable managed audio file.
/// Song identity, editing fields, artwork, and playlist membership stay on Track.
public struct TrackAudioPayload: Equatable, Sendable {
    public var id: UUID
    public var fileName: String
    public var fingerprint: String
    public var duration: Double
    public var byteCount: Int64
    public var originalFileName: String
    public var addedAt: Date

    public init(id: UUID = UUID(), fileName: String, fingerprint: String, duration: Double,
                byteCount: Int64, originalFileName: String, addedAt: Date = Date()) {
        self.id = id; self.fileName = fileName; self.fingerprint = fingerprint
        self.duration = duration; self.byteCount = byteCount
        self.originalFileName = originalFileName; self.addedAt = addedAt
    }

    public func validate() throws {
        try LibraryDocument.validateFileName(fileName)
        guard !fingerprint.isEmpty, duration.isFinite, duration > 0, byteCount > 0,
              addedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw AudioVersionError.invalidAudio
        }
    }
}

/// Archived files are retained in Media at their original immutable filename.
public struct TrackAudioVersion: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var fileName: String
    public var fingerprint: String
    public var duration: Double
    public var byteCount: Int64
    public var originalFileName: String
    public var addedAt: Date
    public var archivedAt: Date

    public init(id: UUID = UUID(), fileName: String, fingerprint: String, duration: Double,
                byteCount: Int64, originalFileName: String, addedAt: Date, archivedAt: Date = Date()) {
        self.id = id; self.fileName = fileName; self.fingerprint = fingerprint
        self.duration = duration; self.byteCount = byteCount
        self.originalFileName = originalFileName; self.addedAt = addedAt; self.archivedAt = archivedAt
    }

    public func validate() throws {
        try LibraryDocument.validateFileName(fileName)
        guard !fingerprint.isEmpty, duration.isFinite, duration >= 0, byteCount >= 0,
              addedAt.timeIntervalSinceReferenceDate.isFinite,
              archivedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw AudioVersionError.invalidAudio
        }
    }
}

extension Track {
    public var currentAudioDate: Date { currentAudioAddedAt ?? addedAt }

    fileprivate func archivedAudio(at date: Date) -> TrackAudioVersion {
        TrackAudioVersion(id: currentAudioVersionID ?? UUID(), fileName: fileName,
                          fingerprint: fingerprint, duration: duration, byteCount: byteCount,
                          originalFileName: originalFileName, addedAt: currentAudioDate, archivedAt: date)
    }

    fileprivate mutating func use(_ payload: TrackAudioPayload) {
        fileName = payload.fileName; fingerprint = payload.fingerprint
        duration = payload.duration; byteCount = payload.byteCount
        originalFileName = payload.originalFileName
        currentAudioAddedAt = payload.addedAt; currentAudioVersionID = payload.id
    }
}

extension LibraryDocument {
    /// A pure atomic document transformation. Callers validate/copy files first,
    /// then save the returned document; no audio is moved or removed here.
    public mutating func replaceAudio(trackID: UUID, with payload: TrackAudioPayload,
                                      at date: Date = Date()) throws {
        try validate()
        try payload.validate()
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { throw AudioVersionError.missingTrack }
        guard tracks[index].fingerprint != payload.fingerprint else { throw AudioVersionError.alreadyCurrent }
        guard !tracks[index].audioVersions.contains(where: { $0.fingerprint == payload.fingerprint }) else {
            throw AudioVersionError.alreadyArchived
        }
        guard !tracks.contains(where: { $0.id != trackID && $0.fingerprint == payload.fingerprint }) else {
            throw AudioVersionError.belongsToAnotherTrack
        }
        var next = self
        let archived = next.tracks[index].archivedAudio(at: date)
        next.tracks[index].audioVersions.insert(archived, at: 0)
        next.tracks[index].use(payload)
        // Previous Wisp versions reject schema 2 rather than saving away archives
        // they do not understand. Unversioned libraries remain schema 1.
        next.schemaVersion = max(next.schemaVersion, 2)
        try next.validate()
        self = next
    }

    public mutating func restoreAudioVersion(trackID: UUID, versionID: UUID,
                                             at date: Date = Date()) throws {
        try validate()
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { throw AudioVersionError.missingTrack }
        guard let oldIndex = tracks[index].audioVersions.firstIndex(where: { $0.id == versionID }) else {
            throw AudioVersionError.missingVersion
        }
        let restored = tracks[index].audioVersions[oldIndex]
        guard !tracks.contains(where: { $0.id != trackID && $0.fingerprint == restored.fingerprint }) else {
            throw AudioVersionError.belongsToAnotherTrack
        }
        var next = self
        let archived = next.tracks[index].archivedAudio(at: date)
        next.tracks[index].audioVersions.remove(at: oldIndex)
        next.tracks[index].audioVersions.insert(archived, at: 0)
        next.tracks[index].use(TrackAudioPayload(id: restored.id, fileName: restored.fileName,
            fingerprint: restored.fingerprint, duration: restored.duration, byteCount: restored.byteCount,
            originalFileName: restored.originalFileName, addedAt: restored.addedAt))
        next.schemaVersion = max(next.schemaVersion, 2)
        try next.validate()
        self = next
    }
}

public enum AudioVersionError: LocalizedError {
    case invalidAudio, missingTrack, missingVersion, alreadyCurrent, alreadyArchived, belongsToAnotherTrack
    public var errorDescription: String? {
        switch self {
        case .invalidAudio: return "This audio version has invalid file details."
        case .missingTrack: return "This song is no longer in your library."
        case .missingVersion: return "That audio version is no longer available."
        case .alreadyCurrent: return "This is already the current audio file."
        case .alreadyArchived: return "This audio is already saved under Previous versions. Restore it there."
        case .belongsToAnotherTrack: return "This audio is already the current version of another song in your library."
        }
    }
}
