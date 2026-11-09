import AVFoundation
import Foundation

/// Measured RMS energy, not generated animation values. Stereo spread is the
/// side-channel energy ratio: identical channels are zero, opposite channels one.
struct MusicLightFrame: Equatable, Sendable {
    var bass: Double
    var mid: Double
    var treble: Double
    var left: Double
    var right: Double
    var stereoSpread: Double
    var energy: Double { sqrt((left * left + right * right) * 0.5) }

    static let zero = Self(bass: 0, mid: 0, treble: 0, left: 0, right: 0, stereoSpread: 0)
}

struct MusicLightTrack: Sendable {
    let frames: [MusicLightFrame]
    let frameDuration: Double
    let duration: Double

    func frame(at seconds: Double) -> MusicLightFrame {
        guard seconds.isFinite, seconds >= 0, seconds < duration,
              frameDuration > 0, !frames.isEmpty else { return .zero }
        let index = min(frames.count - 1, Int(seconds / frameDuration))
        return frames[index]
    }
}

/// A bounded, sequential decode on a background task. Two low-pass crossovers
/// split each channel into <250 Hz, 250–2500 Hz, and >2500 Hz RMS bands.
/// Long files use wider time bins instead of growing the feature array forever.
enum MusicLightDecoder {
    static let maximumFrames = 24_000
    static let samplesPerSecond = 12.0

    static func analyze(_ url: URL, maximumFrames: Int = maximumFrames) throws -> MusicLightTrack {
        try Task.checkCancellation()
        let limit = min(Self.maximumFrames, max(2, maximumFrames))
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let rate = format.sampleRate
        let channels = Int(format.channelCount)
        guard rate.isFinite, rate >= 8_000, rate <= 384_000, channels > 0, channels <= 32,
              file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_192) else {
            throw MusicLightDecodeError.unavailable
        }
        let hop = max(1, Int(ceil(max(rate / samplesPerSecond, Double(file.length) / Double(limit - 1)))))
        let lowCoefficient = 1 - exp(-2 * Double.pi * 250 / rate)
        let highCoefficient = 1 - exp(-2 * Double.pi * min(2_500, rate * 0.35) / rate)
        var low = Array(repeating: 0.0, count: channels)
        var high = Array(repeating: 0.0, count: channels)
        var frames: [MusicLightFrame] = []
        frames.reserveCapacity(min(limit, Int(ceil(Double(file.length) / Double(hop)))))
        var totalRead: Int64 = 0
        var count = 0
        var bass = 0.0, mid = 0.0, treble = 0.0
        var left = 0.0, right = 0.0, side = 0.0

        func boundedRMS(_ sum: Double, divisor: Double) -> Double {
            min(1, sqrt(max(0, sum / divisor)))
        }
        func measuredFrame() -> MusicLightFrame {
            let divisor = Double(count)
            let stereoEnergy = (left + right) * 0.5
            return MusicLightFrame(
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
            guard let data = buffer.floatChannelData else { throw MusicLightDecodeError.unavailable }
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
                    guard frames.count < limit else { throw MusicLightDecodeError.unavailable }
                    frames.append(measuredFrame())
                    count = 0
                    bass = 0; mid = 0; treble = 0; left = 0; right = 0; side = 0
                }
            }
        }
        try Task.checkCancellation()
        if count > 0 {
            guard frames.count < limit else { throw MusicLightDecodeError.unavailable }
            frames.append(measuredFrame())
        }
        guard !frames.isEmpty else { throw MusicLightDecodeError.unavailable }
        return MusicLightTrack(frames: frames, frameDuration: Double(hop) / rate,
                               duration: Double(totalRead) / rate)
    }
}

private enum MusicLightDecodeError: Error { case unavailable }
