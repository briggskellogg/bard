import SwiftUI
import AppKit
import WispCore

/// The same metadata surface serves one song, a saved selection, and import drafts.
/// In batch mode, unchecked fields never change any selected song.
struct TrackMetadataFields: View {
    @Binding var patch: TrackMetadataPatch
    var tracks: [Track]
    var bulk = false
    var focusSource = false
    @FocusState private var sourceFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            row("Title", applied: $patch.applyTitle) {
                TextField(placeholder(\.title, empty: "Track title"), text: $patch.title)
                    .modifier(QuietFieldLine()).accessibilityLabel("Title")
            }
            row("Artist", applied: $patch.applyArtist) {
                TextField(placeholder(\.artist, empty: "Artist"), text: $patch.artist)
                    .modifier(QuietFieldLine()).accessibilityLabel("Artist")
            }
            row("Genre", applied: $patch.applyGenre) {
                TextField(placeholder(\.genre, empty: "Music genre (optional)"), text: $patch.genre)
                    .modifier(QuietFieldLine()).accessibilityLabel("Genre")
            }
            row("Origin", applied: $patch.applyOrigin) {
                TextField(placeholder(\.origin, empty: "Game, film, original song… (optional)"), text: $patch.origin)
                    .modifier(QuietFieldLine()).accessibilityLabel("Origin")
            }
            row("Category", applied: $patch.applyMediaKind) {
                if bulk && !patch.applyMediaKind && mixed(\.originMediaKind) {
                    mixedValue
                } else { MediaKindPicker(selection: $patch.originMediaKind) }
            }
            row("Collection", applied: $patch.applyRemix) {
                if bulk && !patch.applyRemix && mixed(\.remix) {
                    mixedValue
                } else { RemixPicker(selection: $patch.remix) }
            }
            row("Source", applied: $patch.applySource) {
                HStack(spacing: 8) {
                    TextField(bulk && mixed(\.sourceURL) ? "Multiple values" : "Website link (optional)", text: $patch.source)
                        .modifier(QuietFieldLine()).accessibilityLabel("Source").focused($sourceFocused)
                    if let url = validatedWebURL(patch.source) {
                        Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.right") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Open source link")
                    }
                }
            }
            row("Favorite", applied: $patch.applyFavorite) {
                if bulk && !patch.applyFavorite && mixed(\.favorite) {
                    mixedValue
                } else {
                    Picker("Favorite", selection: $patch.favorite) {
                        Text("Favorite").tag(true)
                        Text("Not a favorite").tag(false)
                    }.labelsHidden().pickerStyle(.menu).buttonStyle(.borderless)
                }
            }
        }
        .task { if focusSource { sourceFocused = true } }
    }

    private var mixedValue: some View {
        Text("Multiple values").font(WispType.ui(12)).foregroundStyle(.secondary).padding(.vertical, 4)
    }

    private func row<Content: View>(_ label: String, applied: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            if bulk {
                Toggle(label, isOn: applied).toggleStyle(.checkbox).font(WispType.ui(12))
                    .frame(width: 110, alignment: .leading)
                    .help("Change \(label.lowercased()) for these songs")
            } else {
                Text(label).font(WispType.ui(12)).foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)
            }
            content().frame(maxWidth: .infinity, alignment: .leading)
                .disabled(bulk && !applied.wrappedValue)
        }
        .frame(minHeight: 28)
    }

    private func placeholder(_ path: KeyPath<Track, String>, empty: String) -> String {
        bulk && mixed(path) ? "Multiple values" : empty
    }

    private func mixed<Value: Equatable>(_ path: KeyPath<Track, Value>) -> Bool {
        guard let first = tracks.first else { return false }
        return tracks.dropFirst().contains { $0[keyPath: path] != first[keyPath: path] }
    }
}

/// Shared preparation and validation keep batches honest about common/mixed values.
enum MetadataEditorState {
    static func batch(_ tracks: [Track]) -> TrackMetadataPatch {
        var patch = TrackMetadataPatch()
        guard let first = tracks.first else { return patch }
        if tracks.allSatisfy({ $0.title == first.title }) { patch.title = first.title }
        if tracks.allSatisfy({ $0.artist == first.artist }) { patch.artist = first.artist }
        if tracks.allSatisfy({ $0.genre == first.genre }) { patch.genre = first.genre }
        if tracks.allSatisfy({ $0.origin == first.origin }) { patch.origin = first.origin }
        if tracks.allSatisfy({ $0.originMediaKind == first.originMediaKind }) { patch.originMediaKind = first.originMediaKind }
        if tracks.allSatisfy({ $0.remix == first.remix }) { patch.remix = first.remix }
        if tracks.allSatisfy({ $0.sourceURL == first.sourceURL }) { patch.source = first.sourceURL ?? "" }
        if tracks.allSatisfy({ $0.favorite == first.favorite }) { patch.favorite = first.favorite }
        return patch
    }

