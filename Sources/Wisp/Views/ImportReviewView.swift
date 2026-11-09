import SwiftUI
import WispCore

/// Import drafts use the same fields and batch editor as songs already saved.
/// Nothing enters the library until the final Import action succeeds.
@MainActor
struct ImportReviewView: View {
    @EnvironmentObject private var store: LibraryStore
    let review: ImportReview
    let close: () -> Void
    @State private var drafts: [Track]
    @State private var included: Set<UUID>
    @State private var focusedID: UUID?
    @State private var query = ""
    @State private var editingIncluded = false
    @State private var batchTracks: [Track] = []
    @State private var saving = false
    @StateObject private var artwork: EditorArtworkImportDrafts

    init(review: ImportReview, close: @escaping () -> Void) {
        self.review = review
        self.close = close
        _drafts = State(initialValue: review.tracks)
        _included = State(initialValue: Set(review.tracks.map(\.id)))
        _focusedID = State(initialValue: review.tracks.first?.id)
        _artwork = StateObject(wrappedValue: EditorArtworkImportDrafts(tracks: review.tracks))
    }

    private var chosen: [Track] { drafts.filter { included.contains($0.id) } }
    private var visible: [Track] { drafts.filter { TrackSearch.matches($0, query: query) } }
    private var validation: String? {
        for track in chosen {
            if let message = MetadataEditorState.error(.allFields(from: track), tracks: [track]) {
                return "\(track.title.isEmpty ? "Untitled song" : track.title): \(message)"
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Review import").font(WispType.display(22))
                Text("\(review.tracks.count) new \(review.tracks.count == 1 ? "song" : "songs") · \(review.destinationName)")
                    .font(WispType.ui(12)).foregroundStyle(.secondary)
                Text("Select a song to edit it, or edit the included songs together.")
                    .font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
            }
            batchTools
            HStack(alignment: .top, spacing: 28) {
                List(selection: $focusedID) {
                    ForEach(visible) { track in
                        reviewRow(track).tag(track.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 4, bottom: 5, trailing: 8))
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .frame(width: 310)
                .accessibilityLabel("Songs awaiting import")
                .overlay {
                    if visible.isEmpty {
                        Text("No songs match this search.").font(WispType.ui(11)).foregroundStyle(.secondary)
                    }
                }
                WispSurface.divider.frame(width: 1)
                ScrollView {
                    if let focusedID, let index = drafts.firstIndex(where: { $0.id == focusedID }) {
                        details(index).padding(.trailing, 4)
                    } else {
                        Text("Choose a song to review its details.")
                            .font(WispType.ui(12)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .disabled(saving)
            if review.duplicateCount > 0 {
                Text("\(review.duplicateCount) already in your library. Their edits stay unchanged; no extra copies are added.")
                    .font(WispType.ui(11)).foregroundStyle(.secondary)
            }
            if !review.failures.isEmpty {
                DisclosureGroup("\(review.failures.count) files could not be read") {
                    ScrollView {
                        Text(review.failures.joined(separator: "\n"))
                            .font(WispType.ui(11)).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 60)
                }.font(WispType.ui(11))
            }
            if let validation {
                Text(validation).font(WispType.ui(11)).foregroundStyle(.red).lineLimit(2)
            }
            EditorError()
            HStack(spacing: 14) {
                Text("Original files stay unchanged.").font(WispType.ui(11)).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { store.cancelImportReview(); close() }
                    .buttonStyle(.plain).keyboardShortcut(.cancelAction).disabled(saving)
                if saving { ProgressView().controlSize(.small) }
                Button("Import \(chosen.count) \(chosen.count == 1 ? "song" : "songs")", action: confirm)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(validation != nil || (chosen.isEmpty && review.duplicateCount == 0) || !store.canEdit || saving || artwork.isLoading(ids: included))
            }
        }
        .padding(28).frame(width: 920, height: 660)
        .font(WispType.ui(12))
        .background(WispSurface.main)
        .interactiveDismissDisabled()
        .onDisappear { artwork.cancelLoading() }
        .onChange(of: query) { _ in
            if !visible.contains(where: { $0.id == focusedID }) { focusedID = visible.first?.id }
        }
        .sheet(isPresented: $editingIncluded) {
            MetadataBatchSheet(tracks: batchTracks, currentArtwork: batchTracks.map(currentArtwork),
                               heading: "Edit \(batchTracks.count) included songs",
                               saveTitle: "Apply to drafts",
                               explanation: "These changes stay in review until you import.", saveEnabled: store.canEdit) { patch, edit in
                do {
                    let ids = Set(batchTracks.map(\.id))
                    let updated = try drafts.map { ids.contains($0.id) ? try patch.applying(to: $0) : $0 }
                    try await artwork.apply(edit, to: ids)
                    drafts = updated
                    return true
                } catch {
                    store.errorMessage = error.localizedDescription
                    return false
                }
            }
        }
    }

    private var batchTools: some View {
        HStack(spacing: 16) {
            Toggle("Include all", isOn: Binding(get: { included.count == drafts.count }, set: {
                included = $0 ? Set(drafts.map(\.id)) : []
            })).toggleStyle(.checkbox).help("Include or exclude every new song, including songs hidden by search")
            Text("\(included.count) included").foregroundStyle(.secondary)
            Button("Edit included…") { store.errorMessage = nil; batchTracks = chosen; editingIncluded = true }
                .buttonStyle(.plain).foregroundStyle(.tint).disabled(included.isEmpty)
                .help("Edit all \(included.count) included songs together, including those hidden by search")
            Spacer()
            TextField("Find in batch", text: $query).textFieldStyle(.plain).frame(width: 160)
                .accessibilityLabel("Search this import batch")
        }
        .font(WispType.ui(11))
        .disabled(saving)
    }

    private func reviewRow(_ track: Track) -> some View {
        HStack(spacing: 10) {
            Toggle("Include \(track.displayTitle)", isOn: Binding(get: { included.contains(track.id) }, set: {
                if $0 { included.insert(track.id) } else { included.remove(track.id) }
            })).labelsHidden().toggleStyle(.checkbox).frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.displayTitle).lineLimit(1).help(track.displayTitle)
                    .foregroundStyle(WispSurface.ink)
                Text(track.artist.isEmpty ? "Add artist…" : track.artist)
                    .font(WispType.ui(10))
                    .foregroundStyle(track.artist.isEmpty ? PaletteColor.amber.color : WispSurface.mutedText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(WispType.ui(12)).frame(minHeight: 34).contentShape(Rectangle())
        .opacity(included.contains(track.id) ? 1 : 0.5)
    }

    private func details(_ index: Int) -> some View {
        let track = drafts[index]
        let metadata = Binding<TrackMetadataPatch>(get: { .allFields(from: drafts[index]) }, set: {
            MetadataEditorState.setRaw($0, on: &drafts[index])
        })
        return VStack(alignment: .leading, spacing: 18) {
            Text(track.originalFileName).font(WispType.ui(10)).foregroundStyle(.secondary)
                .lineLimit(1).help(track.originalFileName).textSelection(.enabled)
            TrackMetadataFields(patch: metadata, tracks: [track])
            if let artworkDraft = artwork.drafts[track.id] {
                EditorArtworkSection(draft: artworkDraft, tracks: [track],
                                     current: [baselineArtwork(track)], enabled: !saving && !editingIncluded)
                    .id(track.id)
            }
            Text("Basic is music from other artists. Classic is music you created. Origin is optional.")
                .font(WispType.ui(10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let notes = review.notes[track.id], !notes.isEmpty {
                Text(notes.joined(separator: " "))
                    .font(WispType.ui(10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func baselineArtwork(_ track: Track) -> EditorArtworkCurrent {
        let original = review.tracks.first { $0.id == track.id } ?? track
        return EditorArtworkCurrent(track: original, url: store.artworkURL(for: original))
    }

    private func currentArtwork(_ track: Track) -> EditorArtworkCurrent {
        let current = baselineArtwork(track)
        return artwork.drafts[track.id]?.preview(current: current) ?? current
    }

    private func confirm() {
        let selected = chosen
        saving = true
        Task { @MainActor in
            do {
                let edits = try await artwork.edits(for: selected)
                if store.confirmImport(selected, artworkEdits: edits) { close() }
            } catch { store.errorMessage = error.localizedDescription }
            saving = false
        }
    }
}
