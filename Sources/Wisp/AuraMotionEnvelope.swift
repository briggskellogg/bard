import Foundation

/// A bounded summary of the current audio, not a song-section classifier.
struct AuraMotion: Equatable, Sendable {
    var bass = 0.0
    var mid = 0.0
    var treble = 0.0
    var energy = 0.0
    var sustained = 0.0
    var impact = 0.0
    var spread = 0.0
    var balance = 0.0
    var phase = 0.0

    static let zero = Self()
}

/// Consumes real feature frames only. Fast attacks, slower releases, and a
/// two-second energy bed let short hits and longer musical changes read apart.
/// There is no timer, queued work, audio processing, or unbounded history here.
struct AuraMotionEnvelope {
    private(set) var motion = AuraMotion.zero
    private var lastTime: TimeInterval?
    private var previousEnergy = 0.0
    private var previousBass = 0.0

    static func mappedLevel(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return log1p(min(1, max(0, value)) * 12) / log(13)
    }

    mutating func reset() {
        motion = .zero
        lastTime = nil
        previousEnergy = 0
        previousBass = 0
    }

    @discardableResult
    mutating func consume(_ frame: MusicLightFrame, at time: TimeInterval, enabled: Bool = true) -> AuraMotion {
        guard time.isFinite, enabled else { reset(); return motion }
        func unit(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
        let left = unit(frame.left), right = unit(frame.right)
        let rawEnergy = sqrt((left * left + right * right) * 0.5)
        guard rawEnergy > 0.0005 else { reset(); return motion }
        let energy = Self.mappedLevel(rawEnergy)
        let bass = Self.mappedLevel(frame.bass)
        let mid = Self.mappedLevel(frame.mid)
        let treble = Self.mappedLevel(frame.treble)
        let spread = unit(frame.stereoSpread)
        let balance = (right - left) / max(0.001, right + left)
        let elapsed = lastTime.map { time - $0 }
        // A seek, stale frame gap, or clock reset starts a fresh response rather
        // than turning the discontinuity into a false impact.
        guard let elapsed, elapsed > 0, elapsed <= 1 else {
            motion = AuraMotion(bass: bass, mid: mid, treble: treble, energy: energy,
                                sustained: energy * 0.3, spread: spread, balance: balance)
            previousEnergy = energy; previousBass = bass; lastTime = time
            return motion
        }
        let dt = min(0.25, elapsed)
        func follow(_ current: Double, _ target: Double, attack: Double, release: Double) -> Double {
            let seconds = target > current ? attack : release
            return current + (target - current) * (1 - exp(-dt / seconds))
        }
        let rise = max(0, energy - previousEnergy) * 1.6 + max(0, bass - previousBass) * 1.2
        motion.bass = follow(motion.bass, bass, attack: 0.035, release: 0.38)
        motion.mid = follow(motion.mid, mid, attack: 0.065, release: 0.55)
        motion.treble = follow(motion.treble, treble, attack: 0.03, release: 0.25)
        motion.energy = follow(motion.energy, energy, attack: 0.045, release: 0.7)
        motion.sustained = follow(motion.sustained, energy, attack: 1.8, release: 1.2)
        motion.impact = max(min(1, rise), motion.impact * exp(-dt / 0.22))
        motion.spread = follow(motion.spread, spread, attack: 0.25, release: 0.45)
        motion.balance = follow(motion.balance, balance, attack: 0.18, release: 0.18)
        // Travel is integrated only when real audio frames arrive, and its speed
        // is proportional to their energy. Silence resets it instead of drifting.
        let speed = motion.energy * 0.8 + motion.bass * 1.8 + motion.mid * 0.55
            + motion.treble * 0.9 + motion.impact * 2.5
        motion.phase = min(100_000, motion.phase + dt * speed)
        previousEnergy = energy; previousBass = bass; lastTime = time
        return motion
    }
}
