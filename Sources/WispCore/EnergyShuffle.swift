import Foundation

/// Five landmarks describe the relative energy across a listening queue.
public struct EnergyCurve: Codable, Equatable, Sendable {
    public private(set) var levels: [Double]
    public static let flow = EnergyCurve(levels: [0.25, 0.60, 0.40, 0.70, 0.30])
    public static let surge = EnergyCurve(levels: [0.15, 0.35, 0.65, 1.0, 0.25])
    public static let focus = EnergyCurve(levels: [0.15, 0.20, 0.20, 0.25, 0.15])
    public static let build = EnergyCurve(levels: [0.1, 0.3, 0.5, 0.75, 0.95])
    public static let wave = EnergyCurve(levels: [0.15, 0.85, 0.3, 0.95, 0.2])
    public static let settle = EnergyCurve(levels: [0.95, 0.75, 0.5, 0.3, 0.1])

    /// A continuous Focus (0), Flow (1), Surge (2) control. Invalid input uses Flow.
    public static func clampListeningBlendPosition(_ position: Double) -> Double {
        position.isFinite ? min(2, max(0, position)) : 1
    }

    public static func listeningBlend(at position: Double) -> EnergyCurve {
        let position = clampListeningBlendPosition(position)
        if position == 0 { return .focus }
        if position == 1 { return .flow }
        if position == 2 { return .surge }
        let first = position < 1 ? focus : flow
        let second = position < 1 ? flow : surge
        let fraction = position < 1 ? position : position - 1
        let eased = fraction * fraction * (3 - 2 * fraction)
        return EnergyCurve(levels: zip(first.levels, second.levels).map { $0 + ($1 - $0) * eased })
    }

    /// Finds the closest representable blend without altering a stored custom curve.
    /// The inverse easing preserves the slider position of an existing blended queue.
    public var nearestListeningBlendPosition: Double {
        let presets = [Self.focus, Self.flow, Self.surge]
        var bestPosition = 1.0
        var bestError = Double.infinity
        for segment in 0..<2 {
            let first = presets[segment].levels, second = presets[segment + 1].levels
            let differences = zip(first, second).map { $1 - $0 }
            let denominator = differences.reduce(0) { $0 + $1 * $1 }
            let numerator = zip(zip(levels, first), differences).reduce(0) { $0 + ($1.0.0 - $1.0.1) * $1.1 }
            let fraction = min(1, max(0, numerator / denominator))
            let error = zip(zip(levels, first), differences).reduce(0) {
                let delta = $1.0.0 - ($1.0.1 + $1.1 * fraction)
                return $0 + delta * delta
            }
            if error < bestError {
                var low = 0.0, high = 1.0
                for _ in 0..<48 {
                    let midpoint = (low + high) / 2
                    if midpoint * midpoint * (3 - 2 * midpoint) < fraction { low = midpoint }
                    else { high = midpoint }
                }
                let inverse = fraction == 0 ? 0 : fraction == 1 ? 1 : (low + high) / 2
                bestPosition = Double(segment) + inverse
                bestError = error
            }
        }
        return Self.clampListeningBlendPosition(bestPosition)
    }

    public init(levels: [Double]) {
        let values = levels.prefix(5).map { $0.isFinite ? min(1, max(0, $0)) : 0.5 }
        self.levels = values + Array(repeating: values.last ?? 0.5, count: 5 - values.count)
    }

    public mutating func set(_ index: Int, to value: Double) {
        guard levels.indices.contains(index), value.isFinite else { return }
        levels[index] = min(1, max(0, value))
    }

    public func value(at position: Double) -> Double {
        let x = min(1, max(0, position.isFinite ? position : 0)) * 4
        let index = min(3, Int(x)), fraction = x - Double(index)
        let smooth = fraction * fraction * (3 - 2 * fraction)
        return levels[index] + (levels[index + 1] - levels[index]) * smooth
    }

