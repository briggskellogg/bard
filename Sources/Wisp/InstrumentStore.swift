import AppKit
import AVFoundation
import Combine
import Foundation

public enum SoundKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case air, pulse, glass

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// A separate output-only instrument. It never opens the microphone or changes playback.
@MainActor
final class InstrumentStore: ObservableObject {
    static let shared = InstrumentStore()
    @Published var sound: SoundKind = .air { didSet { publishParameters() } }
    @Published var echo = false { didSet { publishParameters() } }
    @Published var volume: Double = 0.20 {
        didSet {
            let bounded = Self.clamp(volume, 0...0.5, fallback: 0.20)
            if volume != bounded { volume = bounded; return }
            publishParameters()
            if isLoopPlaying { rampLoopVolume(to: loopOutputVolume) }
        }
    }
    @Published var quantized = true { didSet { updatePitch(); publishParameters() } }
    @Published var rootNote = 9 {
        didSet {
            let bounded = min(11, max(0, rootNote))
            if rootNote != bounded { rootNote = bounded; return }
            updatePitch()
            publishParameters()
        }
    }
    @Published private(set) var active = false
    @Published private(set) var noteName = "A3"
    @Published var errorMessage: String?
    @Published private(set) var isRecording = false
    @Published private(set) var recordingElapsed = 0.0
    @Published private(set) var hasLoop = false
    @Published private(set) var loopDuration = 0.0
    @Published private(set) var isLoopPlaying = false
    @Published private(set) var isLoopMuted = false
    @Published private(set) var isPreparingLoop = false
    @Published private(set) var savedPhrases: [InstrumentPhraseSummary] = []
    @Published private(set) var currentPhraseID: UUID?
    @Published private(set) var isSavingPhrase = false

    private var x = 0.0
    private var y = 0.5
    private var frequency = 220.0
    private let parameters = InstrumentParameterBridge()
    private var engine: AVAudioEngine?
    private var source: AVAudioSourceNode?
    private var idleStopTask: Task<Void, Never>?
    private var resignObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var configurationObserver: NSObjectProtocol?
    private var loopPlayer: AVAudioPlayerNode?
    private var preparedLoop: PreparedInstrumentPhrase?
    private var loopScheduled = false
    private var phrase: InstrumentPhrase?
    private let repository: InstrumentPhraseRepository
    private let outputVolume: Float
    private var recordingStart = 0.0
    private var recordedEvents: [InstrumentPhrase.Event] = []
    private var recordingTimer: Timer?
    private var renderTask: Task<PreparedInstrumentPhrase, Error>?
    private var renderID = UUID()
    private var loopVolumeTask: Task<Void, Never>?
    private var libraryRefreshID = UUID()

