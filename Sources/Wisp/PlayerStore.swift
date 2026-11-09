import AppKit
import AVFoundation
import Combine
import CoreAudio
import Foundation
import MediaPlayer
import WispCore

/// Owns the single native audio player. The library supplies managed file URLs;
/// browsing or editing a playlist never recreates the active audio player.
@MainActor
final class PlayerStore: NSObject, ObservableObject {
    @Published private(set) var currentID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var volume: Double = 0.75
    @Published private(set) var shuffle = false
    @Published private(set) var smartShuffle = false
    @Published private(set) var energyCurve = EnergyCurve.flow
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var queueIDs: [UUID] = []
    @Published var errorMessage: String?

    // A separate observable object keeps meter updates local to the tiny meter view.
    let meters = PlaybackMeters()
    let listening: ListeningStore
    let energyAnalysis: SongEnergyAnalysis
    private var energyScores: [String: Double] = [:]
    private var energyRequest = UUID()

    var currentTrack: Track? { currentID.flatMap { store.track(id: $0) } }
    var queue: [Track] { queueIDs.compactMap { store.track(id: $0) } }

    private let store: LibraryStore
    private let defaults: UserDefaults
    private let connectsSystemPlayback: Bool
    private let stateKey = "wisp.native.playback.v1"
    private var ordering = PlaybackQueue()
    private var audio: AVAudioPlayer?
    private var preparedAudioFingerprint: String?
    private var ticker: AnyCancellable?
    private var meterTicker: AnyCancellable?
    private var libraryObservation: AnyCancellable?
    private var sleepObserver: NSObjectProtocol?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var commandTargets: [(command: MPRemoteCommand, target: Any)] = []
    private var failedIDs = Set<UUID>()
    private var lastSave: TimeInterval = 0
    private var stoppedTicks = 0
    private var artworkID: UUID?
    private var artwork: MPMediaItemArtwork?
    private var ownsNowPlaying = false
    private var isShutDown = false

    private struct SavedPlayback: Codable {
        var sourceIDs: [UUID]
        var orderedIDs: [UUID]
        var currentID: UUID?
        var position: Double
        var volume: Double
        var shuffle: Bool
        var repeatMode: RepeatMode
        var smartShuffle: Bool?
        var energyCurve: EnergyCurve?
        var energyScores: [String: Double]?
    }

    init(store: LibraryStore, listening: ListeningStore? = nil,
         defaults: UserDefaults = .standard, connectSystemPlayback: Bool = true) {
        self.store = store
        self.listening = listening ?? ListeningStore(directory: store.directory)
        self.energyAnalysis = SongEnergyAnalysis(directory: store.directory)
        self.defaults = defaults
        self.connectsSystemPlayback = connectSystemPlayback
        super.init()
        restorePaused()
        if connectsSystemPlayback {
            configureRemoteCommands()
            observeOutputChanges()
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        }
        // @Published emits before its property is changed. Deliver on the next main
        // turn so lookups in LibraryStore see the committed document.
        libraryObservation = store.$document.dropFirst().receive(on: RunLoop.main).sink { [weak self] document in
            self?.libraryChanged(available: Set(document.tracks.map(\.id)))
        }
    }

    func play(ids: [UUID], startID: UUID? = nil) {
        guard !isShutDown, !WispInput.instrumentPresented else { return }
        if energyAnalysis.isAnalyzing { cancelSmartShuffle() }
        let available = Set(store.tracks.map(\.id))
        let valid = ids.filter { available.contains($0) }
        guard !valid.isEmpty else { return }
        errorMessage = nil
        failedIDs.removeAll()
        if smartShuffle && !hasEnergy(for: valid) { smartShuffle = false }
        let randomize = queueRandomizer(after: startID)
        let candidate = ordering.start(ids: valid, startID: startID, shuffled: shuffle, randomize: randomize)
        publishQueue()
        ownsNowPlaying = connectsSystemPlayback
        prepare(candidate: candidate, autoplay: true)
    }

