import AVFoundation
import Foundation
import WispAudioAtomics

struct RemixRecordedTake: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let duration: Double
    let createdAt: Date
}

private struct RemixTakeManifest: Codable {
    var schemaVersion = 1
    var id: UUID
    var createdAt: Date
    var duration: Double
}

enum RemixAudioError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum RemixTakeRepository {
    static func recover(in directory: URL) throws -> [RemixRecordedTake] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        var result: [RemixRecordedTake] = []
        for file in files where file.pathExtension == "json" {
            guard let attributes = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                  (attributes.fileSize ?? 0) <= 8_192,
                  let bytes = try? Data(contentsOf: file),
                  let manifest = try? JSONDecoder().decode(RemixTakeManifest.self, from: bytes),
                  manifest.schemaVersion == 1,
                  file.deletingPathExtension().lastPathComponent == manifest.id.uuidString else { continue }
            let wav = directory.appendingPathComponent(manifest.id.uuidString + ".wav")
            guard let attributes = try? wav.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                  let audio = try? AVAudioFile(forReading: wav), audio.processingFormat.sampleRate > 0 else { continue }
            let duration = Double(audio.length) / audio.processingFormat.sampleRate
            guard duration.isFinite, duration >= 0.15,
                  duration <= RemixPCMRecorder.maximumDuration + 0.1 else { continue }
            // The file is authoritative. A capture interrupted after its last write
            // can still be recovered even if the final manifest wasn't saved.
            let take = RemixRecordedTake(id: manifest.id, url: wav, duration: duration, createdAt: manifest.createdAt)
            result.append(take)
            if abs(manifest.duration - duration) > 0.01 { try? saveManifest(take) }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    static func saveManifest(_ take: RemixRecordedTake) throws {
        let manifest = RemixTakeManifest(id: take.id, createdAt: take.createdAt, duration: take.duration)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: take.url.deletingPathExtension().appendingPathExtension("json"), options: .atomic)
    }

    static func discard(_ take: RemixRecordedTake, in directory: URL) throws {
        let expected = directory.appendingPathComponent(take.id.uuidString + ".wav").standardizedFileURL
        guard take.url.standardizedFileURL == expected else {
            throw RemixAudioError.message("This take is outside Bard’s recording folder.")
        }
        // Only the UUID pair created by this recorder is eligible for deletion.
        for file in [expected, expected.deletingPathExtension().appendingPathExtension("json")] {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        }
    }
}

/// An output-only capture sink. A fixed buffer pool bounds memory; disk work is
/// serialized away from the render callback. An overrun stops at the captured
/// prefix instead of silently dropping blocks or growing an unbounded queue.
final class RemixPCMRecorder: @unchecked Sendable {
    static let maximumDuration = 15.0 * 60
    static let sampleRate = 48_000.0
    struct Status: Sendable {
        let duration: Double
        let reachedLimit: Bool
        let failure: String?
    }
    struct Finished: Sendable { let take: RemixRecordedTake; let warning: String? }

    private let queue = DispatchQueue(label: "com.briggskellogg.wisp.remix-capture", qos: .userInitiated)
    private let wakeup: DispatchSourceUserDataAdd
    private let state: OpaquePointer
    private let id = UUID()
    private let createdAt = Date()
    private let url: URL
    private let capacity: AVAudioFrameCount = 8_192
    private var pool: [AVAudioPCMBuffer] = []
    private var writtenFrames: AVAudioFramePosition = 0
    private var writeFailure: String?
    private var audioFile: AVAudioFile?