    init(loopsDirectory: URL = InstrumentPhraseRepository.defaultDirectory, outputVolume: Float = 1) {
        repository = InstrumentPhraseRepository(directory: loopsDirectory)
        self.outputVolume = outputVolume.isFinite ? min(1, max(0, outputVolume)) : 1
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] notification in
            guard let changedEngine = notification.object as? AVAudioEngine else { return }
            Task { @MainActor in
                guard let self, self.engine === changedEngine else { return }
                self.stop()
            }
        }
        refreshSavedPhrases()
    }

    deinit {
        idleStopTask?.cancel()
        recordingTimer?.invalidate()
        renderTask?.cancel()
        loopVolumeTask?.cancel()
        engine?.stop()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }

    func touch(x: Double, y: Double) {
        idleStopTask?.cancel()
        idleStopTask = nil
        self.x = Self.clamp(x, 0...1, fallback: 0.5)
        self.y = Self.clamp(y, 0...1, fallback: 0.5)
        updatePitch()
        do {
            try startEngineIfNeeded()
            if !active { active = true }
            errorMessage = nil
            publishParameters()
        } catch {
            stop()
            errorMessage = "The instrument could not start audio output. \(error.localizedDescription)"
        }
    }

    func release() {
        guard active else { return }
        active = false
        publishParameters()
        scheduleIdleStop()
    }

    func stop() {
        if isRecording { finishRecording(autoplay: false) }
        idleStopTask?.cancel()
        idleStopTask = nil
        renderID = UUID()
        renderTask?.cancel()
        renderTask = nil
        isPreparingLoop = false
        loopVolumeTask?.cancel()
        loopVolumeTask = nil
        isLoopPlaying = false
        loopPlayer?.stop()
        loopScheduled = false
        if active { active = false }
        publishParameters()
        engine?.stop()
        if let source { engine?.detach(source) }
        if let loopPlayer { engine?.detach(loopPlayer) }
        source = nil
        loopPlayer = nil
        engine = nil
    }

    func beginRecording() {
        guard !isRecording, !isPreparingLoop else { return }
        pauseLoop()
        renderTask?.cancel()
        preparedLoop = nil
        phrase = nil
        hasLoop = false
        loopDuration = 0
        currentPhraseID = nil
        isLoopMuted = false
        recordedEvents = [.init(time: 0, parameters: phraseParameters(currentParameters))]
        recordingStart = ProcessInfo.processInfo.systemUptime
        recordingElapsed = 0
        isRecording = true
        errorMessage = nil
        idleStopTask?.cancel()
        recordingTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.recordingElapsed = min(InstrumentPhrase.maximumDuration, self.elapsedRecordingTime)
                if self.recordingElapsed >= InstrumentPhrase.maximumDuration { self.finishRecording() }
            }
        }
        recordingTimer = timer
        // Keep the duration cap active while AppKit is tracking a held pointer.
        RunLoop.main.add(timer, forMode: .common)
    }

    func finishRecording() { finishRecording(autoplay: true) }

    private func finishRecording(autoplay: Bool) {
        guard isRecording else { return }
        let duration = min(InstrumentPhrase.maximumDuration, max(0.15, elapsedRecordingTime))
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingElapsed = duration
        let newPhrase = InstrumentPhrase(id: UUID(), name: "", createdAt: Date(), duration: duration, events: recordedEvents)
        recordedEvents.removeAll(keepingCapacity: false)
        guard newPhrase.isValid else {
            errorMessage = InstrumentPhraseError.noSound.localizedDescription
            scheduleIdleStop()
            return
        }
        phrase = newPhrase
        hasLoop = true
        loopDuration = duration
        if autoplay { prepareLoop(newPhrase, autoplay: true) }
        else { scheduleIdleStop() }
    }

    func toggleLoopPlayback() {
        guard hasLoop, !isRecording, !isPreparingLoop else { return }
        if isLoopPlaying { pauseLoop(); scheduleIdleStop() }
        else if preparedLoop != nil { playPreparedLoop() }
        else if let phrase { prepareLoop(phrase, autoplay: true) }
    }

    func toggleLoopMute() {
        guard hasLoop else { return }
        isLoopMuted.toggle()
        if isLoopPlaying { rampLoopVolume(to: loopOutputVolume) }
    }

    func removeLoop() {
        pauseLoop()
        renderID = UUID()
        renderTask?.cancel()
        renderTask = nil
        isPreparingLoop = false
        loopPlayer?.stop()
        loopScheduled = false
        preparedLoop = nil
        phrase = nil
        hasLoop = false
        loopDuration = 0
        currentPhraseID = nil
        isLoopMuted = false
        scheduleIdleStop()
    }

    func saveLoop(name: String = "") {
        guard var saved = phrase, !isRecording, !isSavingPhrase else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { saved.name = String(trimmed.prefix(100)) }
        else if saved.name.isEmpty { saved.name = "Phrase · " + DateFormatter.localizedString(from: saved.createdAt, dateStyle: .short, timeStyle: .short) }
        isSavingPhrase = true
        let repository = repository
        Task { [weak self] in
            do {
                try await Task.detached(priority: .utility) { try repository.save(saved) }.value
                guard let self else { return }
                if self.phrase?.id == saved.id { self.phrase = saved; self.currentPhraseID = saved.id }
                self.isSavingPhrase = false
                self.refreshSavedPhrases()
            } catch {
                self?.isSavingPhrase = false
                self?.errorMessage = "The phrase could not be saved. \(error.localizedDescription)"
            }
        }
    }

    func loadPhrase(id: UUID) {
        guard !isRecording else { return }
        let request = UUID()
        renderID = request
        renderTask?.cancel()
        renderTask = nil
        isPreparingLoop = true
        pauseLoop()
        let repository = repository
        Task { [weak self] in
            do {
                let loaded = try await Task.detached(priority: .utility) { try repository.load(id: id) }.value
                guard let self, self.renderID == request else { return }
                self.preparedLoop = nil
                self.phrase = loaded
                self.hasLoop = true
                self.loopDuration = loaded.duration
                self.currentPhraseID = loaded.id
                self.isLoopMuted = false
                self.errorMessage = nil
                // Reopening a saved phrase is deliberately silent until Play.
                self.prepareLoop(loaded, autoplay: false)
            } catch {
                guard let self, self.renderID == request else { return }
                self.isPreparingLoop = false
                self.errorMessage = "The phrase could not be opened. \(error.localizedDescription)"
            }
        }
    }

    func deletePhrase(id: UUID) {
        let repository = repository
        Task { [weak self] in
            do {
                try await Task.detached(priority: .utility) { try repository.delete(id: id) }.value
                if self?.currentPhraseID == id { self?.currentPhraseID = nil }
                self?.refreshSavedPhrases()
            } catch { self?.errorMessage = "The saved phrase could not be removed. \(error.localizedDescription)" }
        }
    }

    private var elapsedRecordingTime: Double { max(0, ProcessInfo.processInfo.systemUptime - recordingStart) }

    private func phraseParameters(_ value: InstrumentRenderParameters) -> InstrumentRenderParameters {
        var normalized = value
        // Expression is saved at a reference level so one volume slider controls
        // both the live voice and any phrase, including phrases saved earlier.
        normalized.gain = 0.5 * (0.20 + 0.80 * value.brightness)
        return normalized
    }

    private func captureParameters(_ liveValue: InstrumentRenderParameters) {
        guard isRecording else { return }
        let value = phraseParameters(liveValue)
        let time = min(InstrumentPhrase.maximumDuration, elapsedRecordingTime)
        guard recordedEvents.last?.parameters != value else { return }
        if let last = recordedEvents.last, last.parameters.gate == value.gate,
           time - last.time < 1.0 / 120, recordedEvents.count > 1 {
            recordedEvents[recordedEvents.count - 1] = .init(time: time, parameters: value)
        } else if recordedEvents.count < InstrumentPhrase.maximumEvents {
            recordedEvents.append(.init(time: time, parameters: value))
        } else {
            // Bound even synthetic pointer floods; completing retains the whole
            // phrase recorded so far instead of dropping a release event.
            finishRecording()
        }
        if time >= InstrumentPhrase.maximumDuration { finishRecording() }
    }

    private func refreshSavedPhrases() {
        let request = UUID()
        libraryRefreshID = request
        let repository = repository
        Task { [weak self] in
            do {
                let summaries = try await Task.detached(priority: .utility) { try repository.list() }.value
                guard let self, self.libraryRefreshID == request else { return }
                self.savedPhrases = summaries
            } catch { self?.errorMessage = "Saved phrases could not be read. \(error.localizedDescription)" }
        }
    }

    private func prepareLoop(_ phrase: InstrumentPhrase, autoplay: Bool) {
        renderTask?.cancel()
        let request = UUID()
        renderID = request
        isPreparingLoop = true
        let job = Task.detached(priority: .userInitiated) { try InstrumentPhraseRenderer.render(phrase) }
        renderTask = job
        Task { [weak self] in
            do {
                let prepared = try await job.value
                guard let self, self.renderID == request else { return }
                self.preparedLoop = prepared
                self.loopPlayer?.stop()
                self.loopScheduled = false
                self.renderTask = nil
                self.isPreparingLoop = false
                if autoplay { self.playPreparedLoop() }
            } catch {
                guard let self, self.renderID == request else { return }
                self.renderTask = nil
                self.isPreparingLoop = false
                if !(error is CancellationError) { self.errorMessage = error.localizedDescription }
            }
        }
    }

    private func playPreparedLoop() {
        guard let preparedLoop else { return }
        do {
            try startEngineIfNeeded()
            guard let loopPlayer else { return }
            idleStopTask?.cancel()
            if !loopScheduled {
                loopPlayer.scheduleBuffer(preparedLoop.buffer, at: nil, options: [.loops])
                loopScheduled = true
            }
            loopVolumeTask?.cancel()
            if !loopPlayer.isPlaying {
                loopPlayer.volume = 0
                loopPlayer.play()
            }
            isLoopPlaying = true
            rampLoopVolume(to: loopOutputVolume)
            errorMessage = nil
        } catch {
            stop()
            errorMessage = "The loop could not start audio output. \(error.localizedDescription)"
        }
    }

    private func pauseLoop() {
        isLoopPlaying = false
        rampLoopVolume(to: 0, pauseWhenFinished: true)
    }

    private var loopOutputVolume: Float { isLoopMuted ? 0 : Float(volume * 2) }

    var isAudioRunning: Bool { engine?.isRunning == true }
    var isLoopAudioRunning: Bool { isAudioRunning && loopPlayer?.isPlaying == true }

    private func rampLoopVolume(to target: Float, pauseWhenFinished: Bool = false) {
        loopVolumeTask?.cancel()
        guard let player = loopPlayer else { return }
        let start = player.volume
        let mixer = engine?.mainMixerNode
        let mixerStart = mixer?.outputVolume ?? outputVolume
        let mixerTarget = outputVolume * (isLoopPlaying && !isLoopMuted ? InstrumentMix.loopHeadroom : 1)
        loopVolumeTask = Task { @MainActor [weak self, weak player] in
            for step in 1...10 {
                do { try await Task.sleep(nanoseconds: 4_000_000) } catch { return }
                guard let self, let player, self.loopPlayer === player else { return }
                let mixGain = mixerStart + (mixerTarget - mixerStart) * Float(step) / 10
                if mixerTarget < mixerStart { mixer?.outputVolume = mixGain }
                player.volume = start + (target - start) * Float(step) / 10
                if mixerTarget >= mixerStart { mixer?.outputVolume = mixGain }
            }
            if pauseWhenFinished {
                player?.stop()
                self?.loopScheduled = false
            }
        }
    }

    private func scheduleIdleStop() {
        idleStopTask?.cancel()
        guard !isRecording, !isLoopPlaying, !isPreparingLoop else { return }
        idleStopTask = Task { @MainActor [weak self] in
            // The release and feedback delay finish before reclaiming the graph.
            do { try await Task.sleep(nanoseconds: 2_400_000_000) } catch { return }
            guard let self, !self.active, !self.isRecording, !self.isLoopPlaying, !self.isPreparingLoop else { return }
            self.stop()
        }
    }

    private func updatePitch() {
        let midi = Self.midiNote(x: x, rootNote: rootNote, quantized: quantized)
        frequency = 440 * pow(2, (midi - 69) / 12)
        let nearest = Int(midi.rounded())
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        let cents = Int(((midi - Double(nearest)) * 100).rounded())
        let base = "\(names[nearest % 12])\(nearest / 12 - 1)"
        let label = !quantized && cents != 0 ? "\(base) \(cents > 0 ? "+" : "")\(cents)¢" : base
        if noteName != label { noteName = label }
    }

    /// MIDI note range spans two octaves, using nearest notes of a minor pentatonic scale.
    static func midiNote(x: Double, rootNote: Int, quantized: Bool) -> Double {
        let position = clamp(x, 0...1, fallback: 0.5) * 24
        let root = Double(48 + min(11, max(0, rootNote)))
        guard quantized else { return root + position }
        let steps: [Double] = [0, 3, 5, 7, 10, 12, 15, 17, 19, 22, 24]
        return root + (steps.min(by: { abs($0 - position) < abs($1 - position) }) ?? 0)
    }

    private var currentParameters: InstrumentRenderParameters {
        InstrumentRenderParameters(
            frequency: frequency,
            gain: volume * (0.20 + 0.80 * y),
            brightness: y,
            gate: active,
            echo: echo,
            sound: sound
        ).sanitized
    }

    private func publishParameters() {
        let value = currentParameters
        parameters.update(value)
        captureParameters(value)
    }

    private func startEngineIfNeeded() throws {
        if let engine, engine.isRunning { return }
        let candidate = AVAudioEngine()
        let hardware = candidate.outputNode.inputFormat(forBus: 0)
        guard hardware.sampleRate.isFinite, hardware.sampleRate >= 8_000,
              hardware.channelCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: hardware.sampleRate, channels: 2) else {
            throw InstrumentAudioError.noOutput
        }
        let renderer = InstrumentRenderer(sampleRate: hardware.sampleRate, parameters: parameters)
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let leftData = buffers.first?.mData else { return noErr }
            let left = leftData.assumingMemoryBound(to: Float.self)
            let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            renderer.render(frameCount: Int(frameCount), left: left, right: right)
            return noErr
        }
        let loop = AVAudioPlayerNode()
        candidate.attach(node)
        candidate.attach(loop)
        candidate.connect(node, to: candidate.mainMixerNode, format: format)
        candidate.connect(loop, to: candidate.mainMixerNode,
                          format: AVAudioFormat(standardFormatWithSampleRate: InstrumentPhraseRenderer.sampleRate, channels: 2))
        candidate.mainMixerNode.outputVolume = outputVolume
        candidate.prepare()
        do { try candidate.start() }
        catch { candidate.stop(); candidate.detach(node); candidate.detach(loop); throw error }
        source = node
        loopPlayer = loop
        loopScheduled = false
        engine = candidate
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

