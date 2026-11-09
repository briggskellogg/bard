import AVFoundation
import Foundation
import WispCore

struct MixtapeExportRequest: Sendable {
    let playlist: Playlist
    let plan: MixtapePlan
    let audioURLs: [UUID: URL]
    let coverURL: URL?
    let destination: URL
}

enum MixtapeExportError: LocalizedError {
    case invalid(String)
    case missing(String)
    case conversion(String)
    case capacity(String)
    var errorDescription: String? {
        switch self {
        case .invalid(let reason): return reason
        case .missing(let title): return "The audio for “\(title)” could not be found. No mixtape was exported."
        case .conversion(let title): return "“\(title)” could not be converted to cassette audio. No mixtape was exported."
        case .capacity(let side): return "The decoded audio exceeds Side \(side)’s capacity. Move the split or use a longer cassette. No tracks were truncated."
        }
    }
}

/// Streams one track at a time through bounded PCM buffers. Publication is a
/// directory rename after both sides and the tracklist have finished successfully.
enum MixtapeExporter {
    static let sampleRate = 44_100.0
    static let bufferFrames: AVAudioFrameCount = 8_192

    static func export(_ request: MixtapeExportRequest,
                       progress: @Sendable (Double, String) -> Void = { _, _ in }) throws -> URL {
        guard request.plan.canExport else {
            throw MixtapeExportError.invalid(request.plan.problems.joined(separator: "\n"))
        }
        try Task.checkCancellation()
        let manager = FileManager.default
        let scoped = request.destination.startAccessingSecurityScopedResource()
        defer { if scoped { request.destination.stopAccessingSecurityScopedResource() } }
        let token = UUID().uuidString
        let staging = request.destination.appendingPathComponent(".Wisp-mixtape-\(token)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        var published = false
        defer { if !published { try? manager.removeItem(at: staging) } }
        let requestedName = safeName(request.playlist.name)
        let destination = request.destination.appendingPathComponent("\(requestedName) — \(request.plan.capacity.title) — \(token.prefix(8))", isDirectory: true)
        let total = request.plan.tracks.count
        var completed = 0
        var text = [request.playlist.name, request.playlist.description,
                    "\(request.plan.capacity.title) cassette · \(request.plan.capacity.sideMinutes) minutes per side",
                    "44.1 kHz · 16-bit stereo WAV · \(request.plan.gap.title.lowercased()) between tracks", ""]
        for side in request.plan.sides {
            try Task.checkCancellation()
            text.append("SIDE \(side.label)")
            if side.tracks.isEmpty {
                text.append("Unused side — no audio file.\n")
                continue
            }
            let result = try writeSide(side, request: request, to: staging.appendingPathComponent("Side \(side.label).wav")) { title in
                progress(Double(completed) / Double(max(1, total)), "Side \(side.label) · \(title)")
            } trackFinished: {
                completed += 1
            }
            text.append(contentsOf: result.entries)
            text.append("Total: \(MixtapePlan.time(Double(result.frames) / sampleRate))\n")
        }
        if let cover = request.coverURL, manager.fileExists(atPath: cover.path) {
            let ext = cover.pathExtension.lowercased()
            let suffix = ["png", "jpg", "jpeg", "heic", "tiff", "gif"].contains(ext) ? ext : "image"
            try manager.copyItem(at: cover, to: staging.appendingPathComponent("Cover.\(suffix)"))
        }
        text.append("Play Side A to record the first side of your cassette, then turn the tape over and play Side B. The files contain the music and selected gaps without padding to the end of the tape.")
        try text.joined(separator: "\n").write(to: staging.appendingPathComponent("Tracklist.txt"), atomically: true, encoding: .utf8)
        try Task.checkCancellation()
        try manager.moveItem(at: staging, to: destination)
        published = true
        progress(1, "Mixtape exported")
        return destination
    }

    private static func safeName(_ name: String) -> String {
        let clean = name.unicodeScalars.map { scalar -> String in
            CharacterSet.controlCharacters.contains(scalar) || "/\\:".unicodeScalars.contains(scalar) ? " " : String(scalar)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? "Mixtape" : String(clean.prefix(80))
    }

    private static func writeSide(_ side: MixtapeSide, request: MixtapeExportRequest, to url: URL,
                                  starting: (String) -> Void, trackFinished: () -> Void) throws -> (frames: Int64, entries: [String]) {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false) else {
            throw MixtapeExportError.conversion("Audio format")
        }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        let output = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let capacityFrames = Int64(request.plan.capacity.sideSeconds * sampleRate)
        var frames: Int64 = 0
        var entries: [String] = []
        for (index, track) in side.tracks.enumerated() {
            try Task.checkCancellation()
            if index > 0 && side.gap != .none {
                let silenceFrames = Int64(side.gap.seconds * sampleRate)
                guard frames + silenceFrames <= capacityFrames else { throw MixtapeExportError.capacity(side.label) }
                try writeSilence(silenceFrames, format: format, output: output)
                frames += silenceFrames
            }
            starting(track.displayTitle)
            let timestamp = trackTimestamp(Double(frames) / sampleRate)
            let artist = track.artist.isEmpty ? "" : " — \(track.artist)"
            let origin = track.displayOrigin.isEmpty ? "" : " (\(track.displayOrigin))"
            let remix = track.remix.map { " [\($0.title) Remix]" } ?? ""
            entries.append("\(timestamp)  \(index + 1). \(track.displayTitle)\(artist)\(origin)\(remix)")
            if let source = track.sourceURL { entries.append("             Source: \(source)") }
            guard let source = request.audioURLs[track.id], FileManager.default.fileExists(atPath: source.path) else {
                throw MixtapeExportError.missing(track.displayTitle)
            }
            do {
                let input = try AVAudioFile(forReading: source)
                guard input.length > 0,
                      let converter = AVAudioConverter(from: input.processingFormat, to: format),
                      let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferFrames),
                      let incoming = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: bufferFrames) else {
                    throw MixtapeExportError.conversion(track.displayTitle)
                }
                var readError: Error?
                var emptyPasses = 0
                while true {
                    try Task.checkCancellation()
                    var conversionError: NSError?
                    let status = converter.convert(to: converted, error: &conversionError) { requested, state in
                        guard input.framePosition < input.length else { state.pointee = .endOfStream; return nil }
                        do {
                            let count = min(bufferFrames, AVAudioFrameCount(requested))
                            try input.read(into: incoming, frameCount: count)
                            state.pointee = incoming.frameLength > 0 ? .haveData : .endOfStream
                            return incoming.frameLength > 0 ? incoming : nil
                        } catch {
                            readError = error
                            state.pointee = .endOfStream
                            return nil
                        }
                    }
                    if let readError { throw readError }
                    if let conversionError { throw conversionError }
                    guard status != .error else { throw MixtapeExportError.conversion(track.displayTitle) }
                    if converted.frameLength > 0 {
                        let count = Int64(converted.frameLength)
                        guard frames + count <= capacityFrames else { throw MixtapeExportError.capacity(side.label) }
                        try output.write(from: converted)
                        frames += count
                        emptyPasses = 0
                    } else { emptyPasses += 1 }
                    if status == .endOfStream { break }
                    guard emptyPasses < 8 else { throw MixtapeExportError.conversion(track.displayTitle) }
                }
            } catch let error as MixtapeExportError { throw error }
            catch is CancellationError { throw CancellationError() }
            catch { throw MixtapeExportError.conversion(track.displayTitle) }
            trackFinished()
        }
        return (frames, entries)
    }

    private static func writeSilence(_ frames: Int64, format: AVAudioFormat, output: AVAudioFile) throws {
        guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferFrames), let channels = silence.floatChannelData else {
            throw MixtapeExportError.conversion("Silence")
        }
        for channel in 0..<Int(format.channelCount) { channels[channel].initialize(repeating: 0, count: Int(bufferFrames)) }
        var remaining = frames
        while remaining > 0 {
            try Task.checkCancellation()
            silence.frameLength = AVAudioFrameCount(min(Int64(bufferFrames), remaining))
            try output.write(from: silence)
            remaining -= Int64(silence.frameLength)
        }
    }

    private static func trackTimestamp(_ seconds: Double) -> String {
        let milliseconds = Int((seconds * 1_000).rounded())
        return String(format: "%02d:%02d.%03d", milliseconds / 60_000, (milliseconds / 1_000) % 60, milliseconds % 1_000)
    }
}
