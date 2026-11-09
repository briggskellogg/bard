import AppKit
import Combine
import Foundation
import WispCore

/// A user-connected, one-way publishing destination. Merely launching Wisp or
/// opening Data never selects a folder or publishes the user's library.
@MainActor
final class PhoneSyncStore: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isPublishing = false
    @Published private(set) var isRenaming = false
    @Published private(set) var folderPath: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var publishedSongCount: Int?
    @Published private(set) var errorMessage: String?

    private struct Connection: Codable {
        let bookmark: Data
        let displayPath: String
    }
    private struct PublishResult {
        let manifest: PhoneLibraryManifest
        let renewedBookmark: Data?
        let folder: URL
        let favoriteWarning: String?
    }
    private let store: LibraryStore
    private let defaults: UserDefaults
    private let worker = DispatchQueue(label: "com.briggskellogg.wisp.phone-publisher", qos: .utility)
    private let connectionKey = "wisp.phone.folder.v1"
    private let identityKey = "wisp.phone.sourceLibraryID.v1"
    private var connection: Connection?
    private let sourceLibraryID: UUID
    private var generation = UUID()
    private var pending = false
    private var observation: AnyCancellable?
    private var favoriteTimer: Timer?
    @Published private(set) var isCheckingFavorites = false

    var canPublish: Bool { store.canEdit }
    var songCount: Int { store.tracks.count }
    var isBusy: Bool { isPublishing || isRenaming || isCheckingFavorites }
    var folderName: String { folderPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? PhoneSyncFolder.name }
    var canRename: Bool { isConnected && folderName != PhoneSyncFolder.name }

    init(store: LibraryStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        sourceLibraryID = defaults.string(forKey: identityKey).flatMap(UUID.init(uuidString:)) ?? UUID()
        if let data = defaults.data(forKey: connectionKey) {
            do {
                let saved = try JSONDecoder().decode(Connection.self, from: data)
                guard defaults.string(forKey: identityKey).flatMap(UUID.init(uuidString:)) != nil else {
                    throw PhoneLibrarySyncError.differentLibrary
                }
                connection = saved
                folderPath = saved.displayPath
                isConnected = true
            } catch {
                errorMessage = "The saved Phone Sync folder could not be opened. Connect it again."
            }
        }
        observation = store.$document
            .dropFirst()
            .debounce(for: .milliseconds(650), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.requestSync() }
            }
        // Reopening may refresh a previously approved destination. A new
        // installation has no destination and performs no filesystem writes.
        if isConnected { requestSync() }
        favoriteTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.receivePhoneFavorites() }
        }
    }

    deinit { favoriteTimer?.invalidate() }

    func chooseFolder() {
        guard !isBusy, store.canEdit else { return }
        let panel = NSOpenPanel()
        panel.title = "Connect Phone Sync"
        panel.message = "Choose iCloud Drive or your connected library folder. Bard keeps the Wisp folder name so existing iPhone connections continue to work."
        panel.prompt = "Connect"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        let cloud = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if FileManager.default.fileExists(atPath: cloud.path) { panel.directoryURL = cloud }
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        connect(to: selected)
    }

    /// The native chooser calls this only after explicit selection. It is also
    /// directly usable by isolated fixtures without opening a real picker.
    func connect(to selected: URL) {
        guard !isBusy, store.canEdit else { return }
        let accessed = selected.startAccessingSecurityScopedResource()
        generation = UUID()
        let expected = generation
        let document = store.document, libraryDirectory = store.directory, identity = sourceLibraryID
        pending = false
        isPublishing = true
        errorMessage = nil
        worker.async { [weak self] in
          defer { if accessed { selected.stopAccessingSecurityScopedResource() } }
          let result: Result<(Connection, PhoneLibraryManifest, URL), Error> = Result {
            guard selected.isFileURL,
                  try selected.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw PhoneLibrarySyncError.unsafePath
            }
            guard selected.lastPathComponent != "Assets" else {
                throw NSError(domain: "WispPhoneSync", code: 2, userInfo: [NSLocalizedDescriptionKey: "Choose the shared library folder above Assets, not its contents."])
            }
            let folder = try PhoneSyncFolder.destination(in: selected, libraryID: identity)
            let local = libraryDirectory.standardizedFileURL.resolvingSymlinksInPath().path
            let destination = folder.standardizedFileURL.resolvingSymlinksInPath().path
            guard destination != local, !destination.hasPrefix(local + "/"), !local.hasPrefix(destination + "/") else {
                throw PhoneLibrarySyncError.unsafePath
            }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else { throw PhoneLibrarySyncError.unsafePath }
            } else {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            }
            let bookmark = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            let saved = Connection(bookmark: bookmark, displayPath: folder.path)
            let manifest = try PhoneLibraryPublisher.publish(document: document, libraryDirectory: libraryDirectory, destination: folder, sourceLibraryID: identity)
            return (saved, manifest, folder)
          }
          Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPublishing = false
            guard self.generation == expected else { return }
            switch result {
            case .success(let (saved, manifest, folder)):
                self.saveConnection(saved)
                self.lastUpdated = manifest.publishedAt
                self.publishedSongCount = manifest.document.tracks.count
                self.applyFolderIcon(at: folder)
            case .failure(let error): self.errorMessage = error.localizedDescription
            }
            self.publishNextIfNeeded()
            if self.errorMessage == nil { self.receivePhoneFavorites() }
          }
        }
    }

    func revealFolder() {
        guard let folderPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folderPath)])
    }

    func renameFolder() {
        guard canRename, !isBusy, let folderPath else { return }
        let parent = URL(fileURLWithPath: folderPath).deletingLastPathComponent()
        let panel = NSOpenPanel()
        panel.title = "Simplify shared folder name"
        panel.message = "Select the containing folder shown here to rename the shared folder to Wisp. Your songs stay in place. On your iPhone, select that folder again if the connection needs refreshing."
        panel.prompt = "Rename to Wisp"
        panel.directoryURL = parent
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        renameFolder(in: selected)
    }

    /// The containing-folder chooser grants the scope required for a sibling
    /// rename; a selected Assets folder is never used to escape that scope.
    func renameFolder(in parent: URL) {
        guard canRename, !isBusy, let saved = connection else { return }
        let parentAccess = parent.startAccessingSecurityScopedResource()
        isRenaming = true
        errorMessage = nil
        let expected = generation, identity = sourceLibraryID
        worker.async { [weak self] in
            defer { if parentAccess { parent.stopAccessingSecurityScopedResource() } }
            let result: Result<Connection, Error> = Result {
                var stale = false
                let source = try URL(resolvingBookmarkData: saved.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }
                let moved = try PhoneSyncFolder.rename(source, inside: parent, libraryID: identity) {
                    try $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                }
                return Connection(bookmark: moved.bookmark, displayPath: moved.url.path)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isRenaming = false
                guard self.generation == expected else { return }
                switch result {
                case .success(let updated):
                    self.saveConnection(updated)
                    self.applyFolderIcon(at: URL(fileURLWithPath: updated.displayPath))
                    self.requestSync()
                case .failure(let error): self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func saveConnection(_ saved: Connection) {
        guard let encoded = try? JSONEncoder().encode(saved) else { return }
        defaults.set(sourceLibraryID.uuidString, forKey: identityKey)
        defaults.set(encoded, forKey: connectionKey)
        connection = saved
        isConnected = true
        folderPath = saved.displayPath
    }

    private func applyFolderIcon(at folder: URL) {
        // Files on iPhone may continue to use the system folder icon.
        WispFolderIcon.apply(to: folder, defaults: defaults)
    }

    func requestSync() {
        guard (isConnected && connection != nil) || isPublishing else { return }
        guard store.canEdit else {
            errorMessage = "Phone Sync is paused because the Mac library is unavailable. Your existing shared copy is unchanged."
            return
        }
        pending = true
        publishNextIfNeeded()
    }

    func disconnect() {
        guard !isRenaming else { return }
        // An in-flight coordinated copy may finish. There are no subsequent
        // jobs, and the existing shared files are deliberately left intact.
        generation = UUID()
        pending = false
        connection = nil
        defaults.removeObject(forKey: connectionKey)
        isConnected = false
        folderPath = nil
        lastUpdated = nil
        publishedSongCount = nil
        errorMessage = nil
    }

    private func publishNextIfNeeded() {
        guard pending, !isBusy, isConnected, let saved = connection else { return }
        guard store.canEdit else { pending = false; return }
        pending = false
        isPublishing = true
        errorMessage = nil
        let document = store.document
        let libraryDirectory = store.directory
        let identity = sourceLibraryID
        let expected = generation
        worker.async { [weak self] in
            let result: Result<PublishResult, Error> = Result {
                var stale = false
                let folder = try URL(resolvingBookmarkData: saved.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                let accessed = folder.startAccessingSecurityScopedResource()
                defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
                let renewed = stale ? try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) : nil
                let manifest = try PhoneLibraryPublisher.publish(document: document, libraryDirectory: libraryDirectory, destination: folder, sourceLibraryID: identity)
                var warning: String?
                for (key, sequence) in document.phoneFavoriteReceipts {
                    guard let device = UUID(uuidString: key) else { continue }
                    do {
                        try PhoneFavoritesSync.acknowledge(PhoneFavoriteAcknowledgement(sourceLibraryID: identity,
                            deviceID: device, sequence: sequence, publishedRevision: manifest.revision), in: folder)
                    } catch { warning = "Songs are shared; favorite confirmation will retry. \(error.localizedDescription)" }
                }
                return PublishResult(manifest: manifest, renewedBookmark: renewed, folder: folder, favoriteWarning: warning)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPublishing = false
                guard expected == self.generation, self.isConnected else { return }
                switch result {
                case .success(let output):
                    self.lastUpdated = output.manifest.publishedAt
                    self.publishedSongCount = output.manifest.document.tracks.count
                    self.folderPath = output.folder.path
                    self.applyFolderIcon(at: output.folder)
                    self.errorMessage = output.favoriteWarning
                    if let renewed = output.renewedBookmark {
                        let updated = Connection(bookmark: renewed, displayPath: output.folder.path)
                        if let encoded = try? JSONEncoder().encode(updated) {
                            self.connection = updated
                            self.defaults.set(encoded, forKey: self.connectionKey)
                        }
                    }
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                // Edits during a long copy collapse into one latest snapshot.
                self.publishNextIfNeeded()
                if self.errorMessage == nil { self.receivePhoneFavorites() }
            }
        }
    }

    private func receivePhoneFavorites() {
        guard isConnected, !isBusy, store.canEdit, let saved = connection else { return }
        isCheckingFavorites = true
        let expected = generation, identity = sourceLibraryID
        worker.async { [weak self] in
            let result: Result<[(PhoneFavoriteBatch, Int64)], Error> = Result {
                var stale = false
                let folder = try URL(resolvingBookmarkData: saved.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                let access = folder.startAccessingSecurityScopedResource()
                defer { if access { folder.stopAccessingSecurityScopedResource() } }
                return try PhoneFavoritesSync.batches(in: folder, sourceLibraryID: identity).map { batch in
                    let acknowledged = try PhoneFavoritesSync.acknowledgement(in: folder, sourceLibraryID: identity, deviceID: batch.deviceID)?.sequence ?? 0
                    return (batch, acknowledged)
                }
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isCheckingFavorites = false
                guard expected == self.generation, self.isConnected else { return }
                switch result {
                case .success(let batches):
                    var needsPublication = false
                    for (batch, acknowledged) in batches {
                        let consumed = self.store.document.phoneFavoriteReceipts[batch.deviceID.uuidString] ?? 0
                        guard self.store.applyPhoneFavorites(batch, sourceLibraryID: identity) else {
                            self.errorMessage = "Phone favorites could not be saved. They will retry."
                            return
                        }
                        needsPublication = needsPublication || batch.sequence > consumed || acknowledged < batch.sequence
                    }
                    if needsPublication { self.requestSync() }
                    else { self.publishNextIfNeeded() }
                case .failure(let error):
                    self.errorMessage = "Phone favorites will retry. \(error.localizedDescription)"
                    self.publishNextIfNeeded()
                }
            }
        }
    }
}
