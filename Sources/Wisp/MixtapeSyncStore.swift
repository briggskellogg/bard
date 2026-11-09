import AppKit
import Combine
import Foundation
import WispCore

/// A value snapshot keeps an in-flight Music request independent of later edits.
struct MixtapeSyncSnapshot: Equatable, Sendable {
    struct Item: Equatable, Sendable {
        var track: Track
        var audioURL: URL
        var artworkURL: URL?
        var artworkModified: Date?
    }
    var items: [Item]
    var playlistArtworkURL: URL?
    var playlistArtworkModified: Date?

    @MainActor
    init(document: LibraryDocument, store: LibraryStore) {
        let tracks = Dictionary(uniqueKeysWithValues: document.tracks.map { ($0.id, $0) })
        let playlist = document.playlists.first { $0.id == MixtapeCollection.id }
        playlistArtworkURL = playlist.flatMap { store.coverURL(for: $0) }
        playlistArtworkModified = playlistArtworkURL.flatMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        items = (playlist?.trackIDs ?? []).compactMap { id in
            guard let track = tracks[id] else { return nil }
            let artwork = store.artworkURL(for: track)
            return Item(track: track, audioURL: store.audioURL(for: track), artworkURL: artwork,
                        artworkModified: artwork.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate })
        }
    }

    init(items: [Item], playlistArtworkURL: URL? = nil, playlistArtworkModified: Date? = nil) {
        self.items = items
        self.playlistArtworkURL = playlistArtworkURL
        self.playlistArtworkModified = playlistArtworkModified
    }
}

protocol MixtapeSyncRunning: Sendable {
    func synchronize(_ snapshot: MixtapeSyncSnapshot) async throws -> MusicPlaylistBridgeResult
}

/// Debounces edits, serializes requests, and catches up to edits made during a sync.
/// Music work never blocks the player or the main actor.
@MainActor
final class MixtapeSyncStore: ObservableObject {
    @Published private(set) var status = "Waiting to sync"
    @Published private(set) var detail = "Bard controls the songs and order. Apple’s Sync Library carries them to your other devices."
    @Published private(set) var isSyncing = false
    @Published private(set) var needsAttention = false
    @Published private(set) var lastSyncedAt: Date?

    private weak var store: LibraryStore?
    private let runner: any MixtapeSyncRunning
    private let debounceNanoseconds: UInt64
    private var subscription: AnyCancellable?
    private var timer: AnyCancellable?
    private var debounce: Task<Void, Never>?
    private var pending: MixtapeSyncSnapshot?
    private var latest: MixtapeSyncSnapshot?
    private var permissionBlocked = false

    init(store: LibraryStore, runner: (any MixtapeSyncRunning)? = nil,
         startsAutomatically: Bool = true, debounceNanoseconds: UInt64 = 800_000_000) {
        self.store = store
        self.runner = runner ?? MusicSyncWorker(directory: store.directory)
        self.debounceNanoseconds = debounceNanoseconds
        guard startsAutomatically else { return }
        subscription = store.$document.sink { [weak self, weak store] document in
            guard let self, let store, store.canEdit,
                  document.playlists.contains(where: { $0.id == MixtapeCollection.id }) else { return }
            let snapshot = MixtapeSyncSnapshot(document: document, store: store)
            guard snapshot != self.latest else { return }
            self.latest = snapshot
            self.enqueue(snapshot)
        }
        timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self, !self.permissionBlocked, !self.isSyncing,
                  !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty,
                  let latest = self.latest else { return }
            self.enqueue(latest)
        }
    }

    deinit { debounce?.cancel() }

    func syncNow() {
        guard let store, store.canEdit, store.mixtape != nil else { return }
        permissionBlocked = false
        let snapshot = MixtapeSyncSnapshot(document: store.document, store: store)
        latest = snapshot
        enqueue(snapshot, immediately: true)
    }

    private func enqueue(_ snapshot: MixtapeSyncSnapshot, immediately: Bool = false) {
        pending = snapshot
        guard !permissionBlocked else { return }
        debounce?.cancel()
        guard !isSyncing else { return }
        if !needsAttention { status = "Waiting to sync" }
        debounce = Task { [weak self] in
            guard let self else { return }
            if !immediately { try? await Task.sleep(nanoseconds: self.debounceNanoseconds) }
            guard !Task.isCancelled else { return }
            await self.drain()
        }
    }

    private func drain() async {
        guard !isSyncing, !permissionBlocked, let snapshot = pending else { return }
        pending = nil
        isSyncing = true
        needsAttention = false
        status = "Syncing to Music"
        do {
            let result = try await runner.synchronize(snapshot)
            lastSyncedAt = Date()
            status = result.warnings.isEmpty ? "Synced to Music" : "Synced · check details"
            detail = result.warnings.isEmpty
                ? "\(result.trackCount) \(result.trackCount == 1 ? "song" : "songs") in Music’s Mixtape playlist, in Bard order. iPhone availability follows Apple’s Sync Library."
                : result.warnings.joined(separator: "\n")
            needsAttention = !result.warnings.isEmpty
        } catch {
            needsAttention = true
            permissionBlocked = (error as? MusicPlaylistBridgeError)?.isAutomationDenied == true
            status = permissionBlocked ? "Allow Music access" : "Sync needs attention"
            detail = error.localizedDescription
        }
        isSyncing = false
        // A new edit always wins. Never overwrite it with the completed snapshot.
        if let pending, !permissionBlocked { enqueue(pending) }
    }
}
