import SwiftUI
import WispCore

private enum PhoneLibrarySheet: Identifiable {
    case sync, search, player
    case smart([Track], String)
    var id: String {
        switch self { case .sync: return "sync"; case .search: return "search"; case .player: return "player"; case .smart: return "smart" }
    }
}

@MainActor
private final class PhoneLibraryPresentation: ObservableObject {
    @Published var sheet: PhoneLibrarySheet?
}

struct PhoneLibraryView: View {
    @EnvironmentObject private var library: PhoneLibraryStore
    @EnvironmentObject private var player: PhonePlayerStore
    @StateObject private var presentation = PhoneLibraryPresentation()

    var body: some View {
        NavigationStack {
            Group {
                if library.isLoading {
                    ProgressView("Opening your library…").font(.wispText(.body))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if library.document.tracks.isEmpty {
                    emptyLibrary
                } else {
                    libraryHome
                }
            }
            .background(PhoneStyle.background)
            .navigationTitle("Library").navigationBarTitleDisplayMode(.inline)
            .modifier(PhoneLibraryToolbar())
            .navigationDestination(for: PhoneCollectionRoute.self) { route in PhoneTrackList(route: route) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.currentTrack != nil { PhoneMiniPlayer() }
        }
        .environmentObject(presentation)
        .sheet(item: $presentation.sheet) { sheet in
            Group {
                switch sheet {
                case .sync: PhoneSyncView()
                case .search: PhoneLibrarySearchView()
                case .player: PhonePlayerView()
                case .smart(let tracks, let title): PhoneSmartShuffleView(tracks: tracks, title: title)
                }
            }.environmentObject(presentation)
        }
        .alert("Playback", isPresented: Binding(get: { presentation.sheet == nil && player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } })) {
                Button("OK") { player.errorMessage = nil }
            } message: { Text(player.errorMessage ?? "") }
    }

    private var libraryHome: some View {
        List {
            Section {
                Button { showLibrarySmartShuffle() } label: {
                    HStack(spacing: 14) {
                        PhoneNavigationGlyph(symbol: "waveform.path", color: PhoneStyle.blue, prominent: true)
                        Text("Smart Shuffle").font(.wispText(.body, medium: true)).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "slider.horizontal.3").font(.system(size: 14)).foregroundStyle(.secondary)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(PhoneStyle.blue)
                    .accessibilityHint("Choose an energy curve for your whole library")
                    .modifier(PhoneListRow())
            }
            Section {
                homeLink(.music, title: "Music", symbol: "music.note", count: library.document.tracks.count)
                homeLink(.favorites, title: "Favorites", symbol: "heart.fill", tint: PhoneStyle.rose)
                homeLink(.recentlyAdded, title: "Recent", symbol: "clock.fill", tint: PhoneStyle.amber)
                homeLink(.collection(.basic), title: "Basic", subtitle: "External sources", symbol: "tray.and.arrow.down.fill", tint: PhoneStyle.teal)
                homeLink(.collection(.classic), title: "Classic", subtitle: "Created by you", symbol: "pencil.tip.crop.circle.fill", tint: PhoneStyle.violet)
            } header: { PhoneSectionHeading("Collection") }.listSectionSeparator(.hidden)

            Section {
                if library.document.playlists.isEmpty {
                    Text("Playlists you make on your Mac appear here.")
                        .font(.wispText(.caption)).foregroundStyle(.secondary).padding(.vertical, 10)
                        .modifier(PhoneListRow())
                } else {
                    ForEach(library.document.playlists) { playlist in
                        let page = PhoneLibraryNavigation.page(.playlist(playlist.id), in: library.document)
                        NavigationLink(value: PhoneCollectionRoute.playlist(playlist.id)) {
                            PhoneLibraryNavigationRow(title: playlist.name,
                                symbol: playlist.isMixtape ? "music.note" : "music.note.list",
                                tint: playlist.isMixtape ? PhoneStyle.rose : PhoneStyle.muted,
                                count: page.tracks.count, prominent: playlist.isMixtape)
                        }.modifier(PhoneListRow())
                    }
                }
            } header: { PhoneSectionHeading("Playlists") }.listSectionSeparator(.hidden)

            Section {
                homeLink(.artists, title: "Artists", symbol: "person", tint: PhoneStyle.muted, count: PhoneLibraryNavigation.page(.artists, in: library.document).groups.count)
                homeLink(.origins, title: "Origins", symbol: "square.stack", tint: PhoneStyle.muted, count: nil)
                homeLink(.genres, title: "Genres", symbol: "tag", tint: PhoneStyle.muted, count: PhoneLibraryNavigation.page(.genres, in: library.document).groups.count)
            } header: { PhoneSectionHeading("Browse") }.listSectionSeparator(.hidden)

            Section {
                HStack(spacing: 8) {
                    Text("\(library.document.tracks.count) songs available offline")
                        .font(.wispText(.small)).foregroundStyle(.tertiary)
                    Spacer()
                    PhoneMakerMark()
                }.padding(.vertical, 6).accessibilityElement(children: .combine).modifier(PhoneListRow())
            }
        }
        .modifier(PhonePlainList())
        .toolbar {
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) { PhoneBrandSignature() }.sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) { PhoneBrandSignature() }
            }
        }
    }

    private func showLibrarySmartShuffle() {
        guard let snapshot = library.snapshot, !snapshot.document.tracks.isEmpty else { return }
        presentation.sheet = .smart(TrackSearch.alphabetized(snapshot.document.tracks), "Music")
    }

    private func homeLink(_ route: PhoneCollectionRoute, title: String, subtitle: String? = nil,
                          symbol: String, tint: Color = PhoneStyle.blue, count: Int? = nil) -> some View {
        let page = PhoneLibraryNavigation.page(route, in: library.document)
        let trackRoute: Bool
        switch route { case .music, .favorites, .recentlyAdded, .collection: trackRoute = true; default: trackRoute = false }
        return NavigationLink(value: route) {
            PhoneLibraryNavigationRow(title: title, subtitle: subtitle, symbol: symbol,
                                      tint: tint, count: count ?? (trackRoute ? page.tracks.count : nil), prominent: trackRoute)
        }.modifier(PhoneListRow())
    }

    private var emptyLibrary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PhoneBrandSignature()
                Text(library.hasPendingConnection ? "Connecting your library…" : "Made on your Mac.\nPlayed everywhere.")
                    .font(.wispText(.title)).fixedSize(horizontal: false, vertical: true)
                Text(library.hasPendingConnection ? library.status : "Your songs and playlists, downloaded for the moments offline.")
                    .font(.wispText(.body)).foregroundStyle(.secondary).lineSpacing(4)
                Button(library.hasPendingConnection ? "Connection status" : "Connect your library") { presentation.sheet = .sync }
                    .font(.wispText(.body, medium: true)).buttonStyle(PhoneActionButtonStyle(prominent: true))
                PhoneAura(level: 0, playing: false).frame(height: 120).padding(.top, 22)
            }.frame(maxWidth: 540, alignment: .leading).padding(28).padding(.top, 38)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PhoneMakerMark().frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 28).padding(.bottom, 16)
        }
    }
}

