import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WispCore

@MainActor
struct PlaylistEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist?
    let saved: (UUID) -> Void
    @State private var name: String
    @State private var description: String
    @State private var symbol: String
    @State private var tint: PaletteColor
    @State private var folderID: UUID?
    @State private var coverURL: URL?
    @State private var removeCover = false
    @FocusState private var nameFocused: Bool

    init(playlist: Playlist?, folderID: UUID?, saved: @escaping (UUID) -> Void) {
        self.playlist = playlist
        self.saved = saved
        _name = State(initialValue: playlist?.name ?? "")
        _description = State(initialValue: playlist?.description ?? "")
        _symbol = State(initialValue: playlist?.symbol ?? "music.note.list")
        _tint = State(initialValue: playlist?.tint ?? .blue)
        _folderID = State(initialValue: playlist == nil ? folderID : playlist?.folderID)
    }

    private var displayedCover: URL? {
        if let coverURL { return coverURL }
        return removeCover ? nil : playlist.flatMap { store.coverURL(for: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(playlist == nil ? "New playlist" : "Edit playlist").font(WispType.display(22))
            HStack(alignment: .top, spacing: 25) {
                VStack(spacing: 12) {
                    ArtworkView(url: displayedCover, symbol: symbol, tint: tint, size: 94)
                    Button(displayedCover == nil ? "Add cover" : "Change cover") {
                        if let url = NativeFiles.chooseCover() { coverURL = url; removeCover = false }
                    }.buttonStyle(.plain).font(WispType.ui(12)).foregroundStyle(.tint).help("Choose a cover image")
                    if displayedCover != nil {
                        Button("Remove") { coverURL = nil; removeCover = true }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                            .help("Remove cover image")
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Name").font(WispType.ui(12)).foregroundStyle(.secondary)
                        TextField("Name", text: $name).modifier(QuietFieldLine()).focused($nameFocused)
                            .accessibilityLabel("Playlist name")
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Description").font(WispType.ui(12)).foregroundStyle(.secondary)
                        TextEditor(text: $description).font(WispType.ui(13)).scrollContentBackground(.hidden)
                            .padding(.vertical, 4).frame(height: 94)
                            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 0.5) }
                            .accessibilityLabel("Playlist description")
                    }
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 18) {
                GridRow {
                    Text("Icon").font(WispType.ui(12)).foregroundStyle(.secondary)
                    Picker("Icon", selection: $symbol) {
                        ForEach(PlaylistSymbols.choices.indices, id: \.self) { index in
                            let choice = PlaylistSymbols.choices[index]
                            Label(choice.title, systemImage: choice.name).tag(choice.name)
                        }
                    }.labelsHidden().pickerStyle(.menu).buttonStyle(.borderless).frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow {
                    Text("Color").font(WispType.ui(12)).foregroundStyle(.secondary)
                    Picker("Color", selection: $tint) {
                        ForEach(PaletteColor.allCases) { color in
                            Label(color.title, systemImage: "circle.fill").foregroundStyle(color.color).tag(color)
                        }
                    }.labelsHidden().pickerStyle(.menu).buttonStyle(.borderless).frame(maxWidth: .infinity, alignment: .leading)
                }

            }
            EditorError()
            HStack(spacing: 16) {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.plain)
                Button(playlist == nil ? "Create" : "Save", action: save)
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canEdit)
            }
        }
        .padding(30).frame(width: 520)
        .onAppear { store.errorMessage = nil; nameFocused = true }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if var updated = playlist {
            updated.name = trimmed
            updated.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.symbol = symbol
            updated.tint = tint
            updated.folderID = folderID
            if store.updatePlaylist(updated, coverURL: coverURL, removeCover: removeCover) { saved(updated.id); dismiss() }
        } else if let id = store.createPlaylist(name: trimmed, description: description.trimmingCharacters(in: .whitespacesAndNewlines), folderID: folderID, symbol: symbol, tint: tint, coverURL: coverURL) {
            saved(id); dismiss()
        }
    }
}

