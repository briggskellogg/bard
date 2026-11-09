import Foundation

/// Detects prominent rising level changes in the player's 12 Hz average-power
/// meter. This is a conservative accent trigger, not a BPM or beat-grid analyzer.
struct MusicOnsetDetector {
    let minimumInterval: TimeInterval
    private var baseline = 0.0
    private var deviation = 0.0
    private var previousLevel = 0.0
    private var previousTime: TimeInterval?
    private var startedAt: TimeInterval?
    private var lastOnset: TimeInterval?

    init(minimumInterval: TimeInterval = 1.2) {
        self.minimumInterval = max(0.8, minimumInterval.isFinite ? minimumInterval : 1.2)
    }

    mutating func reset() {
        baseline = 0
        deviation = 0
        previousLevel = 0
        previousTime = nil
        startedAt = nil
        lastOnset = nil
    }

    mutating func process(level rawLevel: Double, at time: TimeInterval) -> Bool {
        guard rawLevel.isFinite, time.isFinite else { return false }
        let level = min(1, max(0, rawLevel))
        guard let previousTime else {
            prime(level: level, at: time)
            return false
        }
        let elapsed = time - previousTime
        guard elapsed > 0 else { return false }
        if elapsed > 2 {
            reset()
            prime(level: level, at: time)
            return false
        }

        let delta = level - baseline
        let rise = level - previousLevel
        let threshold = max(0.055, deviation * 2.4)
        let warm = time - (startedAt ?? time) >= 0.25
        let cooled = lastOnset.map { time - $0 >= minimumInterval } ?? true
        let onset = warm && cooled && level > 0.14 && rise > 0.025 && delta > threshold

        baseline += (level - baseline) * (1 - exp(-elapsed / 0.90))
        deviation += (abs(delta) - deviation) * (1 - exp(-elapsed / 1.50))
        self.previousTime = time
        previousLevel = level
        if onset { lastOnset = time }
        return onset
    }

    private mutating func prime(level: Double, at time: TimeInterval) {
        baseline = level
        previousLevel = level
        previousTime = time
        startedAt = time
    }
}
