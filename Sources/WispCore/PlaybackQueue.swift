import Foundation

public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off, all, one

    public var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

/// The order of a listening session is independent of the playlist it came from.
/// Keeping this state outside the audio API makes end-of-queue and shuffle rules
/// deterministic and testable on every platform.
public struct PlaybackQueue: Codable, Equatable, Sendable {
    public private(set) var sourceIDs: [UUID]
    public private(set) var orderedIDs: [UUID]
    public private(set) var currentID: UUID?
    public private(set) var isShuffled: Bool

    public init(
        sourceIDs: [UUID] = [],
        orderedIDs: [UUID]? = nil,
        currentID: UUID? = nil,
        isShuffled: Bool = false
    ) {
        let source = Self.unique(sourceIDs)
        let allowed = Set(source)
        var order = Self.unique(orderedIDs ?? source).filter { allowed.contains($0) }
        let included = Set(order)
        order.append(contentsOf: source.filter { !included.contains($0) })
        self.sourceIDs = source
        self.orderedIDs = isShuffled ? order : source
        self.currentID = currentID.flatMap { allowed.contains($0) ? $0 : nil }
        self.isShuffled = isShuffled
    }

    public var currentIndex: Int? {
        guard let currentID else { return nil }
        return orderedIDs.firstIndex(of: currentID)
    }

    @discardableResult
    public mutating func start(
        ids: [UUID],
        startID: UUID? = nil,
        shuffled: Bool = false,
        randomize: ([UUID]) -> [UUID] = { $0.shuffled() }
    ) -> UUID? {
        sourceIDs = Self.unique(ids)
        isShuffled = shuffled
        let selected = startID.flatMap { sourceIDs.contains($0) ? $0 : nil }
        if shuffled {
            let remaining = sourceIDs.filter { $0 != selected }
            orderedIDs = Self.validPermutation(randomize(remaining), of: remaining)
            if let selected { orderedIDs.insert(selected, at: 0) }
        } else {
            orderedIDs = sourceIDs
        }
        currentID = selected ?? orderedIDs.first
        return currentID
    }

    @discardableResult
    public mutating func select(_ id: UUID) -> Bool {
        guard orderedIDs.contains(id) else { return false }
        currentID = id
        return true
    }

    /// Automatic completion honors repeat-one. A deliberate Next always moves on.
    /// At an ordinary queue boundary, nil is returned and the last item stays selected.
    @discardableResult
    public mutating func next(
        repeating mode: RepeatMode,
        userInitiated: Bool = true,
        randomize: ([UUID]) -> [UUID] = { $0.shuffled() }
    ) -> UUID? {
        guard !orderedIDs.isEmpty else { currentID = nil; return nil }
        guard let index = currentIndex else {
            currentID = orderedIDs.first
            return currentID
        }
        if mode == .one && !userInitiated { return currentID }
        if index + 1 < orderedIDs.count {
            currentID = orderedIDs[index + 1]
            return currentID
        }
        guard mode == .all else { return nil }
        let previous = currentID
        if isShuffled {
            orderedIDs = Self.validPermutation(randomize(sourceIDs), of: sourceIDs)
            if orderedIDs.count > 1, orderedIDs.first == previous {
                orderedIDs.swapAt(0, 1)
            }
        }
        currentID = orderedIDs.first
        return currentID
    }

    /// Skip files already rejected by the decoder. A partial old shuffle cycle
    /// plus one complete new cycle is sufficient to inspect every candidate.
    /// The bound also guarantees termination when every file is unavailable.
    @discardableResult
    public mutating func nextPlayable(
        repeating mode: RepeatMode,
        userInitiated: Bool = true,
        excluding rejected: Set<UUID>,
        randomize: ([UUID]) -> [UUID] = { $0.shuffled() }
    ) -> UUID? {
        let skipRepeatOne = currentID.map { rejected.contains($0) } ?? false
        for _ in 0..<max(1, orderedIDs.count * 2) {
            guard let candidate = next(
                repeating: mode,
                userInitiated: userInitiated || skipRepeatOne,
                randomize: randomize
            ) else { return nil }
            if !rejected.contains(candidate) { return candidate }
        }
        return nil
    }

