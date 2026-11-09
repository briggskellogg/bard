import Foundation

enum RemixVoice: String, CaseIterable, Identifiable, Codable, Sendable {
    case air, pulse, glass, sub, pluck, arc, haze, drift
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var detail: String {
        switch self {
        case .air: return "Soft, rounded sine"
        case .pulse: return "Hollow electronic pulse"
        case .glass: return "Shimmering FM bell"
        case .sub: return "Deep octave bass"
        case .pluck: return "Short, bright string"
        case .arc: return "Saturated saw lead"
        case .haze: return "Breathy resonant noise"
        case .drift: return "Wide, detuned pad"
        }
    }
}

struct RemixRenderParameters: Equatable, Sendable {
    var frequency = 220.0
    var gain = 0.10
    var brightness = 0.5
    var gate = false
    var echo = false
    var voice: RemixVoice = .air
    var trigger: UInt64 = 0

    var sanitized: Self {
        var p = self
        p.frequency = frequency.isFinite ? min(2_000, max(40, frequency)) : 220
        p.gain = gain.isFinite ? min(0.4, max(0, gain)) : 0
        p.brightness = brightness.isFinite ? min(1, max(0, brightness)) : 0.5
        return p
    }
}

/// The audio callback never waits for the UI. It keeps its prior parameters if
/// an update is in progress. All oscillator/delay state stays on the audio thread.
final class RemixParameterBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var value = RemixRenderParameters()
    func update(_ next: RemixRenderParameters) {
        lock.lock(); value = next.sanitized; lock.unlock()
    }
    func snapshot(or previous: RemixRenderParameters) -> RemixRenderParameters {
        guard lock.try() else { return previous }
        defer { lock.unlock() }
        return value
    }
}

final class RemixLevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0.0
    func update(_ next: Double) {
        guard lock.try() else { return }
        value = next.isFinite ? min(1, max(0, next)) : 0
        lock.unlock()
    }
    func read() -> Double { lock.lock(); defer { lock.unlock() }; return value }
}

/// Eight authored timbres share the original theremin's smooth attack, release,
/// pitch glide and vertical expression. Arrays are allocated before rendering.
final class RemixRenderer: @unchecked Sendable {
    private let rate: Double
    private let bridge: RemixParameterBridge
    private var parameters = RemixRenderParameters()
    private var phase = 0.0
    private var subPhase = 0.0
    private var driftPhase = 0.0
    private var driftPhase2 = 0.0
    private var slowPhase = 0.0
    private var frequency = 220.0
    private var gain = 0.0
    private var envelope = 0.0
    private var cutoff = 0.1
    private var filterL = 0.0
    private var filterR = 0.0
    private var echoMix = 0.0
    private var noiseLow = 0.0
    private var noiseBand = 0.0
    private var random: UInt64 = 0x6a09e667f3bcc909
    private var noteAge = 100.0
    private var lastTrigger: UInt64 = 0
    private var lastGate = false
    private var weights = [1.0, 0, 0, 0, 0, 0, 0, 0]
    private var delayL: [Double]
    private var delayR: [Double]
    private var delayIndexL = 0
    private var delayIndexR = 0
    private let attack: Double
    private let release: Double
    private let glide: Double
    private let smoothing: Double

    init(sampleRate: Double = 48_000, parameters: RemixParameterBridge) {
        rate = sampleRate.isFinite ? min(192_000, max(8_000, sampleRate)) : 48_000
        bridge = parameters
        delayL = Array(repeating: 0, count: max(1, Int(rate * 0.28)))
        delayR = Array(repeating: 0, count: max(1, Int(rate * 0.37)))
        attack = 1 - exp(-1 / (rate * 0.014))
        release = 1 - exp(-1 / (rate * 0.065))
        glide = 1 - exp(-1 / (rate * 0.030))
        smoothing = 1 - exp(-1 / (rate * 0.020))
    }

    static func midiNote(x: Double, rootNote: Int, quantized: Bool) -> Double {
        let safeX = x.isFinite ? min(1, max(0, x)) : 0.5
        let offset = safeX * 24
        let root = Double(48 + min(11, max(0, rootNote)))
        guard quantized else { return root + offset }
        let notes: [Double] = [0, 3, 5, 7, 10, 12, 15, 17, 19, 22, 24]
        return root + (notes.min(by: { abs($0 - offset) < abs($1 - offset) }) ?? 0)
    }

