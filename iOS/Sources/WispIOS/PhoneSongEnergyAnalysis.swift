import AVFoundation
import Combine
import Foundation
import WispCore

/// Measures the immutable, downloaded audio off the main actor. Uses the same
/// RMS/crossover/onset scoring as Mac Wisp; the cache contains scores only.
@MainActor
final class PhoneSongEnergyAnalysis: ObservableObject {
    @Published private(set) var isAnalyzing = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    struct Item: Sendable { let fingerprint: String; let title: String; let url: URL }
    private struct Cache: Codable, Sendable { let version: Int; let scores: [String: Double] }
    private let cacheURL: URL
    private let analyze: @Sendable (URL) throws -> Double
    private var cached: [String: Double] = [:]
    private var loaded = false
    private var worker: Task<Double, Error>?
    private var generation = UUID()

    enum Failure: LocalizedError {
        case unavailable(String), busy
        var errorDescription: String? {
            switch self {
            case .unavailable(let title): return "Couldn’t measure “\(title)”. Your current queue is unchanged. Try syncing the song again, or use Shuffle."
            case .busy: return "Another energy scan is still finishing."
            }
        }
    }

    init(directory: URL, analyze: @escaping @Sendable (URL) throws -> Double = { try PhoneSongEnergyAnalysis.measureFile($0) }) {
        cacheURL = directory.appendingPathComponent("Energy-v1.json")
        self.analyze = analyze
    }

    func cancel() { generation = UUID(); worker?.cancel() }

    func measure(_ items: [Item]) async throws -> [String: Double] {
        guard !isAnalyzing else { throw Failure.busy }
        let request = UUID(); generation = request
        isAnalyzing = true; completed = 0; total = items.count
        defer { worker = nil; isAnalyzing = false }
        if !loaded {
            let url = cacheURL
            cached = await Task.detached(priority: .utility) {
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), (values.fileSize ?? Int.max) <= 2_000_000,
                      let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Cache.self, from: data), saved.version == 1 else { return [:] }
                return Dictionary(uniqueKeysWithValues: saved.scores.filter { $0.key.count == 64 && $0.value.isFinite && (0...1).contains($0.value) }.prefix(10_000).map { ($0.key,$0.value) })
            }.value
            loaded = true
        }
        var result: [String: Double] = [:]
        for item in items {
            try Task.checkCancellation()
            guard generation == request else { throw CancellationError() }
            guard FileManager.default.isReadableFile(atPath: item.url.path) else { throw Failure.unavailable(item.title) }
            if let score = cached[item.fingerprint] { result[item.fingerprint] = score; completed += 1; continue }
            let analyze = self.analyze
            let task = Task.detached(priority: .utility) { try analyze(item.url) }
            worker = task
            let value: Double
            do {
                value = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            } catch is CancellationError { throw CancellationError() }
            catch { throw Failure.unavailable(item.title) }
            try Task.checkCancellation()
            guard generation == request else { throw CancellationError() }
            guard value.isFinite, (0...1).contains(value) else { throw Failure.unavailable(item.title) }
            if cached.count >= 10_000, let oldest = cached.keys.sorted().first { cached.removeValue(forKey: oldest) }
            cached[item.fingerprint] = value; result[item.fingerprint] = value; completed += 1
        }
        let saved = Cache(version: 1, scores: cached), url = cacheURL
        await Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(saved) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }.value
        try Task.checkCancellation()
        guard generation == request else { throw CancellationError() }
        return result
    }

    nonisolated static func measureFile(_ url: URL) throws -> Double {
        try score(PhoneEnergyDecoder.analyze(url))
    }
    nonisolated static func score(_ audio: PhoneEnergyTrack) throws -> Double {
        guard !audio.frames.isEmpty, audio.duration > 0 else { throw Failure.unavailable("this song") }
        var squaredEnergy = 0.0, brightness = 0.0, onsets = 0
        var detector = PhoneEnergyOnsetDetector(minimumInterval: 0.8)
        for (index, frame) in audio.frames.enumerated() {
            try Task.checkCancellation()
            let rms = frame.energy
            squaredEnergy += rms * rms
            brightness += min(1, frame.treble / max(0.000001, frame.bass + frame.mid + frame.treble))
            let level = min(1, max(0, (20 * log10(max(0.000001, rms)) + 60) / 60))
            if detector.process(level: level, at: Double(index) * audio.frameDuration) { onsets += 1 }
        }
        let meanRMS = sqrt(squaredEnergy / Double(audio.frames.count))
        let loudness = min(1, max(0, (20 * log10(max(0.000001, meanRMS)) + 48) / 40))
        let rhythmicActivity = min(1, Double(onsets) * 60 / max(1, audio.duration) / 45)
        let highFrequencyShare = brightness / Double(audio.frames.count)
        return min(1, max(0, 0.60 * loudness + 0.30 * rhythmicActivity + 0.10 * highFrequencyShare))
    }
}


/// Measured RMS energy, not generated animation values. Stereo spread is the
/// side-channel energy ratio: identical channels are zero, opposite channels one.
struct PhoneEnergyFrame: Equatable, Sendable {
    var bass: Double
    var mid: Double
    var treble: Double
    var left: Double
    var right: Double
    var stereoSpread: Double
    var energy: Double { sqrt((left * left + right * right) * 0.5) }