    static func error(_ patch: TrackMetadataPatch, tracks: [Track]) -> String? {
        do {
            for track in tracks { _ = try patch.applying(to: track) }
            return nil
        } catch { return error.localizedDescription }
    }

    /// Editing a draft must not normalize characters under the user's cursor.
    static func setRaw(_ patch: TrackMetadataPatch, on track: inout Track) {
        if patch.applyTitle { track.title = patch.title }
        if patch.applyArtist { track.artist = patch.artist }
        if patch.applyGenre { track.genre = patch.genre }
        if patch.applyOrigin { track.origin = patch.origin }
        if patch.applyMediaKind { track.originMediaKind = patch.originMediaKind }
        if patch.applyRemix { track.remix = patch.remix }
        if patch.applySource { track.sourceURL = patch.source.isEmpty ? nil : patch.source }
        if patch.applyFavorite { track.favorite = patch.favorite }
    }
}

/// Saved selections and import drafts share staged metadata and artwork.
@MainActor
struct MetadataBatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tracks: [Track]
    @State private var currentArtwork: [EditorArtworkCurrent]
    var heading: String
    var saveTitle = "Save changes"
    var explanation: String
    var saveEnabled = true
    var focusArtwork = false
    let save: (TrackMetadataPatch, TrackArtworkEdit) async -> Bool
    @State private var patch: TrackMetadataPatch
    @State private var saveError: String?
    @State private var saving = false
    @StateObject private var artwork: EditorArtworkDraft

    init(tracks: [Track], currentArtwork: [EditorArtworkCurrent] = [], heading: String,
         saveTitle: String = "Save changes", explanation: String,
         saveEnabled: Bool = true, focusArtwork: Bool = false, artworkDraft: EditorArtworkDraft? = nil,
         save: @escaping (TrackMetadataPatch, TrackArtworkEdit) async -> Bool) {
        _tracks = State(initialValue: tracks)
        _currentArtwork = State(initialValue: currentArtwork)
        self.heading = heading
        self.saveTitle = saveTitle
        self.explanation = explanation
        self.saveEnabled = saveEnabled
        self.focusArtwork = focusArtwork
        self.save = save
        _patch = State(initialValue: MetadataEditorState.batch(tracks))
        _artwork = StateObject(wrappedValue: artworkDraft ?? EditorArtworkDraft())
    }

    private var validation: String? { MetadataEditorState.error(patch, tracks: tracks) }
    private var searchTracks: [Track] { tracks.map { (try? patch.applying(to: $0)) ?? $0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text(heading).font(WispType.display(22))
                Text(explanation).font(WispType.ui(11)).foregroundStyle(.secondary)
                Text("Only checked details change. An empty checked optional field clears it.")
                    .font(WispType.ui(11)).foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        TrackMetadataFields(patch: $patch, tracks: tracks, bulk: true)
                        EditorArtworkSection(draft: artwork, tracks: searchTracks,
                            current: currentArtwork, enabled: !saving).id("editor-artwork")
                        VStack(alignment: .leading, spacing: 6) {
                            if patch.applyTitle && tracks.count > 1 {
                                Text("This gives all \(tracks.count) songs the same title.")
                                    .font(WispType.ui(11)).foregroundStyle(PaletteColor.amber.color)
                            }
                            if let validation { Text(validation).font(WispType.ui(11)).foregroundStyle(.red) }
                            if let saveError { Text(saveError).font(WispType.ui(11)).foregroundStyle(.red) }
                            EditorError()
                        }
                    }.padding(.trailing, 4)
                }.disabled(saving)
                .task { if focusArtwork { await Task.yield(); proxy.scrollTo("editor-artwork", anchor: .top) } }
            }
            HStack(spacing: 16) {
                if saving { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.plain).disabled(saving)
                Button(saveTitle, action: commit)
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled((patch.isEmpty && !artwork.hasChanges) || validation != nil || tracks.isEmpty || !saveEnabled || saving || artwork.isLoading)
            }
        }
        .padding(28).frame(width: 620, height: 700)
        .background(WispSurface.main)
        .interactiveDismissDisabled()
    }

    private func commit() {
        saving = true; saveError = nil
        let selectedPatch = patch
        Task { @MainActor in
            do {
                let edit = try await artwork.preparedEdit()
                if await save(selectedPatch, edit) { dismiss() }
                else { saveError = "The changes could not be saved. Your selection remains open." }
            } catch { saveError = error.localizedDescription }
            saving = false
        }
    }
}
