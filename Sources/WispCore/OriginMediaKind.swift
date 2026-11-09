import Foundation

/// A small offline catalog supplies a useful default; the track editor can
/// override ambiguous or unfamiliar titles without making a network request.
public enum OriginMediaKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case game, movie, tvShow, book, podcast, music, unknown

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .game: return "Game"
        case .movie: return "Movie"
        case .tvShow: return "TV show"
        case .book: return "Book"
        case .podcast: return "Podcast"
        case .music: return "Music"
        case .unknown: return "Other"
        }
    }

    public var symbolName: String {
        switch self {
        case .game: return "gamecontroller"
        case .movie: return "film"
        case .tvShow: return "tv"
        case .book: return "book.closed"
        case .podcast: return "mic"
        case .music: return "music.note"
        case .unknown: return "square.stack"
        }
    }

    /// Navigation labels distinguish ordinary songs from the whole Music library.
    public var categoryTitle: String {
        switch self {
        case .game: return "Games"
        case .movie: return "Movies"
        case .tvShow: return "TV shows"
        case .book: return "Books"
        case .podcast: return "Podcasts"
        case .music: return "Songs"
        case .unknown: return "Other"
        }
    }

    public static func originKey(_ origin: String) -> String {
        TrackNameParser.normalizeName(origin)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    public static func infer(from origin: String) -> OriginMediaKind {
        let key = originKey(origin)
        guard !key.isEmpty else { return .unknown }
        let games = ["hollow knight", "silksong", "hades", "celeste", "stardew valley",
                     "undertale", "deltarune", "the legend of zelda", "zelda", "ocarina of time",
                     "breath of the wild", "tears of the kingdom", "final fantasy", "chrono trigger",
                     "animal crossing", "super mario", "mario kart", "minecraft", "terraria",
                     "outer wilds", "ori and the blind forest", "ori and the will of the wisps",
                     "elden ring", "dark souls", "bloodborne", "baldur s gate", "skyrim",
                     "the elder scrolls", "disco elysium", "tunic", "journey", "gris",
                     "sea of stars", "octopath traveler", "pokemon", "metroid", "mass effect"]
        if games.contains(where: { key == $0 || key.hasPrefix($0 + " ") }) { return .game }
        let movies: Set<String> = ["spirited away", "my neighbor totoro", "howl s moving castle",
                                  "princess mononoke", "kiki s delivery service", "interstellar",
                                  "inception", "the social network", "the grand budapest hotel",
                                  "blade runner", "blade runner 2049", "the fellowship of the ring",
                                  "the two towers", "the return of the king"]
        if movies.contains(key) { return .movie }
        let shows: Set<String> = ["severance", "succession", "twin peaks", "stranger things",
                                 "the last airbender", "avatar the last airbender", "the legend of korra",
                                 "cowboy bebop", "samurai champloo", "over the garden wall",
                                 "adventure time", "steven universe", "bluey", "the white lotus"]
        if shows.contains(key) { return .tvShow }
        return .unknown
    }
}

public extension Track {
    var displayTitle: String { TrackNameParser.normalizeName(title) }
    var displayOrigin: String { TrackNameParser.normalizeName(origin) }
    var resolvedMediaKind: OriginMediaKind { originMediaKind ?? OriginMediaKind.infer(from: origin) }
    /// An ordinary original or remix need not name a game, film, or other work.
    /// This browsing default does not rewrite its origin or ownership metadata.
    var libraryMediaKind: OriginMediaKind {
        if let originMediaKind { return originMediaKind }
        return OriginMediaKind.originKey(origin).isEmpty ? .music : OriginMediaKind.infer(from: origin)
    }
}