    func render(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?) {
        parameters = bridge.snapshot(or: parameters)
        if (parameters.gate && !lastGate) || parameters.trigger != lastTrigger { noteAge = 0 }
        lastGate = parameters.gate; lastTrigger = parameters.trigger
        let voiceIndex = RemixVoice.allCases.firstIndex(of: parameters.voice) ?? 0
        let targetCutoff = 1 - exp(-2 * .pi * min(rate * 0.40, 400 + 8_000 * parameters.brightness) / rate)
        let targetEnvelope = parameters.gate ? 1.0 : 0.0
        let envelopeRate = parameters.gate ? attack : release
        let targetEcho = parameters.echo ? 1.0 : 0.0
        let increment = 2 * Double.pi / rate
        for i in 0..<frameCount {
            frequency += (parameters.frequency - frequency) * glide
            gain += (parameters.gain - gain) * smoothing
            envelope += (targetEnvelope - envelope) * envelopeRate
            cutoff += (targetCutoff - cutoff) * smoothing
            echoMix += (targetEcho - echoMix) * smoothing
            for w in weights.indices { weights[w] += ((w == voiceIndex ? 1.0 : 0.0) - weights[w]) * smoothing }
            phase += frequency * increment
            subPhase += frequency * 0.5 * increment
            driftPhase += frequency * 1.004 * increment
            driftPhase2 += frequency * 0.996 * increment
            slowPhase += 0.23 * increment
            if phase >= 2 * .pi { phase -= 2 * .pi }
            if subPhase >= 2 * .pi { subPhase -= 2 * .pi }
            if driftPhase >= 2 * .pi { driftPhase -= 2 * .pi }
            if driftPhase2 >= 2 * .pi { driftPhase2 -= 2 * .pi }
            if slowPhase >= 2 * .pi { slowPhase -= 2 * .pi }
            noteAge += 1 / rate
            let sine = sin(phase)
            let second = sin(phase * 2)
            let third = frequency * 3 < rate * 0.44 ? sin(phase * 3) : 0
            let fourth = frequency * 4 < rate * 0.44 ? sin(phase * 4) : 0
            let fifth = frequency * 5 < rate * 0.44 ? sin(phase * 5) : 0
            let air = (sine + 0.12 * second) / 1.12
            let pulse = (sine + 0.30 * third + 0.15 * fifth) / 1.45
            let glass = sin(phase + sin(phase * 2) * (0.5 + 2.2 * parameters.brightness) * exp(-noteAge * 1.2))
                * (0.55 + 0.45 * exp(-noteAge * 1.8))
            let sub = 0.80 * sin(subPhase) + 0.20 * sine
            let pluck = (sine + 0.42 * second + 0.22 * third + 0.11 * fourth) / 1.75
                * exp(-noteAge * (1.5 + 3.5 * (1 - parameters.brightness)))
            var saw = sine + 0.5 * second + third / 3 + fourth / 4 + fifth / 5
            if frequency * 6 < rate * 0.44 { saw += sin(phase * 6) / 6 }
            if frequency * 7 < rate * 0.44 { saw += sin(phase * 7) / 7 }
            let arc = tanh(saw * 1.4) * 0.75
            random = random &* 6364136223846793005 &+ 1442695040888963407
            let noise = Double(random >> 11) / 4_503_599_627_370_496 - 1
            let resonanceStep = min(0.4, 2 * sin(.pi * frequency / rate))
            noiseLow += resonanceStep * noiseBand
            let noiseHigh = noise - noiseLow - 0.48 * noiseBand
            noiseBand += resonanceStep * noiseHigh
            let haze = tanh(noiseBand * 1.6) * 0.75
            let driftL = (sin(driftPhase) + 0.55 * sin(driftPhase2) + 0.2 * second) / 1.75
            let driftR = (sin(driftPhase2) + 0.55 * sin(driftPhase) + 0.2 * second) / 1.75
            let mono = air * weights[0] + pulse * weights[1] + glass * weights[2] + sub * weights[3]
                + pluck * weights[4] + arc * weights[5] + haze * weights[6]
            let shimmer = 0.92 + 0.08 * sin(slowPhase)
            filterL += (mono + driftL * weights[7] * shimmer - filterL) * cutoff
            filterR += (mono + driftR * weights[7] * shimmer - filterR) * cutoff
            if envelope < 1e-10 { envelope = 0 }
            let dryL = filterL * envelope * gain
            let dryR = filterR * envelope * gain
            let oldL = delayL[delayIndexL], oldR = delayR[delayIndexR]
            delayL[delayIndexL] = dryL * echoMix + oldR * 0.30
            delayR[delayIndexR] = dryR * echoMix + oldL * 0.30
            delayIndexL = (delayIndexL + 1) % delayL.count
            delayIndexR = (delayIndexR + 1) % delayR.count
            let mixedL = dryL * (1 - 0.08 * echoMix) + oldL * 0.25 * echoMix
            let mixedR = dryR * (1 - 0.08 * echoMix) + oldR * 0.25 * echoMix
            left[i] = Float(mixedL.isFinite ? min(0.8, max(-0.8, mixedL)) : 0)
            right?[i] = Float(mixedR.isFinite ? min(0.8, max(-0.8, mixedR)) : 0)
        }
    }
}
