import Foundation

/// Shared matching for the library and playlist picker, using the names shown
/// in Wisp rather than requiring the spelling of an imported filename.
public enum TrackSearch {
    public static func matches(_ track: Track, query: String) -> Bool {
        let needle = TrackNameParser.normalizeName(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return true }
        return [track.displayTitle, track.artist, track.displayOrigin, track.genre, track.remix?.title ?? ""]
            .contains { field in
                TrackNameParser.normalizeName(field).range(of: needle,
                    options: [.caseInsensitive, .diacriticInsensitive], locale: .current) != nil
            }
    }

    /// The playlist picker uses this full order for both its filtered rows and
    /// the eventual insertion, so selections across searches stay predictable.
    public static func alphabetized(_ tracks: [Track]) -> [Track] {
        tracks.sorted { lhs, rhs in
            let comparison = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
            return comparison == .orderedSame
                ? lhs.id.uuidString < rhs.id.uuidString
                : comparison == .orderedAscending
        }
    }
}
