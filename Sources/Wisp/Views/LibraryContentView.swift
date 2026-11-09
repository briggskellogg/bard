import SwiftUI
import AppKit
import WispCore

@MainActor
struct LibraryContentView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    let destination: Destination
    let playlist: Playlist?
    let tracks: [Track]
    @Binding var query: String
    var isSearching = false
    @Binding var selectedTracks: Set<UUID>
    @Binding var sort: TrackSort
    @Binding var filter: TrackLibraryFilter
    let genres: [TrackFilterChoice]
    let origins: [TrackFilterChoice]
    let importMusic: () -> Void
    let editPlaylist: () -> Void
    let addTracks: () -> Void
    let editTrack: (UUID) -> Void
    let editTracks: ([UUID]) -> Void
    let makeMixtape: () -> Void
    let addToPlaylist: ([UUID]) -> Void
    let deleteTracks: (Set<UUID>) -> Void
    var syncStatus: String? = nil
    var syncDetail = ""
    var syncInProgress = false
    var syncNeedsAttention = false
    var syncNow: (() -> Void)? = nil
    @StateObject private var downloads = LibraryDownloadController.shared
    @State private var showsEnergyCurve = false

    private var title: String {
        if isSearching { return "Search results" }
        if let playlist { return playlist.name }
        switch destination {
        case .favorites: return "Favorites"
        case .recent: return "Recent"
        case .basic: return "Basic"
        case .classic: return "Classic"
        case .artist(let artist): return artist.isEmpty ? "Unknown Artist" : artist
        case .origin(_, let origin), .sharedOrigin(let origin): return origin.isEmpty ? "Standalone" : origin
        case .media(let kind): return kind.categoryTitle
        default: return "Music"
        }
    }
    private var symbol: String {
        if let playlist { return playlist.symbol }
        switch destination {
        case .favorites: return "heart.fill"
        case .recent: return "clock.fill"
        case .basic: return "arrow.down.to.line"
        case .classic: return "pencil.line"
        case .artist: return "person.crop.circle"
        case .origin, .sharedOrigin: return tracks.first?.libraryMediaKind.symbolName ?? "square.stack"
        case .media(let kind): return kind.symbolName
        default: return "music.note"
        }
    }
    private var tint: PaletteColor {
        if let playlist { return playlist.tint }
        switch destination {
        case .favorites: return .coral
        case .recent: return .amber
        default: return .blue
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                header
                sectionTools
                if filter.isActive { filterSummary }
                if tracks.isEmpty {
                    emptyState
                } else {
                    TrackList(tracks: tracks, playlist: playlist, selectedTracks: $selectedTracks,
                               showsVersions: destination != .basic && destination != .classic,
                               editTrack: editTrack, editTracks: editTracks, addToPlaylist: addToPlaylist, deleteTracks: deleteTracks,
                               download: { download($0, asSong: $1) }, downloadDisabled: downloads.isWorking)
                        .padding(.horizontal, geometry.size.width < 460 ? 20 : 24).padding(.bottom, 18)
                }
            }
            .overlay(alignment: .bottomLeading) { downloadStatus }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            if let playlist, store.coverURL(for: playlist) != nil {
                ArtworkView(url: store.coverURL(for: playlist), symbol: symbol, tint: tint, size: 72)
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(title).font(WispType.display(35)).tracking(-0.7).lineLimit(2).textSelection(.enabled)
                    if playlist?.isMixtape == true {
                        Menu {
                            Button("Choose Songs…", action: addTracks).disabled(store.tracks.isEmpty)
                            Button("Import Audio…", action: importMusic).disabled(store.isImporting)
                        } label: {
                            Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .foregroundStyle(.secondary).disabled(!store.canEdit)
                        .help("Add songs to Mixtape").accessibilityLabel("Add songs to Mixtape")
                    } else if playlist != nil {
                        Menu {
                            Button("Edit Playlist…", action: editPlaylist)
                            Button("Add Tracks…", action: addTracks).disabled(!store.canEdit)
                            Button("Make Mixtape…", action: makeMixtape).disabled(playlist?.trackIDs.isEmpty ?? true)
                        } label: { Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold)) }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .foregroundStyle(.secondary).help("Playlist actions").accessibilityLabel("Playlist actions")
                    }
                }
                if case .origin(let artist, _) = destination {
                    Text(artist.isEmpty ? "Unknown Artist" : artist).font(WispType.ui(13)).foregroundStyle(.secondary)
                }
                if let playlist, !playlist.description.isEmpty {
                    Text(playlist.description).font(WispType.ui(14)).foregroundStyle(.secondary)
                        .lineLimit(4).textSelection(.enabled)
                }
                HStack(spacing: 10) {
                    if destination == .basic { Text("External sources"); Text("/").opacity(0.4) }
                    if destination == .classic { Text("Created by you"); Text("/").opacity(0.4) }
                    Text("\(tracks.count) \(tracks.count == 1 ? "track" : "tracks")")
                    if isSearching { Text("/").opacity(0.4); Text("Entire library") }
                    if !tracks.isEmpty { Text("/").opacity(0.4); Text(collectionDuration(tracks)) }
                    if destination == .recent { Text("/").opacity(0.4); Text("30 days") }
                }.font(WispType.ui(12)).foregroundStyle(WispSurface.mutedText)
                if playlist?.isMixtape == true { mixtapeSyncStatus }
            }
            Spacer(minLength: 12)
            Button { download(tracks) } label: {
                Image(systemName: "arrow.down.to.line").font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(WispSurface.mutedText)
            .disabled(tracks.isEmpty || downloads.isWorking)
            .help("Download these tracks as a ZIP to Downloads/Wisp")
            .accessibilityLabel("Download \(title)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 34).padding(.top, 19).padding(.bottom, 24)
    }

    @ViewBuilder
    private var mixtapeSyncStatus: some View {
        if let syncStatus, let syncNow {
            Button(action: syncNow) {
                HStack(spacing: 6) {
                    Image(systemName: syncNeedsAttention ? "exclamationmark.circle" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                    Text(syncStatus).lineLimit(1)
                }.font(WispType.ui(11))
            }
            .buttonStyle(.plain).disabled(syncInProgress)
            .foregroundStyle(syncNeedsAttention ? PaletteColor.amber.color : WispSurface.mutedText)
            .help(syncDetail).accessibilityLabel("\(syncStatus). Sync Mixtape with Music")
            .accessibilityHint(syncDetail)
        }
    }

    private var sectionTools: some View {
        HStack(spacing: 8) {
            playbackActions
            if let playlist, !playlist.trackIDs.isEmpty {
                Text(playlist.trackIDs == tracks.map(\.id) ? "Drag to reorder" : "Clear search and filters to reorder")
                    .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                    .padding(.leading, 8)
            }
            Spacer(minLength: 16)
            Menu {
                if playlist == nil {
                    Picker("Sort", selection: $sort) {
                        ForEach(TrackSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Divider()
                }
                Picker("Genre", selection: $filter.genre) {
                    Text("All genres").tag(String?.none)
                    ForEach(genres) { Text($0.label).tag(Optional($0.id)) }
                }
                if filter.isActive {
                    Divider()
                    Button("Clear Filters") { filter = TrackLibraryFilter() }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 10))
                    Text("View")
                    if filter.isActive { Circle().fill(WispSurface.cyan).frame(width: 4, height: 4) }
                }.foregroundStyle(filter.isActive ? WispSurface.cyan : WispSurface.mutedText)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .tint(filter.isActive ? WispSurface.cyan : WispSurface.mutedText)
            .help("Sort and filter this collection").accessibilityLabel("View options")
        }
        .font(WispType.ui(12))
        .padding(.horizontal, 34).padding(.bottom, 19)
    }

    private var playbackActions: some View {
        HStack(spacing: 8) {
            if let playlist, !isSearching {
                Button {
                    let visible = Set(tracks.map(\.id))
                    let sequence = playlist.trackIDs.filter(visible.contains)
                    player.setShuffle(false)
                    player.play(ids: sequence, startID: sequence.first)
                } label: { Label("Play", systemImage: "play.fill") }
                .buttonStyle(WispActionButtonStyle(primary: true)).help("Play the playlist’s saved order")
            }
            Button {
                player.setShuffle(true)
                player.play(ids: tracks.map(\.id))
            } label: { Label("Shuffle", systemImage: "shuffle") }
            .buttonStyle(WispActionButtonStyle(primary: playlist == nil || isSearching)).help("Play these tracks in a random order")
            Button { showsEnergyCurve = true } label: {
                Label("Smart Shuffle", systemImage: "waveform.path")
            }
            .buttonStyle(WispActionButtonStyle()).help("Choose a listening shape and match songs by energy")
            .popover(isPresented: $showsEnergyCurve, arrowEdge: .bottom) {
                EnergyCurvePopover(player: player, trackIDs: tracks.map(\.id)) { showsEnergyCurve = false }
            }
        }.disabled(tracks.isEmpty).fixedSize()
    }

    private func download(_ requested: [Track], asSong: Bool = false) {
        let items = requested.map { LibraryDownloadItem(track: $0, audioURL: store.audioURL(for: $0), artworkURL: store.artworkURL(for: $0)) }
        let selectedOnly = requested.map(\.id) != tracks.map(\.id)
        var request = LibraryDownloadRequest(kind: asSong ? .song : .collection,
            title: selectedOnly ? "\(title) selection" : title, items: items)
        request.description = playlist?.description ?? ""
        request.coverURL = playlist.flatMap { store.coverURL(for: $0) }
        downloads.start(request)
    }

    @ViewBuilder
    private var downloadStatus: some View {
        if let status = downloads.status {
            HStack(spacing: 10) {
                if downloads.isWorking { ProgressView().controlSize(.small).scaleEffect(0.75).frame(width: 14, height: 14) }
                Text(status).font(WispType.ui(11)).lineLimit(2)
                    .foregroundStyle(downloads.failed ? Color.red : WispSurface.mutedText)
                if downloads.resultURL != nil {
                    Button("Show", action: downloads.reveal).buttonStyle(.plain).foregroundStyle(WispSurface.cyan)
                        .help("Show download in Finder")
                }
                if !downloads.isWorking {
                    Button(action: downloads.dismiss) { Image(systemName: "xmark").font(.system(size: 9)) }
                        .buttonStyle(.plain).foregroundStyle(WispSurface.mutedText)
                        .help("Dismiss download status").accessibilityLabel("Dismiss download status")
                }
            }
            .font(WispType.ui(11)).padding(.horizontal, 13).padding(.vertical, 10)
            .background(WispSurface.main.opacity(0.97))
            .padding(.horizontal, 24).padding(.bottom, 8)
            .accessibilityElement(children: .contain)
        }
    }

    private var filterSummary: some View {
        HStack(spacing: 9) {
            if let genre = filter.genre {
                Text(genres.first(where: { $0.id == genre })?.label ?? (genre.isEmpty ? "Unspecified genre" : genre))
            }
            if filter.genre != nil && filter.origin != nil { Text("/").foregroundStyle(.secondary) }
            if let origin = filter.origin {
                Text(origins.first(where: { $0.id == origin })?.label ?? (origin.isEmpty ? "No origin" : origin))
            }
            Button { filter = TrackLibraryFilter() } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                .buttonStyle(.plain).help("Clear filters").accessibilityLabel("Clear filters")
            Spacer(minLength: 0)
        }.font(WispType.ui(12)).foregroundStyle(WispSurface.cyan)
            .lineLimit(1).padding(.horizontal, 36).padding(.bottom, 12)
    }

    @ViewBuilder
    private var emptyState: some View {
        if filter.isActive {
            EmptyMessage(title: "No matches", message: "No tracks match these filters in this collection.", symbol: "line.3.horizontal.decrease",
                         actionTitle: "Clear filters", action: { filter = TrackLibraryFilter() })
        } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyMessage(title: "No results", message: "No tracks match this search.", symbol: "magnifyingglass",
                         actionTitle: "Clear search", action: { query = "" })
        } else if destination == .basic || destination == .classic {
            EmptyMessage(title: title, message: "Tracks marked \(title) appear here.", symbol: symbol)
        } else if let playlist {
            if playlist.isMixtape {
                EmptyMessage(title: "Your Mixtape", message: "Choose songs or drop audio here. Bard controls the Mixtape playlist in Music, keeping your songs in this order.",
                             symbol: "music.note.list", actionTitle: store.tracks.isEmpty ? "Import audio" : "Choose songs",
                             action: store.tracks.isEmpty ? importMusic : addTracks)
            } else {
                EmptyMessage(title: "Empty", message: "Add tracks to \(playlist.name), or drop audio files here.",
                             symbol: playlist.symbol, actionTitle: store.tracks.isEmpty ? "Import" : "Add", action: store.tracks.isEmpty ? importMusic : addTracks)
            }
        } else if destination == .favorites {
            EmptyMessage(title: "Favorites", message: "Use the heart beside a track to keep it here.", symbol: "heart.fill")
        } else if destination == .recent && !store.tracks.isEmpty {
            EmptyMessage(title: "Recent", message: "Music imported in the last 30 days appears here.", symbol: "clock.fill", actionTitle: "Import", action: importMusic)
        } else {
            EmptyMessage(title: "Music", message: "Import audio files or drop a folder here to begin.", symbol: "music.note", actionTitle: "Import", action: importMusic)
        }
    }

}

@MainActor
private struct TrackList: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    let tracks: [Track]
    let playlist: Playlist?
    @Binding var selectedTracks: Set<UUID>
    let showsVersions: Bool
    let editTrack: (UUID) -> Void
    let editTracks: ([UUID]) -> Void
    let addToPlaylist: ([UUID]) -> Void
    let deleteTracks: (Set<UUID>) -> Void
    let download: ([Track], Bool) -> Void
    let downloadDisabled: Bool

    private var canReorder: Bool {
        store.canEdit && playlist?.trackIDs == tracks.map(\.id)
    }

    var body: some View {
        GeometryReader { geometry in
            // Native lists reserve room for a scrollbar independently of their
            // rows. Share fixed column widths with the non-scrolling heading.
            let columns = TrackColumns(width: max(0, geometry.size.width - 44))
            VStack(spacing: 3) {
                columnHeadings(columns)
                List(selection: $selectedTracks) {
                    ForEach(tracks) { track in
                        trackRow(track, columns: columns)
                            .tag(track.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .moveDisabled(!canReorder)
                    }
                    .onMove { offsets, destination in
                        guard canReorder, let playlist else { return }
                        store.moveTracks(fromOffsets: offsets, toOffset: destination, in: playlist.id)
                    }
                }
                .listStyle(.plain)
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: UUID.self) { ids in
                    contextMenu(ids)
                } primaryAction: { ids in
                    guard let first = tracks.first(where: { ids.contains($0.id) }) else { return }
                    player.play(ids: tracks.map(\.id), startID: first.id)
                }
                .onDeleteCommand {
                    guard store.canEdit, !selectedTracks.isEmpty else { return }
                    if let playlist { store.removeTracks(selectedTracks, from: playlist.id) }
                    else { deleteTracks(selectedTracks) }
                }
            }
        }
    }

    private func columnHeadings(_ columns: TrackColumns) -> some View {
        HStack(spacing: 14) {
            Text("Song").frame(width: columns.title, alignment: .leading)
            if !columns.compact { Text("Artist").frame(width: columns.artist, alignment: .leading) }
            Text("Origin").frame(width: columns.origin, alignment: .leading)
            Text("Time").frame(width: 38, alignment: .trailing)
            Color.clear.frame(width: 52, height: 1)
        }
        .frame(width: columns.width, alignment: .leading)
        .font(WispType.ui(11, weight: .medium)).foregroundStyle(WispSurface.mutedText)
        .padding(.leading, 12).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }

    private func trackRow(_ track: Track, columns: TrackColumns) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                TrackCoverBadge(url: store.artworkURL(for: track))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(track.displayTitle)
                            .font(WispType.ui(13, weight: player.currentID == track.id ? .semibold : .medium))
                            .foregroundStyle(WispSurface.ink)
                            .lineLimit(1).help(track.displayTitle)
                        if player.currentID == track.id {
                            Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                                .font(.system(size: 10, weight: .semibold)).foregroundStyle(PaletteColor.blue.color)
                                .accessibilityLabel(player.isPlaying ? "Playing" : "Paused")
                        }
                        if showsVersions && !columns.compact, let version = track.remix { VersionBadge(version: version) }
                    }
                    if columns.compact, !track.artist.isEmpty {
                        Text(track.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: columns.title, alignment: .leading)
            if !columns.compact {
                Text(track.artist.isEmpty ? "—" : track.artist)
                    .foregroundStyle(.secondary).lineLimit(1).help(track.artist)
                    .frame(width: columns.artist, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 3) {
                OriginLabel(track: track)
                if let url = track.sourceURL.flatMap(validatedWebURL) {
                    Text(MusicSource.detect(url).title).font(.system(size: 10)).foregroundStyle(.tertiary)
                        .lineLimit(1).padding(.leading, track.displayOrigin.isEmpty ? 0 : 21)
                }
            }.frame(width: columns.origin, alignment: .leading)
            Text(clockText(track.duration)).font(WispType.readout(17))
                .foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
            HStack(spacing: 4) {
                Button { download([track], true) } label: {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WispSurface.mutedText).frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(downloadDisabled)
                    .help("Download original audio to Downloads/Wisp")
                    .accessibilityLabel("Download \(track.displayTitle)")
                Button { store.toggleFavorite(id: track.id) } label: {
                    Image(systemName: track.favorite ? "heart.fill" : "heart")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(track.favorite ? PaletteColor.coral.color : Color.secondary.opacity(0.55))
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).help(track.favorite ? "Unfavorite" : "Favorite")
                    .accessibilityLabel(track.favorite ? "Remove \(track.displayTitle) from favorites" : "Favorite \(track.displayTitle)")
            }.frame(width: 52)

        }
        .font(WispType.ui(12))
        .frame(width: columns.width, alignment: .leading)
        .frame(minHeight: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func contextMenu(_ ids: Set<UUID>) -> some View {
        if !ids.isEmpty {
            Button("Play") {
                if let first = tracks.first(where: { ids.contains($0.id) }) { player.play(ids: tracks.map(\.id), startID: first.id) }
            }
            Button(ids.count == 1 ? "Edit…" : "Edit \(ids.count) Songs…") {
                if ids.count == 1, let id = ids.first { editTrack(id) }
                else { editTracks(tracks.map(\.id).filter(ids.contains)) }
            }.disabled(!store.canEdit)
            Menu("Add to") {
                if playlist?.isMixtape != true {
                    AddToMixtapeButton(trackIDs: tracks.map(\.id).filter(ids.contains))
                }
                Button("Playlist…") { addToPlaylist(tracks.map(\.id).filter(ids.contains)) }
            }.disabled(!store.canEdit)
            Menu("More") {
                Button(ids.count == 1 ? "Download" : "Download \(ids.count) Songs") {
                    download(tracks.filter { ids.contains($0.id) }, ids.count == 1)
                }.disabled(downloadDisabled)
                if ids.count == 1, let id = ids.first, let track = store.track(id: id) {
                    Button("Remix (Alpha)…") { NotificationCenter.default.post(name: WispAction.remix, object: id) }
                        .disabled(!store.canEdit)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.audioURL(for: track)]) }
                    if let url = track.sourceURL.flatMap(validatedWebURL) {
                        Button("Open Source") { NSWorkspace.shared.open(url) }
                    }
                }
                if let playlist, ids.count == 1, let id = ids.first,
                   let index = playlist.trackIDs.firstIndex(of: id) {
                    Divider()
                    Button("Move Up") { store.moveTrack(id: id, in: playlist.id, offset: -1) }
                        .disabled(!store.canEdit || index == 0)
                    Button("Move Down") { store.moveTrack(id: id, in: playlist.id, offset: 1) }
                        .disabled(!store.canEdit || index + 1 == playlist.trackIDs.count)
                }
                Divider()
                Button("Delete from Library…", role: .destructive) { deleteTracks(ids) }
                    .disabled(!store.canEdit)
            }
            if let playlist {
                Divider()
                Button(playlist.isMixtape ? "Remove from Mixtape" : "Remove from Playlist") {
                    store.removeTracks(ids, from: playlist.id)
                }.disabled(!store.canEdit)
            }
        }
    }
}

