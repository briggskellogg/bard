import AppKit
import AudioToolbox
import AVFoundation
import Combine
import Foundation

/// One shared clock and mixer for the track, instrument and recorded output.
/// The normal library player is deliberately outside this graph.
final class RemixAudioGraph {
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let sourceMixer = AVAudioMixerNode()
    let eq = AVAudioUnitEQ(numberOfBands: 5)
    let mixer = AVAudioMixerNode()
    let limiter: AVAudioUnitEffect
    let sourceFile: AVAudioFile
    let renderFormat: AVAudioFormat
    let synth: AVAudioSourceNode

    init(sourceURL: URL, parameters: RemixParameterBridge, meter: RemixLevelMeter) throws {
        sourceFile = try AVAudioFile(forReading: sourceURL)
        guard sourceFile.length > 0, sourceFile.processingFormat.sampleRate.isFinite,
              sourceFile.processingFormat.sampleRate >= 8_000,
              sourceFile.processingFormat.channelCount > 0,
              sourceFile.processingFormat.channelCount <= 8,
              let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2) else {
            throw RemixAudioError.message("This track doesn’t contain supported audio for Remix.")
        }
        renderFormat = format
        limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
        let renderer = RemixRenderer(sampleRate: format.sampleRate, parameters: parameters)
        synth = AVAudioSourceNode(format: format) { _, _, count, list in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard let left = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            renderer.render(frameCount: Int(count), left: left, right: right)
            return noErr
        }
        for node in [player, sourceMixer, eq, mixer, limiter, synth] as [AVAudioNode] { engine.attach(node) }
        // Normalize the source before EQ so even a mono/low-rate file uses the
        // same audible five-band range and the same stereo recording clock.
        engine.connect(player, to: sourceMixer, format: sourceFile.processingFormat)
        engine.connect(sourceMixer, to: eq, format: format)
        engine.connect(eq, to: mixer, format: format)
        engine.connect(synth, to: mixer, format: format)
        engine.connect(mixer, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        _ = AudioUnitSetParameter(limiter.audioUnit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, -1, 0)
        for (index, band) in eq.bands.enumerated() {
            band.filterType = index == 0 ? .lowShelf : (index == 4 ? .highShelf : .parametric)
            band.frequency = Float([80.0, 250, 1_000, 4_000, 12_000][index])
            band.bandwidth = 1
            band.gain = 0
            band.bypass = false
        }
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1_024, format: nil) { buffer, _ in
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { meter.update(0); return }
            var sum = 0.0
            let count = Int(buffer.frameLength)
            for index in stride(from: 0, to: count, by: 4) {
                let sample = Double(channels[0][index]); if sample.isFinite { sum += sample * sample }
            }
            meter.update(min(1, sqrt(sum / Double(max(1, count / 4))) * 2.5))
        }
    }

    func setEQ(_ gains: [Double]) {
        for (index, band) in eq.bands.enumerated() {
            let value = index < gains.count && gains[index].isFinite ? gains[index] : 0
            band.gain = Float(min(12, max(-12, value)))
        }
    }
}

private final class PreparedRemixLoop: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    static func load(url: URL, start: Double, end: Double) throws -> PreparedRemixLoop {
        try Task.checkCancellation()
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let rate = file.processingFormat.sampleRate
        let first = min(file.length, max(0, AVAudioFramePosition((start * rate).rounded())))
        let last = min(file.length, max(first, AVAudioFramePosition((end * rate).rounded())))
        let frames = last - first
        let samples = frames * AVAudioFramePosition(file.processingFormat.channelCount)
        guard frames > 0, frames <= AVAudioFramePosition(UInt32.max), samples <= 25_000_000,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames)) else {
            throw RemixAudioError.message("That loop is too large to preview. Choose a shorter section.")
        }
        file.framePosition = first
        try file.read(into: buffer, frameCount: AVAudioFrameCount(frames))
        try Task.checkCancellation()
        guard buffer.frameLength > 0, let channels = buffer.floatChannelData else {
            throw RemixAudioError.message("Bard couldn’t read the selected loop.")
        }
        // Very short edge fades prevent a discontinuity at arbitrary loop points.
        let count = Int(buffer.frameLength)
        let fade = min(count / 2, max(1, Int(rate * 0.005)))
        for channel in 0..<Int(file.processingFormat.channelCount) {
            for index in 0..<fade {
                let amplitude = Float(sin(Double(index) / Double(fade) * .pi / 2))
                channels[channel][index] *= amplitude
                channels[channel][count - 1 - index] *= amplitude
            }
        }
        return PreparedRemixLoop(buffer)
    }
}