    static let zero = Self(bass: 0, mid: 0, treble: 0, left: 0, right: 0, stereoSpread: 0)
}

struct PhoneEnergyTrack: Sendable {
    let frames: [PhoneEnergyFrame]
    let frameDuration: Double
    let duration: Double

    func frame(at seconds: Double) -> PhoneEnergyFrame {
        guard seconds.isFinite, seconds >= 0, seconds < duration,
              frameDuration > 0, !frames.isEmpty else { return .zero }
        let index = min(frames.count - 1, Int(seconds / frameDuration))
        return frames[index]
    }
}

/// A bounded, sequential decode on a background task. Two low-pass crossovers
/// split each channel into <250 Hz, 250–2500 Hz, and >2500 Hz RMS bands.
/// Long files use wider time bins instead of growing the feature array forever.
enum PhoneEnergyDecoder {
    static let maximumFrames = 24_000
    static let samplesPerSecond = 12.0

    static func analyze(_ url: URL, maximumFrames: Int = maximumFrames) throws -> PhoneEnergyTrack {
        try Task.checkCancellation()
        let limit = min(Self.maximumFrames, max(2, maximumFrames))
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let rate = format.sampleRate
        let channels = Int(format.channelCount)
        guard rate.isFinite, rate >= 8_000, rate <= 384_000, channels > 0, channels <= 32,
              file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_192) else {
            throw PhoneEnergyDecodeError.unavailable
        }
        let hop = max(1, Int(ceil(max(rate / samplesPerSecond, Double(file.length) / Double(limit - 1)))))
        let lowCoefficient = 1 - exp(-2 * Double.pi * 250 / rate)
        let highCoefficient = 1 - exp(-2 * Double.pi * min(2_500, rate * 0.35) / rate)
        var low = Array(repeating: 0.0, count: channels)
        var high = Array(repeating: 0.0, count: channels)
        var frames: [PhoneEnergyFrame] = []
        frames.reserveCapacity(min(limit, Int(ceil(Double(file.length) / Double(hop)))))
        var totalRead: Int64 = 0
        var count = 0
        var bass = 0.0, mid = 0.0, treble = 0.0
        var left = 0.0, right = 0.0, side = 0.0

        func boundedRMS(_ sum: Double, divisor: Double) -> Double {
            min(1, sqrt(max(0, sum / divisor)))
        }
        func measuredFrame() -> PhoneEnergyFrame {
            let divisor = Double(count)
            let stereoEnergy = (left + right) * 0.5
            return PhoneEnergyFrame(
                bass: boundedRMS(bass, divisor: divisor * Double(channels)),
                mid: boundedRMS(mid, divisor: divisor * Double(channels)),
                treble: boundedRMS(treble, divisor: divisor * Double(channels)),
                left: boundedRMS(left, divisor: divisor), right: boundedRMS(right, divisor: divisor),
                stereoSpread: stereoEnergy > 1e-15 ? min(1, sqrt(max(0, side / stereoEnergy))) : 0)
        }

        while file.framePosition < file.length {
            try Task.checkCancellation()
            let remaining = file.length - file.framePosition
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(Int64(buffer.frameCapacity), remaining)))
            let length = Int(buffer.frameLength)
            guard length > 0 else { break }
            guard let data = buffer.floatChannelData else { throw PhoneEnergyDecodeError.unavailable }
            for sample in 0..<length {
                for channel in 0..<channels {
                    let raw = Double(data[channel][sample])
                    let value = raw.isFinite ? min(4, max(-4, raw)) : 0
                    low[channel] += lowCoefficient * (value - low[channel])
                    high[channel] += highCoefficient * (value - high[channel])
                    let middle = high[channel] - low[channel]
                    let upper = value - high[channel]
                    bass += low[channel] * low[channel]
                    mid += middle * middle
                    treble += upper * upper
                }
                let rawLeft = Double(data[0][sample])
                let rawRight = Double(data[min(1, channels - 1)][sample])
                let l = rawLeft.isFinite ? min(4, max(-4, rawLeft)) : 0
                let r = rawRight.isFinite ? min(4, max(-4, rawRight)) : 0
                left += l * l
                right += r * r
                let difference = (l - r) * 0.5
                side += difference * difference
                count += 1
                totalRead += 1
                if count == hop {
                    guard frames.count < limit else { throw PhoneEnergyDecodeError.unavailable }
                    frames.append(measuredFrame())
                    count = 0
                    bass = 0; mid = 0; treble = 0; left = 0; right = 0; side = 0
                }
            }
        }
        try Task.checkCancellation()
        if count > 0 {
            guard frames.count < limit else { throw PhoneEnergyDecodeError.unavailable }
            frames.append(measuredFrame())
        }
        guard !frames.isEmpty else { throw PhoneEnergyDecodeError.unavailable }
        return PhoneEnergyTrack(frames: frames, frameDuration: Double(hop) / rate,
                               duration: Double(totalRead) / rate)
    }
}

private enum PhoneEnergyDecodeError: Error { case unavailable }


/// Detects prominent rising level changes in the player's 12 Hz average-power
/// meter. This is a conservative accent trigger, not a BPM or beat-grid analyzer.
private struct PhoneEnergyOnsetDetector {
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