private enum InstrumentAudioError: LocalizedError {
    case noOutput
    var errorDescription: String? { "No audio output device is available." }
}

/// Value parameters are copied once per render block. Only this bridge crosses threads.
struct InstrumentRenderParameters: Codable, Equatable, Sendable {
    var frequency = 220.0
    var gain = 0.12
    var brightness = 0.5
    var gate = false
    var echo = false
    var sound: SoundKind = .air

    var sanitized: Self {
        var copy = self
        copy.frequency = frequency.isFinite ? min(2_000, max(40, frequency)) : 220
        copy.gain = gain.isFinite ? min(0.5, max(0, gain)) : 0
        copy.brightness = brightness.isFinite ? min(1, max(0, brightness)) : 0.5
        return copy
    }
}

final class InstrumentParameterBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var current = InstrumentRenderParameters()

    func update(_ parameters: InstrumentRenderParameters) {
        let sanitized = parameters.sanitized
        lock.lock()
        current = sanitized
        lock.unlock()
    }

    func snapshot(or previous: InstrumentRenderParameters) -> InstrumentRenderParameters {
        guard lock.try() else { return previous }
        defer { lock.unlock() }
        return current
    }
}

/// All oscillator, envelope, filter and delay state belongs to the render thread.
/// The delay allocates once at creation; the callback does not wait or allocate.
final class InstrumentRenderer: @unchecked Sendable {
    private let sampleRate: Double
    private let bridge: InstrumentParameterBridge
    private var parameters = InstrumentRenderParameters()
    private var phase = 0.0
    private var frequency = 220.0
    private var envelope = 0.0
    private var gain = 0.0
    private var filter = 0.0
    private var filterCoefficient = 0.1
    private var echoMix = 0.0
    private var pulseWeight = 0.0
    private var glassWeight = 0.0
    private var delay: [Double]
    private var delayIndex = 0
    private let attack: Double
    private let release: Double
    private let glide: Double
    private let smoothing: Double