@MainActor
final class RemixStore: ObservableObject {
    static let eqFrequencies: [Double] = [80, 250, 1_000, 4_000, 12_000]
    static let maximumLoopDuration = 60.0
    static let maximumRecordingDuration = RemixPCMRecorder.maximumDuration
    private static var closingStores: [ObjectIdentifier: RemixStore] = [:]
    static var hasPendingFinalizations: Bool { !closingStores.isEmpty }

    static func finishPendingBeforeTermination() async {
        for store in Array(closingStores.values) { await store.finishBeforeTermination() }
    }

    let sourceURL: URL
    let title: String
    let takesDirectory: URL
    @Published private(set) var isPreparing = false
    @Published private(set) var isPreparingLoop = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isRecording = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var duration = 0.0
    @Published private(set) var position = 0.0
    @Published private(set) var recordingDuration = 0.0
    @Published private(set) var outputLevel = 0.0
    @Published private(set) var isTouching = false
    @Published private(set) var touchX = 0.5
    @Published private(set) var touchY = 0.5
    @Published private(set) var noteName = "A3"
    @Published private(set) var recordedTake: RemixRecordedTake?
    @Published private(set) var recoveredTakes: [RemixRecordedTake] = []
    @Published private(set) var isPreviewingTake = false
    @Published private(set) var takePreviewPosition = 0.0
    @Published var errorMessage: String?
    @Published var volume = 0.8 {
        didSet {
            let clean = bounded(volume, 0...1)
            if clean != volume { volume = clean; return }
            graph?.engine.mainMixerNode.outputVolume = Float(volume)
            previewPlayer?.volume = Float(volume)
        }
    }
    @Published var sourceVolume = 0.80 {
        didSet {
            let clean = bounded(sourceVolume, 0...1)
            if clean != sourceVolume { sourceVolume = clean; return }
            graph?.player.volume = Float(sourceVolume)
        }
    }
    @Published var instrumentVolume = 0.35 {
        didSet {
            let clean = bounded(instrumentVolume, 0...1)
            if clean != instrumentVolume { instrumentVolume = clean; return }
            publishParameters()
        }
    }
    @Published var eqGains: [Double] = Array(repeating: 0, count: 5) {
        didSet {
            let clean = (0..<5).map { $0 < eqGains.count ? bounded(eqGains[$0], -12...12) : 0 }
            if clean != eqGains { eqGains = clean }
            graph?.setEQ(clean)
        }
    }
    @Published var voice: RemixVoice = .air { didSet { trigger &+= 1; publishParameters() } }
    @Published var rootNote = 9 {
        didSet {
            let clean = min(11, max(0, rootNote))
            if clean != rootNote { rootNote = clean; return }
            publishParameters()
        }
    }
    @Published var quantized = true { didSet { publishParameters() } }
    @Published var echo = true { didSet { publishParameters() } }
    @Published var loopEnabled = false { didSet { scheduleLoopChange() } }
    @Published var loopStart = 0.0 { didSet { scheduleLoopChange() } }
    @Published var loopEnd = 16.0 { didSet { scheduleLoopChange() } }
    @Published var loopTakePreview = false { didSet { previewPlayer?.numberOfLoops = loopTakePreview ? -1 : 0 } }

    private let parameters = RemixParameterBridge()
    private let meter = RemixLevelMeter()
    private var graph: RemixAudioGraph?
    private var recorder: RemixPCMRecorder?
    private var preparedLoop: PreparedRemixLoop?
    private var loopTask: Task<Void, Never>?
    private var finalizationTask: Task<RemixRecordedTake?, Never>?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var previewPlayer: AVAudioPlayer?
    private var trigger: UInt64 = 0
    private var scheduleID = UUID()
    private var loopID = UUID()
    private var preparedLoopStart = 0.0
    private var preparedLoopEnd = 0.0
    private var playbackStart = 0.0
    private var hasRecordingTap = false
    private var normalizingLoop = false
    private var loopShouldResume = false
    private var closed = false

