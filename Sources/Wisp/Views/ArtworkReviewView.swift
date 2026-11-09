import AppKit
import ImageIO
import SwiftUI
import WispCore

/// Each proposed image is temporary until this song's explicit Use cover action.
@MainActor
struct ArtworkReviewView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var index = 0
    @State private var expected: Track?
    @State private var subject = ""
    @State private var candidates: [ArtworkCandidate] = []
    @State private var selectedID: String?
    @State private var prepared: PreparedArtwork?
    @State private var cropSource: ArtworkCropSource?
    @State private var cropSelection = ArtworkCropSelection()
    @State private var ownSource: TrackArtworkSource?
    @FocusState private var subjectFocused: Bool
    @State private var imageSize = ""
    @State private var ownName: String?
    @State private var searching = false
    @State private var loadingImage = false
    @State private var saving = false
    @State private var searched = false
    @State private var error: String?
    @State private var approved = 0
    @State private var skipped = 0
    @State private var requestID = UUID()
    @State private var imageRequestID = UUID()
    @State private var searchTask: Task<Void, Never>?
    @State private var imageTask: Task<Void, Never>?
    @State private var saveTask: Task<Void, Never>?

    let tracks: [Track]
    private let viewport: CGSize
    private let discovery: ArtworkReviewDiscovery
    nonisolated private static let maximumOwnImageBytes = 12 * 1024 * 1024

    init(tracks: [Track], discovery: ArtworkReviewDiscovery = .live, viewport: CGSize? = nil) {
        var seen = Set<UUID>()
        self.tracks = tracks.filter { seen.insert($0.id).inserted }
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 900)
        self.discovery = discovery
        self.viewport = viewport ?? CGSize(width: min(840, max(650, screen.width - 100)),
                          height: min(690, max(440, screen.height - 120)))
    }

    private var previewSide: CGFloat { min(306, max(200, viewport.height - 370)) }
    private var finished: Bool { index >= tracks.count }
    private var current: Track? { finished ? nil : tracks[index] }
    private var canApprove: Bool { expected != nil && cropSource != nil && !saving && !loadingImage }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if finished {
                completion
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        sourceControls
                        searchControls
                        HStack(alignment: .top, spacing: 24) {
                            previewColumn.frame(width: previewSide)
                            candidateColumn.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let error {
                            Text(error).font(WispType.ui(11)).foregroundStyle(WispSurface.amber)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.automatic)
                approvalFooter
            }
        }
        .padding(24).frame(width: viewport.width, height: viewport.height)
        .background(WispSurface.main).foregroundStyle(WispSurface.ink).tint(WispSurface.cyan)
        .background(ArtworkKeyboardShortcuts(enabled: !saving && !finished && expected != nil,
            paste: pasteImage, upload: chooseOwnImage, search: searchImages))
        .interactiveDismissDisabled(saving)
        .task { beginCurrent() }
        .onDisappear {
            cancelWork()
            saveTask?.cancel()
            clearImage()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text("Artwork").font(WispType.ui(17, weight: .medium))
                    if !finished {
                        Text("\(index + 1) of \(tracks.count)").font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                    }
                }
                if let current {
                    Text(current.displayTitle).font(WispType.ui(12)).lineLimit(1)
                    let detail = [current.artist, current.origin].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " · ")
                    if !detail.isEmpty {
                        Text(detail).font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText).lineLimit(1)
                    }
                }
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 11)).frame(width: 24, height: 24)
            }.buttonStyle(.plain).foregroundStyle(WispSurface.mutedText)
                .accessibilityLabel("Close artwork review").keyboardShortcut(.cancelAction).disabled(saving)
        }
    }

    private var sourceControls: some View {
        HStack(spacing: 20) {
            sourceButton("Search Images", icon: "magnifyingglass", shortcut: "⌘⇧F", action: searchImages)
            sourceButton("Upload Image", icon: "arrow.up.doc", shortcut: "⌘O", action: chooseOwnImage)
            sourceButton("Paste Image", icon: "doc.on.clipboard", shortcut: "⌘V", action: pasteImage)
            Spacer(minLength: 0)
        }
        .disabled(saving || expected == nil)
    }

    private func sourceButton(_ title: String, icon: String, shortcut: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(WispType.ui(11))
                Text(shortcut).font(WispType.ui(9)).foregroundStyle(WispSurface.mutedText)
            }.padding(.vertical, 7).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.tint).help("\(title) · \(shortcut)")
    }

    private var searchControls: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("Search for").font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
            TextField("Song, soundtrack, or release", text: $subject)
                .modifier(QuietFieldLine()).accessibilityLabel("Artwork subject").focused($subjectFocused)
                .onSubmit { search() }
            Button(action: search) {
                Label("Suggestions", systemImage: "sparkle").font(WispType.ui(11))
            }.buttonStyle(.plain).foregroundStyle(.tint)
                .disabled(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving || expected == nil)
            if searching || loadingImage { ProgressView().controlSize(.small) }
        }
        .disabled(saving)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                WispSurface.sidebar
                if let cropSource {
                    ArtworkCropPreview(source: cropSource, selection: $cropSelection, side: previewSide)
                        .disabled(saving || loadingImage)
                } else {
                    VStack(spacing: 12) {
                        if loadingImage { ProgressView().controlSize(.small) }
                        else { Image(systemName: "photo").font(.system(size: 24, weight: .ultraLight)) }
                        Text(loadingImage ? "Preparing preview…" : "Search, upload, or paste an image")
                            .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                    }
                }
            }
            .frame(width: previewSide, height: previewSide)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .accessibilityLabel("Proposed cover preview")
            if let cropSource {
                cropControls(cropSource)
            }

        }
    }

    private func cropControls(_ source: ArtworkCropSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "minus.magnifyingglass").font(.system(size: 10))
                Slider(value: Binding(get: { cropSelection.zoom }, set: {
                    cropSelection.zoom = $0
                    cropSelection = cropSelection.clamped(sourceWidth: source.pixelWidth, sourceHeight: source.pixelHeight)
                }), in: 1...ArtworkCropSelection.maximumZoom)
                    .accessibilityLabel("Cover zoom")
                Image(systemName: "plus.magnifyingglass").font(.system(size: 10))
                Button("Reset") { cropSelection = ArtworkCropSelection() }.buttonStyle(.plain)
                    .font(WispType.ui(10)).foregroundStyle(.tint)
            }
            Text("Drag to crop · arrow keys to fine-tune")
                .font(WispType.ui(9)).foregroundStyle(WispSurface.mutedText)
        }.disabled(saving || loadingImage)
    }

    private func candidateCredit(_ image: PreparedArtwork) -> some View {
        let candidate = image.candidate
        let width = candidate.sourcePixelWidth ?? image.pixelWidth
        let height = candidate.sourcePixelHeight ?? image.pixelHeight
        return VStack(alignment: .leading, spacing: 5) {
            Link(destination: candidate.pageURL) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(candidate.title).lineLimit(2)
                    Image(systemName: "arrow.up.right").font(.system(size: 8))
                }
            }.font(WispType.ui(11))
            Text("\(candidate.sourceName) · \(width) × \(height)")
                .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
            if !candidate.credit.isEmpty {
                Text(candidate.credit).font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                    .lineLimit(3).help(candidate.credit)
            }
            Text(candidate.isOfficial ? "Artist / publisher release artwork" : "Creator source not verified")
                .font(WispType.ui(9)).foregroundStyle(WispSurface.mutedText)
            switch image.textCheck {
            case .clear:
                Text("No text detected").font(WispType.ui(9)).foregroundStyle(WispSurface.mutedText)
            case .detected:
                Text("Text detected\(image.detectedText.isEmpty ? "" : ": " + image.detectedText.prefix(4).joined(separator: ", "))")
                    .font(WispType.ui(10)).foregroundStyle(WispSurface.amber).lineLimit(2)
            case .unavailable:
                Text("Text check unavailable · inspect the image")
                    .font(WispType.ui(9)).foregroundStyle(WispSurface.mutedText)
            }
        }
    }

    private var candidateColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Suggestions").font(WispType.ui(11, weight: .medium))
                Spacer()
                if !candidates.isEmpty { Text("\(candidates.count)").font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText) }
            }
            if candidates.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text(ownName != nil ? "Adjust your square crop." : searching ? "Finding square release covers…" : searched ? "No matching square cover found." : "Find a cover for this song.")
                        .font(WispType.ui(12))
                    Text(ownName != nil ? "Drag the image or adjust the zoom. Use cover saves this crop only to this song." : searching ? "Looking for artwork released by the artist or publisher. Every cover needs your approval." : "Search in your browser, copy an image, then press ⌘V here. You can crop it before saving.")
                        .font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(candidates) { candidate in candidateRow(candidate) }
                    }
                }.frame(maxHeight: min(220, CGFloat(candidates.count) * 72 + 40))
            }
            if let prepared {
                candidateCredit(prepared)
            } else if let ownName {
                VStack(alignment: .leading, spacing: 5) {
                    Text(ownName).font(WispType.ui(11)).lineLimit(2)
                    Text("Your image · \(imageSize)").font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                }
            }
            Text("Nothing is applied automatically.")
                .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
        }
    }

    private func candidateRow(_ candidate: ArtworkCandidate) -> some View {
        Button { select(candidate) } label: {
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(selectedID == candidate.id ? WispSurface.cyan : .clear).frame(width: 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(candidate.title).font(WispType.ui(11, weight: selectedID == candidate.id ? .medium : .regular))
                        .foregroundStyle(WispSurface.ink).lineLimit(2)
                    Text("\(candidate.sourceName) · \(matchLabel(candidate.match))")
                        .font(WispType.ui(9)).foregroundStyle(WispSurface.mutedText).lineLimit(2)
                    if selectedID == candidate.id, !candidate.explanation.isEmpty {
                        Text(candidate.explanation).font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if selectedID == candidate.id && loadingImage { ProgressView().controlSize(.mini) }
            }
            .padding(.vertical, 9).padding(.trailing, 8).contentShape(Rectangle())
            .background(selectedID == candidate.id ? WispSurface.sidebar : .clear)
        }
        .buttonStyle(.plain).disabled(saving)
        .accessibilityLabel("Preview \(candidate.title), \(candidate.sourceName), \(matchLabel(candidate.match))")
        .accessibilityAddTraits(selectedID == candidate.id ? .isSelected : [])
    }

    private var approvalFooter: some View {
        HStack(spacing: 14) {
            if let expected, let url = store.artworkURL(for: expected),
               let image = WispImageCache.image(at: url, fitting: CGSize(width: 34, height: 34), scale: displayScale, fill: true) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill().frame(width: 34, height: 34).clipped()
                    .accessibilityLabel("Current cover")
                Button("Edit current", action: editCurrentImage).buttonStyle(.plain)
                    .font(WispType.ui(10)).foregroundStyle(.tint).disabled(saving)
                    .help("Crop the current cover without replacing it until you approve")
            } else {
                Text("Approve each song’s cover.")
                    .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
            }
            Spacer()
            Button("Skip") { advance(approved: false) }.buttonStyle(.plain).disabled(saving)
            Button(saving ? "Saving…" : "Use cover", action: useCover)
                .buttonStyle(.borderedProminent).disabled(!canApprove)
                .accessibilityLabel(expected?.artworkFileName == nil ? "Use this cover for this song" : "Replace this song’s current cover with this image")
        }
        .font(WispType.ui(11))
    }

    private var completion: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark").font(.system(size: 25, weight: .light)).foregroundStyle(WispSurface.cyan)
            Text("Artwork reviewed").font(WispType.ui(16, weight: .medium))
            Text("\(approved) \(approved == 1 ? "cover" : "covers") updated · \(skipped) skipped")
                .font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
            Spacer()
            HStack { Spacer(); Button("Done", action: close).buttonStyle(.borderedProminent) }
        }.frame(maxWidth: .infinity)
    }

    private func beginCurrent() {
        guard let current else { return }
        cancelWork()
        clearImage()
        candidates = []
        selectedID = nil
        searched = false
        error = nil
        subject = current.title
        expected = store.track(id: current.id)
        guard expected != nil else { error = "This song is no longer in your library. You can skip it."; return }
        search()
    }

    private func search() {
        guard !saving, let expected else { return }
        let value = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        cancelWork()
        clearImage()
        candidates = []
        selectedID = nil
        error = nil
        searching = true
        searched = false
        let token = UUID()
        requestID = token
        let override = value == expected.title.trimmingCharacters(in: .whitespacesAndNewlines) ? nil : value
        let request = ArtworkRequest(track: expected, subjectOverride: override)
        searchTask = Task { @MainActor in
            do {
                let result = try await discovery.search(request)
                guard !Task.isCancelled, requestID == token else { return }
                candidates = result
                searching = false
                searched = true
                searchTask = nil
                if let first = result.first { select(first) }
            } catch {
                guard !Task.isCancelled, requestID == token else { return }
                searching = false
                searched = true
                searchTask = nil
                self.error = "Artwork search couldn’t finish: \(error.localizedDescription) Refine the song or release, or choose a square cover from the creator."
            }
        }
    }

    private func select(_ candidate: ArtworkCandidate) {
        guard !saving else { return }
        imageTask?.cancel()
        clearImage()
        selectedID = candidate.id
        loadingImage = true
        error = nil
        let token = UUID()
        imageRequestID = token
        imageTask = Task { @MainActor in
            do {
                let result = try await discovery.prepare(candidate)
                guard !Task.isCancelled, imageRequestID == token else { discovery.discard(result); return }
                let crop: ArtworkCropSource
                do {
                    crop = try await Task.detached(priority: .userInitiated) {
                        try ArtworkCrop.prepare(Data(contentsOf: result.fileURL))
                    }.value
                } catch { discovery.discard(result); throw error }
                guard !Task.isCancelled, imageRequestID == token else { discovery.discard(result); return }
                prepared = result
                cropSource = crop
                cropSelection = ArtworkCropSelection()
                loadingImage = false
                imageTask = nil
            } catch {
                guard !Task.isCancelled, imageRequestID == token else { return }
                loadingImage = false
                imageTask = nil
                self.error = "This image couldn’t be prepared: \(error.localizedDescription) Choose another candidate or your own image."
            }
        }
    }

    private func chooseOwnImage() {
        guard !saving, let url = NativeFiles.chooseCover() else { return }
        subjectFocused = false
        loadImage(name: url.lastPathComponent) { try Self.readOwnImage(url) }
    }

    private func editCurrentImage() {
        guard !saving, let expected, let url = store.artworkURL(for: expected) else { return }
        subjectFocused = false
        loadImage(name: "Current cover", provenance: expected.artworkSource) { try Self.readOwnImage(url) }
    }

    private func loadImage(name: String, provenance: TrackArtworkSource? = nil,
                           maximumBytes: Int = ArtworkCrop.maximumImageBytes,
                           read: @escaping @Sendable () throws -> Data) {
        // Loading and cropping remain temporary until the explicit approval action.
        cancelWork()
        loadingImage = true
        error = nil
        let token = UUID()
        imageRequestID = token
        imageTask = Task { @MainActor in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ArtworkCrop.prepare(read(), maximumBytes: maximumBytes)
                }.value
                guard !Task.isCancelled, imageRequestID == token else { return }
                clearImage()
                selectedID = nil
                cropSource = result
                cropSelection = ArtworkCropSelection()
                ownName = name
                ownSource = provenance
                imageSize = "\(result.pixelWidth) × \(result.pixelHeight)"
                loadingImage = false
                imageTask = nil
            } catch {
                guard !Task.isCancelled, imageRequestID == token else { return }
                loadingImage = false
                imageTask = nil
                self.error = error.localizedDescription
            }
        }
    }

    private func searchImages() {
        guard !saving, let expected else { return }
        let value = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let override = value.isEmpty || value == expected.title ? nil : value
        subjectFocused = false
        let url = ArtworkSearch.googleImagesURL(for: ArtworkRequest(track: expected, subjectOverride: override))
        if !NSWorkspace.shared.open(url) {
            error = "The browser couldn’t open. Try again, or choose a saved cover."
        }
    }

    private func pasteImage() {
        guard !saving, expected != nil else { return }
        do {
            let data = try ArtworkClipboard.imageData()
            subjectFocused = false
            loadImage(name: "Pasted image", maximumBytes: ArtworkCrop.maximumClipboardBytes) { data }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func useCover() {
        guard canApprove, let expected, let cropSource else { return }
        saving = true
        error = nil
        store.errorMessage = nil
        let chosen = prepared
        let selection = cropSelection
        let existingSource = ownSource
        saveTask = Task { @MainActor in
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try ArtworkCrop.render(source: cropSource, selection: selection)
                }.value
                guard !Task.isCancelled else { saving = false; return }
                let source = chosen.map { image in
                    TrackArtworkSource(provider: image.candidate.sourceName,
                        sourcePageURL: image.candidate.pageURL.absoluteString,
                        imageURL: image.candidate.imageURL.absoluteString,
                        credit: image.candidate.credit, title: image.candidate.title)
                } ?? existingSource
                let applied = store.applyArtwork(to: expected, data: output.data, source: source,
                                                 replaceExisting: expected.artworkFileName != nil)
                saving = false
                saveTask = nil
                if applied { advance(approved: true) }
                else { error = store.errorMessage ?? "The cover could not be saved. The song is unchanged." }
            } catch {
                guard !Task.isCancelled else { saving = false; return }
                saving = false
                saveTask = nil
                self.error = "The cover could not be saved: \(error.localizedDescription)"
            }
        }
    }

    private func advance(approved didApprove: Bool) {
        guard !saving else { return }
        cancelWork()
        clearImage()
        if didApprove { approved += 1 } else { skipped += 1 }
        index += 1
        expected = nil
        beginCurrent()
    }

    private func cancelWork() {
        requestID = UUID()
        imageRequestID = UUID()
        searchTask?.cancel(); searchTask = nil
        imageTask?.cancel(); imageTask = nil
        searching = false
        loadingImage = false
    }

    private func clearImage() {
        if let prepared { discovery.discard(prepared) }
        prepared = nil
        cropSource = nil
        cropSelection = ArtworkCropSelection()
        ownSource = nil
        ownName = nil
        imageSize = ""
    }

    private func close() {
        guard !saving else { return }
        cancelWork()
        clearImage()
        dismiss()
    }

    private func matchLabel(_ match: ArtworkMatchLevel) -> String {
        switch match {
        case .specificSubject: return "Subject match"
        case .originOnly: return "Origin only"
        case .uncertain: return "Check subject"
        }
    }

    nonisolated private static func readOwnImage(_ url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumOwnImageBytes else {
            throw ArtworkReviewError.invalid("Choose an image smaller than 12 MB.")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumOwnImageBytes + 1) ?? Data()
        guard !data.isEmpty, data.count <= maximumOwnImageBytes else { throw ArtworkReviewError.invalid("Choose an image smaller than 12 MB.") }
        return data
    }


}

private enum ArtworkReviewError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

/// The live provider owns temporary proposals; injection keeps native previews offline.
struct ArtworkReviewDiscovery {
    var search: (ArtworkRequest) async throws -> [ArtworkCandidate]
    var prepare: (ArtworkCandidate) async throws -> PreparedArtwork
    var discard: (PreparedArtwork) -> Void

    static let live = ArtworkReviewDiscovery(
        search: { try await ArtworkDiscovery.search($0) },
        prepare: { try await ArtworkDiscovery.prepare($0) },
        discard: { ArtworkDiscovery.discard($0) }
    )
}
