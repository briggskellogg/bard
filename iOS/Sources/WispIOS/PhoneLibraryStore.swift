import Foundation
import Combine
import WispCore

/// The phone is a listening copy. Only the Mac publishes the library.
@MainActor
final class PhoneLibraryStore: ObservableObject {
    @Published private(set) var document = LibraryDocument()
    @Published private(set) var snapshot: PhoneLibrarySnapshot?
    @Published private(set) var isSyncing = false
    @Published private(set) var isLoading = true
    @Published private(set) var isConnected = false
    @Published private(set) var hasPendingConnection = false
    @Published private(set) var selectedFolderName: String?
    @Published private(set) var status = "Connect your Mac library"
    @Published private(set) var lastSynced: Date?
    @Published private(set) var pendingFavoriteCount = 0
    @Published private(set) var favoriteStatus: String?
    @Published var errorMessage: String?
    private let worker = DispatchQueue(label: "co.wisp.phone.receive", qos: .utility)
    private let cacheDirectory: URL
    private let defaults: UserDefaults
    private let bookmarkKey = "PhoneSync.folderBookmark.v1"
    private let pendingBookmarkKey = "PhoneSync.pendingFolderBookmark.v1"
    private let favoriteOutboxKey = "PhoneSync.favoriteOutbox.v1"
    private var favoriteOutbox: PhoneFavoriteOutbox?
    private var loadedFavoriteSource: UUID?
    private var favoriteLoadFailure: String?
    private var pendingBookmark: Data?
    private var connectedFolderName: String?
    private let retryInterval: Duration
    private var generation = UUID()
    private var refreshTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, cacheDirectory: URL? = nil, retryInterval: Duration = .seconds(30)) {
        self.defaults = defaults
        self.retryInterval = retryInterval
        self.cacheDirectory = cacheDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PhoneLibrary", isDirectory: true)
        isConnected = defaults.data(forKey: bookmarkKey) != nil
        pendingBookmark = defaults.data(forKey: pendingBookmarkKey)
        hasPendingConnection = pendingBookmark != nil
        if hasPendingConnection { status = "Waiting for your selected folder…" }
        let savedDirectory = self.cacheDirectory
        worker.async { [weak self] in
            let result = Result { try PhoneLibraryReceiver.current(cacheDirectory: savedDirectory) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoading = false
                guard self.snapshot == nil else { return }
                switch result {
                case .success(let saved):
                    if let saved {
                        self.snapshot = saved
                        self.applyFavoriteOverlay(to: saved)
                        if !self.isSyncing && !self.hasPendingConnection { self.status = "Available offline" }
                    }
                case .failure(let error):
                    if !self.isSyncing { self.errorMessage = "Your downloaded library could not be opened. \(error.localizedDescription)" }
                }
            }
        }
        #if DEBUG
        // Simulator validation uses an explicitly seeded local fixture only.
        if ProcessInfo.processInfo.arguments.contains("--wisp-test-library") {
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("SyncFixture", isDirectory: true)
            Task { [weak self] in self?.connect(to: folder) }
        }
        #endif
    }

    func connect(to folder: URL) {
        guard !isSyncing else { return }
        guard folder.lastPathComponent != "Assets" else {
            errorMessage = "Assets contains the audio and covers. Go back one level, select the shared library folder, then tap Open. Your current connection is unchanged."
            return
        }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            // A selected folder is a pending request, not a working connection.
            // Keep it separately so an initial iCloud wait survives retries and
            // relaunch without replacing a previously working bookmark.
            generation = UUID()
            pendingBookmark = bookmark
            selectedFolderName = folder.lastPathComponent
            defaults.set(bookmark, forKey: pendingBookmarkKey)
            hasPendingConnection = true
            receive(bookmark: bookmark, connecting: true)
        } catch { errorMessage = "This folder could not be connected. \(error.localizedDescription)" }
    }

    func refresh() {
        guard !isSyncing else { return }
        if let pendingBookmark {
            receive(bookmark: pendingBookmark, connecting: true)
        } else if let bookmark = defaults.data(forKey: bookmarkKey) {
            receive(bookmark: bookmark, connecting: false)
        }
    }

    private func receive(bookmark: Data, connecting: Bool) {
        isSyncing = true
        status = connecting ? "Connecting your Mac library…" : "Checking your Mac library…"
        errorMessage = nil
        let cache = cacheDirectory
        let expected = generation
        let outgoing = favoriteOutbox?.batch
        let favoriteDevice = favoriteOutbox?.deviceID
        worker.async { [weak self] in
            let result: Result<(PhoneLibrarySnapshot, Data?, String, PhoneFavoriteAcknowledgement?, String?), Error> = Result {
                var stale = false
                let source = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
                Task { @MainActor [weak self] in
                    guard let self, self.generation == expected else { return }
                    self.selectedFolderName = source.lastPathComponent
                }
                let accessed = source.startAccessingSecurityScopedResource()
                defer { if accessed { source.stopAccessingSecurityScopedResource() } }
                let renewed = stale ? try source.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) : nil
                let saved = try PhoneLibraryReceiver.receive(source: source, cacheDirectory: cache)
                var receipt: PhoneFavoriteAcknowledgement?, favoriteWarning: String?
                if let outgoing, outgoing.sourceLibraryID == saved.sourceLibraryID {
                    do { try PhoneFavoritesSync.publish(outgoing, to: source) }
                    catch { favoriteWarning = "Favorites are saved here and will retry. \(error.localizedDescription)" }
                }
                // A publish conflict must not hide the acknowledgement for an
                // already-delivered batch (including a partially acknowledged one).
                if let favoriteDevice {
                    do { receipt = try PhoneFavoritesSync.acknowledgement(in: source, sourceLibraryID: saved.sourceLibraryID, deviceID: favoriteDevice) }
                    catch { favoriteWarning = "Favorites are saved here and will retry. \(error.localizedDescription)" }
                }
                return (saved, renewed, source.lastPathComponent, receipt, favoriteWarning)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSyncing = false
                guard expected == self.generation else { return }
                switch result {
                case .success(let (saved, renewed, folderName, receipt, favoriteWarning)):
                    self.snapshot = saved
                    self.loadFavoriteOutbox(for: saved.sourceLibraryID)
                    var receiptWarning: String?
                    if let receipt, var outbox = self.favoriteOutbox, outbox.sourceLibraryID == saved.sourceLibraryID {
                        do {
                            try outbox.acknowledge(receipt, snapshot: saved)
                            try self.saveFavoriteOutbox(outbox)
                        } catch { receiptWarning = "Favorites will retry. \(error.localizedDescription)" }
                    }
                    self.applyFavoriteOverlay(to: saved)
                    if let receiptWarning { self.favoriteStatus = receiptWarning }
                    else if self.pendingFavoriteCount > 0, let favoriteWarning { self.favoriteStatus = favoriteWarning }
                    self.selectedFolderName = folderName
                    self.connectedFolderName = folderName
                    self.lastSynced = Date()
                    self.status = "\(saved.document.tracks.count) songs available offline"
                    if connecting || renewed != nil {
                        self.defaults.set(renewed ?? bookmark, forKey: self.bookmarkKey)
                    }
                    self.isConnected = true
                    if connecting { self.clearPendingConnection() }
                    var excluded = cache
                    var values = URLResourceValues()
                    values.isExcludedFromBackup = true
                    try? excluded.setResourceValues(values)
                    // A tap during the background copy must not wait for the
                    // next periodic retry, or be removed by the older receipt.
                    if let latest = self.favoriteOutbox?.batch, latest.sequence > (outgoing?.sequence ?? 0) {
                        self.refresh()
                    }
                case .failure(let error):
                    if connecting, (error as? PhoneLibrarySyncError)?.isRetryable == true {
                        self.status = "Waiting for iCloud files…"
                        self.errorMessage = "Your folder is remembered. Bard will retry while open. \(error.localizedDescription)"
                    } else if connecting {
                        self.clearPendingConnection()
                        self.status = self.snapshot == nil ? "Choose your library folder" : "Your downloaded library is ready"
                        self.errorMessage = "This folder could not be connected. \(error.localizedDescription)"
                    } else {
                        self.status = self.snapshot == nil ? "Waiting for your Mac library" : "Your downloaded library is ready"
                        self.errorMessage = "Sync will retry while Bard is open. \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func setActive(_ active: Bool) {
        refreshTask?.cancel()
        refreshTask = nil
        guard active else { return }
        refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: self?.retryInterval ?? .seconds(30)) } catch { return }
                self?.refresh()
            }
        }
    }

    func cancelPendingConnection() {
        guard !isSyncing, hasPendingConnection else { return }
        generation = UUID()
        clearPendingConnection()
        selectedFolderName = connectedFolderName
        status = snapshot == nil ? "Connect your Mac library" : "Available offline"
        errorMessage = nil
    }

    private func clearPendingConnection() {
        pendingBookmark = nil
        hasPendingConnection = false
        defaults.removeObject(forKey: pendingBookmarkKey)
    }

    func disconnect() {
        guard !isSyncing else { return }
        generation = UUID()
        clearPendingConnection()
        defaults.removeObject(forKey: bookmarkKey)
        isConnected = false
        connectedFolderName = nil
        selectedFolderName = nil
        status = snapshot == nil ? "Connect your Mac library" : "Available offline · Sync disconnected"
        errorMessage = nil
    }

    func artworkURL(for track: Track) -> URL? {
        guard let name = track.artworkFileName else { return nil }
        return snapshot?.artworkDirectory.appendingPathComponent(name)
    }

    func isFavorite(_ track: Track) -> Bool {
        document.tracks.first(where: { $0.id == track.id })?.favorite ?? track.favorite
    }

    func toggleFavorite(_ track: Track) {
        guard let snapshot, snapshot.document.tracks.contains(where: { $0.id == track.id }) else { return }
        loadFavoriteOutbox(for: snapshot.sourceLibraryID)
        guard favoriteLoadFailure == nil else { favoriteStatus = favoriteLoadFailure; return }
        do {
            var outbox = favoriteOutbox.flatMap { $0.sourceLibraryID == snapshot.sourceLibraryID ? $0 : nil }
                ?? PhoneFavoriteOutbox(sourceLibraryID: snapshot.sourceLibraryID, deviceID: UUID())
            try outbox.set(!isFavorite(track), for: track.id)
            try saveFavoriteOutbox(outbox)
            applyFavoriteOverlay(to: snapshot)
            if isConnected && !hasPendingConnection { refresh() }
        } catch { favoriteStatus = "This favorite could not be saved. \(error.localizedDescription)" }
    }

    private func saveFavoriteOutbox(_ outbox: PhoneFavoriteOutbox) throws {
        try outbox.validate()
        let bytes = try JSONEncoder().encode(outbox)
        guard bytes.count <= 2 * 1024 * 1024 else { throw PhoneFavoriteError.limit }
        let key = favoriteOutboxKey + "." + outbox.sourceLibraryID.uuidString
        defaults.set(bytes, forKey: key)
        guard defaults.data(forKey: key) == bytes else { throw PhoneFavoriteError.invalidData }
        favoriteOutbox = outbox
        loadedFavoriteSource = outbox.sourceLibraryID
        favoriteLoadFailure = nil
    }

    private func applyFavoriteOverlay(to saved: PhoneLibrarySnapshot) {
        loadFavoriteOutbox(for: saved.sourceLibraryID)
        if let favoriteOutbox, favoriteOutbox.sourceLibraryID == saved.sourceLibraryID {
            document = favoriteOutbox.applying(to: saved.document)
            pendingFavoriteCount = favoriteOutbox.changes.count
        } else {
            document = saved.document
            pendingFavoriteCount = 0
        }
        favoriteStatus = favoriteLoadFailure ?? (pendingFavoriteCount > 0 ? "Favorites saved on this iPhone · Waiting for Mac" : nil)
    }

    /// Each source keeps its own device identity and monotonic sequence, including
    /// after all pending changes are acknowledged. Never replace an unreadable
    /// outbox with a fresh sequence that could replay older cloud intent.
    private func loadFavoriteOutbox(for source: UUID) {
        guard loadedFavoriteSource != source else { return }
        loadedFavoriteSource = source
        favoriteOutbox = nil; favoriteLoadFailure = nil
        let key = favoriteOutboxKey + "." + source.uuidString
        let scopedBytes = defaults.data(forKey: key)
        let legacyBytes = scopedBytes == nil ? defaults.data(forKey: favoriteOutboxKey) : nil
        guard let bytes = scopedBytes ?? legacyBytes else { return }
        do {
            guard bytes.count <= 2 * 1024 * 1024 else { throw PhoneFavoriteError.limit }
            let outbox = try JSONDecoder().decode(PhoneFavoriteOutbox.self, from: bytes)
            try outbox.validate()
            if outbox.sourceLibraryID != source {
                // A legacy record for another source remains untouched.
                guard scopedBytes == nil else { throw PhoneFavoriteError.differentLibrary }
                return
            }
            favoriteOutbox = outbox
        } catch {
            favoriteLoadFailure = "Saved favorite changes could not be read. They were kept unchanged. \(error.localizedDescription)"
        }
    }
}
