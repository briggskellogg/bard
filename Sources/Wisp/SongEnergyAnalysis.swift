import Combine
import Foundation
import WispCore

/// A cache of measured audio features; no library metadata or source audio changes.
@MainActor
final class SongEnergyAnalysis: ObservableObject {
    @Published private(set) var isAnalyzing = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    private let cacheURL: URL
    private var cached: [String: Double] = [:]
    private var worker: Task<Double, Error>?
    private var generation = UUID()

    private struct Cache: Codable { var version: Int; var scores: [String: Double] }
    struct Item: Sendable { var fingerprint: String; var title: String; var url: URL }
    enum Failure: LocalizedError {
        case unavailable(String), busy
        var errorDescription: String? {
            switch self {
            case .unavailable(let title): return "Could not measure “\(title)”. The queue is unchanged. Check its audio file, or use Shuffle."
            case .busy: return "An energy scan is already running."
            }
        }
    }

    init(directory: URL) {
        cacheURL = directory.appendingPathComponent("Analysis/Energy-v1.json")
        if let data = try? Data(contentsOf: cacheURL), data.count <= 20_000_000,
           let cache = try? JSONDecoder().decode(Cache.self, from: data), cache.version == 1 {
            cached = cache.scores.filter { $0.value.isFinite && (0...1).contains($0.value) }
        }
    }

    func cancel() { generation = UUID(); worker?.cancel() }

    func measure(_ items: [Item]) async throws -> [String: Double] {
        guard !isAnalyzing else { throw Failure.busy }
        let token = UUID(); generation = token
        isAnalyzing = true; completed = 0; total = items.count
        defer { worker = nil; isAnalyzing = false }
        var result: [String: Double] = [:]
        for item in items {
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            guard FileManager.default.isReadableFile(atPath: item.url.path) else { throw Failure.unavailable(item.title) }
            if let score = cached[item.fingerprint] { result[item.fingerprint] = score; completed += 1; continue }
            let task = Task.detached(priority: .utility) {
                let audio = try MusicLightDecoder.analyze(item.url)
                return try Self.score(audio)
            }
            worker = task
            let score: Double
            do {
                score = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            } catch is CancellationError { throw CancellationError() }
            catch { throw Failure.unavailable(item.title) }
            try Task.checkCancellation()
            guard generation == token else { throw CancellationError() }
            cached[item.fingerprint] = score; result[item.fingerprint] = score; completed += 1
            saveCache()
        }
        return result
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(Cache(version: 1, scores: cached)) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    nonisolated static func score(_ audio: MusicLightTrack) throws -> Double {
        guard !audio.frames.isEmpty, audio.duration > 0 else { throw Failure.unavailable("this song") }
        var squaredEnergy = 0.0, brightness = 0.0, onsets = 0
        var detector = MusicOnsetDetector(minimumInterval: 0.8)
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