    private enum CodingKeys: String, CodingKey { case levels }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(levels: try values.decode([Double].self, forKey: .levels))
    }
}

/// Matches the measured relative energy of a collection to curve positions.
/// This changes order only. It adds no songs and makes no mood or emotion claims.
public enum EnergyShuffle {
    public static func order(ids: [UUID], tracks: [Track], scores: [UUID: Double], curve: EnergyCurve, count requestedCount: Int? = nil,
                             after previousID: UUID? = nil,
                             randomUnit: () -> Double = { Double.random(in: 0..<1) }) -> [UUID]? {
        var seen = Set<UUID>()
        let source = ids.filter { seen.insert($0).inserted }
        guard source.allSatisfy({ scores[$0].map { $0.isFinite && (0...1).contains($0) } == true }) else { return nil }
        let count = min(source.count, max(0, requestedCount ?? source.count))
        guard count > 0 else { return [] }
        guard source.count > 1 else { return source }
        let low = source.compactMap { scores[$0] }.min()!, high = source.compactMap { scores[$0] }.max()!
        let relative = Dictionary(uniqueKeysWithValues: source.map { id in
            (id, high - low > 0.001 ? (scores[id]! - low) / (high - low) : 0.5)
        })
        func jitter() -> Double {
            let unit = randomUnit()
            return ((unit.isFinite ? min(1, max(0, unit)) : 0.5) - 0.5) * 0.04
        }
        // Sorted matching minimizes rank crossings and respects the whole curve,
        // rather than exhausting low-energy songs greedily at its first valley.
        var positions: [(index: Int, score: Double)] = []
        var ranked: [(index: Int, id: UUID, score: Double)] = []
        for index in 0..<count {
            let position = count > 1 ? Double(index) / Double(count - 1) : 0.5
            positions.append((index, curve.value(at: position) + jitter()))
        }
        for index in source.indices {
            let id = source[index]
            ranked.append((index, id, relative[id]! + jitter()))
        }
        positions.sort { lhs, rhs in lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score < rhs.score }
        ranked.sort { lhs, rhs in lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score < rhs.score }
        var chosen: [UUID]
        if count == source.count {
            chosen = ranked.map(\.id)
        } else {
            // Minimum-cost matching of the sorted curve targets to a subset of
            // the full energy pool. Skipping candidates reserves low/high tracks
            // across every valley/peak instead of greedily exhausting them.
            var previous = Array(repeating: 0.0, count: source.count + 1)
            var takes = Array(repeating: Array(repeating: false, count: source.count), count: count)
            for point in 1...count {
                var row = Array(repeating: Double.infinity, count: source.count + 1)
                for candidate in point...source.count {
                    let difference = ranked[candidate - 1].score - positions[point - 1].score
                    let take = previous[candidate - 1] + difference * difference
                    let skip = row[candidate - 1]
                    if take < skip { row[candidate] = take; takes[point - 1][candidate - 1] = true }
                    else { row[candidate] = skip }
                }
                previous = row
            }
            chosen = Array(repeating: source[0], count: count)
            var point = count, candidate = source.count
            while point > 0 && candidate > 0 {
                if takes[point - 1][candidate - 1] {
                    chosen[point - 1] = ranked[candidate - 1].id
                    point -= 1
                }
                candidate -= 1
            }
        }
        var result = chosen
        for index in 0..<count { result[positions[index].index] = chosen[index] }
        var artists: [UUID: String] = [:]
        for track in tracks {
            let name = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            if !name.isEmpty { artists[track.id] = name }
        }
        var previousArtist = previousID.flatMap { artists[$0] }
        for index in result.indices {
            if let artist = artists[result[index]], artist == previousArtist,
               let alternate = result.indices.dropFirst(index + 1).first(where: {
                   artists[result[$0]] != previousArtist && abs(relative[result[$0]]! - relative[result[index]]!) <= 0.10
               }) {
                result.swapAt(index, alternate)
            }
            previousArtist = artists[result[index]]
        }
        return result
    }
}
