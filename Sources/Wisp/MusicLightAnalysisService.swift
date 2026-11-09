import Combine
import Foundation
import WispCore

/// Reads managed audio independently of playback. Failure leaves the band lights
/// at zero; playback and the existing native level meters remain untouched.
@MainActor
final class MusicLightAnalysis: ObservableObject {
    static let shared = MusicLightAnalysis()

    @Published private(set) var frame = MusicLightFrame.zero
    @Published private(set) var isAnalyzing = false
    private var observations = Set<AnyCancellable>()
    private var ticker: AnyCancellable?
    private var decodeTask: Task<MusicLightTrack, Error>?
    private var completionTask: Task<Void, Never>?
    private weak var player: PlayerStore?
    private weak var store: LibraryStore?
    private var generation = UUID()
    private var analysis: MusicLightTrack?
    private var cache: [(key: String, value: MusicLightTrack)] = []
    private var positionAnchor = 0.0
    private var anchorTime = ProcessInfo.processInfo.systemUptime

    func connect(to player: PlayerStore, store: LibraryStore) {
        disconnect()
        self.player = player
        self.store = store
        player.$currentID.removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] id in self?.select(id) }.store(in: &observations)
        player.$position.receive(on: RunLoop.main)
            .sink { [weak self] position in
                self?.positionAnchor = position
                self?.anchorTime = ProcessInfo.processInfo.systemUptime
            }.store(in: &observations)
        player.$isPlaying.removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] playing in self?.setPlaying(playing) }.store(in: &observations)
    }

    func disconnect() {
        observations.removeAll()
        ticker?.cancel(); ticker = nil
        decodeTask?.cancel(); decodeTask = nil
        completionTask?.cancel(); completionTask = nil
        generation = UUID()
        analysis = nil
        isAnalyzing = false
        publish(.zero)
        player = nil
        store = nil
    }

    private func select(_ id: UUID?) {
        decodeTask?.cancel(); decodeTask = nil
        completionTask?.cancel(); completionTask = nil
        generation = UUID()
        analysis = nil
        isAnalyzing = false
        publish(.zero)
        guard let store, let id, let track = store.track(id: id) else { return }
        let url = store.audioURL(for: track)
        // Managed audio is immutable; import assigns file identity and fingerprint.
        let key = url.path + "|" + track.fingerprint
        if let index = cache.firstIndex(where: { $0.key == key }) {
            let cached = cache.remove(at: index)
            cache.append(cached)
            analysis = cached.value
            sample()
            return
        }
        isAnalyzing = true
        let request = generation
        let task = Task.detached(priority: .utility) { try MusicLightDecoder.analyze(url) }
        decodeTask = task
        completionTask = Task { [weak self] in
            let result = await task.result
            guard !Task.isCancelled, let self, self.generation == request else { return }
            self.decodeTask = nil
            self.completionTask = nil
            self.isAnalyzing = false
            if case .success(let decoded) = result {
                self.analysis = decoded
                self.cache.append((key: key, value: decoded))
                // Three bounded arrays: at most 72,000 frames, under 3.5 MB of values.
                if self.cache.count > 3 { self.cache.removeFirst(self.cache.count - 3) }
            }
            self.sample()
        }
    }

    private func setPlaying(_ playing: Bool) {
        ticker?.cancel(); ticker = nil
        positionAnchor = player?.position ?? 0
        anchorTime = ProcessInfo.processInfo.systemUptime
        guard playing else { publish(.zero); return }
        sample()
        ticker = Timer.publish(every: 1.0 / 12.0, tolerance: 0.02, on: .main, in: .common)
            .autoconnect().sink { [weak self] _ in self?.sample() }
    }

    private func sample() {
        guard let player, player.isPlaying, let analysis else { publish(.zero); return }
        // The player publishes its real clock at 4 Hz. Between those updates,
        // extrapolate at most 350 ms to sample the decoded 12 Hz feature timeline.
        let elapsed = min(0.35, max(0, ProcessInfo.processInfo.systemUptime - anchorTime))
        publish(analysis.frame(at: min(player.duration, positionAnchor + elapsed)))
    }

    private func publish(_ next: MusicLightFrame) {
        if next != frame { frame = next }
    }
}
