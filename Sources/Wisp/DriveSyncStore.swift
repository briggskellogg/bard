import AppKit
import Combine
import Foundation
import WispCore

/// Publishes an additional, readable copy of the Mac library. Proton Drive's
/// Finder provider is responsible for uploading it; Wisp never treats a local
/// file write as confirmation that the remote service has received the file.
@MainActor
final class DriveSyncStore: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isPublishing = false
    @Published private(set) var folderPath: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var publishedSongCount: Int?
    @Published private(set) var errorMessage: String?

    private struct Connection: Codable {
        var bookmark: Data
        var displayPath: String
        var lastUpdated: Date?
        var songCount: Int?
    }

    private struct PublishResult {
        let mirror: DriveLibraryMirrorResult
        let connection: Connection
        let folder: URL
    }

    private let store: LibraryStore
    private let defaults: UserDefaults
    private let cloudStorage: URL
    private let worker = DispatchQueue(label: "com.briggskellogg.wisp.drive-publisher", qos: .utility)
    private let connectionKey = "wisp.drive.folder.v1"
    private let identityKey = "wisp.drive.sourceLibraryID.v1"
    private let sourceLibraryID: UUID
    private var connection: Connection?
    private var generation = UUID()
    private var pending = false
    private var observation: AnyCancellable?
    private var retryTimer: Timer?
    private var wakeObservation: NSObjectProtocol?

    var canPublish: Bool { store.canEdit && !store.tracks.isEmpty }
    var songCount: Int { store.tracks.count }

    init(store: LibraryStore, defaults: UserDefaults = .standard, cloudStorage: URL? = nil,
         retryInterval: TimeInterval = 60) {
        self.store = store
        self.defaults = defaults
        self.cloudStorage = cloudStorage ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let savedIdentity = defaults.string(forKey: identityKey).flatMap(UUID.init(uuidString:))
        sourceLibraryID = savedIdentity ?? UUID()
        if let data = defaults.data(forKey: connectionKey) {
            do {
                guard savedIdentity != nil else { throw DriveConnectionError.missingIdentity }
                let saved = try JSONDecoder().decode(Connection.self, from: data)
                connection = saved
                folderPath = saved.displayPath
                lastUpdated = saved.lastUpdated
                publishedSongCount = saved.songCount
                isConnected = true
            } catch {
                errorMessage = "The saved Proton Drive connection needs to be selected again. Existing copies are unchanged."
            }
        }
        observation = store.$document
            .dropFirst()
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.requestSync() }
            }
        retryTimer = Timer.scheduledTimer(withTimeInterval: max(0.05, retryInterval), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.retryIfNeeded() }
        }
        wakeObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.requestSync() }
        }
        // A new install is inert. Only a previously selected destination is
        // refreshed on launch, after edits, on wake, and after failed updates.
        if isConnected { requestSync() }
    }

    deinit {
        retryTimer?.invalidate()
        if let wakeObservation { NSWorkspace.shared.notificationCenter.removeObserver(wakeObservation) }
    }

    func chooseFolder() {
        guard !isPublishing, canPublish else { return }
        let panel = NSOpenPanel()
        panel.title = "Connect Proton Drive"
        panel.message = "Choose your connected library folder, or a place inside Proton Drive for a new one. Bard keeps your songs, artwork, and playlists updated there."
        panel.prompt = "Connect"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        let candidates = Self.protonRoots(in: cloudStorage)
        // File Provider leaves dated folders behind after some reconnections.
        // Prefer a sole current root only as the picker's starting location.
        let current = candidates.filter { $0.lastPathComponent.hasSuffix("-folder") }
        if let folderPath, FileManager.default.fileExists(atPath: folderPath) {
            panel.directoryURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        } else {
            panel.directoryURL = current.count == 1 ? current[0] : (candidates.count == 1 ? candidates[0] : cloudStorage)
        }
        guard panel.runModal() == .OK, let selected = panel.url else { return }
        connect(to: selected)
    }

    /// Called by the native picker. Tests may supply a fixture CloudStorage root
    /// to exercise connection logic without reading or writing real user data.
    func connect(to selected: URL) {
        guard !isPublishing, canPublish else { return }
        let access = selected.startAccessingSecurityScopedResource()
        let expected = UUID()
        generation = expected
        pending = false
        isPublishing = true
        errorMessage = nil
        let document = store.document, directory = store.directory, identity = sourceLibraryID
        let providerRoot = cloudStorage
        // Save the identity before an owned folder can be created. If the app
        // closes mid-copy, choosing that folder again safely resumes its work.
        defaults.set(identity.uuidString, forKey: identityKey)
        worker.async { [weak self] in
            defer { if access { selected.stopAccessingSecurityScopedResource() } }
            let result: Result<PublishResult, Error> = Result {
                let folder = try Self.destination(for: selected, cloudStorage: providerRoot)
                let mirror = try DriveLibraryMirror.publish(document: document, libraryDirectory: directory,
                                                           destination: folder, sourceLibraryID: identity)
                let bookmark = try folder.bookmarkData(options: .withSecurityScope,
                                                      includingResourceValuesForKeys: nil, relativeTo: nil)
                let saved = Connection(bookmark: bookmark, displayPath: folder.path,
                                       lastUpdated: mirror.publishedAt, songCount: mirror.songCount)
                return PublishResult(mirror: mirror, connection: saved, folder: folder)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPublishing = false
                guard self.generation == expected else { return }
                switch result {
                case .success(let output):
                    self.saveConnection(output.connection)
                    self.applyFolderIcon(at: output.folder)
                case .failure(let error): self.errorMessage = error.localizedDescription
                }
                if !self.isConnected { self.pending = false }
                self.publishNextIfNeeded()
            }
        }
    }

    func requestSync() {
        guard isConnected || isPublishing else { return }
        guard store.canEdit else {
            errorMessage = "Copying is paused because the Bard library is unavailable. Existing Proton Drive files are unchanged."
            return
        }
        guard !store.tracks.isEmpty else {
            errorMessage = "There are no songs to copy. Existing Proton Drive files are unchanged."
            return
        }
        pending = true
        publishNextIfNeeded()
    }

    func retryIfNeeded() {
        // Do not read or rehydrate an already-current cloud library every
        // minute. Successful updates wait for an edit, launch, wake, or request.
        guard isConnected, pending || errorMessage != nil else { return }
        requestSync()
    }

    func disconnect() {
        // An in-flight coordinated copy may finish; invalidating its generation
        // prevents it reconnecting itself or scheduling more work afterward.
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

    func revealFolder() {
        guard let folderPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folderPath)])
    }

    private func publishNextIfNeeded() {
        guard pending, !isPublishing, isConnected, let saved = connection, canPublish else { return }
        pending = false
        isPublishing = true
        errorMessage = nil
        let expected = generation, identity = sourceLibraryID
        let document = store.document, directory = store.directory, providerRoot = cloudStorage
        worker.async { [weak self] in
            let result: Result<PublishResult, Error> = Result {
                var stale = false
                let folder = try URL(resolvingBookmarkData: saved.bookmark,
                                     options: [.withSecurityScope, .withoutUI], relativeTo: nil,
                                     bookmarkDataIsStale: &stale)
                let access = folder.startAccessingSecurityScopedResource()
                defer { if access { folder.stopAccessingSecurityScopedResource() } }
                // A moved bookmark must still resolve inside Proton Drive.
                // Never redirect copies into an unrelated replacement path.
                try Self.validateProtonSelection(folder, cloudStorage: providerRoot)
                let mirror = try DriveLibraryMirror.publish(document: document, libraryDirectory: directory,
                                                           destination: folder, sourceLibraryID: identity)
                let bookmark = stale ? try folder.bookmarkData(options: .withSecurityScope,
                    includingResourceValuesForKeys: nil, relativeTo: nil) : saved.bookmark
                let updated = Connection(bookmark: bookmark, displayPath: folder.path,
                                         lastUpdated: mirror.publishedAt, songCount: mirror.songCount)
                return PublishResult(mirror: mirror, connection: updated, folder: folder)
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPublishing = false
                guard self.generation == expected, self.isConnected else { return }
                switch result {
                case .success(let output):
                    self.saveConnection(output.connection)
                    self.applyFolderIcon(at: output.folder)
                case .failure(let error): self.errorMessage = error.localizedDescription
                }
                self.publishNextIfNeeded()
            }
        }
    }

    private func saveConnection(_ saved: Connection) {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        connection = saved
        defaults.set(data, forKey: connectionKey)
        isConnected = true
        folderPath = saved.displayPath
        lastUpdated = saved.lastUpdated
        publishedSongCount = saved.songCount
    }

    private func applyFolderIcon(at folder: URL) {
        WispFolderIcon.apply(to: folder, defaults: defaults)
    }

    nonisolated static func protonRoots(in cloudStorage: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let children = (try? FileManager.default.contentsOfDirectory(at: cloudStorage,
            includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
        return children.filter { url in
            guard url.lastPathComponent.hasPrefix("ProtonDrive-"),
                  let values = try? url.resourceValues(forKeys: keys) else { return false }
            return values.isDirectory == true && values.isSymbolicLink != true
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    nonisolated static func destination(for selected: URL, cloudStorage: URL) throws -> URL {
        try validateProtonSelection(selected, cloudStorage: cloudStorage)
        // Keep a user's casing or renamed mirror. Publishing still verifies
        // the ownership marker and refuses another library or unowned files.
        let isNamedWisp = selected.lastPathComponent.caseInsensitiveCompare("Wisp") == .orderedSame
        let hasMirrorIdentity = FileManager.default.fileExists(atPath:
            selected.appendingPathComponent(DriveLibraryMirror.ownershipName).path)
        return isNamedWisp || hasMirrorIdentity ? selected : selected.appendingPathComponent("Wisp", isDirectory: true)
    }

    nonisolated private static func validateProtonSelection(_ selected: URL, cloudStorage: URL) throws {
        guard selected.isFileURL else { throw DriveConnectionError.notProton }
        let selectedURL = selected.standardizedFileURL
        let providerURL = cloudStorage.standardizedFileURL.resolvingSymlinksInPath()
        let values = try selectedURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw DriveConnectionError.notProton }
        let resolved = selectedURL.resolvingSymlinksInPath()
        let prefix = providerURL.path + "/"
        guard resolved.path.hasPrefix(prefix) else { throw DriveConnectionError.notProton }
        let relative = String(resolved.path.dropFirst(prefix.count))
        guard let root = relative.split(separator: "/").first, root.hasPrefix("ProtonDrive-") else {
            throw DriveConnectionError.notProton
        }
        // Reject a nested symlink that resolves into a different provider path,
        // while accepting macOS's normal /var -> /private/var normalization.
        let standardizedProvider = cloudStorage.standardizedFileURL.path + "/"
        guard selectedURL.path.hasPrefix(standardizedProvider) else { throw DriveConnectionError.notProton }
        let lexicalRelative = String(selectedURL.path.dropFirst(standardizedProvider.count))
        guard lexicalRelative == relative else { throw DriveConnectionError.notProton }
    }

    private enum DriveConnectionError: LocalizedError {
        case notProton, missingIdentity
        var errorDescription: String? {
            switch self {
            case .notProton: return "Choose a folder inside Proton Drive in Finder. Bard keeps using the Wisp folder name for compatibility with existing connections."
            case .missingIdentity: return "The saved Proton Drive connection needs to be selected again."
            }
        }
    }
}