private struct PhoneLibraryToolbar: ViewModifier {
    @EnvironmentObject private var presentation: PhoneLibraryPresentation
    @EnvironmentObject private var library: PhoneLibraryStore
    @AppStorage(PhoneAppearance.preferenceKey) private var appearance: PhoneAppearance = .system
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { presentation.sheet = .search } label: { Image(systemName: "magnifyingglass") }
                    .foregroundStyle(PhoneStyle.muted).accessibilityLabel("Search whole library")
                Menu {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(PhoneAppearance.allCases) { option in
                            Label(option.title, systemImage: option.symbol).tag(option)
                        }
                    }.pickerStyle(.inline)
                } label: { Image(systemName: appearance.symbol) }
                    .foregroundStyle(PhoneStyle.muted).accessibilityLabel("Appearance")
                    .accessibilityValue(appearance.title)
                Button { presentation.sheet = .sync } label: {
                    Image(systemName: library.isSyncing ? "arrow.triangle.2.circlepath" : "iphone.and.arrow.right.inward")
                }.foregroundStyle(PhoneStyle.muted).accessibilityLabel("Phone Sync")
            }
        }
    }
}

private struct PhonePlainList: ViewModifier {
    func body(content: Content) -> some View {
        content.listStyle(.plain).scrollContentBackground(.hidden)
            .listSectionSpacing(10)
            .contentMargins(.top, 0, for: .scrollContent)
            .environment(\.defaultMinListRowHeight, 48)
            .background(PhoneStyle.background)
    }
}

