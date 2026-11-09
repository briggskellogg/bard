import Foundation

public enum ListeningPeriod: String, CaseIterable, Identifiable, Sendable {
    case today, week, month, year, all
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "7 days"
        case .month: return "30 days"
        case .year: return "This year"
        case .all: return "All time"
        }
    }
}

/// A local, daily ledger of actual playback. It is deliberately independent of
/// Library.json so collecting listening time never rewrites a song or playlist.
public struct ListeningHistory: Codable, Equatable, Sendable {
    public var version: Int
    public var trackingStartedAt: Date
    public private(set) var entries: [ListeningDayEntry]

    public init(trackingStartedAt: Date = Date()) {
        version = 1
        self.trackingStartedAt = trackingStartedAt
        entries = []
    }

    /// Records an observed interval ending at `at`; seeks and pauses must already
    /// have been removed by ListeningSessionAccumulator. A play is counted once
    /// when that session crosses its qualification threshold, on the ending day.
    public mutating func record(track: Track, seconds: Double, qualifiedPlay: Bool,
                                at end: Date, calendar: Calendar = .current) {
        guard seconds.isFinite, seconds >= 0, seconds <= 86_400,
              end.timeIntervalSinceReferenceDate.isFinite,
              seconds > 0 || qualifiedPlay else { return }
        var cursor = end.addingTimeInterval(-seconds)
        while cursor < end {
            let day = calendar.startOfDay(for: cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > cursor else { return }
            let boundary = min(end, next)
            update(track: track, day: day, seconds: boundary.timeIntervalSince(cursor), plays: 0)
            cursor = boundary
        }
        if qualifiedPlay {
            update(track: track, day: calendar.startOfDay(for: end), seconds: 0, plays: 1)
        }
    }

    private mutating func update(track: Track, day: Date, seconds: Double, plays: Int) {
        if let index = entries.firstIndex(where: { $0.day == day && $0.trackID == track.id }) {
            entries[index].seconds += seconds
            entries[index].plays += plays
            entries[index].title = track.title
            entries[index].artist = track.artist
            entries[index].origin = track.origin
            entries[index].genre = track.genre
        } else {
            entries.append(ListeningDayEntry(day: day, trackID: track.id, title: track.title,
                                             artist: track.artist, origin: track.origin, genre: track.genre,
                                             seconds: seconds, plays: plays))
        }
    }

    public func validate() throws {
        guard version == 1 else { throw ListeningHistoryError.unsupportedVersion(version) }
        guard trackingStartedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw ListeningHistoryError.invalidData
        }
        var keys = Set<String>()
        for entry in entries {
            guard entry.day.timeIntervalSinceReferenceDate.isFinite,
                  entry.seconds.isFinite, entry.seconds >= 0, entry.plays >= 0,
                  entry.seconds > 0 || entry.plays > 0,
                  keys.insert("\(entry.day.timeIntervalSinceReferenceDate):\(entry.trackID.uuidString)").inserted else {
                throw ListeningHistoryError.invalidData
            }
        }
    }

