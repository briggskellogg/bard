import AppKit
import Combine
import SwiftUI
import WispCore

/// A preview may refer to saved artwork or an unsaved import draft. Neither
/// representation writes a file or changes a song.
struct EditorArtworkCurrent {
    var identity: String?
    var url: URL?
    var image: CGImage?
    var source: TrackArtworkSource?

    init(track: Track, url: URL?) {
        self.identity = track.artworkFileName
        self.url = url
        self.image = nil
        self.source = track.artworkSource
    }

    init(identity: String? = nil, image: CGImage? = nil, source: TrackArtworkSource? = nil) {
        self.identity = identity; self.image = image; self.source = source
    }
}

@MainActor
final class EditorArtworkDraft: ObservableObject {
    enum Change { case unchanged, replace, remove }
    @Published private(set) var change = Change.unchanged
    @Published private(set) var image: ArtworkCropSource?
    @Published var selection = ArtworkCropSelection()
    @Published private(set) var isLoading = false
    @Published var error: String?
    @Published private(set) var imageName = ""
    private var attribution: TrackArtworkSource?
    private var imageID = UUID()
    private var requestID = UUID()
    private var loadingTask: Task<Void, Never>?

    var hasChanges: Bool { change != .unchanged }

    func reset() {
        cancelLoading(); image = nil; selection = ArtworkCropSelection()
        attribution = nil; imageName = ""; change = .unchanged; error = nil
    }

    func remove() {
        reset(); change = .remove
    }

    func cancelLoading() {
        requestID = UUID(); loadingTask?.cancel(); loadingTask = nil; isLoading = false
    }

    @discardableResult
    func load(name: String, maximumBytes: Int = ArtworkCrop.maximumImageBytes,
              source: TrackArtworkSource? = nil,
              read: @escaping @Sendable () throws -> Data) -> Task<Void, Never> {
        cancelLoading(); error = nil; isLoading = true
        let token = UUID(); requestID = token
        let task = Task { @MainActor [weak self] in
            do {
                let prepared = try await Task.detached(priority: .userInitiated) {
                    try ArtworkCrop.prepare(read(), maximumBytes: maximumBytes)
                }.value
                guard let self, !Task.isCancelled, self.requestID == token else { return }
                self.adopt(prepared, name: name, attribution: source)
            } catch {
                guard let self, !Task.isCancelled, self.requestID == token else { return }
                self.error = error.localizedDescription
                self.isLoading = false; self.loadingTask = nil
            }
        }
        loadingTask = task
        return task
    }

    func adopt(_ image: ArtworkCropSource, name: String, attribution: TrackArtworkSource? = nil,
               sharedID: UUID = UUID()) {
        cancelLoading()
        self.image = image; self.imageName = name; self.attribution = attribution
        imageID = sharedID; selection = ArtworkCropSelection(); change = .replace; error = nil
    }

    func cropCurrent(_ current: EditorArtworkCurrent) {
        if let image = current.image {
            adopt(ArtworkCropSource(image: image), name: "Current cover", attribution: current.source)
        } else if let url = current.url {
            load(name: "Current cover", source: current.source) { try Self.readFile(url) }
        }
    }

    func preview(current: EditorArtworkCurrent) -> EditorArtworkCurrent {
        switch change {
        case .unchanged: return current
        case .remove: return EditorArtworkCurrent()
        case .replace:
            guard let image else { return current }
            let crop = image.image.cropping(to: selection.pixelRect(sourceWidth: image.pixelWidth, sourceHeight: image.pixelHeight))
            return EditorArtworkCurrent(identity: "\(imageID)-\(selection.centerX)-\(selection.centerY)-\(selection.zoom)",
                                        image: crop, source: attribution)
        }
    }

    /// Snapshot once when Save/Import is pressed. All mutation belongs to the
    /// caller's transactional save, never image loading or crop gestures.
    func preparedEdit() async throws -> TrackArtworkEdit {
        guard !isLoading else { throw EditorArtworkError.preparing }
        switch change {
        case .unchanged: return .unchanged
        case .remove: return .remove
        case .replace:
            guard let image else { throw EditorArtworkError.preparing }
            let crop = selection, source = attribution
            let result = try await Task.detached(priority: .userInitiated) {
                try ArtworkCrop.render(source: image, selection: crop)
            }.value
            return .replace(data: result.data, source: source)
        }
    }

    nonisolated static func readFile(_ url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize,
              size > 0, size <= ArtworkCrop.maximumImageBytes else { throw ArtworkCropError.oversized }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: ArtworkCrop.maximumImageBytes + 1) ?? Data()
        guard data.count <= ArtworkCrop.maximumImageBytes else { throw ArtworkCropError.oversized }
        return data
    }
}

enum EditorArtworkError: LocalizedError {
    case preparing
    var errorDescription: String? { "Wait for the image preview to finish, then save again." }
}

enum EditorArtworkSearch {
    static func shared(_ values: [String]) -> String? {
        guard let first = values.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty,
              values.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(first) == .orderedSame }) else { return nil }
        return first
    }

    static func subject(for tracks: [Track]) -> String {
        if tracks.count > 1 {
            return shared(tracks.map(\.origin)) ?? shared(tracks.map(\.artist)) ?? tracks.first?.title ?? ""
        }
        return tracks.first?.title ?? ""
    }

    static func request(tracks: [Track], subject: String) -> ArtworkRequest? {
        guard var track = tracks.first else { return nil }
        if tracks.count > 1 {
            track.origin = shared(tracks.map(\.origin)) ?? ""
            track.artist = shared(tracks.map(\.artist)) ?? ""
        }
        return ArtworkRequest(track: track, subjectOverride: subject)
    }
}

/// Each import song keeps its own staged crop when the selection changes.
/// Forward child changes so the final Import action knows when images are ready.
@MainActor
final class EditorArtworkImportDrafts: ObservableObject {
    let drafts: [UUID: EditorArtworkDraft]
    private var observations: [AnyCancellable] = []

    init(tracks: [Track]) {
        drafts = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, EditorArtworkDraft()) })
        observations = drafts.values.map { draft in
            draft.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }

    func isLoading(ids: Set<UUID>) -> Bool { ids.contains { drafts[$0]?.isLoading == true } }
    func cancelLoading() { drafts.values.forEach { $0.cancelLoading() } }

    func edits(for tracks: [Track]) async throws -> [UUID: TrackArtworkEdit] {
        var edits: [UUID: TrackArtworkEdit] = [:]
        for track in tracks {
            if let draft = drafts[track.id] {
                let edit = try await draft.preparedEdit()
                if edit.changesArtwork { edits[track.id] = edit }
            }
        }
        return edits
    }

    func apply(_ edit: TrackArtworkEdit, to ids: Set<UUID>) async throws {
        switch edit {
        case .unchanged: break
        case .remove: ids.forEach { drafts[$0]?.remove() }
        case let .replace(data, source):
            let image = try await Task.detached(priority: .userInitiated) { try ArtworkCrop.prepare(data) }.value
            let sharedID = UUID()
            ids.forEach { drafts[$0]?.adopt(image, name: "Shared cover", attribution: source, sharedID: sharedID) }
        }
    }
}
