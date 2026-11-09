import Foundation

/// A frozen credit to the audio used to make a child song. It survives a source
/// rename, audio replacement, or deletion without claiming to own that source.
public struct RemixSource: Codable, Equatable, Sendable {
    public var trackID: UUID
    public var title: String
    public var artist: String
    public var fingerprint: String
    public var audioVersionID: UUID?
    public var createdAt: Date

    public init(track: Track, createdAt: Date = Date()) {
        trackID = track.id; title = track.title; artist = track.artist
        fingerprint = track.fingerprint; audioVersionID = track.currentAudioVersionID
        self.createdAt = createdAt
    }

    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !fingerprint.isEmpty, createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw LibraryError.invalidData("A remix has invalid source details.")
        }
    }
}

extension LibraryDocument {
    /// Adds a distinct Classic song. The original and every playlist stay intact.
    @discardableResult
    public mutating func addRemix(source: Track, audio: TrackAudioPayload,
                                  title: String, artist: String, at date: Date = Date()) throws -> UUID {
        try validate()
        try audio.validate()
        guard tracks.contains(where: { $0.id == source.id }) else { throw AudioVersionError.missingTrack }
        guard !tracks.contains(where: { $0.fingerprint == audio.fingerprint }) else {
            throw AudioVersionError.belongsToAnotherTrack
        }
        var child = Track(title: title, artist: artist, fileName: audio.fileName,
            fingerprint: audio.fingerprint, artworkFileName: source.artworkFileName,
            duration: audio.duration, byteCount: audio.byteCount, addedAt: date,
            origin: source.origin, remix: .classic, originalFileName: audio.originalFileName,
            sourceURL: source.sourceURL, originMediaKind: source.originMediaKind, genre: source.genre,
            currentAudioAddedAt: audio.addedAt, currentAudioVersionID: audio.id,
            remixSource: RemixSource(track: source, createdAt: date), artworkSource: source.artworkSource)
        child = try TrackMetadataPatch.allFields(from: child).applying(to: child)
        var next = self
        next.schemaVersion = max(next.schemaVersion, 3)
        next.tracks.append(child)
        try next.validate()
        self = next
        return child.id
    }
}