    func toggle() {
        guard !isShutDown, !WispInput.instrumentPresented else { return }
        if isPlaying { pause(); return }
        errorMessage = nil
        ownsNowPlaying = connectsSystemPlayback
        if let audio, currentID != nil {
            let replay = position >= duration - 0.05
            if replay { listening.end(); audio.currentTime = 0; position = 0 }
            guard audio.play() else {
                failCurrent("This track could not start playing.")
                return
            }
            isPlaying = true
            beginListening(newRun: replay)
            startTicker()
            publishNowPlaying()
            save()
        } else if let candidate = ordering.currentID ?? ordering.orderedIDs.first {
            failedIDs.removeAll()
            prepare(candidate: candidate, autoplay: true)
        } else {
            play(ids: store.tracks.sorted { $0.addedAt > $1.addedAt }.map(\.id))
        }
    }

    func pause() {
        sampleListening()
        if let audio {
            if audio.isPlaying { position = audio.currentTime }
            audio.pause()
        }
        isPlaying = false
        listening.flush()
        stopTicker()
        publishNowPlaying()
        save()
    }

    func stop() {
        cancelSmartShuffle()
        unload()
        ordering.clear()
        publishQueue()
        currentID = nil
        position = 0
        duration = 0
        artwork = nil
        artworkID = nil
        if ownsNowPlaying {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            ownsNowPlaying = false
        }
        save()
    }

    func next() {
        guard !isShutDown, !WispInput.instrumentPresented, currentID != nil else { return }
        let autoplay = isPlaying
        if let candidate = advancePastFailures(userInitiated: true) {
            prepare(candidate: candidate, autoplay: autoplay)
        } else {
            finishQueue()
        }
    }

    func previous() {
        guard !isShutDown, !WispInput.instrumentPresented, currentID != nil else { return }
        if position > 3 { seek(to: 0); return }
        let autoplay = isPlaying
        guard let candidate = ordering.previous(repeating: repeatMode) else { return }
        failedIDs.remove(candidate)
        prepare(candidate: candidate, autoplay: autoplay)
    }

    func seek(to seconds: Double) {
        guard !WispInput.instrumentPresented, let audio, seconds.isFinite else { return }
        sampleListening()
        let target = min(max(0, seconds), duration)
        audio.currentTime = target
        listening.resetBaseline(position: target)
        position = target
        publishNowPlaying()
        save()
    }

    func setVolume(_ value: Double) {
        guard value.isFinite else { return }
        volume = min(max(value, 0), 1)
        audio?.volume = Float(volume)
        save()
    }

    func setShuffle(_ enabled: Bool) {
        if energyAnalysis.isAnalyzing { cancelSmartShuffle() }
        let wasSmart = smartShuffle
        shuffle = enabled
        smartShuffle = false
        if enabled && ordering.isShuffled && wasSmart { ordering.reshuffleUpcoming { $0.shuffled() } }
        else { ordering.setShuffled(enabled) }
        publishQueue()
        if connectsSystemPlayback {
            MPRemoteCommandCenter.shared().changeShuffleModeCommand.currentShuffleType = enabled ? .items : .off
        }
        save()
    }

    /// Analysis prepares a complete measured order before touching playback.
    /// A failed/cancelled scan or changed audio leaves the existing queue intact.
    func startSmartShuffle(ids: [UUID], curve: EnergyCurve, limit: Int? = 20) async -> Bool {
        guard !isShutDown, !WispInput.instrumentPresented, !energyAnalysis.isAnalyzing else { return false }
        var seen = Set<UUID>()
        let selected = ids.filter { seen.insert($0).inserted }.compactMap { store.track(id: $0) }
        guard !selected.isEmpty, selected.count == seen.count else {
            errorMessage = "Some songs are no longer in this collection. Reopen Smart Shuffle and try again."; return false
        }
        let request = UUID(); energyRequest = request
        errorMessage = nil
        do {
            let scores = try await energyAnalysis.measure(selected.map {
                SongEnergyAnalysis.Item(fingerprint: $0.fingerprint, title: $0.title, url: store.audioURL(for: $0))
            })
            try Task.checkCancellation()
            guard energyRequest == request, !isShutDown, !WispInput.instrumentPresented else { throw CancellationError() }
            guard selected.allSatisfy({ store.track(id: $0.id)?.fingerprint == $0.fingerprint }) else {
                errorMessage = "A song changed during the energy scan. Try Smart Shuffle again."; return false
            }
            let byID = Dictionary(uniqueKeysWithValues: selected.compactMap { track in scores[track.fingerprint].map { (track.id, $0) } })
            guard let plan = EnergyShuffle.order(ids: selected.map(\.id), tracks: selected, scores: byID, curve: curve, count: limit), !plan.isEmpty else {
                errorMessage = "The energy scan did not produce a complete set. The queue is unchanged."; return false
            }
            energyScores = scores; energyCurve = curve
            smartShuffle = true; shuffle = true
            if connectsSystemPlayback { MPRemoteCommandCenter.shared().changeShuffleModeCommand.currentShuffleType = .items }
            let included = Set(plan)
            let source = selected.map(\.id).filter(included.contains)
            failedIDs.removeAll()
            let candidate = ordering.start(ids: source, shuffled: true, randomize: { _ in plan })
            publishQueue()
            ownsNowPlaying = connectsSystemPlayback
            prepare(candidate: candidate, autoplay: true)
            return true
        } catch is CancellationError { return false }
        catch { errorMessage = error.localizedDescription; return false }
    }

