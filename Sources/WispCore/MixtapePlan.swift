import Foundation

public enum CassetteCapacity: Int, CaseIterable, Identifiable, Sendable {
    case c60 = 60, c90 = 90, c120 = 120
    public var id: Int { rawValue }
    public var title: String { "C\(rawValue)" }
    public var sideSeconds: Double { Double(rawValue * 30) }
    public var sideMinutes: Int { rawValue / 2 }
}

public enum MixtapeGap: Int, CaseIterable, Identifiable, Sendable {
    case none = 0, twoSeconds = 2
    public var id: Int { rawValue }
    public var title: String { self == .none ? "No gap" : "2 seconds" }
    public var seconds: Double { Double(rawValue) }
}

public struct MixtapeSide: Sendable {
    public let label: String
    public let tracks: [Track]
    public let gap: MixtapeGap
    public var duration: Double {
        tracks.reduce(0) { $0 + ($1.duration.isFinite && $1.duration > 0 ? $1.duration : 0) }
            + Double(max(0, tracks.count - 1)) * gap.seconds
    }
}

/// Plans two sequential cassette sides without moving or truncating any track.
public struct MixtapePlan: Sendable {
    public let tracks: [Track]
    public let capacity: CassetteCapacity
    public let gap: MixtapeGap
    public let splitIndex: Int

    public init(tracks: [Track], capacity: CassetteCapacity = .c90, gap: MixtapeGap = .twoSeconds,
                splitIndex: Int? = nil) {
        self.tracks = tracks
        self.capacity = capacity
        self.gap = gap
        if let splitIndex {
            self.splitIndex = min(max(0, splitIndex), tracks.count)
        } else {
            var elapsed = 0.0
            var count = 0
            for track in tracks {
                let duration = track.duration.isFinite && track.duration > 0 ? track.duration : 0
                let next = elapsed + (count > 0 ? gap.seconds : 0) + duration
                guard next <= capacity.sideSeconds else { break }
                elapsed = next
                count += 1
            }
            self.splitIndex = count
        }
    }

    public var sideA: MixtapeSide { MixtapeSide(label: "A", tracks: Array(tracks.prefix(splitIndex)), gap: gap) }
    public var sideB: MixtapeSide { MixtapeSide(label: "B", tracks: Array(tracks.dropFirst(splitIndex)), gap: gap) }
    public var sides: [MixtapeSide] { [sideA, sideB] }
    public var problems: [String] {
        guard !tracks.isEmpty else { return ["Add music to this playlist before making a mixtape."] }
        var result: [String] = []
        if let track = tracks.first(where: { !$0.duration.isFinite || $0.duration <= 0 }) {
            result.append("The duration of “\(track.displayTitle)” is unavailable. Reimport it before exporting.")
        }
        for side in sides where side.duration > capacity.sideSeconds {
            result.append("Side \(side.label) is \(Self.time(side.duration - capacity.sideSeconds)) over its \(capacity.sideMinutes)-minute capacity. Move the split or shorten the playlist.")
        }
        return result
    }
    public var canExport: Bool { problems.isEmpty }

    public static func time(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        let rounded = Int(min(Double(Int.max / 2), max(0, seconds.rounded(.up))))
        return String(format: "%d:%02d", rounded / 60, rounded % 60)
    }
}