@MainActor
struct FolderEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let folder: PlaylistFolder?
    let saved: (UUID) -> Void
    @State private var name: String
    @State private var tint: PaletteColor = .graphite
    @FocusState private var nameFocused: Bool

    init(folder: PlaylistFolder?, saved: @escaping (UUID) -> Void) {
        self.folder = folder
        self.saved = saved
        _name = State(initialValue: folder?.name ?? "")
        _tint = State(initialValue: folder?.tint ?? .graphite)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(folder == nil ? "New folder" : "Edit folder").font(WispType.display(22))
            TextField("Name", text: $name).modifier(QuietFieldLine()).focused($nameFocused).accessibilityLabel("Folder name")
            if folder == nil {
                EditorFieldRow(title: "Color") {
                    Picker("Color", selection: $tint) {
                        ForEach(PaletteColor.allCases) { color in Text(color.title).tag(color) }
                    }.labelsHidden().pickerStyle(.menu).buttonStyle(.borderless)
                }
            }
            EditorError()
            HStack(spacing: 16) {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.plain)
                Button(folder == nil ? "Create" : "Save") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let folder {
                        store.renameFolder(id: folder.id, name: trimmed)
                        if store.errorMessage == nil && store.folder(id: folder.id)?.name == trimmed { saved(folder.id); dismiss() }
                    } else if let id = store.createFolder(name: trimmed, tint: tint) { saved(id); dismiss() }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canEdit)
            }
        }.padding(30).frame(width: 390).onAppear { store.errorMessage = nil; nameFocused = true }
    }
}