    func cancelSmartShuffle() { energyRequest = UUID(); energyAnalysis.cancel() }

    private func hasEnergy(for ids: [UUID]) -> Bool {
        ids.allSatisfy { id in
            guard let track = store.track(id: id), let score = energyScores[track.fingerprint] else { return false }
            return score.isFinite && (0...1).contains(score)
        }
    }

    private func queueRandomizer(after previousID: UUID?) -> ([UUID]) -> [UUID] {
        guard smartShuffle else { return { $0.shuffled() } }
        let tracks = store.tracks, curve = energyCurve
        let scores = Dictionary(uniqueKeysWithValues: tracks.compactMap { track in
            energyScores[track.fingerprint].map { (track.id, $0) }
        })
        return { ids in
            EnergyShuffle.order(ids: ids, tracks: tracks, scores: scores, curve: curve, after: previousID) ?? ids
        }
    }

    func toggleShuffle() { setShuffle(!shuffle) }

    func cycleRepeat() {
        setRepeat(repeatMode.next)
    }

    /// Select a queued track without creating a new queue or reshuffling it.
    func playQueued(id: UUID) {
        guard !isShutDown, !WispInput.instrumentPresented, ordering.orderedIDs.contains(id), store.track(id: id) != nil else { return }
        if energyAnalysis.isAnalyzing { cancelSmartShuffle() }
        if currentID == id {
            if !isPlaying { toggle() }
            return
        }
        errorMessage = nil
        failedIDs.remove(id)
        ownsNowPlaying = connectsSystemPlayback
        prepare(candidate: id, autoplay: true)
    }

    func moveQueued(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard !isShutDown, ordering.move(fromOffsets: offsets, toOffset: destination) else { return }
        publishQueue()
        publishNowPlaying()
        save()
    }

    func moveQueued(id: UUID, offset: Int) {
        guard !isShutDown, ordering.move(id: id, offset: offset) else { return }
        publishQueue()
        publishNowPlaying()
        save()
    }

    func removeQueued(id: UUID) {
        guard !isShutDown else { return }
        let wasCurrent = id == currentID
        let autoplay = isPlaying
        let successor = ordering.remove(Set([id]), repeating: repeatMode)
        publishQueue()
        failedIDs.remove(id)
        if wasCurrent {
            if let successor { prepare(candidate: successor, autoplay: autoplay) }
            else { clearSelectionKeepingQueue() }
        } else {
            publishNowPlaying()
            save()
        }
    }

    /// Called by the app's termination handler. Closing the window may keep playing;
    /// quitting the app always pauses and saves before removing system handlers.
    func shutdown() {
        guard !isShutDown else { return }
        cancelSmartShuffle()
        pause()
        isShutDown = true
        audio?.delegate = nil
        audio?.stop()
        audio = nil
        libraryObservation?.cancel()
        libraryObservation = nil
        for registration in commandTargets {
            registration.command.removeTarget(registration.target)
        }
        commandTargets.removeAll()
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
        if let outputListener {
            var address = Self.outputAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, outputListener
            )
            self.outputListener = nil
        }
        if ownsNowPlaying {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
    }

    // MARK: - Audio lifecycle

