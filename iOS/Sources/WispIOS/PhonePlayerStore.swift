import AVFoundation
import Combine
import Foundation
import ImageIO
import MediaPlayer
import UIKit
import WispCore

/// Meter traffic is observed only by Aura, never by the whole song library.
@MainActor
final class PhonePlaybackMeters: ObservableObject {
    @Published fileprivate(set) var level: Double = 0
}

/// Offline playback only. Queue items retain the exact library-generation URLs
/// chosen when playback starts; a later sync cannot silently replace that audio.
@MainActor
final class PhonePlayerStore: NSObject, ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    /// Complete session order, including the current song and listening history.
    @Published private(set) var queue: [Track] = []
    let meters = PhonePlaybackMeters()
    var level: Double { meters.level }
    @Published var errorMessage: String?
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var isShuffled = false
    @Published private(set) var smartShuffle = false
    @Published private(set) var energyCurve = EnergyCurve.flow
    let energyAnalysis: PhoneSongEnergyAnalysis
    var currentQueueIndex: Int? { ordering.currentIndex }
    private var energyRequest = UUID()
    private var energyScores: [String: Double] = [:]
    private let connectsSystemPlayback: Bool
    private let startAudio: (AVAudioPlayer) throws -> Bool

    func artworkURL(for track: Track) -> URL? { items[track.id]?.artworkURL }

    /// Artwork belongs to the same captured generation as the playing audio,
    /// even when a newer library snapshot arrives during this session.
    var currentArtworkURL: URL? {
        ordering.currentID.flatMap { items[$0]?.artworkURL }
    }

    private struct Item {
        let track: Track
        let mediaURL: URL
        let artworkURL: URL?
    }
    private var items: [UUID: Item] = [:]
    private var ordering = PlaybackQueue()
    private var audio: AVAudioPlayer?
    private var ticker: Timer?
    private var artwork: MPMediaItemArtwork?
    private var observers: [NSObjectProtocol] = []
    private var commandTargets: [(MPRemoteCommand, Any)] = []
    private var sessionActive = false
    private var interrupted = false
    private var resumeAfterInterruption = false
    private var shutDown = false
    private var lastNowPlayingUpdate: TimeInterval = 0
    private var lastPositionUpdate: TimeInterval = 0
    private let nowPlayingPrefix = "wisp-phone://\(UUID().uuidString)/"

    override convenience init() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("WispEnergy", isDirectory: true)
        self.init(energyAnalysis: PhoneSongEnergyAnalysis(directory: directory))
    }

    /// Fixtures can disable system ownership and inject a start failure without
    /// controlling a real playback session. Production uses native play().
    init(energyAnalysis: PhoneSongEnergyAnalysis, connectsSystemPlayback: Bool = true,
         startAudio: @escaping (AVAudioPlayer) throws -> Bool = { $0.play() }) {
        self.energyAnalysis = energyAnalysis
        self.connectsSystemPlayback = connectsSystemPlayback
        self.startAudio = startAudio
        super.init()
        if connectsSystemPlayback { configureRemoteCommands(); observeAudioSession() }
    }

    deinit {
        ticker?.invalidate()
        audio?.delegate = nil
        audio?.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        commandTargets.forEach { $0.0.removeTarget($0.1) }
        if sessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        guard connectsSystemPlayback else { return }
        let center = MPNowPlayingInfoCenter.default()
        if let identifier = center.nowPlayingInfo?[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String,
           identifier.hasPrefix(nowPlayingPrefix) {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
        }
    }

    func play(_ track: Track, in tracks: [Track], mediaDirectory: URL, artworkDirectory: URL) {
        guard !shutDown else { return }
        cancelSmartShuffle()
        var candidates = tracks
        if let index = candidates.firstIndex(where: { $0.id == track.id }) { candidates[index] = track }
        else { candidates.insert(track, at: 0) }
        startQueue(candidates, first: track.id, shuffled: false,
                   mediaDirectory: mediaDirectory, artworkDirectory: artworkDirectory)
    }

    func shuffle(tracks: [Track], mediaDirectory: URL, artworkDirectory: URL) {
        guard !shutDown else { return }
        cancelSmartShuffle()
        startQueue(tracks, first: nil, shuffled: true,
                   mediaDirectory: mediaDirectory, artworkDirectory: artworkDirectory)
    }

    func togglePlayback() {
        guard !shutDown else { return }
        cancelSmartShuffle()
        resumeAfterInterruption = false
        if isPlaying { pause() }
        else { _ = startPlayback() }
    }

    func next() {
        guard !shutDown, currentTrack != nil else { return }
        cancelSmartShuffle()
        resumeAfterInterruption = false
        advance(autoplay: isPlaying, userInitiated: true)
    }

    func previous() {
        guard !shutDown, currentTrack != nil else { return }
        cancelSmartShuffle()
        resumeAfterInterruption = false
        if (audio?.currentTime ?? position) > 3 || (ordering.currentIndex == 0 && repeatMode != .all) { seek(to: 0); return }
        var previous = ordering
        guard let id = previous.previous(repeating: repeatMode), let item = items[id] else { return }
        do {
            let prepared = try Self.player(for: item)
            let autoplay = isPlaying
            _ = commit(prepared, item: item, captured: items, order: previous, autoplay: autoplay)
        } catch { errorMessage = message(for: item.track, error: error) }
    }

    func seek(to seconds: Double) {
        guard !shutDown, let audio, seconds.isFinite, duration > 0 else { return }
        cancelSmartShuffle()
        let target = min(duration, max(0, seconds))
        audio.currentTime = target
        position = target
        publishNowPlaying()
    }

    func moveQueue(from offsets: IndexSet, to destination: Int) {
        guard !shutDown, ordering.move(fromOffsets: offsets, toOffset: destination) else { return }
        cancelSmartShuffle()
        publishQueue()
        publishNowPlaying()
    }

    func cycleRepeatMode() {
        guard !shutDown else { return }
        repeatMode = repeatMode.next
        publishNowPlaying()
    }

    func toggleShuffle() {
        guard !shutDown else { return }
        cancelSmartShuffle()
        // Switching away from Smart Shuffle becomes ordinary shuffle, while
        // preserving this song and everything already heard.
        if smartShuffle {
            smartShuffle = false
            ordering.reshuffleUpcoming { $0.shuffled() }
        } else { ordering.setShuffled(!ordering.isShuffled) }
        publishQueue(); publishNowPlaying()
    }

    func selectQueueTrack(id: UUID) {
        guard !shutDown, let item = items[id] else { return }
        cancelSmartShuffle()
        var selected = ordering
        guard selected.select(id) else { return }
        do { _ = commit(try Self.player(for: item), item: item, captured: items, order: selected, autoplay: true) }
        catch { errorMessage = message(for: item.track, error: error) }
    }

    func removeFromQueue(ids: Set<UUID>) {
        guard !shutDown, !ids.isEmpty else { return }
        cancelSmartShuffle()
        var updated = ordering
        let nextID = updated.remove(ids, repeating: repeatMode)
        let remaining = items.filter { !ids.contains($0.key) }
        if nextID == ordering.currentID {
            ordering = updated; items = remaining; publishQueue(); publishNowPlaying()
        } else if let nextID, let item = remaining[nextID] {
            do { _ = commit(try Self.player(for: item), item: item, captured: remaining, order: updated, autoplay: isPlaying) }
            catch { errorMessage = message(for: item.track, error: error) }
        } else {
            pause(); audio?.delegate = nil; audio?.stop(); audio = nil
            items = remaining; ordering = updated
            currentTrack = nil; duration = 0; position = 0; artwork = nil
            publishQueue(); clearNowPlaying(); updateRemoteCommands()
        }
    }

    func playNext(_ track: Track, mediaDirectory: URL, artworkDirectory: URL) {
        enqueue(track, next: true, mediaDirectory: mediaDirectory, artworkDirectory: artworkDirectory)
    }

    func addToQueue(_ track: Track, mediaDirectory: URL, artworkDirectory: URL) {
        enqueue(track, next: false, mediaDirectory: mediaDirectory, artworkDirectory: artworkDirectory)
    }

    private func enqueue(_ track: Track, next: Bool, mediaDirectory: URL, artworkDirectory: URL) {
        guard !shutDown, track.id != ordering.currentID else { return }
        cancelSmartShuffle()
        do {
            var captured = items
            if captured[track.id] == nil {
                captured.merge(try Self.capture([track], mediaDirectory: mediaDirectory, artworkDirectory: artworkDirectory)) { old, _ in old }
            }
            guard let item = captured[track.id] else { return }
            var ids = ordering.orderedIDs.filter { $0 != track.id }
            let insertion = next ? (ordering.currentID.flatMap { ids.firstIndex(of: $0) }.map { $0 + 1 } ?? 0) : ids.count
            ids.insert(track.id, at: insertion)
            var source = ordering.sourceIDs
            if !source.contains(track.id) { source.append(track.id) }
            let updated = PlaybackQueue(sourceIDs: ordering.isShuffled ? source : ids, orderedIDs: ids,
                                        currentID: ordering.currentID ?? track.id, isShuffled: ordering.isShuffled)
            if currentTrack == nil {
                guard commit(try Self.player(for: item), item: item, captured: captured, order: updated, autoplay: false) else { return }
            } else { items = captured; ordering = updated; publishQueue(); publishNowPlaying() }
            // An unmeasured insertion cannot claim an energy-shaped repeat cycle.
            if energyScores[item.track.fingerprint] == nil { smartShuffle = false }
        } catch { errorMessage = message(for: track, error: error) }
    }

    func cancelSmartShuffle() {
        energyRequest = UUID()
        energyAnalysis.cancel()
    }

    /// The snapshot, metadata, audio paths and fingerprints are captured before
    /// suspension. A sync arriving during analysis cannot mix library generations.
    func startSmartShuffle(tracks: [Track], snapshot: PhoneLibrarySnapshot,
                           curve: EnergyCurve, limit: Int = 20) async -> Bool {
        guard !shutDown else { return false }
        guard !energyAnalysis.isAnalyzing else { errorMessage = "Another energy scan is still finishing."; return false }
        let request = UUID(); energyRequest = request
        var seen = Set<UUID>()
        let unique = tracks.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { errorMessage = "There are no downloaded songs in this collection."; return false }
        let snapshotTracks = Dictionary(uniqueKeysWithValues: snapshot.document.tracks.map { ($0.id, $0) })
        guard unique.allSatisfy({ snapshotTracks[$0.id] == $0 }) else {
            errorMessage = "This collection changed during sync. Open Smart Shuffle again to use the updated songs."
            return false
        }
        errorMessage = nil
        do {
            let captured = try Self.capture(unique, mediaDirectory: snapshot.mediaDirectory, artworkDirectory: snapshot.artworkDirectory)
            let measurements = unique.compactMap { track -> PhoneSongEnergyAnalysis.Item? in
                guard let item = captured[track.id] else { return nil }
                return .init(fingerprint: track.fingerprint, title: track.displayTitle, url: item.mediaURL)
            }
            let scores = try await energyAnalysis.measure(measurements)
            try Task.checkCancellation()
            guard energyRequest == request, !shutDown else { return false }
            let byID = Dictionary(uniqueKeysWithValues: unique.compactMap { track in scores[track.fingerprint].map { (track.id, $0) } })
            guard let ids = EnergyShuffle.order(ids: unique.map(\.id), tracks: unique, scores: byID, curve: curve, count: max(1, limit)),
                  let first = ids.first, let item = captured[first] else {
                errorMessage = "These songs couldn’t form an energy-shaped queue. Your current queue is unchanged."
                return false
            }
            let chosen = Set(ids)
            let subset = captured.filter { chosen.contains($0.key) }
            let order = PlaybackQueue(sourceIDs: unique.map(\.id).filter { chosen.contains($0) }, orderedIDs: ids, currentID: first, isShuffled: true)
            let prepared = try Self.player(for: item)
            try Task.checkCancellation()
            guard energyRequest == request, !shutDown else { return false }
            guard commit(prepared, item: item, captured: subset, order: order, autoplay: true) else { return false }
            energyScores = scores; energyCurve = curve; smartShuffle = true
            return true
        } catch is CancellationError { return false }
        catch {
            if energyRequest == request { errorMessage = error.localizedDescription }
            return false
        }
    }

    private func queueRandomizer() -> ([UUID]) -> [UUID] {
        guard smartShuffle else { return { $0.shuffled() } }
        let tracks = items.values.map(\.track), curve = energyCurve, previous = ordering.currentID
        let scores = Dictionary(uniqueKeysWithValues: tracks.compactMap { track in energyScores[track.fingerprint].map { (track.id, $0) } })
        return { ids in EnergyShuffle.order(ids: ids, tracks: tracks, scores: scores, curve: curve, after: previous) ?? ids }
    }

    /// The app may call this before discarding its player. Deinit also releases
    /// timers, notification observers and this instance's remote-command targets.
    func shutdown() {
        guard !shutDown else { return }
        pause()
        shutDown = true
        audio?.delegate = nil
        audio?.stop()
        audio = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        commandTargets.forEach { $0.0.removeTarget($0.1) }
        commandTargets.removeAll()
        clearNowPlaying()
        items.removeAll(); ordering.clear(); queue = []
        currentTrack = nil; artwork = nil; duration = 0; position = 0
    }

    private static func capture(_ tracks: [Track], mediaDirectory: URL, artworkDirectory: URL) throws -> [UUID: Item] {
        var captured: [UUID: Item] = [:]
        for track in tracks where captured[track.id] == nil {
            let media = try assetURL(track.fileName, in: mediaDirectory)
            let cover = track.artworkFileName.flatMap { try? assetURL($0, in: artworkDirectory) }
            captured[track.id] = Item(track: track, mediaURL: media, artworkURL: cover)
        }
        return captured
    }

    private func startQueue(_ tracks: [Track], first: UUID?, shuffled: Bool,
                            mediaDirectory: URL, artworkDirectory: URL) {
        var seen = Set<UUID>()
        let unique = tracks.filter { seen.insert($0.id).inserted }
        guard !unique.isEmpty else { errorMessage = "There are no downloaded songs in this collection."; return }
        do {
            let captured = try Self.capture(unique, mediaDirectory: mediaDirectory, artworkDirectory: artworkDirectory)
            var order = PlaybackQueue()
            guard let selected = order.start(ids: unique.map(\.id), startID: first, shuffled: shuffled), let item = captured[selected] else { return }
            let prepared = try Self.player(for: item)
            if commit(prepared, item: item, captured: captured, order: order, autoplay: true) { smartShuffle = false }
        } catch { errorMessage = "This song couldn’t open. \(error.localizedDescription)" }
    }

    /// Admission is transactional: validate and successfully start the new audio
    /// before replacing any queue, captured URL, or old player. A start failure
    /// leaves the previous session and its audio position untouched.
    @discardableResult
    private func commit(_ prepared: AVAudioPlayer, item: Item, captured: [UUID: Item], order: PlaybackQueue,
                        autoplay: Bool) -> Bool {
        guard !shutDown else { return false }
        if autoplay {
            guard !interrupted else { errorMessage = "Playback can resume when the audio interruption ends."; return false }
            let wasActive = sessionActive
            do {
                try activateSession()
                guard try startAudio(prepared) else { throw PlaybackError.couldNotStart }
            } catch {
                prepared.stop()
                if !wasActive { deactivateSession() }
                errorMessage = "Playback couldn’t start. \(error.localizedDescription)"
                return false
            }
        }
        ticker?.invalidate(); ticker = nil
        audio?.delegate = nil; audio?.stop()
        items = captured; ordering = order
        audio = prepared; prepared.delegate = self; prepared.isMeteringEnabled = true
        currentTrack = item.track; duration = prepared.duration
        position = 0; meters.level = 0; isPlaying = autoplay
        resumeAfterInterruption = false
        artwork = Self.lockScreenArtwork(at: item.artworkURL); errorMessage = nil
        publishQueue()
        if autoplay { startTicker() } else { deactivateSession() }
        publishNowPlaying()
        return true
    }

    private func activateSession() throws {
        guard connectsSystemPlayback else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        sessionActive = true
    }

    @discardableResult
    private func startPlayback() -> Bool {
        guard !shutDown, currentTrack != nil else { return false }
        guard !interrupted else {
            errorMessage = "Playback can resume when the audio interruption ends."
            return false
        }
        if audio == nil, let id = ordering.currentID, let item = items[id] {
            do {
                let restored = try Self.player(for: item)
                restored.delegate = self; restored.isMeteringEnabled = true
                restored.currentTime = min(position, restored.duration)
                audio = restored; duration = restored.duration
            } catch { errorMessage = message(for: item.track, error: error); return false }
        }
        guard let audio else { return false }
        do {
            try activateSession()
            if audio.currentTime >= duration - 0.05 { audio.currentTime = 0; position = 0 }
            guard try startAudio(audio) else { throw PlaybackError.couldNotStart }
            isPlaying = true; errorMessage = nil
            startTicker()
            publishNowPlaying()
            return true
        } catch {
            audio.pause(); isPlaying = false; meters.level = 0
            deactivateSession()
            errorMessage = "Playback couldn’t start. \(error.localizedDescription)"
            publishNowPlaying()
            return false
        }
    }

    private func pause(keepingResumeIntent: Bool = false) {
        cancelSmartShuffle()
        if !keepingResumeIntent { resumeAfterInterruption = false }
        if let audio { position = min(duration, max(0, audio.currentTime)); audio.pause() }
        isPlaying = false; meters.level = 0
        ticker?.invalidate(); ticker = nil
        deactivateSession()
        publishNowPlaying()
    }

    private func advance(autoplay: Bool, userInitiated: Bool = true) {
        var next = ordering
        var lastFailure: String?
        // A finite, non-repeating queue skips unreadable files without recursion.
        var rejected = Set<UUID>()
        for _ in 0..<ordering.orderedIDs.count {
            guard let id = next.nextPlayable(repeating: repeatMode, userInitiated: userInitiated, excluding: rejected, randomize: queueRandomizer()), let item = items[id] else { break }
            do {
                let prepared = try Self.player(for: item)
                if commit(prepared, item: item, captured: items, order: next, autoplay: autoplay) {
                    if let lastFailure { errorMessage = lastFailure }
                } else if !userInitiated {
                    // The previous audio has already ended. Preserve its queue,
                    // but do not leave a stale Playing state after start failure.
                    let failure = errorMessage
                    pause()
                    audio?.currentTime = duration; position = duration
                    errorMessage = failure; publishNowPlaying()
                }
                return
            } catch { rejected.insert(id); lastFailure = message(for: item.track, error: error) }
        }
        pause()
        if let audio { audio.currentTime = duration }
        position = duration
        if let lastFailure { errorMessage = lastFailure }
        publishNowPlaying()
    }

    private func deactivateSession() {
        guard sessionActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActive = false
        } catch {
            // An interruption may already have deactivated it. A later pause or
            // shutdown retries rather than claiming a session transition succeeded.
        }
    }

    private func startTicker() {
        ticker?.invalidate()
        lastPositionUpdate = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        guard isPlaying, let audio else { return }
        let time = min(duration, max(0, audio.currentTime))
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastPositionUpdate >= 1 {
            position = time
            lastPositionUpdate = now
        }
        audio.updateMeters()
        let channels = max(1, audio.numberOfChannels)
        var power: Float = -160
        for channel in 0..<channels { power = max(power, audio.averagePower(forChannel: channel)) }
        let target = power.isFinite && power > -60 ? min(1, pow(10, Double(power) / 40)) : 0
        meters.level += (target - meters.level) * (target > meters.level ? 0.34 : 0.12)
        if meters.level < 0.001 { meters.level = 0 }
        if now - lastNowPlayingUpdate >= 1 { publishNowPlaying() }
    }

    private func publishQueue() {
        queue = ordering.orderedIDs.compactMap { items[$0]?.track }
        isShuffled = ordering.isShuffled
    }

    private func publishNowPlaying() {
        guard connectsSystemPlayback, !shutDown, let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.displayTitle,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.origin,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queue.count,
            MPNowPlayingInfoPropertyExternalContentIdentifier: nowPlayingPrefix + track.id.uuidString
        ]
        if let index = ordering.currentIndex { info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
        lastNowPlayingUpdate = ProcessInfo.processInfo.systemUptime
        updateRemoteCommands()
    }

    private func clearNowPlaying() {
        guard connectsSystemPlayback else { return }
        let center = MPNowPlayingInfoCenter.default()
        guard let value = center.nowPlayingInfo?[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String,
              value.hasPrefix(nowPlayingPrefix) else { return }
        center.nowPlayingInfo = nil; center.playbackState = .stopped
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand) { $0.isPlaying || $0.startPlayback() ? .success : .commandFailed }
        register(center.pauseCommand) { $0.pause(); return .success }
        register(center.togglePlayPauseCommand) {
            $0.resumeAfterInterruption = false
            if $0.isPlaying { $0.pause(); return .success }
            return $0.startPlayback() ? .success : .commandFailed
        }
        register(center.stopCommand) { $0.pause(); $0.seek(to: 0); return .success }
        register(center.nextTrackCommand) { $0.next(); return .success }
        register(center.previousTrackCommand) { $0.previous(); return .success }
        let target = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let seek = event as? MPChangePlaybackPositionCommandEvent,
                  seek.positionTime.isFinite else { return .commandFailed }
            let time = seek.positionTime
            return Self.onMain {
                guard !self.shutDown, self.currentTrack != nil else { return .noActionableNowPlayingItem }
                self.seek(to: time)
                return .success
            }
        }
        commandTargets.append((center.changePlaybackPositionCommand, target))
        updateRemoteCommands()
    }

    private func register(_ command: MPRemoteCommand,
                          action: @escaping @MainActor (PhonePlayerStore) -> MPRemoteCommandHandlerStatus) {
        let target = command.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return Self.onMain {
                guard !self.shutDown, self.currentTrack != nil else { return .noActionableNowPlayingItem }
                self.cancelSmartShuffle()
                return action(self)
            }
        }
        commandTargets.append((command, target))
    }

    /// MediaPlayer handlers may arrive outside the main actor. Return the actual
    /// action result, while all audio and observable state stays serialized.
    private nonisolated static func onMain(_ action: @MainActor () -> MPRemoteCommandHandlerStatus) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread { return MainActor.assumeIsolated { action() } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { action() } }
    }

    private func updateRemoteCommands() {
        guard connectsSystemPlayback else { return }
        let center = MPRemoteCommandCenter.shared()
        let selected = currentTrack != nil && !shutDown
        center.playCommand.isEnabled = selected
        center.pauseCommand.isEnabled = selected
        center.togglePlayPauseCommand.isEnabled = selected
        center.stopCommand.isEnabled = selected
        center.changePlaybackPositionCommand.isEnabled = selected && duration > 0
        center.nextTrackCommand.isEnabled = selected && ((ordering.currentIndex ?? 0) + 1 < queue.count || repeatMode == .all)
        center.previousTrackCommand.isEnabled = selected
    }

    private func observeAudioSession() {
        let notifications = NotificationCenter.default
        observers.append(notifications.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let type = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue
            let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
            Task { @MainActor [weak self] in self?.interruption(type: type, options: options) }
        })
        observers.append(notifications.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            Task { @MainActor [weak self] in
                guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                self?.pause()
            }
        })
        observers.append(notifications.addObserver(forName: AVAudioSession.mediaServicesWereLostNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pause(); self.audio?.delegate = nil; self.audio = nil
                self.errorMessage = "The audio system stopped. Tap Play to try again."
            }
        })
        observers.append(notifications.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pause(); self.audio?.delegate = nil; self.audio = nil
                self.sessionActive = false; self.interrupted = false
                // Recreate from the captured URL only after an explicit Play.
            }
        })
    }

    private func interruption(type raw: UInt?, options: UInt) {
        guard !shutDown, let raw, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            resumeAfterInterruption = isPlaying
            interrupted = true
            pause(keepingResumeIntent: true)
            sessionActive = false // The system has deactivated the interrupted session.
        case .ended:
            interrupted = false
            let shouldResume = resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
            resumeAfterInterruption = false
            if shouldResume { _ = startPlayback() }
        @unknown default:
            pause(); interrupted = false
        }
    }

    private nonisolated static func assetURL(_ name: String, in directory: URL) throws -> URL {
        guard directory.isFileURL, !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\") else { throw PlaybackError.invalidFile }
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root.appendingPathComponent(name).standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.deletingLastPathComponent() == root else { throw PlaybackError.invalidFile }
        return candidate
    }

    private static func player(for item: Item) throws -> AVAudioPlayer {
        let values = try item.mediaURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { throw PlaybackError.missingFile }
        let player = try AVAudioPlayer(contentsOf: item.mediaURL)
        guard player.duration.isFinite, player.duration > 0 else { throw PlaybackError.invalidAudio }
        return player
    }

    private static func lockScreenArtwork(at url: URL?) -> MPMediaItemArtwork? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: pixels)
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func message(for track: Track, error: Error) -> String {
        "“\(track.displayTitle)” couldn’t play. \(error.localizedDescription)"
    }

    private enum PlaybackError: LocalizedError {
        case invalidFile, missingFile, invalidAudio, couldNotStart
        var errorDescription: String? {
            switch self {
            case .invalidFile: return "This song has an invalid local file reference. Sync it again from Bard on your Mac."
            case .missingFile: return "The downloaded audio is missing. Sync this song again from your Mac."
            case .invalidAudio: return "The audio file is empty or unsupported on this iPhone."
            case .couldNotStart: return "The audio output is unavailable. Try again."
            }
        }
    }
}

extension PhonePlayerStore: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self, weak player] in
            guard let self, let player, self.audio === player, !self.shutDown else { return }
            if flag {
                // A user pause may arrive before this delegate task is delivered.
                // Do not start the next song after that explicit pause.
                guard self.isPlaying else { return }
                self.advance(autoplay: true, userInitiated: false)
            }
            else {
                self.pause()
                self.errorMessage = "This song stopped because its audio could not be decoded."
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self, weak player] in
            guard let self, let player, self.audio === player, !self.shutDown else { return }
            self.pause()
            self.errorMessage = "This song stopped because its audio could not be decoded. \(error?.localizedDescription ?? "")"
        }
    }
}
