import CryptoKit
import Darwin
import Foundation

/// One serial worker and an advisory process lock protect Music from overlapping
/// Wisp copies. The journal is checkpointed before subsequent external changes.
final class MusicSyncWorker: MixtapeSyncRunning, @unchecked Sendable {
    typealias Operation = (MusicPlaylistBridgeRequest, MusicPlaylistBridgeState,
                          (MusicPlaylistBridgeState) throws -> Void) throws -> MusicPlaylistBridgeResult
    private let directory: URL
    private let queue = DispatchQueue(label: "Wisp.MixtapeMusicSync", qos: .utility)
    private let operation: Operation

    init(directory: URL, operation: @escaping Operation = { request, state, checkpoint in
        try MusicPlaylistBridge.synchronize(request: request, state: state, checkpoint: checkpoint)
    }) {
        self.directory = directory
        self.operation = operation
    }

    func synchronize(_ snapshot: MixtapeSyncSnapshot) async throws -> MusicPlaylistBridgeResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try self.run(snapshot)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private struct Journal: Codable {
        var version = 1
        var state: MusicPlaylistBridgeState
    }

    private func run(_ snapshot: MixtapeSyncSnapshot) throws -> MusicPlaylistBridgeResult {
        let lockURL = directory.appendingPathComponent("MusicSync.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw SyncError.storage("Could not open the Mixtape sync lock.") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw SyncError.busy }
        defer { flock(descriptor, LOCK_UN) }

        let journalURL = directory.appendingPathComponent("MusicSync.json")
        let decoder = JSONDecoder()
        let state: MusicPlaylistBridgeState
        if FileManager.default.fileExists(atPath: journalURL.path) {
            do {
                let journal = try decoder.decode(Journal.self, from: Data(contentsOf: journalURL))
                guard journal.version == 1 else { throw SyncError.storage("The saved Music connection is from a newer Bard version.") }
                state = journal.state
            } catch {
                throw SyncError.storage("The saved Music connection could not be read. It has been preserved to prevent duplicate imports. \(error.localizedDescription)")
            }
        } else { state = MusicPlaylistBridgeState() }

        let publishDirectory = directory.appendingPathComponent("MusicPublishing", isDirectory: true)
        try FileManager.default.createDirectory(at: publishDirectory, withIntermediateDirectories: true)
        var items: [MusicPlaylistBridgeItem] = []
        // Preflight every file before making any changes in Music.
        for item in snapshot.items {
            guard FileManager.default.isReadableFile(atPath: item.audioURL.path) else {
                throw SyncError.storage("“\(item.track.title)” is missing its audio file. Restore it in Bard and sync again.")
            }
            let key = SHA256.hash(data: Data(item.track.fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
            let ext = item.audioURL.pathExtension.lowercased().filter { $0.isLetter || $0.isNumber }
            let copy = publishDirectory.appendingPathComponent("\(item.track.id.uuidString)-\(key).\(ext.isEmpty ? "audio" : ext)")
            if !FileManager.default.fileExists(atPath: copy.path) {
                let temporary = publishDirectory.appendingPathComponent(".\(UUID().uuidString).partial")
                defer { try? FileManager.default.removeItem(at: temporary) }
                try FileManager.default.copyItem(at: item.audioURL, to: temporary)
                try FileManager.default.moveItem(at: temporary, to: copy)
            }
            items.append(MusicPlaylistBridgeItem(id: item.track.id, fingerprint: item.track.fingerprint,
                title: item.track.displayTitle, artist: item.track.artist,
                // Origin is Wisp’s editable collection identity; the imported album tag is legacy metadata.
                album: item.track.displayOrigin.trimmingCharacters(in: .whitespacesAndNewlines),
                genre: item.track.genre, fileURL: copy, artworkURL: item.artworkURL))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let checkpoint: (MusicPlaylistBridgeState) throws -> Void = { state in
            try encoder.encode(Journal(state: state)).write(to: journalURL, options: .atomic)
        }
        return try operation(MusicPlaylistBridgeRequest(items: items,
            playlistArtworkURL: snapshot.playlistArtworkURL), state, checkpoint)
    }

    enum SyncError: LocalizedError {
        case busy
        case storage(String)
        var errorDescription: String? {
            switch self {
            case .busy: return "Another copy of Bard is syncing Mixtape. Close the other copy, then try again."
            case .storage(let message): return message
            }
        }
    }
}