private struct PhoneListRow: ViewModifier {
    func body(content: Content) -> some View {
        content.listRowSeparator(.hidden)
            .listRowBackground(PhoneStyle.background)
            .listRowInsets(EdgeInsets(top: 2, leading: 22, bottom: 2, trailing: 22))
    }
}

private struct PhoneSectionHeading: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(.wispText(.small, medium: true))
            .foregroundStyle(PhoneStyle.muted).textCase(nil).padding(.top, 8).padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct PhoneLibraryNavigationRow: View {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    var tint: Color = PhoneStyle.muted
    var count: Int?
    var prominent = false
    var body: some View {
        HStack(spacing: 14) {
            PhoneNavigationGlyph(symbol: symbol, color: tint, prominent: prominent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.wispText(.body, medium: prominent)).foregroundStyle(.primary)
                if let subtitle { Text(subtitle).font(.wispText(.small)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            if let count { Text(count.formatted()).font(.wispText(.caption)).foregroundStyle(PhoneStyle.muted).monospacedDigit() }
        }.padding(.vertical, subtitle == nil ? 5 : 7).contentShape(Rectangle())
    }
}

struct PhoneSongRow: View {
    let track: Track
    @EnvironmentObject private var library: PhoneLibraryStore
    @EnvironmentObject private var player: PhonePlayerStore
    var body: some View {
        HStack(spacing: 14) {
            PhoneCover(url: library.artworkURL(for: track), size: 36).rotationEffect(.degrees(-2))
            VStack(alignment: .leading, spacing: 4) {
                Text(track.displayTitle).font(.wispText(.caption, medium: true)).foregroundStyle(.primary).lineLimit(2)
                Text(track.artist.isEmpty ? (track.displayOrigin.isEmpty ? "Unknown artist" : track.displayOrigin) : track.artist)
                    .font(.wispText(.small)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 3)
            if player.currentTrack?.id == track.id {
                Image(systemName: "waveform").font(.system(size: 13)).foregroundStyle(PhoneStyle.blue).accessibilityLabel("Now playing")
            }
            if library.isFavorite(track) {
                Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(PhoneStyle.rose).accessibilityLabel("Favorite")
            }
        }.padding(.vertical, 9).contentShape(Rectangle())
            .background {
                if player.currentTrack?.id == track.id {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(PhoneStyle.selection).padding(.horizontal, -10)
                }
            }
            .overlay(alignment: .leading) {
                if player.currentTrack?.id == track.id {
                    Capsule().fill(PhoneStyle.blue).frame(width: 2, height: 24).offset(x: -10)
                }
            }
    }
}

struct PhoneTrackList: View {
    let route: PhoneCollectionRoute
    @EnvironmentObject private var library: PhoneLibraryStore
    @EnvironmentObject private var player: PhonePlayerStore
    @EnvironmentObject private var presentation: PhoneLibraryPresentation
    private var page: PhoneLibraryPage { PhoneLibraryNavigation.page(route, in: library.document) }
    var body: some View {
        let displayed = page
        List {
            if let subtitle = displayed.subtitle {
                Text(subtitle).font(.wispText(.caption)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.vertical, 6).modifier(PhoneListRow())
            }
            if !displayed.groups.isEmpty {
                Section {
                    ForEach(displayed.groups) { group in
                        NavigationLink(value: group.route) {
                            PhoneLibraryNavigationRow(title: group.title, subtitle: group.subtitle,
                                                      symbol: group.symbol, count: group.count)
                        }.modifier(PhoneListRow())
                    }
                } header: { if let heading = displayed.groupHeading { PhoneSectionHeading(heading) } }.listSectionSeparator(.hidden)
            }
            if displayed.showsTracks {
                Section {
                    PhoneCollectionActions(ordered: displayed.ordered, count: displayed.tracks.count,
                        play: playFirst, shuffle: shuffle, smart: smartShuffle).modifier(PhoneListRow())
                    ForEach(displayed.tracks) { track in
                        Button { play(track.id) } label: { PhoneSongRow(track: track) }
                            .buttonStyle(.plain).modifier(PhoneSongQueueActions(trackID: track.id)).modifier(PhoneListRow())
                    }
                } header: { if !displayed.groups.isEmpty { PhoneSectionHeading("Songs") } }.listSectionSeparator(.hidden)
            }
        }
        .modifier(PhonePlainList())
        .navigationTitle(displayed.title).navigationBarTitleDisplayMode(.inline)
        .modifier(PhoneLibraryToolbar())
        .overlay {
            if displayed.tracks.isEmpty && displayed.groups.isEmpty {
                ContentUnavailableView("No songs here", systemImage: "music.note",
                    description: Text(displayed.subtitle ?? "This collection reflects your Mac library. Add songs on your Mac, then sync again."))
                    .allowsHitTesting(false)
            }
        }
    }
    private func play(_ id: UUID) {
        guard let copy = library.snapshot else { return }
        let tracks = currentTracks(for: route, snapshot: copy)
        guard let track = tracks.first(where: { $0.id == id }) else {
            player.errorMessage = "This song is no longer in this collection."; return
        }
        player.play(track, in: tracks, mediaDirectory: copy.mediaDirectory, artworkDirectory: copy.artworkDirectory)
    }
    private func playFirst() {
        guard let copy = library.snapshot, let first = currentTracks(for: route, snapshot: copy).first else { return }
        play(first.id)
    }
    private func shuffle() {
        guard let copy = library.snapshot else { return }
        player.shuffle(tracks: currentTracks(for: route, snapshot: copy),
                       mediaDirectory: copy.mediaDirectory, artworkDirectory: copy.artworkDirectory)
    }
    private func currentTracks(for route: PhoneCollectionRoute, snapshot: PhoneLibrarySnapshot) -> [Track] {
        let available = Dictionary(snapshot.document.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return PhoneLibraryNavigation.page(route, in: library.document).tracks.compactMap { available[$0.id] }
    }
    private func smartShuffle() {
        guard let copy = library.snapshot else { return }
        let current = PhoneLibraryNavigation.page(route, in: library.document)
        let tracks = currentTracks(for: route, snapshot: copy)
        guard !tracks.isEmpty else { return }
        presentation.sheet = .smart(tracks, current.title)
    }
}

private struct PhoneCollectionActions: View {
    let ordered: Bool
    let count: Int
    let play: () -> Void
    let shuffle: () -> Void
    let smart: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(count) \(count == 1 ? "song" : "songs")").font(.wispText(.small)).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions }.fixedSize()
                VStack(alignment: .leading, spacing: 8) { actions }
            }.font(.wispText(.caption, medium: true)).disabled(count == 0)
        }.padding(.vertical, 7)
    }
    @ViewBuilder private var actions: some View {
        if ordered {
            Button(action: play) { actionLabel("Play", symbol: "play.fill") }
                .buttonStyle(PhoneActionButtonStyle(prominent: true))
        }
        Button(action: shuffle) { actionLabel("Shuffle", symbol: "shuffle") }
            .buttonStyle(PhoneActionButtonStyle(prominent: !ordered))
        Button(action: smart) { actionLabel("Smart Shuffle", symbol: "waveform.path") }
            .buttonStyle(PhoneActionButtonStyle())
    }
    private func actionLabel(_ title: String, symbol: String) -> some View {
        // These controls must keep their titles during ViewThatFits' width
        // probes; an adaptive Label can compress into an icon-only column.
        HStack(spacing: 7) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(title).lineLimit(1)
        }.fixedSize()
    }
}

