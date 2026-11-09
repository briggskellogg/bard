import AVFoundation
import Foundation

enum InstrumentMix {
    // Each original synth voice has gain <= .5, feedback .28 and wet mix .22.
    // Even the conservative unit-wave bound gives .61278 per voice. Two voices
    // at .8 remain below .981, including sustained in-phase echo feedback.
    static let loopHeadroom: Float = 0.8
}

struct InstrumentPhraseSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let duration: Double
    let createdAt: Date
}

/// A theremin performance, not a microphone or music recording. Events retain
/// pitch, timbre, expression, echo and gate and replay through the existing synth.
struct InstrumentPhrase: Codable, Sendable {
    static let maximumDuration = 30.0
    static let maximumEvents = 4_000
    var id: UUID
    var name: String
    var createdAt: Date
    var duration: Double
    var events: [Event]

    struct Event: Codable, Sendable {
        var time: Double
        var parameters: InstrumentRenderParameters
    }

    var summary: InstrumentPhraseSummary {
        InstrumentPhraseSummary(id: id, name: name, duration: duration, createdAt: createdAt)
    }

    var isValid: Bool {
        guard duration.isFinite, (0.15...Self.maximumDuration).contains(duration),
              !events.isEmpty, events.count <= Self.maximumEvents,
              name.count <= 100, events[0].time == 0 else { return false }
        var previous = -1.0
        var hasSound = false
        for event in events {
            let p = event.parameters
            guard event.time.isFinite, event.time >= previous, event.time <= duration,
                  p.frequency.isFinite, (40...2_000).contains(p.frequency),
                  p.gain.isFinite, (0...0.5).contains(p.gain),
                  p.brightness.isFinite, (0...1).contains(p.brightness) else { return false }
            hasSound = hasSound || (p.gate && p.gain > 0)
            previous = event.time
        }
        return hasSound
    }
}

struct InstrumentPhraseRepository: Sendable {
    let directory: URL
    private static let maximumFileBytes = 2_000_000

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wisp/Loops", isDirectory: true)
    }

    func list() throws -> [InstrumentPhraseSummary] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
                return try? load(id: id).summary
            }
            .sorted { $0.createdAt == $1.createdAt ? $0.name < $1.name : $0.createdAt > $1.createdAt }
    }

    func load(id: UUID) throws -> InstrumentPhrase {
        let url = fileURL(id)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= Self.maximumFileBytes else { throw InstrumentPhraseError.invalid }
        let phrase = try JSONDecoder().decode(InstrumentPhrase.self, from: Data(contentsOf: url))
        guard phrase.id == id, phrase.isValid else { throw InstrumentPhraseError.invalid }
        return phrase
    }

    func save(_ phrase: InstrumentPhrase) throws {
        guard phrase.isValid else { throw InstrumentPhraseError.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = try JSONEncoder().encode(phrase)
        guard bytes.count <= Self.maximumFileBytes else { throw InstrumentPhraseError.invalid }
        try bytes.write(to: fileURL(phrase.id), options: .atomic)
    }

    func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: fileURL(id))
    }

    private func fileURL(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }
}

enum InstrumentPhraseError: LocalizedError {
    case invalid, noSound, allocation
    var errorDescription: String? {
        switch self {
        case .invalid: return "This saved phrase is incomplete or cannot be read."
        case .noSound: return "Hold the pad to play something before finishing the loop."
        case .allocation: return "The instrument could not prepare this loop."
        }
    }
}

/// Rendering happens off the audio thread and off the main thread. The resulting
/// buffer is immutable once handed to AVAudioPlayerNode, which owns real-time playback.
final class PreparedInstrumentPhrase: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}

enum InstrumentPhraseRenderer {
    static let sampleRate = 48_000.0

    static func render(_ phrase: InstrumentPhrase) throws -> PreparedInstrumentPhrase {
        guard phrase.isValid else { throw InstrumentPhraseError.invalid }
        let frameCount = Int((phrase.duration * sampleRate).rounded())
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let channels = buffer.floatChannelData else { throw InstrumentPhraseError.allocation }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let bridge = InstrumentParameterBridge()
        let renderer = InstrumentRenderer(sampleRate: sampleRate, parameters: bridge)
        var eventIndex = 0
        var position = 0
        while position < frameCount {
            try Task.checkCancellation()
            while eventIndex + 1 < phrase.events.count,
                  Int((phrase.events[eventIndex + 1].time * sampleRate).rounded()) <= position {
                eventIndex += 1
            }
            bridge.update(phrase.events[eventIndex].parameters)
            let nextEvent = eventIndex + 1 < phrase.events.count
                ? Int((phrase.events[eventIndex + 1].time * sampleRate).rounded()) : frameCount
            let count = min(512, min(frameCount - position, max(1, nextEvent - position)))
            renderer.render(frameCount: count, left: channels[0] + position, right: channels[1] + position)
            position += count
        }
        // Both ends meet at zero even if Finish was pressed during a held note.
        // Short equal-power fades preserve the gesture without a click at the join.
        let fadeFrames = min(Int(sampleRate * 0.02), frameCount / 4)
        if fadeFrames > 1 {
            for index in 0..<fadeFrames {
                let gain = Float(sin(Double(index) / Double(fadeFrames - 1) * .pi / 2))
                for channel in 0..<2 {
                    channels[channel][index] *= gain
                    channels[channel][frameCount - 1 - index] *= gain
                }
            }
        }
        return PreparedInstrumentPhrase(buffer: buffer)
    }
}