    private func prepare(candidate initialID: UUID?, autoplay: Bool, resumeAt: Double = 0) {
        guard !isShutDown else { return }
        // Decoder callbacks and library reconciliation also arrive here without
        // passing a user command. They must never restart playback over Remix.
        let autoplay = autoplay && !WispInput.instrumentPresented
        unload()
        var candidate = initialID
        var attempted = Set<UUID>()
        var lastFailure: String?
        while let id = candidate, attempted.insert(id).inserted {
            guard let track = store.track(id: id) else {
                failedIDs.insert(id)
                candidate = advancePastFailures(userInitiated: true)
                continue
            }
            do {
                let url = store.audioURL(for: track)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw PlaybackFailure.missing(track.title)
                }
                let nextAudio = try AVAudioPlayer(contentsOf: url)
                guard nextAudio.duration.isFinite, nextAudio.duration > 0, nextAudio.prepareToPlay() else {
                    throw PlaybackFailure.unreadable(track.title)
                }
                nextAudio.volume = Float(volume)
                nextAudio.isMeteringEnabled = true
                nextAudio.numberOfLoops = 0
                nextAudio.delegate = self
                let requestedPosition = id == initialID && resumeAt.isFinite ? resumeAt : 0
                let resume = min(max(requestedPosition, 0), nextAudio.duration)
                nextAudio.currentTime = resume
                audio = nextAudio
                preparedAudioFingerprint = track.fingerprint
                _ = ordering.select(id)
                currentID = id
                duration = nextAudio.duration
                position = resume
                if autoplay {
                    if resume >= duration - 0.05 { nextAudio.currentTime = 0; position = 0 }
                    guard nextAudio.play() else { throw PlaybackFailure.unreadable(track.title) }
                    isPlaying = true
                    beginListening(newRun: true)
                    startTicker()
                }
                publishQueue()
                publishNowPlaying(rebuildArtwork: true)
                save()
                if let lastFailure { errorMessage = lastFailure }
                return
            } catch {
                audio?.delegate = nil
                audio?.stop()
                audio = nil
                isPlaying = false
                failedIDs.insert(id)
                lastFailure = (error as? PlaybackFailure)?.localizedDescription
                    ?? "“\(track.title)” could not be played. The file may use an unsupported audio format."
                candidate = advancePastFailures(userInitiated: true)
            }
        }
        clearSelectionKeepingQueue()
        errorMessage = lastFailure ?? "No playable tracks remain in this queue."
    }

    private func unload() {
        sampleListening()
        listening.end()
        stopTicker()
        audio?.delegate = nil
        audio?.stop()
        audio = nil
        preparedAudioFingerprint = nil
        isPlaying = false
    }

    private func clearSelectionKeepingQueue() {
        unload()
        currentID = nil
        position = 0
        duration = 0
        publishQueue()
        publishNowPlaying(rebuildArtwork: true)
        save()
    }

    private func advancePastFailures(userInitiated: Bool) -> UUID? {
        if smartShuffle && !hasEnergy(for: ordering.sourceIDs) { smartShuffle = false }
        let randomize = queueRandomizer(after: ordering.currentID)
        return ordering.nextPlayable(
            repeating: repeatMode, userInitiated: userInitiated, excluding: failedIDs, randomize: randomize
        )
    }

    private func failCurrent(_ message: String) {
        errorMessage = message
        if let currentID { failedIDs.insert(currentID) }
        if let candidate = advancePastFailures(userInitiated: true) {
            prepare(candidate: candidate, autoplay: true)
        } else {
            clearSelectionKeepingQueue()
        }
    }

    private func finishQueue() {
        sampleListening()
        listening.end()
        audio?.pause()
        if let audio { audio.currentTime = audio.duration }
        isPlaying = false
        position = duration
        stopTicker()
        publishQueue()
        publishNowPlaying()
        save()
    }

    private func libraryChanged(available: Set<UUID>) {
        guard !isShutDown else { return }
        let oldCurrent = currentID
        let autoplay = isPlaying
        let successor = ordering.retainAvailable(available, repeating: repeatMode)
        failedIDs.formIntersection(available)
        publishQueue()
        if let oldCurrent, !available.contains(oldCurrent) {
            if let successor { prepare(candidate: successor, autoplay: autoplay) }
            else { clearSelectionKeepingQueue() }
        } else if let oldCurrent, let updated = store.track(id: oldCurrent),
                  let preparedAudioFingerprint, updated.fingerprint != preparedAudioFingerprint {
            // A version change retains the song and queue but must unload the old
            // audio buffer. Pause at the saved position so Save never starts a
            // different recording unexpectedly; resume uses the new file.
            let savedPosition = audio?.currentTime ?? position
            prepare(candidate: oldCurrent, autoplay: false, resumeAt: savedPosition)
        } else {
            // Updated titles and artwork are reflected without interrupting audio.
            objectWillChange.send()
            publishNowPlaying()
            save()
        }
    }

    private func beginListening(newRun: Bool) {
        guard let track = currentTrack, let audio else { return }
        listening.beginOrResume(track: track, duration: duration,
                                position: audio.currentTime, newRun: newRun)
    }

    private func sampleListening() {
        guard isPlaying, let audio else { return }
        listening.sample(position: audio.currentTime, track: currentTrack)
    }

    // MARK: - Time and restoration

    private func startTicker() {
        stopTicker()
        stoppedTicks = 0
        ticker = Timer.publish(every: 0.25, tolerance: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
        meterTicker = Timer.publish(every: 1.0 / 12.0, tolerance: 0.025, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.sampleMeters() }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
        meterTicker?.cancel()
        meterTicker = nil
        meters.clear()
        stoppedTicks = 0
    }

    private func sampleMeters() {
        guard let audio, isPlaying, audio.isPlaying, audio.numberOfChannels > 0 else { meters.clear(); return }
        audio.updateMeters()
        let rightChannel = min(1, max(0, audio.numberOfChannels - 1))
        meters.update(left: audio.averagePower(forChannel: 0), right: audio.averagePower(forChannel: rightChannel))
    }

    private func tick() {
        guard let audio, isPlaying else { return }
        if audio.isPlaying {
            stoppedTicks = 0
            position = min(max(audio.currentTime, 0), duration)
            sampleListening()
        } else {
            // Allow the finish delegate to run before treating an unexpected stop
            // as an interruption. Never resume an interruption automatically.
            stoppedTicks += 1
            if stoppedTicks >= 2 { pause(); return }
        }
        if Date.timeIntervalSinceReferenceDate - lastSave >= 2 {
            publishNowPlaying()
            save()
        }
    }

    private func save() {
        lastSave = Date.timeIntervalSinceReferenceDate
        let state = SavedPlayback(
            sourceIDs: ordering.sourceIDs, orderedIDs: ordering.orderedIDs,
            currentID: currentID, position: position, volume: volume,
            shuffle: shuffle, repeatMode: repeatMode,
            smartShuffle: smartShuffle, energyCurve: energyCurve, energyScores: smartShuffle ? energyScores : nil
        )
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: stateKey) }
    }

    private func restorePaused() {
        guard let data = defaults.data(forKey: stateKey),
              let saved = try? JSONDecoder().decode(SavedPlayback.self, from: data) else { return }
        volume = saved.volume.isFinite ? min(max(saved.volume, 0), 1) : 0.75
        shuffle = saved.shuffle
        energyCurve = saved.energyCurve ?? .flow
        energyScores = (saved.energyScores ?? [:]).filter { $0.value.isFinite && (0...1).contains($0.value) }
        smartShuffle = saved.shuffle && saved.smartShuffle == true
        repeatMode = saved.repeatMode
        let available = Set(store.tracks.map(\.id))
        ordering = PlaybackQueue(
            sourceIDs: saved.sourceIDs.filter { available.contains($0) },
            orderedIDs: saved.orderedIDs,
            currentID: saved.currentID,
            isShuffled: saved.shuffle
        )
        if smartShuffle && !hasEnergy(for: ordering.sourceIDs) { smartShuffle = false }
        publishQueue()
        if let candidate = ordering.currentID {
            prepare(candidate: candidate, autoplay: false, resumeAt: saved.position)
        }
    }

    private func publishQueue() { queueIDs = ordering.orderedIDs }

    // MARK: - System playback

    private func setRepeat(_ mode: RepeatMode) {
        repeatMode = mode
        guard connectsSystemPlayback else { save(); return }
        let command = MPRemoteCommandCenter.shared().changeRepeatModeCommand
        switch mode {
        case .off: command.currentRepeatType = .off
        case .all: command.currentRepeatType = .all
        case .one: command.currentRepeatType = .one
        }
        save()
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        register(center.playCommand) { player in if !player.isPlaying { player.toggle() } }
        register(center.pauseCommand) { $0.pause() }
        register(center.togglePlayPauseCommand) { $0.toggle() }
        register(center.stopCommand) { $0.stop() }
        register(center.nextTrackCommand) { $0.next() }
        register(center.previousTrackCommand) { $0.previous() }

        center.changePlaybackPositionCommand.isEnabled = true
        let seekTarget = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let time = event.positionTime
            Task { @MainActor in self.seek(to: time) }
            return .success
        }
        commandTargets.append((center.changePlaybackPositionCommand, seekTarget))

        center.changeShuffleModeCommand.isEnabled = true
        center.changeShuffleModeCommand.currentShuffleType = shuffle ? .items : .off
        let shuffleTarget = center.changeShuffleModeCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            let enabled = event.shuffleType != .off
            Task { @MainActor in self.setShuffle(enabled) }
            return .success
        }
        commandTargets.append((center.changeShuffleModeCommand, shuffleTarget))

        center.changeRepeatModeCommand.isEnabled = true
        let repeatTarget = center.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            let mode: RepeatMode = event.repeatType == .one ? .one : event.repeatType == .all ? .all : .off
            Task { @MainActor in self.setRepeat(mode) }
            return .success
        }
        commandTargets.append((center.changeRepeatModeCommand, repeatTarget))
        setRepeat(repeatMode)
        center.changePlaybackRateCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }

    private func register(_ command: MPRemoteCommand, action: @escaping @MainActor (PlayerStore) -> Void) {
        command.isEnabled = true
        let target = command.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in action(self) }
            return .success
        }
        commandTargets.append((command, target))
    }

    private func publishNowPlaying(rebuildArtwork: Bool = false) {
        // Restoring a paused selection must not take over another app's Now Playing.
        guard ownsNowPlaying else { return }
        let center = MPNowPlayingInfoCenter.default()
        guard let track = currentTrack else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        if rebuildArtwork || artworkID != track.id {
            artworkID = track.id
            artwork = nil
            if let url = store.artworkURL(for: track), let image = NSImage(contentsOf: url) {
                artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            }
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.displayTitle,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.displayOrigin,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackQueueCount: queueIDs.count
        ]
        if let index = ordering.currentIndex { info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    private static var outputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func observeOutputChanges() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                // Bluetooth loss or an output-device switch should not surprise the
                // listener by continuing through a different set of speakers.
                if self?.isPlaying == true { self?.pause() }
            }
        }
        var address = Self.outputAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
        )
        if status == 0 { outputListener = listener }
    }

    private enum PlaybackFailure: LocalizedError {
        case missing(String)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .missing(let title): return "“\(title)” is missing from Bard’s library folder. Reimport the original file to play it again."
            case .unreadable(let title): return "“\(title)” could not be played. The file may be damaged or use an unsupported audio format."
            }
        }
    }
}