private struct TrackColumns {
    let width: CGFloat
    var compact: Bool { width < 600 }
    var artist: CGFloat { max(70, width * 0.19) }
    var origin: CGFloat { compact ? max(72, width * 0.26) : width * 0.27 }
    var title: CGFloat {
        max(0, width - origin - 38 - 52 - (compact ? 42 : artist + 56))
    }
}

struct VersionBadge: View {
    let version: RemixKind

    var body: some View {
        Text(version.title).font(WispType.ui(11, weight: .medium))
            .foregroundStyle(version == .classic ? WispSurface.magenta : WispSurface.cyan)
            .fixedSize(horizontal: true, vertical: false)
            .help(version.attribution)
            .accessibilityLabel("\(version.title): \(version.attribution)")
    }
}

@MainActor
struct FolderContentView: View {
    @EnvironmentObject private var store: LibraryStore
    let folder: PlaylistFolder
    let query: String
    let open: (UUID) -> Void
    let edit: (UUID) -> Void
    let new: () -> Void

    private var playlists: [Playlist] {
        store.playlists.filter { playlist in
            playlist.folderID == folder.id && (query.isEmpty || playlist.name.localizedCaseInsensitiveContains(query) || playlist.description.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 13) {
                StrongSymbol(name: "folder.fill", tint: folder.tint, size: 29).padding(.top, 3)
                VStack(alignment: .leading, spacing: 7) {
                    Text(folder.name).font(WispType.display(40))
                    Text("\(playlists.count) \(playlists.count == 1 ? "playlist" : "playlists")").font(WispType.ui(12)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(32)
            HStack {
                SectionTitle(title: "Playlists")
                Spacer()
                Button(action: new) { Label("New", systemImage: "plus") }.buttonStyle(.borderless).disabled(!store.canEdit)
            }.padding(.horizontal, 36).padding(.bottom, 15)
            if playlists.isEmpty {
                EmptyMessage(title: "Empty", message: query.isEmpty ? "Create a playlist in this folder." : "No playlists match your search.", symbol: "folder.fill", actionTitle: query.isEmpty ? "New" : nil, action: new)
            } else {
                List(playlists) { playlist in
                    HStack(spacing: 12) {
                        Button { open(playlist.id) } label: {
                            HStack(spacing: 12) {
                                if playlist.coverFileName != nil {
                                    ArtworkView(url: store.coverURL(for: playlist), symbol: playlist.symbol, tint: playlist.tint, size: 37)
                                } else {
                                    StrongSymbol(name: playlist.symbol, tint: playlist.tint, size: 25).frame(width: 37)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.name).font(WispType.ui(14, weight: .medium)).foregroundStyle(.primary)
                                    if !playlist.description.isEmpty { Text(playlist.description).font(WispType.ui(12)).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer()
                                Text("\(playlist.trackIDs.count) \(playlist.trackIDs.count == 1 ? "track" : "tracks")").font(.system(size: 11)).foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Button { edit(playlist.id) } label: { Image(systemName: "ellipsis").fontWeight(.semibold) }
                            .buttonStyle(.borderless).help("Edit").accessibilityLabel("Edit \(playlist.name)")
                    }
                    .padding(.vertical, 9)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                }
                .listStyle(.plain).scrollContentBackground(.hidden).padding(.horizontal, 24)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