@MainActor
struct TrackEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var track: Track
    let focusSource: Bool
    let focusArtwork: Bool
    @StateObject private var artwork: EditorArtworkDraft
    @State private var draft: Track
    @State private var replacementURL: URL?
    @State private var restoreVersionID: UUID?
    @State private var saving = false

    init(track: Track, focusSource: Bool = false, focusArtwork: Bool = false,
         artworkDraft: EditorArtworkDraft? = nil) {
        _track = State(initialValue: track)
        self.focusSource = focusSource
        self.focusArtwork = focusArtwork
        _artwork = StateObject(wrappedValue: artworkDraft ?? EditorArtworkDraft())
        _draft = State(initialValue: track)
    }

    private var current: Track { store.track(id: track.id) ?? track }
    private var metadata: Binding<TrackMetadataPatch> {
        Binding(get: { .allFields(from: draft) }, set: { MetadataEditorState.setRaw($0, on: &draft) })
    }
    private var validation: String? {
        MetadataEditorState.error(.allFields(from: draft), tracks: [track])
    }
    private var stagedVersion: TrackAudioVersion? {
        current.audioVersions.first { $0.id == restoreVersionID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit song").font(WispType.display(22))
            ScrollViewReader { proxy in
              ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TrackMetadataFields(patch: metadata, tracks: [track], focusSource: focusSource)
                    Text("Origin is optional, including for originals and remixes of other songs.")
                        .font(WispType.ui(11)).foregroundStyle(.secondary)
                    EditorArtworkSection(draft: artwork, tracks: [draft],
                        current: [EditorArtworkCurrent(track: track, url: store.artworkURL(for: track))], enabled: !saving)
                        .id("editor-artwork")
                    remixRelationships
                    WispSurface.divider.frame(height: 1)
                    audioVersions
                    if let validation { Text(validation).font(WispType.ui(11)).foregroundStyle(.red) }
                    EditorError()
                }
                .padding(.trailing, 4)
            }
              .disabled(saving)
              .task { if focusArtwork { await Task.yield(); proxy.scrollTo("editor-artwork", anchor: .top) } }
            }
            HStack(spacing: 16) {
                if saving {
                    ProgressView().controlSize(.small)
                    Text("Saving…").font(WispType.ui(11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.plain).disabled(saving)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(validation != nil || !store.canEdit || saving || artwork.isLoading)
            }
        }
        .padding(28).frame(width: 590, height: 660)
        .background(WispSurface.main)
        .interactiveDismissDisabled()
        .onAppear { store.errorMessage = nil }
    }

    @ViewBuilder private var remixRelationships: some View {
        if let source = current.remixSource {
            VStack(alignment: .leading, spacing: 5) {
                Label("Remix of \(source.title)", systemImage: "arrow.triangle.branch")
                    .font(WispType.ui(11, weight: .medium))
                if !source.artist.isEmpty {
                    Text("Original artist · \(source.artist)").font(WispType.ui(10)).foregroundStyle(.secondary)
                }
                Text("Source captured \(source.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(WispType.ui(10)).foregroundStyle(.secondary)
            }
        }
        let children = store.tracks.filter { $0.remixSource?.trackID == current.id }
        if !children.isEmpty {
            DisclosureGroup("Child remixes · \(children.count)") {
                ForEach(children) { child in
                    HStack {
                        Text(child.displayTitle).lineLimit(1)
                        Spacer()
                        Button("Reveal audio") {
                            NSWorkspace.shared.activateFileViewerSelecting([store.audioURL(for: child)])
                        }.buttonStyle(.plain).foregroundStyle(.tint)
                    }.padding(.top, 6)
                }
            }.font(WispType.ui(11)).foregroundStyle(.secondary)
        }
    }

    private var audioVersions: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Audio").font(WispType.ui(13, weight: .medium))
                Spacer()
                Button("Replace audio…", action: chooseReplacement)
                    .buttonStyle(.plain).foregroundStyle(.tint).font(WispType.ui(12))
                    .accessibilityLabel("Replace this song's audio")
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(current.originalFileName.isEmpty ? current.fileName : current.originalFileName)
                        .font(WispType.ui(11)).lineLimit(1).truncationMode(.middle)
                        .help(current.originalFileName)
                    Text("Current · \(clockText(current.duration))")
                        .font(WispType.ui(10)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([store.audioURL(for: current)]) }
                    .buttonStyle(.plain).font(WispType.ui(11)).foregroundStyle(.secondary)
            }
            if let replacementURL {
                pendingAudio("Replace with \(replacementURL.lastPathComponent)")
            } else if let stagedVersion {
                pendingAudio("Restore \(stagedVersion.originalFileName)")
            } else {
                Text("Replacing audio keeps this song's details and saves its current audio as a previous version.")
                    .font(WispType.ui(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !current.audioVersions.isEmpty {
                DisclosureGroup("Previous versions · \(current.audioVersions.count)") {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(current.audioVersions) { version in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(version.originalFileName.isEmpty ? version.fileName : version.originalFileName)
                                        .font(WispType.ui(11)).lineLimit(1).truncationMode(.middle)
                                    Text("Archived \(version.archivedAt.formatted(date: .abbreviated, time: .shortened)) · \(clockText(version.duration))")
                                        .font(WispType.ui(10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([store.audioURL(for: version)]) }
                                    .buttonStyle(.plain).font(WispType.ui(11)).foregroundStyle(.secondary)
                                Button(restoreVersionID == version.id ? "Selected" : "Restore") {
                                    replacementURL = nil
                                    restoreVersionID = version.id
                                }.buttonStyle(.plain).font(WispType.ui(11)).foregroundStyle(.tint)
                            }
                        }
                    }.padding(.top, 12)
                }.font(WispType.ui(11)).foregroundStyle(.secondary)
            }
        }
    }

    private func pendingAudio(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(label).font(WispType.ui(11)).lineLimit(2).foregroundStyle(.tint)
                Spacer()
                Button("Clear") { replacementURL = nil; restoreVersionID = nil }
                    .buttonStyle(.plain).font(WispType.ui(11)).foregroundStyle(.secondary)
            }
            Text("Applies when you save. The current audio will remain in Previous versions. If this song is playing, saving a different version pauses it.")
                .font(WispType.ui(10)).foregroundStyle(.secondary)
        }
    }

    private func chooseReplacement() {
        let panel = NSOpenPanel()
        panel.title = "Replace audio"
        panel.prompt = "Choose"
        panel.message = "Choose the new audio file for this song. It will be applied when you save."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = NativeFiles.audioContentTypes
        if panel.runModal() == .OK, let url = panel.url {
            replacementURL = url
            restoreVersionID = nil
        }
    }

    private func save() {
        saving = true
        let patch = TrackMetadataPatch.changes(from: track, to: draft)
        Task { @MainActor in
            let succeeded: Bool
            do {
                let edit = try await artwork.preparedEdit()
                succeeded = await store.saveTrackEdits(trackID: track.id, patch: patch,
                    replacementURL: replacementURL, restoreVersionID: restoreVersionID,
                    artwork: edit, expectedTrack: track)
            } catch {
                store.errorMessage = error.localizedDescription
                succeeded = false
            }
            saving = false
            if succeeded { dismiss() }
        }
    }
}

