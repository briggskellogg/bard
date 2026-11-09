import AVFoundation
import CryptoKit
import Darwin
import Foundation
import WispCore

struct PreparedAudioVersion: Sendable {
    let payload: TrackAudioPayload
    let createdFiles: [URL]
}

/// Prepares only new bytes. It never changes metadata, the library index, or an
/// existing managed file, and removes its own staging file if preparation fails.
enum AudioVersionImporter {
    static func prepare(sourceURL: URL, mediaDirectory: URL) async throws -> PreparedAudioVersion {
        guard sourceURL.isFileURL, mediaDirectory.isFileURL,
              AudioImporter.extensions.contains(sourceURL.pathExtension.lowercased()) else {
            throw Failure.unsupported
        }
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        let sourceValues = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
        guard sourceValues.isRegularFile == true else { throw Failure.unsupported }
        let manager = FileManager.default
        let identifier = UUID()
        let fileName = "\(identifier.uuidString).\(sourceURL.pathExtension.lowercased())"
        let staging = mediaDirectory.appendingPathComponent(".version-\(fileName)")
        let destination = mediaDirectory.appendingPathComponent(fileName)
        var stagingCreated = false
        defer {
            if stagingCreated { try? manager.removeItem(at: staging) }
        }
        guard !manager.fileExists(atPath: staging.path), !manager.fileExists(atPath: destination.path) else {
            throw Failure.writeFailed
        }
        let (fingerprint, bytes) = try copyAndHash(sourceURL, to: staging, created: &stagingCreated)
        let duration = try playableDuration(staging)
        try Task.checkCancellation()
        try manager.moveItem(at: staging, to: destination)
        stagingCreated = false
        return PreparedAudioVersion(payload: TrackAudioPayload(id: identifier, fileName: fileName,
            fingerprint: fingerprint, duration: duration, byteCount: bytes,
            originalFileName: sourceURL.lastPathComponent), createdFiles: [destination])
    }

    /// Restoring never silently accepts changed or unreadable archived bytes.
    static func validateArchived(_ version: TrackAudioVersion, at url: URL) async throws {
        try version.validate()
        guard url.isFileURL, url.lastPathComponent == version.fileName,
              try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw Failure.archiveChanged
        }
        let (fingerprint, bytes) = try hash(url)
        guard fingerprint == version.fingerprint, bytes == version.byteCount else { throw Failure.archiveChanged }
        _ = try playableDuration(url)
        try Task.checkCancellation()
    }

    private static func playableDuration(_ url: URL) throws -> Double {
        let player = try AVAudioPlayer(contentsOf: url)
        let duration = player.duration
        guard duration.isFinite, duration > 0, player.prepareToPlay() else { throw Failure.unreadable }
        return duration
    }

    private static func hash(_ source: URL) throws -> (String, Int64) {
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        return try consume(reader) { _ in }
    }

    private static func copyAndHash(_ source: URL, to destination: URL, created: inout Bool) throws -> (String, Int64) {
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        let descriptor = open(destination.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Failure.writeFailed }
        created = true
        let writer = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? writer.close() }
        let result = try consume(reader) { try writer.write(contentsOf: $0) }
        try writer.synchronize()
        return result
    }

    private static func consume(_ reader: FileHandle, write: (Data) throws -> Void) throws -> (String, Int64) {
        var hasher = SHA256()
        var bytes: Int64 = 0
        while let data = try reader.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            try write(data)
            hasher.update(data: data)
            let (next, overflow) = bytes.addingReportingOverflow(Int64(data.count))
            guard !overflow else { throw Failure.writeFailed }
            bytes = next
        }
        guard bytes > 0 else { throw Failure.empty }
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), bytes)
    }

    enum Failure: LocalizedError {
        case unsupported, empty, writeFailed, unreadable, archiveChanged
        var errorDescription: String? {
            switch self {
            case .unsupported: return "Choose one supported local audio file."
            case .empty: return "This audio file is empty."
            case .writeFailed: return "The new version could not be copied into Bard."
            case .unreadable: return "macOS could not read playable audio from this file."
            case .archiveChanged: return "This archived file is missing or its bytes have changed. The current version is unchanged."
            }
        }
    }
}
