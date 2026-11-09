import Foundation

public struct ListeningSample: Equatable, Sendable {
    public var seconds: Double
    public var qualifiedPlay: Bool
    public init(seconds: Double = 0, qualifiedPlay: Bool = false) {
        self.seconds = seconds; self.qualifiedPlay = qualifiedPlay
    }
}

/// Accounts for one playback run. Pausing or seeking resets only the sample
/// baseline; a new/repeated track starts a new accumulator. Monotonic elapsed
/// time and real playhead progress must agree, so seeking cannot create time.
public struct ListeningSessionAccumulator: Sendable {
    public private(set) var accumulatedSeconds: Double = 0
    public private(set) var hasQualifiedPlay = false
    private let threshold: Double
    private var baseline: (position: Double, uptime: Double)?

    public init(duration: Double) {
        threshold = duration.isFinite && duration > 0 ? min(30, duration / 2) : .infinity
    }

    public mutating func resetBaseline(position: Double, uptime: Double) {
        guard position.isFinite, position >= 0, uptime.isFinite, uptime >= 0 else {
            baseline = nil
            return
        }
        baseline = (position, uptime)
    }

    public mutating func sample(position: Double, uptime: Double) -> ListeningSample {
        let previous = baseline
        resetBaseline(position: position, uptime: uptime)
        guard let previous, baseline != nil else { return ListeningSample() }
        let elapsed = uptime - previous.uptime
        let progress = position - previous.position
        guard elapsed > 0, elapsed <= 2, progress > 0, progress <= elapsed + 0.25 else {
            return ListeningSample()
        }
        let seconds = min(progress, elapsed)
        accumulatedSeconds += seconds
        let qualifies = !hasQualifiedPlay && accumulatedSeconds >= threshold
        if qualifies { hasQualifiedPlay = true }
        return ListeningSample(seconds: seconds, qualifiedPlay: qualifies)
    }
}
