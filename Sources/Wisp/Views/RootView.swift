import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CryptoKit
import WispCore

@MainActor
struct RootView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var mixtapeSync: MixtapeSyncStore
    @AppStorage("selection") private var savedSelection = "music"
    @Bindable private var theme = WispTheme.shared
    @State private var selection: Destination? = .music
    @State private var selectedTracks = Set<UUID>()
    @State private var query = ""
    @State private var sort: TrackSort = .recent
    @State private var filter = TrackLibraryFilter()
    @State private var searchFilter = TrackLibraryFilter()
    @State private var searchSort: TrackSort = .title
    @State private var editor: EditorRoute?
    @State private var remixTrack: Track?
    @State private var artworkReview: ArtworkReviewRoute?
    @State private var reviewPresented = false
    @State private var deletion: DeletionRequest?
    @State private var queueVisible = false
    @State private var playerExpanded = false
    @State private var dropTargeted = false
    @State private var notice: String?
    @FocusState private var searchFocused: Bool

    private var destination: Destination { selection ?? .music }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var playlist: Playlist? {
        guard !isSearching else { return nil }
        if case .playlist(let id) = destination { return store.playlist(id: id) }
        return nil
    }
    private var searchScope: [Track] { isSearching ? store.tracks : destinationTracks }
    private var displayedFilter: Binding<TrackLibraryFilter> {
        isSearching ? $searchFilter : $filter
    }
    private var displayedSort: Binding<TrackSort> { isSearching ? $searchSort : $sort }
    private var destinationTracks: [Track] {
        var tracks: [Track]
        switch destination {
        case .playlist(let id):
            let index = Dictionary(uniqueKeysWithValues: store.tracks.map { ($0.id, $0) })
            tracks = (store.playlist(id: id)?.trackIDs ?? []).compactMap { index[$0] }
        case .favorites: tracks = store.tracks.filter(\.favorite)
        case .basic: tracks = store.tracks.filter { $0.remix == .basic }
        case .classic: tracks = store.tracks.filter { $0.remix == .classic }
        case .artist(let artist): tracks = store.tracks.filter { $0.sidebarArtist == artist }
        case .origin(let artist, let origin):
            tracks = store.tracks.filter { $0.sidebarArtist == artist && OriginMediaKind.originKey($0.sidebarOrigin) == OriginMediaKind.originKey(origin) }
        case .media(let kind): tracks = TrackCategories.tracks(in: store.tracks, kind: kind)
        case .sharedOrigin(let origin): tracks = TrackCategories.tracks(in: store.tracks, origin: origin)
        case .recent:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            tracks = store.tracks.filter { $0.addedAt >= cutoff }
        case .music, .folder: tracks = store.tracks
        }
        return tracks
    }
    private var visibleTracks: [Track] {
        var tracks = displayedFilter.wrappedValue.apply(to: searchScope)
        tracks = tracks.filter { TrackSearch.matches($0, query: query) }
        if playlist == nil {
            let activeSort = displayedSort.wrappedValue
            tracks.sort {
                switch activeSort {
                case .recent: return $0.addedAt > $1.addedAt
                case .title: return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending
                case .artist:
                    if $0.artist == $1.artist { return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
                    return $0.artist.localizedStandardCompare($1.artist) == .orderedAscending
                case .genre:
                    let lhs = TrackLibraryFilter.genreKey($0.genre)
                    let rhs = TrackLibraryFilter.genreKey($1.genre)
                    if lhs == rhs { return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
                    if lhs.isEmpty { return false }
                    if rhs.isEmpty { return true }
                    return lhs.localizedStandardCompare(rhs) == .orderedAscending
                case .origin:
                    if $0.displayOrigin == $1.displayOrigin { return $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
                    return $0.displayOrigin.localizedStandardCompare($1.displayOrigin) == .orderedAscending
                }
            }
        }
        return tracks
    }

    var body: some View {
        HStack(spacing: 0) {
            if !playerExpanded {
                SidebarView(selection: $selection, edit: { editor = $0 }, remove: { deletion = $0 },
                            importMusic: importMusic, importLink: { editor = .source })
                    .frame(width: 220)
                WispSurface.divider.opacity(0.55).frame(width: 0.5).ignoresSafeArea()
            }
            VStack(spacing: 0) {
                Group {
                    if playerExpanded {
                        ExpandedPlayerView(collapse: { playerExpanded = false })
                    } else {
                        VStack(spacing: 0) {
                            contentToolbar
                            HStack(spacing: 0) {
                                detail
                                if queueVisible {
                                    QueueView(close: { queueVisible = false }).frame(width: 255)
                                }
                            }
                        }
                    }
                }
                PlayerBar(queueVisible: $queueVisible, expanded: $playerExpanded)
            }
            .background(WispSurface.main.ignoresSafeArea())
        }
        .frame(minWidth: 850, minHeight: 560)
        .modifier(WispAppearancePolicy(theme: theme))
        .tint(PaletteColor.blue.color)
        .sheet(item: $editor, onDismiss: {
            reviewPresented = store.importReview != nil
            presentPendingArtworkReview()
        }) { route in
            editorView(route)
                .font(WispType.ui(13))
                .presentationBackground(WispSurface.main)
        }
        .sheet(isPresented: $reviewPresented, onDismiss: {
            store.cancelImportReview()
            presentPendingArtworkReview()
        }) {
            if let review = store.importReview {
                ImportReviewView(review: review, close: { reviewPresented = false })
                    .presentationBackground(WispSurface.main)
            }
        }
        .sheet(item: $remixTrack, onDismiss: {
            WispInput.instrumentPresented = false
            presentPendingArtworkReview()
        }) { source in
            RemixView(track: source, sourceURL: store.audioURL(for: source),
                takesDirectory: remixTakesDirectory(for: source),
                saveChild: { take, title, artist in
                    await store.saveRemixChild(source: source, takeURL: take.url, title: title, artist: artist)
                }, saveVersion: { take in
                    await store.saveTrackEdits(trackID: source.id, patch: TrackMetadataPatch(),
                        replacementURL: take.url, expectedFingerprint: source.fingerprint)
                })
                .font(WispType.ui(13))
                .presentationBackground(WispSurface.main)
        }
        .sheet(item: $artworkReview, onDismiss: presentPendingArtworkReview) { route in
            ArtworkReviewView(tracks: route.tracks)
                .font(WispType.ui(13))
                .presentationBackground(WispSurface.main)
        }
        .confirmationDialog("Delete", isPresented: deletionPresented, titleVisibility: .visible, presenting: deletion) { request in
            Button("Delete", role: .destructive) { performDeletion(request) }
            Button("Cancel", role: .cancel) { deletion = nil; presentPendingArtworkReview() }
        } message: { request in Text(deletionMessage(request)) }
        .alert("Bard", isPresented: errorPresented) {
            Button("Done") { store.errorMessage = nil; presentPendingArtworkReview() }
        } message: { Text(store.errorMessage ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: WispAction.importFiles)) { _ in importMusic() }
        .onReceive(NotificationCenter.default.publisher(for: WispAction.newPlaylist)) { _ in
            guard remixTrack == nil, artworkReview == nil, !reviewPresented else { return }
            editor = .playlist(nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: WispAction.search)) { _ in
            playerExpanded = false
            searchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: WispAction.remix)) { notification in
            guard editor == nil, !reviewPresented, remixTrack == nil, artworkReview == nil, store.canEdit,
                  let id = notification.object as? UUID, let track = store.track(id: id) else { return }
            player.pause()
            WispInput.instrumentPresented = true
            remixTrack = track
        }
        .onReceive(NotificationCenter.default.publisher(for: WispAction.editArtwork)) { _ in
            guard canPresentArtwork, NSApp.modalWindow == nil,
                  NSApp.keyWindow?.attachedSheet == nil, NSApp.keyWindow?.sheetParent == nil else { return }
            let selected = visibleTracks.filter { selectedTracks.contains($0.id) }.map(\.id)
            let ids = !selected.isEmpty ? selected : player.currentID.map { [$0] } ?? visibleTracks.map(\.id)
            if ids.count == 1, let id = ids.first, store.track(id: id) != nil { editor = .trackArtwork(id) }
            else if !ids.isEmpty { editor = .bulkArtwork(ids) }
        }
        .onReceive(NotificationCenter.default.publisher(for: WispAction.editTrack)) { notification in
            guard store.canEdit, !store.isImporting, editor == nil, remixTrack == nil, artworkReview == nil,
                  deletion == nil, !reviewPresented, store.importReview == nil, store.errorMessage == nil,
                  NSApp.modalWindow == nil, NSApp.keyWindow?.attachedSheet == nil,
                  NSApp.keyWindow?.sheetParent == nil,
                  let id = notification.object as? UUID, store.track(id: id) != nil else { return }
            editor = .trackSource(id)
        }
        .onReceive(NotificationCenter.default.publisher(for: WispAction.findArtwork)) { notification in
            let ids = notification.object as? [UUID]
                ?? store.tracks.map(\.id)
            presentArtworkReview(ids)
        }
        .onChange(of: store.artworkReviewTrackIDs) { _ in presentPendingArtworkReview() }
        .onChange(of: store.isImporting) { importing in
            if !importing { presentPendingArtworkReview() }
        }
        .onChange(of: store.importReview?.id) { id in
            guard id != nil else { return }
            if case .source? = editor { editor = nil }
            else if editor == nil { reviewPresented = true }
        }
        .onAppear { selection = Destination(savedValue: savedSelection) ?? .music; validateSelection() }
        .onChange(of: selection) { _ in
            savedSelection = destination.savedValue
            selectedTracks.removeAll()
            query = ""
            filter = TrackLibraryFilter()
            if destination == .recent { sort = .recent }
        }
        .onChange(of: filter) { _ in
            selectedTracks.formIntersection(Set(visibleTracks.map(\.id)))
        }
        .onChange(of: searchFilter) { _ in
            selectedTracks.formIntersection(Set(visibleTracks.map(\.id)))
        }
        .onChange(of: query) { _ in
            if !isSearching { searchFilter = TrackLibraryFilter(); searchSort = .title }
            selectedTracks.formIntersection(Set(visibleTracks.map(\.id)))
        }
        .onChange(of: store.document) { _ in
            validateSelection()
            selectedTracks.formIntersection(Set(visibleTracks.map(\.id)))
        }
        .onChange(of: store.notice) { message in
            notice = message
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if notice == message { notice = nil }
            }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !store.canEdit {
                Label("The library could not be opened. Your saved files have been left intact.", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(PaletteColor.amber.color).padding()
            }
            if store.isImporting {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(store.importLabel).font(.callout).lineLimit(1)
                    Spacer()
                }.padding(.horizontal, 32).padding(.vertical, 10)
            }
            LibraryContentView(destination: isSearching ? .music : destination, playlist: playlist, tracks: visibleTracks, query: $query,
                                   isSearching: isSearching, selectedTracks: $selectedTracks, sort: displayedSort,
                                   filter: displayedFilter, genres: TrackLibraryFilter.genres(in: searchScope),
                                   origins: TrackLibraryFilter.origins(in: searchScope),
                                   importMusic: importMusic, editPlaylist: { if let playlist, !playlist.isMixtape { editor = .playlist(playlist.id) } },
                                   addTracks: { if let playlist { editor = .addTracks(playlist.id) } },
                                   editTrack: { editor = .track($0) }, editTracks: { editor = .bulkTracks($0) },
                                   makeMixtape: { if let playlist { editor = .mixtape(playlist.id) } },
                                   addToPlaylist: { editor = .choosePlaylist($0) },
                                   deleteTracks: { deletion = .tracks($0) },
                                   syncStatus: mixtapeSync.status, syncDetail: mixtapeSync.detail,
                                   syncInProgress: mixtapeSync.isSyncing, syncNeedsAttention: mixtapeSync.needsAttention,
                                   syncNow: mixtapeSync.syncNow)
            if let notice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(PaletteColor.teal.color)
                    Text(notice).lineLimit(3)
                    Spacer()
                    Button { self.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss notice")
                }.font(WispType.ui(12)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WispSurface.main)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8).strokeBorder(PaletteColor.blue.color, style: StrokeStyle(lineWidth: 2, dash: [7]))
                    .padding(10).allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted, perform: acceptDrop)
    }

    private var contentToolbar: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search library", text: $query).textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("Search entire music library")
                    .help("Search all songs by title, artist, origin, genre, or Basic and Classic. Escape returns to your collection.")
                    .onExitCommand { query = ""; searchFocused = false }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                } else if !searchFocused {
                    Text("⌘ F")
                        .font(WispType.ui(10, weight: .medium))
                        .foregroundStyle(WispSurface.mutedText)
                        .accessibilityHidden(true)
                }
            }
            .font(WispType.ui(12))
            .padding(.horizontal, 9)
            .frame(width: 260, height: 30)
            .background(WispSurface.sidebar, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Spacer(minLength: 12)
        }
        .font(WispType.ui(12))
        .foregroundStyle(.secondary)
        .frame(height: 40)
        .padding(.horizontal, 28)
    }

    @ViewBuilder
    private func editorView(_ route: EditorRoute) -> some View {
        switch route {
        case .playlist(let id):
            if id == MixtapeCollection.id {
                AddTracksEditor(playlistID: MixtapeCollection.id)
            } else {
                PlaylistEditor(playlist: id.flatMap { store.playlist(id: $0) }, folderID: nil) { selection = .playlist($0) }
            }
        case .folder:
            EmptyView() // Historical route; folder controls are retired.
        case .track(let id):
            if let track = store.track(id: id) { TrackEditor(track: track) }
        case .trackSource(let id):
            if let track = store.track(id: id) { TrackEditor(track: track, focusSource: true) }
        case .trackArtwork(let id):
            if let track = store.track(id: id) { TrackEditor(track: track, focusArtwork: true) }
        case .bulkTracks(let ids):
            BulkTrackEditor(trackIDs: ids)
        case .bulkArtwork(let ids):
            BulkTrackEditor(trackIDs: ids, focusArtwork: true)
        case .mixtape(let id):
            MixtapeEditor(playlistID: id)
        case .addTracks(let id):
            AddTracksEditor(playlistID: id)
        case .choosePlaylist(let ids):
            ChoosePlaylistEditor(trackIDs: ids) { selection = .playlist($0) }
        case .source:
            SourceImportView(playlistID: playlist?.id)
        }
    }

    private var deletionPresented: Binding<Bool> {
        Binding(get: { deletion != nil }, set: {
            if !$0 { deletion = nil; presentPendingArtworkReview() }
        })
    }
    private var errorPresented: Binding<Bool> {
        Binding(get: { editor == nil && remixTrack == nil && artworkReview == nil && !reviewPresented && store.importReview == nil && store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    }

    private func remixTakesDirectory(for source: Track) -> URL {
        let revision = SHA256.hash(data: Data(source.fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
        return store.directory.appendingPathComponent("RemixTakes", isDirectory: true)
            .appendingPathComponent(source.id.uuidString, isDirectory: true)
            .appendingPathComponent(revision, isDirectory: true)
    }

    private func importMusic() {
        guard remixTrack == nil, artworkReview == nil, store.canEdit, !store.isImporting, store.importReview == nil else { return }
        let urls = NativeFiles.chooseAudio()
        guard !urls.isEmpty else { return }
        let target = playlist?.id
        Task { await store.importFiles(urls, into: target) }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard store.canEdit, !store.isImporting, artworkReview == nil, remixTrack == nil else { return false }
        let matches = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !matches.isEmpty else { return false }
        let target = playlist?.id
        NativeFiles.loadURLs(from: matches) { urls in
            guard artworkReview == nil, remixTrack == nil, !reviewPresented,
                  store.importReview == nil, !store.isImporting else {
                store.errorMessage = "Finish the current review or import, then drop those files again."
                return
            }
            guard !urls.isEmpty else {
                store.errorMessage = "Bard could not read those dropped files. Try choosing them with Import."
                return
            }
            Task { await store.importFiles(urls, into: target) }
        }
        return true
    }

    private func validateSelection() {
        switch destination {
        case .playlist(let id): if store.playlist(id: id) == nil { selection = .music }
        case .folder: selection = .music
        case .artist(let artist):
            if !store.tracks.contains(where: { $0.sidebarArtist == artist }) { selection = .music }
        case .origin(let artist, let origin):
            if !store.tracks.contains(where: { $0.sidebarArtist == artist && OriginMediaKind.originKey($0.sidebarOrigin) == OriginMediaKind.originKey(origin) }) {
                selection = store.tracks.contains(where: { $0.sidebarArtist == artist }) ? .artist(artist) : .music
            }
        default: break
        }
    }

    private var canPresentArtwork: Bool {
        store.canEdit && !store.isImporting && editor == nil && remixTrack == nil && artworkReview == nil
            && deletion == nil && !reviewPresented && store.importReview == nil && store.errorMessage == nil
    }

    private func presentArtworkReview(_ ids: [UUID]) {
        guard canPresentArtwork else { return }
        var seen = Set<UUID>()
        let tracks = ids.filter { seen.insert($0).inserted }.compactMap { store.track(id: $0) }
        guard !tracks.isEmpty else { return }
        artworkReview = ArtworkReviewRoute(tracks: tracks)
    }

    private func presentPendingArtworkReview() {
        guard canPresentArtwork, !store.artworkReviewTrackIDs.isEmpty else { return }
        let ids = store.consumeArtworkReviewTrackIDs()
        presentArtworkReview(ids)
    }

    private func deletionMessage(_ request: DeletionRequest) -> String {
        switch request {
        case .playlist(let id): return "Delete \(store.playlist(id: id)?.name ?? "this playlist")? Its tracks will remain in your library."
        case .folder(let id): return "Delete \(store.folder(id: id)?.name ?? "this folder")? Its playlists will become ungrouped."
        case .tracks(let ids): return "Delete \(ids.count == 1 ? "this track" : "these \(ids.count) tracks") from Bard and every playlist? Bard’s copies move to the Trash. Your original files are unchanged."
        }
    }

    private func performDeletion(_ request: DeletionRequest) {
        switch request {
        case .playlist(let id): store.deletePlaylist(id: id)
        case .folder(let id): store.deleteFolder(id: id)
        case .tracks(let ids): store.deleteTracks(ids)
        }
        deletion = nil
        presentPendingArtworkReview()
    }
}

private struct ArtworkReviewRoute: Identifiable {
    let id = UUID()
    let tracks: [Track]
}