private struct PhoneSongQueueActions: ViewModifier {
    let trackID: UUID
    @EnvironmentObject private var library: PhoneLibraryStore
    @EnvironmentObject private var player: PhonePlayerStore
    func body(content: Content) -> some View {
        content.swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let track = library.document.tracks.first(where: { $0.id == trackID }) {
                Button { library.toggleFavorite(track) } label: {
                    Label(library.isFavorite(track) ? "Unfavorite" : "Favorite", systemImage: library.isFavorite(track) ? "heart.slash" : "heart")
                }.tint(PhoneStyle.rose)
            }
        }.contextMenu {
            Button { queue(next: true) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { queue(next: false) } label: { Label("Add to Queue", systemImage: "text.badge.plus") }
        }
    }
    private func queue(next: Bool) {
        guard let copy = library.snapshot, let track = copy.document.tracks.first(where: { $0.id == trackID }) else {
            player.errorMessage = "This song is no longer in the downloaded library."; return
        }
        if next { player.playNext(track, mediaDirectory: copy.mediaDirectory, artworkDirectory: copy.artworkDirectory) }
        else { player.addToQueue(track, mediaDirectory: copy.mediaDirectory, artworkDirectory: copy.artworkDirectory) }
    }
}

private struct PhoneLibrarySearchView: View {
    @EnvironmentObject private var library: PhoneLibraryStore
    @EnvironmentObject private var player: PhonePlayerStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searching = true
    private var results: [Track] { PhoneLibraryNavigation.search(query, in: library.document) }
    var body: some View {
        NavigationStack {
            List {
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        ForEach(results) { track in
                            Button { play(track.id) } label: { PhoneSongRow(track: track) }
                                .buttonStyle(.plain).modifier(PhoneSongQueueActions(trackID: track.id)).modifier(PhoneListRow())
                        }
                    } header: { Text("\(results.count) \(results.count == 1 ? "song" : "songs") in your library").font(.wispText(.small)) }
                }
            }.modifier(PhonePlainList())
                .overlay {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView("Your whole library", systemImage: "magnifyingglass",
                            description: Text("Find songs by title, artist, origin, or genre.")).allowsHitTesting(false)
                    } else if results.isEmpty { ContentUnavailableView.search(text: query).allowsHitTesting(false) }
                }
                .navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
                .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Title, artist, origin, genre")
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
    private func play(_ id: UUID) {
        guard let copy = library.snapshot else { return }
        let available = Dictionary(copy.document.tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let tracks = PhoneLibraryNavigation.search(query, in: library.document).compactMap { available[$0.id] }
        guard let track = tracks.first(where: { $0.id == id }) else { return }
        player.play(track, in: tracks, mediaDirectory: copy.mediaDirectory, artworkDirectory: copy.artworkDirectory)
        dismiss()
    }
}

private struct PhoneMiniPlayer: View {
    @EnvironmentObject private var player: PhonePlayerStore
    @EnvironmentObject private var presentation: PhoneLibraryPresentation
    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 8) {
                Button { presentation.sheet = .player } label: {
                    HStack(spacing: 13) {
                        PhoneCover(url: player.currentArtworkURL, size: 36).rotationEffect(.degrees(-2))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.displayTitle).font(.wispText(.caption, medium: true)).foregroundStyle(.primary).lineLimit(1)
                            Text(track.artist.isEmpty ? "Unknown artist" : track.artist).font(.wispText(.small)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }.frame(minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Now playing: \(track.displayTitle)").accessibilityHint("Opens the player and queue")
                Button { player.togglePlayback() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
                        .background(PhoneStyle.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }.accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { player.next() } label: {
                    Image(systemName: "forward.end.fill").font(.system(size: 15)).frame(width: 44, height: 48)
                }.accessibilityLabel("Next song")
            }.padding(.horizontal, 22).padding(.vertical, 10).background(PhoneStyle.background)
                .overlay(alignment: .top) { Rectangle().fill(PhoneStyle.line).frame(height: 0.5) }
        }
    }
}