    @discardableResult
    public mutating func previous(repeating mode: RepeatMode) -> UUID? {
        guard !orderedIDs.isEmpty else { currentID = nil; return nil }
        guard let index = currentIndex else {
            currentID = orderedIDs.first
            return currentID
        }
        if index > 0 { currentID = orderedIDs[index - 1] }
        else if mode == .all { currentID = orderedIDs.last }
        return currentID
    }

    /// Enabling shuffle preserves listening history and shuffles only upcoming items.
    /// Turning it off restores the source order without replacing the current item.
    public mutating func setShuffled(
        _ enabled: Bool,
        randomize: ([UUID]) -> [UUID] = { $0.shuffled() }
    ) {
        guard enabled != isShuffled else { return }
        isShuffled = enabled
        if enabled {
            let boundary = currentIndex.map { $0 + 1 } ?? 0
            let history = Array(orderedIDs.prefix(boundary))
            let remaining = Array(orderedIDs.dropFirst(boundary))
            orderedIDs = history + Self.validPermutation(randomize(remaining), of: remaining)
        } else {
            orderedIDs = sourceIDs
        }
    }

    /// Changing shuffle strategies keeps everything already heard and the current
    /// selection. The supplied ordering cannot inject, omit, or duplicate songs.
    public mutating func reshuffleUpcoming(randomize: ([UUID]) -> [UUID]) {
        guard isShuffled else { return }
        let boundary = currentIndex.map { $0 + 1 } ?? 0
        let history = Array(orderedIDs.prefix(boundary))
        let remaining = Array(orderedIDs.dropFirst(boundary))
        orderedIDs = history + Self.validPermutation(randomize(remaining), of: remaining)
    }

    /// Reorders this listening session without replacing the selected track.
    /// Destinations use SwiftUI's insertion-offset convention, before removal.
    /// Editing a shuffled sequence leaves its source order available for unshuffle.
    @discardableResult
    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) -> Bool {
        guard !offsets.isEmpty, destination >= 0, destination <= orderedIDs.count,
              offsets.allSatisfy({ orderedIDs.indices.contains($0) }) else { return false }
        let moving = offsets.map { orderedIDs[$0] }
        var remaining = orderedIDs.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: insertion)
        guard remaining != orderedIDs else { return false }
        orderedIDs = remaining
        if !isShuffled { sourceIDs = remaining }
        return true
    }

    /// A stable-ID alternative for keyboard and accessibility move controls.
    @discardableResult
    public mutating func move(id: UUID, offset: Int) -> Bool {
        guard let index = orderedIDs.firstIndex(of: id), offset != 0 else { return false }
        let (target, overflow) = index.addingReportingOverflow(offset)
        guard !overflow, orderedIDs.indices.contains(target) else { return false }
        let destination = target > index ? target + 1 : target
        return move(fromOffsets: IndexSet(integer: index), toOffset: destination)
    }

    /// Removing the current item selects its next surviving successor. At the
    /// boundary only repeat-all wraps; removal never silently replays a prior item.
    @discardableResult
    public mutating func remove(_ ids: Set<UUID>, repeating mode: RepeatMode) -> UUID? {
        let oldCurrent = currentID
        let oldIndex = currentIndex
        let successors = oldIndex.map { Array(orderedIDs.dropFirst($0 + 1)) } ?? []
        sourceIDs.removeAll { ids.contains($0) }
        orderedIDs.removeAll { ids.contains($0) }
        if let oldCurrent, !ids.contains(oldCurrent), orderedIDs.contains(oldCurrent) {
            currentID = oldCurrent
        } else if oldCurrent != nil {
            currentID = successors.first { orderedIDs.contains($0) }
            if currentID == nil && mode == .all { currentID = orderedIDs.first }
        } else {
            currentID = nil
        }
        return currentID
    }

    @discardableResult
    public mutating func retainAvailable(_ ids: Set<UUID>, repeating mode: RepeatMode) -> UUID? {
        remove(Set(sourceIDs).subtracting(ids), repeating: mode)
    }

    public mutating func clear() {
        sourceIDs = []
        orderedIDs = []
        currentID = nil
    }

    private static func unique(_ values: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func validPermutation(_ candidate: [UUID], of source: [UUID]) -> [UUID] {
        let allowed = Set(source)
        var result = unique(candidate).filter { allowed.contains($0) }
        let included = Set(result)
        result.append(contentsOf: source.filter { !included.contains($0) })
        return result
    }
}