    init(directory: URL, maximumDuration: Double = RemixPCMRecorder.maximumDuration) throws {
        let duration = maximumDuration.isFinite ? min(Self.maximumDuration, max(0.15, maximumDuration)) : Self.maximumDuration
        guard let counter = wisp_capture_create(64, UInt64((duration * Self.sampleRate).rounded())) else {
            throw RemixAudioError.message("Bard couldn’t create the recording buffer.")
        }
        state = counter
        wakeup = DispatchSource.makeUserDataAddSource(queue: queue)
        // Activate before any throwing setup so teardown can always cancel it.
        wakeup.activate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(id.uuidString + ".wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        do {
            audioFile = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2) else {
                throw RemixAudioError.message("The recording format is unavailable.")
            }
            for _ in 0..<64 {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                    throw RemixAudioError.message("Bard couldn’t reserve recording memory.")
                }
                pool.append(buffer)
            }
            try RemixTakeRepository.saveManifest(RemixRecordedTake(id: id, url: url, duration: 0, createdAt: createdAt))
            wakeup.setEventHandler { [weak self] in self?.drain() }
        } catch {
            audioFile = nil
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("json"))
            throw error
        }
    }

    deinit { wakeup.cancel(); wisp_capture_destroy(state) }

    func capture(_ incoming: AVAudioPCMBuffer) {
        guard incoming.frameLength > 0 else { return }
        guard incoming.format.commonFormat == .pcmFormatFloat32,
              incoming.format.channelCount == 2,
              abs(incoming.format.sampleRate - Self.sampleRate) < 0.1,
              incoming.frameLength <= capacity,
              let input = incoming.floatChannelData else {
            wisp_capture_fail(state, 1); wakeup.add(data: 1)
            return
        }
        var slot: UInt64 = 0, count: UInt32 = 0
        guard wisp_capture_begin(state, incoming.frameLength, &slot, &count) == 1 else { return }
        let buffer = pool[Int(slot)]
        buffer.frameLength = count
        // Every pool buffer is float PCM allocated successfully during init.
        let output = buffer.floatChannelData!
        for channel in 0..<2 {
            for index in 0..<Int(count) {
                let sample = input[channel][index]
                output[channel][index] = sample.isFinite ? min(0.999, max(-0.999, sample)) : 0
            }
        }
        wisp_capture_commit(state, count)
        // Coalesced dispatch-source signals don't enqueue a closure per block.
        wakeup.add(data: 1)
    }

    /// The serial writer is the only consumer. It returns a slot only after its
    /// bytes have reached AVAudioFile; callback/state polling never take a lock.
    private func drain() {
        var slot: UInt64 = 0
        while wisp_capture_peek(state, &slot) == 1 {
            let buffer = pool[Int(slot)]
            if writeFailure == nil, let audioFile {
                do {
                    try audioFile.write(from: buffer)
                    writtenFrames += AVAudioFramePosition(buffer.frameLength)
                } catch {
                    writeFailure = "Recording stopped: \(error.localizedDescription)"
                    wisp_capture_fail(state, 3)
                }
            }
            wisp_capture_consume(state)
        }
    }

    private func failureMessage() -> String? {
        switch wisp_capture_error(state) {
        case 1: return "The audio device changed its recording format. The captured portion was kept."
        case 2: return "The disk couldn’t keep up with recording. The captured portion was kept."
        case 3: return "The recording file couldn’t be written completely. The captured portion was kept."
        default: return nil
        }
    }

    func status() -> Status {
        Status(duration: Double(wisp_capture_frames(state)) / Self.sampleRate,
               reachedLimit: wisp_capture_limit_reached(state) != 0, failure: failureMessage())
    }

    func finish() async throws -> Finished {
        guard wisp_capture_request_finish(state) == 1 else { throw RemixAudioError.message("This recording is already being saved.") }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in finishWhenQuiescent(continuation) }
        }
    }

    private func finishWhenQuiescent(_ continuation: CheckedContinuation<Finished, Error>) {
        drain()
        guard wisp_capture_in_flight(state) == 0 else {
            // A callback already holding a slot may still publish its last block.
            // Yield this writer, not the render thread, until that block arrives.
            queue.asyncAfter(deadline: .now() + .milliseconds(1)) { [self] in finishWhenQuiescent(continuation) }
            return
        }
        drain()
        wakeup.cancel()
        audioFile = nil // Close the WAV header before exposing the take.
        let warning = writeFailure ?? failureMessage()
        let duration = Double(writtenFrames) / Self.sampleRate
        guard duration >= 0.15 else {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("json"))
            continuation.resume(throwing: RemixAudioError.message(warning ?? "The take was too short. Record a little longer."))
            return
        }
        let take = RemixRecordedTake(id: id, url: url, duration: duration, createdAt: createdAt)
        do {
            try RemixTakeRepository.saveManifest(take)
            continuation.resume(returning: Finished(take: take, warning: warning))
        } catch {
            // Keep the WAV and initial manifest so the next opening can recover it.
            continuation.resume(throwing: RemixAudioError.message("The audio was kept, but its details couldn’t be saved: \(error.localizedDescription)"))
        }
    }
}
