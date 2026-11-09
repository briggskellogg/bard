import Foundation

/// The editable metadata contract shared by import review, one song, and a selection.
/// A disabled field is untouched; an enabled optional empty value explicitly clears it.
public struct TrackMetadataPatch: Equatable, Sendable {
    public var applyTitle = false
    public var title = ""
    public var applyArtist = false
    public var artist = ""
    public var applyGenre = false
    public var genre = ""
    public var applyOrigin = false
    public var origin = ""
    public var applyMediaKind = false
    public var originMediaKind: OriginMediaKind?
    public var applyRemix = false
    public var remix: RemixKind?
    public var applySource = false
    public var source = ""
    public var applyFavorite = false
    public var favorite = false

    public init() {}

    public var isEmpty: Bool {
        !applyTitle && !applyArtist && !applyGenre && !applyOrigin && !applyMediaKind
            && !applyRemix && !applySource && !applyFavorite
    }

    public static func allFields(from track: Track) -> Self {
        var patch = Self()
        patch.applyTitle = true; patch.title = track.title
        patch.applyArtist = true; patch.artist = track.artist
        patch.applyGenre = true; patch.genre = track.genre
        patch.applyOrigin = true; patch.origin = track.origin
        patch.applyMediaKind = true; patch.originMediaKind = track.originMediaKind
        patch.applyRemix = true; patch.remix = track.remix
        patch.applySource = true; patch.source = track.sourceURL ?? ""
        patch.applyFavorite = true; patch.favorite = track.favorite
        return patch
    }

    public static func changes(from original: Track, to edited: Track) -> Self {
        var patch = allFields(from: edited)
        patch.applyTitle = edited.title != original.title
        patch.applyArtist = edited.artist != original.artist
        patch.applyGenre = edited.genre != original.genre
        patch.applyOrigin = edited.origin != original.origin
        patch.applyMediaKind = edited.originMediaKind != original.originMediaKind
        patch.applyRemix = edited.remix != original.remix
        patch.applySource = edited.sourceURL != original.sourceURL
        patch.applyFavorite = edited.favorite != original.favorite
        return patch
    }

    public func applying(to track: Track) throws -> Track {
        var edited = track
        if applyTitle {
            let value = TrackNameParser.normalizeName(title.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !value.isEmpty else { throw TrackMetadataError.titleRequired }
            guard value.count <= 500 else { throw TrackMetadataError.titleTooLong }
            edited.title = value
        }
        if applyArtist { edited.artist = trimmed(artist) }
        if applyGenre { edited.genre = trimmed(genre) }
        if applyOrigin { edited.origin = String(TrackNameParser.normalizeName(trimmed(origin)).prefix(500)) }
        if applyMediaKind { edited.originMediaKind = originMediaKind }
        if applyRemix { edited.remix = remix }
        if applyFavorite { edited.favorite = favorite }
        if applySource {
            let value = source.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { edited.sourceURL = nil }
            else {
                guard let url = MusicSource.validatedURL(value) else { throw TrackMetadataError.sourceLink }
                edited.sourceURL = url.absoluteString
            }
        }
        return edited
    }

    private func trimmed(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
    }
}

public enum TrackMetadataError: LocalizedError {
    case titleRequired, titleTooLong, sourceLink
    public var errorDescription: String? {
        switch self {
        case .titleRequired: return "Enter a title before saving."
        case .titleTooLong: return "Use a title of 500 characters or fewer."
        case .sourceLink: return "Use a complete http or https source link."
        }
    }
}
