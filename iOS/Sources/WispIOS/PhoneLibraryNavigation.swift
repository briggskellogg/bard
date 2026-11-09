import Foundation
import WispCore

/// Routes store identities, never a stale copy of a cloud snapshot.
enum PhoneCollectionRoute: Hashable {
    case music, favorites, recentlyAdded
    case collection(RemixKind)
    case playlist(UUID)
    case artists, artist(String), artistOrigin(artist: String, origin: String)
    case origins, category(OriginMediaKind), origin(String, category: OriginMediaKind? = nil)
    case genres, genre(String)
}

struct PhoneLibraryGroup: Identifiable {
    var id: PhoneCollectionRoute { route }
    let route: PhoneCollectionRoute
    let title: String
    let subtitle: String?
    let symbol: String
    let count: Int
}

struct PhoneLibraryPage {
    let title: String
    var subtitle: String? = nil
    var groups: [PhoneLibraryGroup] = []
    var groupHeading: String? = nil
    var tracks: [Track] = []
    var showsTracks = true
    var ordered = false
}

enum PhoneLibraryNavigation {
    static let recentInterval: TimeInterval = 30 * 24 * 60 * 60

    static func key(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func search(_ query: String, in document: LibraryDocument) -> [Track] {
        TrackSearch.alphabetized(document.tracks.filter { TrackSearch.matches($0, query: query) })
    }

    static func page(_ route: PhoneCollectionRoute, in document: LibraryDocument, now: Date = Date()) -> PhoneLibraryPage {
        let all = document.tracks
        switch route {
        case .music:
            return PhoneLibraryPage(title: "Music", tracks: TrackSearch.alphabetized(all))
        case .favorites:
            return PhoneLibraryPage(title: "Favorites", tracks: TrackSearch.alphabetized(all.filter(\.favorite)))
        case .recentlyAdded:
            return PhoneLibraryPage(title: "Recently Added", subtitle: "Added in the last 30 days", tracks: all.filter {
                $0.addedAt >= now.addingTimeInterval(-recentInterval) && $0.addedAt <= now
            }.sorted {
                $0.addedAt == $1.addedAt ? $0.id.uuidString < $1.id.uuidString : $0.addedAt > $1.addedAt
            })
        case .collection(let kind):
            return PhoneLibraryPage(title: kind.title, subtitle: kind.attribution,
                                    tracks: TrackSearch.alphabetized(all.filter { $0.remix == kind }))
        case .playlist(let id):
            guard let playlist = document.playlists.first(where: { $0.id == id }) else {
                return PhoneLibraryPage(title: "Playlist", subtitle: "This playlist is no longer in your Mac library.", ordered: true)
            }
            let current = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var seen = Set<UUID>()
            return PhoneLibraryPage(title: playlist.name,
                subtitle: playlist.description.isEmpty ? nil : playlist.description,
                tracks: playlist.trackIDs.compactMap { seen.insert($0).inserted ? current[$0] : nil }, ordered: true)
        case .artists:
            let grouped = Dictionary(grouping: all, by: { key($0.artist) })
            let rows = sortedKeys(grouped.keys).map { artist in
                PhoneLibraryGroup(route: .artist(artist), title: artistTitle(grouped[artist] ?? []),
                    subtitle: nil, symbol: "person", count: grouped[artist]?.count ?? 0)
            }
            return PhoneLibraryPage(title: "Artists", groups: rows, showsTracks: false)
        case .artist(let artist):
            let tracks = all.filter { key($0.artist) == artist }
            return PhoneLibraryPage(title: artistTitle(tracks), groups: originGroups(tracks, artist: artist),
                groupHeading: "Origins", tracks: TrackSearch.alphabetized(tracks))
        case .artistOrigin(let artist, let origin):
            let artistTracks = all.filter { key($0.artist) == artist }
            let tracks = TrackCategories.tracks(in: artistTracks, origin: origin)
            return PhoneLibraryPage(title: originTitle(tracks), subtitle: artistTitle(artistTracks), tracks: TrackSearch.alphabetized(tracks))
        case .origins:
            let groups = TrackCategories.availableKinds(in: all).compactMap { kind -> PhoneLibraryGroup? in
                let count = TrackCategories.tracks(in: all, kind: kind).count
                guard count > 0 else { return nil }
                return PhoneLibraryGroup(route: .category(kind), title: kind.categoryTitle, subtitle: nil,
                                         symbol: kind.symbolName, count: count)
            }
            return PhoneLibraryPage(title: "Origins", subtitle: "Browse by the work your music comes from.",
                                    groups: groups, groupHeading: "Categories", showsTracks: false)
        case .category(let kind):
            let tracks = TrackCategories.tracks(in: all, kind: kind)
            return PhoneLibraryPage(title: kind.categoryTitle, groups: originGroups(tracks, category: kind),
                                    groupHeading: "Origins", tracks: TrackSearch.alphabetized(tracks))
        case .origin(let origin, let category):
            let tracks = TrackCategories.tracks(in: all, origin: origin).filter { category == nil || $0.libraryMediaKind == category }
            return PhoneLibraryPage(title: originTitle(tracks), tracks: TrackSearch.alphabetized(tracks))
        case .genres:
            let groups = TrackLibraryFilter.genres(in: all).map { choice in
                PhoneLibraryGroup(route: .genre(choice.id), title: choice.id.isEmpty ? "Unspecified genre" : choice.label,
                    subtitle: nil, symbol: "tag", count: TrackLibraryFilter(genre: choice.id).apply(to: all).count)
            }
            return PhoneLibraryPage(title: "Genres", groups: groups, showsTracks: false)
        case .genre(let genre):
            let tracks = TrackLibraryFilter(genre: genre).apply(to: all)
            return PhoneLibraryPage(title: genreTitle(tracks), tracks: TrackSearch.alphabetized(tracks))
        }
    }

    static func originGroups(_ tracks: [Track], artist: String? = nil, category: OriginMediaKind? = nil) -> [PhoneLibraryGroup] {
        TrackCategories.origins(in: tracks).map { choice in
            let songs = TrackCategories.tracks(in: tracks, origin: choice.id)
            let route: PhoneCollectionRoute = artist.map { .artistOrigin(artist: $0, origin: choice.id) } ?? .origin(choice.id, category: category)
            let kind = songs.first(where: { $0.originMediaKind != nil })?.libraryMediaKind ?? songs.first?.libraryMediaKind ?? .music
            return PhoneLibraryGroup(route: route, title: choice.label, subtitle: nil,
                symbol: kind.symbolName, count: songs.count)
        }
    }

    private static func sortedKeys(_ keys: Dictionary<String, [Track]>.Keys) -> [String] {
        keys.sorted { a, b in
            if a.isEmpty != b.isEmpty { return !a.isEmpty }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
    private static func artistTitle(_ tracks: [Track]) -> String {
        let name = tracks.map { $0.artist.split(whereSeparator: \.isWhitespace).joined(separator: " ") }.sorted {
            let comparison = $0.localizedStandardCompare($1)
            return comparison == .orderedSame ? $0 < $1 : comparison == .orderedAscending
        }.first ?? ""
        return name.isEmpty ? "Unknown artist" : name
    }
    private static func originTitle(_ tracks: [Track]) -> String {
        TrackCategories.origins(in: tracks).first?.label ?? "No origin"
    }
    private static func genreTitle(_ tracks: [Track]) -> String {
        let choice = TrackLibraryFilter.genres(in: tracks).first
        return choice?.id.isEmpty != false ? "Unspecified genre" : choice!.label
    }
}