    public func summary(period: ListeningPeriod, now: Date = Date(), calendar: Calendar = .current) -> ListeningSummary {
        let today = calendar.startOfDay(for: now)
        let start: Date
        switch period {
        case .today: start = today
        case .week: start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .month: start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .year: start = calendar.dateInterval(of: .year, for: now)?.start ?? today
        case .all: start = min(calendar.startOfDay(for: trackingStartedAt), entries.map(\.day).min() ?? today, today)
        }
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let selected = entries.filter { $0.day >= start && $0.day < end }
            .sorted { $0.day == $1.day ? $0.trackID.uuidString < $1.trackID.uuidString : $0.day < $1.day }
        var byTrack: [UUID: ListeningTrackStat] = [:]
        var byDay: [Date: ListeningDayStat] = [:]
        for entry in selected {
            var track = byTrack[entry.trackID] ?? ListeningTrackStat(id: entry.trackID, title: entry.title,
                artist: entry.artist, origin: entry.origin, genre: entry.genre, seconds: 0, plays: 0)
            track.title = entry.title
            track.artist = entry.artist
            track.origin = entry.origin
            track.genre = entry.genre
            track.seconds += entry.seconds
            track.plays += entry.plays
            byTrack[entry.trackID] = track
            let day = calendar.startOfDay(for: entry.day)
            var activity = byDay[day] ?? ListeningDayStat(date: day, seconds: 0, plays: 0)
            activity.seconds += entry.seconds
            activity.plays += entry.plays
            byDay[day] = activity
        }
        let tracks = byTrack.values.sorted {
            if $0.seconds != $1.seconds { return $0.seconds > $1.seconds }
            if $0.plays != $1.plays { return $0.plays > $1.plays }
            if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
        var days: [ListeningDayStat] = []
        var day = start
        // Recording starts on first use; the bound also makes malformed old dates
        // unable to allocate an unbounded chart in an otherwise valid history.
        while day < end && days.count < 36_600 {
            days.append(byDay[day] ?? ListeningDayStat(date: day, seconds: 0, plays: 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return ListeningSummary(totalSeconds: tracks.reduce(0) { $0 + $1.seconds },
            totalPlays: tracks.reduce(0) { $0 + $1.plays }, uniqueTracks: tracks.count,
            tracks: tracks,
            artists: Self.groups(tracks, key: \.artist, fallback: "Unknown artist"),
            origins: Self.groups(tracks, key: \.origin, fallback: "No origin"),
            genres: Self.groups(tracks, key: \.genre, fallback: "Unspecified genre"), days: days)
    }

    private static func groups(_ tracks: [ListeningTrackStat], key: KeyPath<ListeningTrackStat, String>, fallback: String) -> [ListeningGroupStat] {
        var groups: [String: ListeningGroupStat] = [:]
        for track in tracks {
            let raw = track[keyPath: key].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = raw.isEmpty ? fallback : raw
            let id = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            var group = groups[id] ?? ListeningGroupStat(id: id, name: name, seconds: 0, plays: 0)
            group.seconds += track.seconds
            group.plays += track.plays
            groups[id] = group
        }
        return groups.values.sorted {
            if $0.seconds != $1.seconds { return $0.seconds > $1.seconds }
            if $0.plays != $1.plays { return $0.plays > $1.plays }
            return $0.id < $1.id
        }
    }
}

public struct ListeningDayEntry: Codable, Equatable, Sendable {
    public var day: Date
    public var trackID: UUID
    public var title: String
    public var artist: String
    public var origin: String
    public var genre: String
    public var seconds: Double
    public var plays: Int
}

public struct ListeningTrackStat: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var artist: String
    public var origin: String
    public var genre: String
    public var seconds: Double
    public var plays: Int
    public init(id: UUID, title: String, artist: String, origin: String = "", genre: String = "", seconds: Double, plays: Int) {
        self.id = id; self.title = title; self.artist = artist; self.origin = origin; self.genre = genre
        self.seconds = seconds; self.plays = plays
    }
}

public struct ListeningGroupStat: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var seconds: Double
    public var plays: Int
    public init(id: String, name: String, seconds: Double, plays: Int) {
        self.id = id; self.name = name; self.seconds = seconds; self.plays = plays
    }
}

public struct ListeningDayStat: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var seconds: Double
    public var plays: Int
    public init(date: Date, seconds: Double, plays: Int) { self.date = date; self.seconds = seconds; self.plays = plays }
}

public struct ListeningSummary: Equatable, Sendable {
    public var totalSeconds: Double
    public var totalPlays: Int
    public var uniqueTracks: Int
    public var tracks: [ListeningTrackStat]
    public var artists: [ListeningGroupStat]
    public var origins: [ListeningGroupStat]
    public var genres: [ListeningGroupStat]
    public var days: [ListeningDayStat]
    public init(totalSeconds: Double, totalPlays: Int, uniqueTracks: Int, tracks: [ListeningTrackStat],
                artists: [ListeningGroupStat], origins: [ListeningGroupStat], genres: [ListeningGroupStat], days: [ListeningDayStat]) {
        self.totalSeconds = totalSeconds; self.totalPlays = totalPlays; self.uniqueTracks = uniqueTracks
        self.tracks = tracks; self.artists = artists; self.origins = origins; self.genres = genres; self.days = days
    }
}

public enum ListeningHistoryError: LocalizedError {
    case unsupportedVersion(Int), invalidData, notLoaded, changedExternally, unreadable(String)
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "Listening history uses a newer format. It has been left untouched."
        case .invalidData: return "Listening history contains invalid data. It has been left untouched."
        case .notLoaded: return "Listening history is unavailable. Its saved file has been left untouched."
        case .changedExternally: return "Listening history changed outside Bard. Reopen Bard to reload it."
        case .unreadable(let detail): return "Listening history could not be read: \(detail)"
        }
    }
}
