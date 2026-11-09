import SwiftUI
import AppKit
import WispCore

@MainActor
struct SidebarView: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var selection: Destination?
    let edit: (EditorRoute) -> Void
    let remove: (DeletionRequest) -> Void
    let importMusic: () -> Void
    let importLink: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedCategories = Set<OriginMediaKind>()
    @State private var artistHover = SidebarHoverState()

    private var artists: [ArtistGroup] {
        Dictionary(grouping: store.tracks, by: \.sidebarArtist)
            .map { ArtistGroup(name: $0.key, tracks: $0.value) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                WispBrandSignature()
                Spacer(minLength: 14)
                AppearanceMenu()
            }.foregroundStyle(WispSurface.ink)
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 17)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    sectionHeader("Collection") {
                        Menu {
                            Button("Import Audio…", action: importMusic)
                            Button("Import Link…", action: importLink)
                        } label: {
                            Image(systemName: "plus").font(.system(size: 10, weight: .medium))
                                .frame(width: 18, height: 18)
                        }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                        .help("Import music").accessibilityLabel("Import music")
                        .disabled(!store.canEdit || store.isImporting)
                    }
                    row(.music, title: "Music", symbol: "wisp.music", tint: .blue, count: store.tracks.count)
                    row(.favorites, title: "Favorites", symbol: "heart.fill", tint: .coral, count: store.tracks.filter(\.favorite).count)
                    row(.recent, title: "Recent", symbol: "clock.fill", tint: .amber)
                    row(.basic, title: "Basic", symbol: "wisp.external", tint: .teal, count: store.tracks.filter { $0.remix == .basic }.count)
                    row(.classic, title: "Classic", symbol: "wisp.original", tint: .violet, count: store.tracks.filter { $0.remix == .classic }.count)
                    row(.playlist(MixtapeCollection.id), title: MixtapeCollection.name, symbol: MixtapeCollection.symbol,
                        tint: .blue, count: store.mixtape?.trackIDs.count ?? 0)

                    sectionHeader("Categories") { EmptyView() }.padding(.top, 23)
                    ForEach(TrackCategories.availableKinds(in: store.tracks)) { kind in categoryRows(kind) }

                    sectionHeader("Playlists") {
                        Button { edit(.playlist(nil)) } label: {
                            Image(systemName: "plus").font(.system(size: 10, weight: .medium))
                                .frame(width: 18, height: 18).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!store.canEdit)
                            .help("New playlist").accessibilityLabel("New playlist")
                    }.padding(.top, 24)
                    // Folder membership is historical metadata; every playlist is
                    // visible here without mutating or deleting those records.
                    ForEach(store.playlists.filter { !$0.isMixtape }) { playlist in playlistRow(playlist) }
                    if !store.playlists.contains(where: { !$0.isMixtape }) {
                        Button { edit(.playlist(nil)) } label: {
                            Label { Text("New Playlist") } icon: { WispIcon(name: "plus", size: 12) }
                                .font(WispType.ui(12)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).frame(height: 32)
                        }.buttonStyle(.plain).disabled(!store.canEdit)
                    }
                    if !artists.isEmpty {
                        sectionHeader("Artists") { EmptyView() }.padding(.top, 24)
                        ForEach(artists) { artist in artistRows(artist) }
                    }

                }
                .padding(.horizontal, 12).padding(.top, 0).padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            footer
        }
        .background(WispSurface.sidebar.ignoresSafeArea())
        .onContinuousHover { phase in
            let now = ProcessInfo.processInfo.systemUptime
            switch phase {
            case .active: artistHover.move(pointer: NSEvent.mouseLocation, now: now)
            case .ended: artistHover.depart(now: now)
            }
        }
        .onAppear { revealCategorySelection() }
        .onChange(of: selection) { _ in revealCategorySelection() }
        .task(id: artistHover.pending) {
            guard let request = artistHover.pending else { return }
            let delay = max(0, request.deadline - ProcessInfo.processInfo.systemUptime)
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(artistAnimation) {
                artistHover.resolve(request, pointer: NSEvent.mouseLocation,
                                    now: ProcessInfo.processInfo.systemUptime)
            }
        }
        .onDisappear { artistHover.cancelPending() }
    }

    private func sectionHeader<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 6) {
            Text(title).font(WispType.ui(11, weight: .medium))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing()
        }
        .foregroundStyle(WispSurface.mutedText)
        .padding(.horizontal, 8).padding(.bottom, 6)
    }

    private func row(_ destination: Destination, title: String, symbol: String, tint: PaletteColor = .graphite,
                     count: Int? = nil, indent: CGFloat = 0) -> some View {
        Button { selection = destination } label: {
            SidebarRow(title: title, symbol: symbol, tint: tint, count: count,
                       selected: selection == destination, prominent: isPrimary(destination))
                .padding(.leading, indent)
                .padding(.horizontal, 8).frame(height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(SidebarSelection(selected: selection == destination))
        .accessibilityAddTraits(selection == destination ? [.isSelected] : [])
        .help(destination == .basic ? "Music from external sources" : destination == .classic ? "Music you created" : title)
    }

    private func isPrimary(_ destination: Destination) -> Bool {
        switch destination {
        case .music, .favorites, .recent, .basic, .classic: return true
        case .playlist(let id): return id == MixtapeCollection.id
        default: return false
        }
    }

    private func artistRows(_ artist: ArtistGroup) -> some View {
        let expanded = artistHover.expanded == artist.name
        let origins = artist.origins
        return VStack(spacing: 0) {
            Button { selection = .artist(artist.name) } label: {
                HStack(spacing: 0) {
                    SidebarRow(title: artist.title, symbol: "person.crop.circle", tint: .graphite,
                               selected: selection == .artist(artist.name))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .medium)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 18).accessibilityHidden(true)
                }
                .padding(.horizontal, 8).frame(height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(SidebarSelection(selected: artistContainsSelection(artist.name)))
            .accessibilityAddTraits(selection == .artist(artist.name) ? [.isSelected] : [])
            .accessibilityHint("Hover to show origins, or use Right Arrow. Left Arrow hides them.")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            .accessibilityAction(named: "Show origins") { showArtist(artist.name) }
            .accessibilityAction(named: "Hide origins") { if expanded { showArtist(nil) } }
            .onKeyPress(.rightArrow) { showArtist(artist.name); return .handled }
            .onKeyPress(.leftArrow) { if expanded { showArtist(nil) }; return .handled }
            VStack(spacing: 0) {
                ForEach(origins) { origin in
                    row(.origin(artist: artist.name, origin: origin.name), title: origin.title,
                        symbol: origin.kind.symbolName, indent: 16)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: expanded ? CGFloat(origins.count) * 32 : 0, alignment: .top)
            .opacity(expanded ? 1 : 0)
            .clipped()
            .allowsHitTesting(expanded)
            .disabled(!expanded)
            .accessibilityHidden(!expanded)
        }
        // Observe the whole group so crossing from its parent into an origin
        // never closes the list under the pointer.
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            let pointer = NSEvent.mouseLocation
            let now = ProcessInfo.processInfo.systemUptime
            switch phase {
            case .active: artistHover.enter(artist.name, pointer: pointer, now: now)
            case .ended: artistHover.leave(artist.name, pointer: pointer, now: now)
            }
        }
    }

    private func categoryRows(_ kind: OriginMediaKind) -> some View {
        let tracks = TrackCategories.tracks(in: store.tracks, kind: kind)
        let origins = TrackCategories.origins(in: tracks)
        let expanded = expandedCategories.contains(kind)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { selection = .media(kind) } label: {
                    SidebarRow(title: kind.categoryTitle, symbol: kind.symbolName, tint: .graphite, count: tracks.count,
                               selected: selection == .media(kind))
                        .padding(.leading, 8).frame(height: 32).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if !origins.isEmpty {
                    disclosure(expanded: expanded, title: kind.categoryTitle) {
                        if expanded { expandedCategories.remove(kind) }
                        else { expandedCategories.insert(kind) }
                    }
                } else {
                    Color.clear.frame(width: 25, height: 32)
                }
            }
            .modifier(SidebarSelection(selected: selection == .media(kind)))
            .accessibilityAddTraits(selection == .media(kind) ? [.isSelected] : [])
            if expanded {
                ForEach(origins) { origin in
                    row(.sharedOrigin(origin.id.isEmpty ? "" : origin.label),
                        title: origin.id.isEmpty ? "Standalone" : origin.label,
                        symbol: kind.symbolName, indent: 16)
                }
            }
        }
    }

    private func disclosure(expanded: Bool, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                .frame(width: 25, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(title)")
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        Button { selection = .playlist(playlist.id) } label: {
            HStack(spacing: 9) {
                if playlist.coverFileName != nil {
                    ArtworkView(url: store.coverURL(for: playlist), symbol: playlist.symbol, tint: playlist.tint, size: 17).frame(width: 20)
                } else { WispNavigationIcon(name: playlist.symbol, tint: playlist.tint, usesTint: true) }
                Text(playlist.name)
                    .font(WispType.ui(13, weight: selection == .playlist(playlist.id) ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 2)
            }
            .padding(.horizontal, 8).frame(height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(SidebarSelection(selected: selection == .playlist(playlist.id)))
        .accessibilityAddTraits(selection == .playlist(playlist.id) ? [.isSelected] : [])
        .contextMenu {
            Button("Edit") { edit(.playlist(playlist.id)) }
            Button("Make Mixtape…") { edit(.mixtape(playlist.id)) }.disabled(playlist.trackIDs.isEmpty)
            Divider()
            Button("Delete", role: .destructive) { remove(.playlist(playlist.id)) }
        }
    }

    private var footer: some View {
        HStack {
            SettingsLink { Label { Text("Data") } icon: { WispIcon(name: "slider.horizontal.3", size: 12) }.font(WispType.ui(11)) }
                .buttonStyle(.plain).help("Data").accessibilityLabel("Data")
            Spacer()
            WispMakerMark()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20).padding(.vertical, 15)
    }

    private func revealCategorySelection() {
        guard case .sharedOrigin(let origin) = selection else { return }
        for track in TrackCategories.tracks(in: store.tracks, origin: origin) {
            expandedCategories.insert(track.libraryMediaKind)
        }
    }

    private func artistContainsSelection(_ artist: String) -> Bool {
        if selection == .artist(artist) { return true }
        if case .origin(let selectedArtist, _) = selection { return selectedArtist == artist }
        return false
    }

    private var artistAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    private func showArtist(_ artist: String?) {
        withAnimation(artistAnimation) {
            artistHover.reveal(artist, pointer: NSEvent.mouseLocation)
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let symbol: String
    let tint: PaletteColor
    var count: Int? = nil
    var selected = false
    var prominent = false

    var body: some View {
        HStack(spacing: 9) {
            WispNavigationIcon(name: symbol, tint: tint, prominent: prominent)
            Text(title).font(WispType.ui(13, weight: selected ? .semibold : .regular))
                .foregroundStyle(WispSurface.ink).lineLimit(1)
            Spacer(minLength: 2)
            if let count, count > 0 { Text(count.formatted()).font(WispType.ui(12, weight: .medium)).monospacedDigit().foregroundStyle(WispSurface.mutedText) }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ArtistGroup: Identifiable {
    let name: String
    let tracks: [Track]
    var id: String { name }
    var title: String { name.isEmpty ? "Unknown Artist" : name }
    var origins: [OriginGroup] {
        TrackCategories.origins(in: tracks).map { choice in
            let matches = TrackCategories.tracks(in: tracks, origin: choice.id)
            return OriginGroup(name: choice.id.isEmpty ? "" : choice.label,
                               kind: matches.first(where: { $0.originMediaKind != nil })?.libraryMediaKind
                                ?? matches.first?.libraryMediaKind ?? .music)
        }
    }
}

private struct OriginGroup: Identifiable {
    let name: String
    let kind: OriginMediaKind
    var id: String { name }
    var title: String { name.isEmpty ? "Standalone" : name }
}

private struct SidebarSelection: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        content.background {
            if selected {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(WispSurface.selection)
            }
        }
    }
}