@MainActor
struct AddTracksEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let playlistID: UUID
    @State private var query = ""
    @State private var selected = Set<UUID>()

    private var eligible: [Track] {
        let existing = Set(store.playlist(id: playlistID)?.trackIDs ?? [])
        return TrackSearch.alphabetized(store.tracks.filter { !existing.contains($0.id) })
    }

    private var available: [Track] {
        eligible.filter { TrackSearch.matches($0, query: query) }
    }

    private var selectedIDs: [UUID] {
        eligible.map(\.id).filter(selected.contains)
    }

    private var addTitle: String {
        let count = selectedIDs.count
        return "Add \(count) \(count == 1 ? "song" : "songs")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Add tracks").font(WispType.display(22))
            Text("Choose tracks for \(store.playlist(id: playlistID)?.name ?? "this playlist").").font(WispType.ui(13)).foregroundStyle(.secondary)
            TextField("Search", text: $query).modifier(QuietFieldLine())
                .accessibilityLabel("Search songs to add")
            if available.isEmpty {
                EmptyMessage(title: "Empty", message: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "There are no other tracks to add." : "No tracks match your search.").frame(height: 250)
            } else {
                List(available) { track in
                    HStack(spacing: 10) {
                        Toggle(isOn: Binding(get: { selected.contains(track.id) }, set: { if $0 { selected.insert(track.id) } else { selected.remove(track.id) } })) {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(track.displayTitle).font(WispType.ui(13))
                                    if !track.origin.isEmpty {
                                        Label(track.displayOrigin, systemImage: track.resolvedMediaKind.symbolName)
                                            .font(WispType.ui(11)).foregroundStyle(.secondary)
                                    }
                                }
                                if let version = track.remix {
                                    Text(version.rawValue.capitalized).font(WispType.ui(11)).foregroundStyle(.tertiary)
                                }
                            }
                        }.toggleStyle(.checkbox)
                        Spacer()
                        Text(clockText(track.duration)).font(WispType.ui(11)).monospacedDigit().foregroundStyle(.secondary)
                    }.padding(.vertical, 7).listRowSeparator(.hidden)
                }.listStyle(.plain).scrollContentBackground(.hidden).frame(height: 290)
            }
            EditorError()
            HStack {
                Button("Select all") { selected.formUnion(available.map(\.id)) }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(available.isEmpty)
                    .help("Select all songs shown by this search")
                if !selectedIDs.isEmpty {
                    Button("Clear selection") { selected.removeAll() }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.plain)
                Button(addTitle) {
                    let ids = selectedIDs
                    store.addTracks(ids, to: playlistID)
                    if let playlist = store.playlist(id: playlistID), Set(ids).isSubset(of: Set(playlist.trackIDs)) { dismiss() }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(selectedIDs.isEmpty || !store.canEdit)
            }
        }.padding(30).frame(width: 500).onAppear { store.errorMessage = nil }
            .onChange(of: eligible.map(\.id)) { ids in selected.formIntersection(ids) }
    }
}

@MainActor
struct ChoosePlaylistEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let trackIDs: [UUID]
    let selected: (UUID) -> Void
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Add to playlist").font(WispType.display(22))
            Text("Add \(trackIDs.count) \(trackIDs.count == 1 ? "track" : "tracks") to a playlist.").font(WispType.ui(13)).foregroundStyle(.secondary)
            if !store.playlists.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(store.playlists) { playlist in
                            Button { add(to: playlist.id) } label: {
                                HStack(spacing: 10) {
                                    if playlist.isMixtape {
                                        StrongSymbol(name: MixtapeCollection.symbol, tint: .blue, size: 19).frame(width: 32, height: 32)
                                    } else {
                                        ArtworkView(url: store.coverURL(for: playlist), symbol: playlist.symbol, tint: playlist.tint, size: 32)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(playlist.name).foregroundStyle(.primary)
                                        if playlist.isMixtape {
                                            Text("Syncs to Music").font(WispType.ui(11)).foregroundStyle(.secondary)
                                        } else if let folderID = playlist.folderID, let folder = store.folder(id: folderID) {
                                            Text(folder.name).font(WispType.ui(11)).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "plus").font(WispType.ui(12)).foregroundStyle(.tertiary)
                                }.padding(.vertical, 10).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 270)
            }
            HStack(spacing: 10) {
                TextField("New playlist name", text: $name).modifier(QuietFieldLine()).accessibilityLabel("New playlist name")
                Button("Create") {
                    if let id = store.createPlaylist(name: name.trimmingCharacters(in: .whitespacesAndNewlines)) { add(to: id) }
                }.buttonStyle(.plain).foregroundStyle(.tint).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canEdit)
            }
            EditorError()
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(.plain) }
        }.padding(30).frame(width: 440).onAppear { store.errorMessage = nil }
    }

    private func add(to id: UUID) {
        store.addTracks(trackIDs, to: id)
        if let playlist = store.playlist(id: id), Set(trackIDs).isSubset(of: Set(playlist.trackIDs)) {
            selected(id); dismiss()
        }
    }
}

@MainActor
struct EditorError: View {
    @EnvironmentObject private var store: LibraryStore
    var body: some View {
        if let error = store.errorMessage { Text(error).font(WispType.ui(12)).foregroundStyle(.red).textSelection(.enabled) }
    }
}