    init(sourceURL: URL, title: String, takesDirectory: URL? = nil) {
        self.sourceURL = sourceURL; self.title = title
        self.takesDirectory = takesDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wisp/RemixTakes", isDirectory: true)
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.releaseTouch() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pause(); self.releaseTouch()
                if self.isRecording { _ = await self.finishRecording() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] notification in
            let engine = notification.object as? AVAudioEngine
            Task { @MainActor in
                guard let self, let engine, engine === self.graph?.engine, !self.closed else { return }
                self.pause(); self.releaseTouch()
                if self.isRecording { _ = await self.finishRecording() }
                self.errorMessage = "The audio output changed. Press Play to continue; any recording was kept."
            }
        })
    }

    deinit {
        timer?.invalidate()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    func prepare() async {
        guard graph == nil, !isPreparing, !closed else { return }
        isPreparing = true; errorMessage = nil
        do {
            let url = sourceURL, directory = takesDirectory
            let recovered = try await Task.detached(priority: .userInitiated) {
                try RemixTakeRepository.recover(in: directory)
            }.value
            guard !closed else { isPreparing = false; return }
            recoveredTakes = recovered; recordedTake = recovered.first
            let candidate = try RemixAudioGraph(sourceURL: url, parameters: parameters, meter: meter)
            duration = Double(candidate.sourceFile.length) / candidate.sourceFile.processingFormat.sampleRate
            guard duration.isFinite, duration > 0 else { throw RemixAudioError.message("This track’s duration is unavailable.") }
            graph = candidate
            candidate.player.volume = Float(sourceVolume)
            candidate.engine.mainMixerNode.outputVolume = Float(volume)
            candidate.setEQ(eqGains)
            normalizingLoop = true; loopStart = 0; loopEnd = min(16, duration); normalizingLoop = false
            publishParameters()
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
        } catch {
            errorMessage = "Remix couldn’t open this audio: \(error.localizedDescription)"
        }
        isPreparing = false
    }

    func resetEQ() { eqGains = Array(repeating: 0, count: 5) }

    func touch(x: Double, y: Double) {
        guard graph != nil, !closed else { return }
        stopTakePreview()
        do { try startEngine() }
        catch { errorMessage = error.localizedDescription; return }
        let prior = RemixRenderer.midiNote(x: touchX, rootNote: rootNote, quantized: quantized)
        touchX = bounded(x, 0...1); touchY = bounded(y, 0...1)
        let next = RemixRenderer.midiNote(x: touchX, rootNote: rootNote, quantized: quantized)
        if !isTouching || (voice == .pluck && abs(next - prior) >= 1) { trigger &+= 1 }
        isTouching = true
        publishParameters()
    }

    func releaseTouch() { isTouching = false; publishParameters() }

    private func publishParameters() {
        let midi = RemixRenderer.midiNote(x: touchX, rootNote: rootNote, quantized: quantized)
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        let nearest = Int(midi.rounded()); noteName = "\(names[nearest % 12])\(nearest / 12 - 1)"
        parameters.update(RemixRenderParameters(frequency: 440 * pow(2, (midi - 69) / 12),
            gain: instrumentVolume * 0.4 * (0.20 + 0.80 * touchY), brightness: touchY,
            gate: isTouching, echo: echo, voice: voice, trigger: trigger))
    }

    func playPause() { if isPlaying { pause() } else { play() } }

    private func play() {
        guard let graph, !closed, !isPreparingLoop else { return }
        stopTakePreview()
        do {
            try startEngine()
            graph.player.stop()
            let id = UUID(); scheduleID = id
            if loopEnabled {
                guard let preparedLoop else { scheduleLoopChange(); return }
                position = position >= preparedLoopStart && position < preparedLoopEnd ? position : preparedLoopStart
                playbackStart = position
                let rate = graph.sourceFile.processingFormat.sampleRate
                let first = AVAudioFramePosition((position * rate).rounded())
                let last = min(graph.sourceFile.length, AVAudioFramePosition((preparedLoopEnd * rate).rounded()))
                if position > preparedLoopStart + 0.01, last > first {
                    graph.player.scheduleSegment(graph.sourceFile, startingFrame: first, frameCount: AVAudioFrameCount(last - first), at: nil)
                } else { position = preparedLoopStart; playbackStart = position }
                graph.player.scheduleBuffer(preparedLoop.buffer, at: nil, options: [.loops])
            } else {
                if position >= duration - 0.01 { position = 0 }
                playbackStart = position
                let first = AVAudioFramePosition((position * graph.sourceFile.processingFormat.sampleRate).rounded())
                let remaining = graph.sourceFile.length - first
                guard remaining > 0, remaining <= AVAudioFramePosition(UInt32.max) else {
                    throw RemixAudioError.message("This track is too long for a single preview.")
                }
                graph.player.scheduleSegment(graph.sourceFile, startingFrame: first, frameCount: AVAudioFrameCount(remaining), at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.scheduleID == id else { return }
                        self.position = self.duration; self.isPlaying = false
                    }
                }
            }
            graph.player.volume = Float(sourceVolume)
            graph.player.play(); isPlaying = true
        } catch { isPlaying = false; errorMessage = error.localizedDescription }
    }

    private func pause() {
        if isPlaying { position = currentPosition() }
        scheduleID = UUID(); graph?.player.pause(); isPlaying = false
    }

    func stop() {
        pause(); stopTakePreview(); releaseTouch()
        position = loopEnabled ? preparedLoopStart : 0
    }

    func seek(to seconds: Double) {
        let resume = isPlaying
        pause(); position = bounded(seconds, 0...max(0, duration))
        if resume { play() }
    }

    private func currentPosition() -> Double {
        guard let graph, let time = graph.player.lastRenderTime,
              let playerTime = graph.player.playerTime(forNodeTime: time), playerTime.sampleRate > 0 else { return position }
        let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
        guard elapsed.isFinite else { return position }
        let raw = playbackStart + max(0, elapsed)
        if loopEnabled, preparedLoopEnd > preparedLoopStart {
            let length = preparedLoopEnd - preparedLoopStart
            return preparedLoopStart + max(0, raw - preparedLoopStart).truncatingRemainder(dividingBy: length)
        }
        return min(duration, raw)
    }

    private func scheduleLoopChange() {
        guard !normalizingLoop, graph != nil, !closed else { return }
        normalizingLoop = true
        loopStart = bounded(loopStart, 0...max(0, duration - 0.15))
        loopEnd = bounded(loopEnd, min(duration, loopStart + 0.15)...min(duration, loopStart + Self.maximumLoopDuration))
        normalizingLoop = false
        let resume = isPlaying || loopShouldResume
        pause(); loopTask?.cancel(); loopID = UUID()
        loopShouldResume = resume
        guard loopEnabled else { loopShouldResume = false; isPreparingLoop = false; preparedLoop = nil; if resume { play() }; return }
        isPreparingLoop = true
        let id = loopID, start = loopStart, end = loopEnd, url = sourceURL
        loopTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(150))
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try PreparedRemixLoop.load(url: url, start: start, end: end)
                }.value
                guard let self, !self.closed, self.loopID == id, !Task.isCancelled else { return }
                self.preparedLoop = prepared; self.preparedLoopStart = start; self.preparedLoopEnd = end
                self.isPreparingLoop = false; self.loopShouldResume = false
                if resume { self.play() }
            } catch is CancellationError { }
            catch {
                guard let self, self.loopID == id else { return }
                self.isPreparingLoop = false; self.loopShouldResume = false; self.errorMessage = error.localizedDescription
            }
        }
    }

    func startRecording() {
        guard graph != nil, !isRecording, !isFinalizing, !isPreparingLoop, !closed else { return }
        guard recordedTake == nil else { errorMessage = "Save or discard the current take before starting another."; return }
        errorMessage = nil; stopTakePreview()
        do {
            try startEngine()
            guard let graph else { return }
            let sink = try RemixPCMRecorder(directory: takesDirectory)
            graph.limiter.installTap(onBus: 0, bufferSize: 1_024, format: graph.renderFormat) { buffer, _ in sink.capture(buffer) }
            recorder = sink; hasRecordingTap = true
            recordingDuration = 0; isRecording = true
            if !isPlaying { play() }
        } catch { errorMessage = "Recording couldn’t start: \(error.localizedDescription)" }
    }

    @discardableResult
    func finishRecording() async -> RemixRecordedTake? {
        if let finalizationTask { return await finalizationTask.value }
        guard let sink = recorder else { return recordedTake }
        if hasRecordingTap { graph?.limiter.removeTap(onBus: 0); hasRecordingTap = false }
        recorder = nil; isRecording = false; isFinalizing = true
        Self.closingStores[ObjectIdentifier(self)] = self
        let task = Task { @MainActor [self] () -> RemixRecordedTake? in
            defer { Self.closingStores.removeValue(forKey: ObjectIdentifier(self)) }
            do {
                let result = try await sink.finish()
                recordedTake = result.take
                recoveredTakes.removeAll { $0.id == result.take.id }; recoveredTakes.insert(result.take, at: 0)
                recordingDuration = result.take.duration
                if let warning = result.warning { errorMessage = warning }
                isFinalizing = false
                return result.take
            } catch { errorMessage = error.localizedDescription; isFinalizing = false; return nil }
        }
        finalizationTask = task
        let result = await task.value
        finalizationTask = nil
        return result
    }

    func selectRecoveredTake(id: UUID) {
        guard !isRecording, !isFinalizing, let take = recoveredTakes.first(where: { $0.id == id }) else { return }
        stopTakePreview(); recordedTake = take; takePreviewPosition = 0
    }

    func discardTake(id: UUID? = nil) {
        guard !isRecording, !isFinalizing,
              let take = recoveredTakes.first(where: { $0.id == (id ?? recordedTake?.id) }) else { return }
        if recordedTake?.id == take.id { stopTakePreview() }
        do {
            try RemixTakeRepository.discard(take, in: takesDirectory)
            recoveredTakes.removeAll { $0.id == take.id }
            if recordedTake?.id == take.id { recordedTake = recoveredTakes.first; takePreviewPosition = 0 }
        } catch { errorMessage = "The take couldn’t be discarded: \(error.localizedDescription)" }
    }

    func previewTake() {
        guard !isRecording, !isFinalizing, let take = recordedTake, !closed else { return }
        if isPreviewingTake { stopTakePreview(); return }
        pause(); releaseTouch(); graph?.engine.stop()
        do {
            let player = try AVAudioPlayer(contentsOf: take.url)
            player.numberOfLoops = loopTakePreview ? -1 : 0
            player.volume = Float(volume)
            guard player.prepareToPlay(), player.play() else { throw RemixAudioError.message("The take couldn’t be played.") }
            previewPlayer = player; isPreviewingTake = true; takePreviewPosition = 0
        } catch { errorMessage = error.localizedDescription }
    }

    func stopTakePreview() {
        previewPlayer?.stop(); previewPlayer = nil; isPreviewingTake = false
    }

    /// Finishing runs to completion even when its sheet goes away. Captures are
    /// durable, and are removed only by an explicit discard or successful save.
    func shutdown() {
        guard !closed else { return }
        pause(); stopTakePreview(); releaseTouch()
        closed = true; loopTask?.cancel(); timer?.invalidate(); timer = nil
        if isRecording || isFinalizing {
            Self.closingStores[ObjectIdentifier(self)] = self
            Task { [self] in _ = await finishRecording() }
        }
        graph?.engine.stop(); outputLevel = 0
    }

    func finishBeforeTermination() async {
        shutdown()
        _ = await finishRecording()
    }

    private func startEngine() throws {
        guard let graph else { throw RemixAudioError.message("The track is still loading.") }
        if !graph.engine.isRunning { graph.engine.prepare(); try graph.engine.start() }
    }

    private func tick() {
        guard !closed else { return }
        if isPlaying { position = currentPosition() }
        let level = graph?.engine.isRunning == true ? meter.read() : 0
        outputLevel += (level - outputLevel) * (level > outputLevel ? 0.55 : 0.12)
        if isPreviewingTake, let previewPlayer {
            takePreviewPosition = previewPlayer.currentTime
            if !previewPlayer.isPlaying { isPreviewingTake = false }
        }
        if isRecording, let recorder {
            let status = recorder.status(); recordingDuration = status.duration
            if status.reachedLimit || status.failure != nil { Task { [weak self] in _ = await self?.finishRecording() } }
        }
    }

    private func bounded(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : range.lowerBound
    }
}