    init(sampleRate: Double, parameters: InstrumentParameterBridge) {
        self.sampleRate = sampleRate.isFinite ? min(192_000, max(8_000, sampleRate)) : 48_000
        self.bridge = parameters
        delay = Array(repeating: 0, count: max(1, Int(self.sampleRate * 0.28)))
        attack = 1 - exp(-1 / (self.sampleRate * 0.014))
        release = 1 - exp(-1 / (self.sampleRate * 0.065))
        glide = 1 - exp(-1 / (self.sampleRate * 0.030))
        smoothing = 1 - exp(-1 / (self.sampleRate * 0.020))
    }

    func render(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>?) {
        parameters = bridge.snapshot(or: parameters)
        let cutoff = min(sampleRate * 0.40, 400 + 8_000 * parameters.brightness)
        let targetFilter = 1 - exp(-2 * Double.pi * cutoff / sampleRate)
        let targetEnvelope = parameters.gate ? 1.0 : 0.0
        let envelopeSmoothing = parameters.gate ? attack : release
        let targetPulse = parameters.sound == .pulse ? 1.0 : 0.0
        let targetGlass = parameters.sound == .glass ? 1.0 : 0.0
        let targetEcho = parameters.echo ? 1.0 : 0.0
        let increment = 2 * Double.pi / sampleRate
        for index in 0..<frameCount {
            frequency += (parameters.frequency - frequency) * glide
            gain += (parameters.gain - gain) * smoothing
            envelope += (targetEnvelope - envelope) * envelopeSmoothing
            filterCoefficient += (targetFilter - filterCoefficient) * smoothing
            pulseWeight += (targetPulse - pulseWeight) * smoothing
            glassWeight += (targetGlass - glassWeight) * smoothing
            echoMix += (targetEcho - echoMix) * smoothing
            phase += frequency * increment
            if phase >= 2 * Double.pi { phase -= 2 * Double.pi }

            // Band-limited additive timbres avoid the aliasing of a hard square wave.
            let fundamental = sin(phase)
            let second = sin(phase * 2)
            let air = (fundamental + 0.12 * second) / 1.12
            let third = frequency * 3 < sampleRate * 0.45 ? sin(phase * 3) : 0
            let fifth = frequency * 5 < sampleRate * 0.45 ? sin(phase * 5) : 0
            let fourth = frequency * 4 < sampleRate * 0.45 ? sin(phase * 4) : 0
            let pulse = (fundamental + 0.30 * third + 0.15 * fifth) / 1.45
            let glass = 0.68 * fundamental + 0.24 * second + 0.08 * fourth
            let waveform = air * max(0, 1 - pulseWeight - glassWeight) + pulse * pulseWeight + glass * glassWeight
            filter += (waveform - filter) * filterCoefficient
            if envelope < 1e-10 { envelope = 0 }
            let dry = filter * envelope * gain
            let delayed = delay[delayIndex]
            let delayInput = dry * echoMix + delayed * 0.28
            delay[delayIndex] = abs(delayInput) < 1e-12 ? 0 : delayInput
            delayIndex += 1
            if delayIndex == delay.count { delayIndex = 0 }
            let mixed = dry * (1 - 0.08 * echoMix) + delayed * 0.22 * echoMix
            let sample = Float(mixed.isFinite ? min(0.8, max(-0.8, mixed)) : 0)
            left[index] = sample
            right?[index] = sample
        }
    }
}