extension PlayerStore: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === audio else { return }
        if !flag {
            failCurrent("This track stopped because its audio could not be decoded.")
            return
        }
        guard isPlaying else { return }
        // AVAudioPlayer may reset currentTime before delivering its finish callback.
        // Only successful natural completion can use the known endpoint.
        listening.sample(position: duration, track: currentTrack)
        listening.end()
        if let candidate = advancePastFailures(userInitiated: false) {
            prepare(candidate: candidate, autoplay: true)
        } else {
            finishQueue()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard player === audio else { return }
        failCurrent("This track stopped because its audio could not be decoded.")
    }

    func audioPlayerBeginInterruption(_ player: AVAudioPlayer) {
        guard player === audio else { return }
        pause()
    }
}

/// Actual channel power from AVAudioPlayer, mapped from -60...0 dB to the meter scale.
/// These are level meters, not a spectrum analyzer or a synthesized waveform.
@MainActor
final class PlaybackMeters: ObservableObject {
    struct Levels: Equatable {
        var left: Double = 0
        var right: Double = 0
    }

    @Published private(set) var levels = Levels()

    func update(left: Float, right: Float) {
        func normalized(_ decibels: Float) -> Double {
            guard decibels.isFinite else { return 0 }
            return min(1, max(0, (Double(decibels) + 60) / 60))
        }
        let next = Levels(left: normalized(left), right: normalized(right))
        if next != levels { levels = next }
    }

    func clear() {
        if levels != Levels() { levels = Levels() }
    }
}
