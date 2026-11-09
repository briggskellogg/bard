import Foundation

/// A menu choice identifies normalized metadata while preserving a readable label.
public struct TrackFilterChoice: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// Filters only the supplied destination's tracks and never changes their order.
/// A nil field means all values; an empty key explicitly selects missing metadata.
public struct TrackLibraryFilter: Equatable, Sendable {
    public var genre: String?
    public var origin: String?

    public init(genre: String? = nil, origin: String? = nil) {
        self.genre = genre.map(Self.genreKey)
        self.origin = origin.map(OriginMediaKind.originKey)
    }

    public var isActive: Bool { genre != nil || origin != nil }

    public func apply(to tracks: [Track]) -> [Track] {
        guard isActive else { return tracks }
        let selectedGenre = genre.map(Self.genreKey)
        let selectedOrigin = origin.map(OriginMediaKind.originKey)
        return tracks.filter { track in
            (selectedGenre == nil || Self.genreKey(track.genre) == selectedGenre)
                && (selectedOrigin == nil || OriginMediaKind.originKey(track.origin) == selectedOrigin)
        }
    }

    public static func genreKey(_ genre: String) -> String {
        cleanLabel(genre).folding(options: [.caseInsensitive, .diacriticInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
    }

    public static func genres(in tracks: [Track]) -> [TrackFilterChoice] {
        choices(from: tracks.map(\.genre), key: genreKey, label: cleanLabel, emptyLabel: "Unspecified")
    }

    public static func origins(in tracks: [Track]) -> [TrackFilterChoice] {
        choices(from: tracks.map(\.origin), key: OriginMediaKind.originKey,
                label: { cleanLabel(TrackNameParser.normalizeName($0)) }, emptyLabel: "No origin")
    }

    private static func cleanLabel(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func choices(from values: [String], key: (String) -> String,
                                label: (String) -> String, emptyLabel: String) -> [TrackFilterChoice] {
        var labels: [String: String] = [:]
        for value in values {
            let identifier = key(value)
            let candidate = identifier.isEmpty ? emptyLabel : label(value)
            // Picking by text instead of first occurrence keeps menus stable when
            // the destination or track sort order changes.
            if let existing = labels[identifier] {
                if orderedBefore(candidate, existing) { labels[identifier] = candidate }
            } else {
                labels[identifier] = candidate
            }
        }
        return labels.map { TrackFilterChoice(id: $0.key, label: $0.value) }.sorted {
            if $0.label == $1.label { return $0.id < $1.id }
            return orderedBefore($0.label, $1.label)
        }
    }

    private static func orderedBefore(_ lhs: String, _ rhs: String) -> Bool {
        let comparison = lhs.localizedStandardCompare(rhs)
        return comparison == .orderedSame ? lhs < rhs : comparison == .orderedAscending
    }
}
