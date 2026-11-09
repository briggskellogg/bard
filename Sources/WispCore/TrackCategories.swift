import Foundation

/// Sidebar categories are views onto the existing tracks. They neither change
/// origin/source metadata nor tie ordinary songs to Basic or Classic ownership.
public enum TrackCategories {
    public static func availableKinds(in tracks: [Track]) -> [OriginMediaKind] {
        let present = Set(tracks.map(\.libraryMediaKind))
        return OriginMediaKind.allCases.filter { $0 == .music || present.contains($0) }
    }

    public static func tracks(in tracks: [Track], kind: OriginMediaKind) -> [Track] {
        tracks.filter { $0.libraryMediaKind == kind }
    }

    /// A work may be shared by several artists and may have punctuation/case
    /// variations. Preserve the original ordering while matching a stable key.
    public static func tracks(in tracks: [Track], origin: String) -> [Track] {
        let key = OriginMediaKind.originKey(origin)
        return tracks.filter { OriginMediaKind.originKey($0.origin) == key }
    }

    public static func origins(in tracks: [Track], kind: OriginMediaKind? = nil) -> [TrackFilterChoice] {
        let scope = kind.map { Self.tracks(in: tracks, kind: $0) } ?? tracks
        return TrackLibraryFilter.origins(in: scope)
    }
}
