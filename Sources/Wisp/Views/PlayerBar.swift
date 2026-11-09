import SwiftUI
import WispCore

func trackSubtitle(_ track: Track) -> String {
    let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
    if !artist.isEmpty && artist.lowercased() != "unknown artist" { return artist }
    return track.displayOrigin
}

@MainActor
struct PlayerBar: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    @Binding var queueVisible: Bool
    @Binding var expanded: Bool
    @State private var isScrubbing = false
    @State private var scrubPosition = 0.0
    @State private var volumeVisible = false

    init(queueVisible: Binding<Bool>, expanded: Binding<Bool> = .constant(false)) {
        _queueVisible = queueVisible
        _expanded = expanded
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 780
            VStack(spacing: 10) {
                HStack(spacing: compact ? 14 : 24) {
                    if expanded {
                        Spacer(minLength: 0).frame(width: 146)
                    } else {
                        identity.frame(width: compact ? 220 : 265, alignment: .leading)
                    }
                    transport.frame(maxWidth: .infinity)
                    utilityControls(compact: compact).frame(width: expanded ? 146 : compact ? 110 : 144)
                }.frame(height: 50)
                progress
            }
            .padding(.horizontal, compact ? 20 : 28)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity)
        }
        .frame(height: 110)
        .background {
            ZStack(alignment: .top) {
                WispSurface.main
                if !expanded {
                    DiscoAtmosphere()
                        .frame(height: 17)
                        .padding(.horizontal, 28)
                }
            }
            .overlay(alignment: .top) { WispSurface.divider.opacity(0.55).frame(height: 1) }
        }
        .onChange(of: player.currentID) { _ in isScrubbing = false; scrubPosition = 0 }
        .alert("Playback", isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })) {
            Button("Done") { player.errorMessage = nil }
        } message: { Text(player.errorMessage ?? "") }
    }

    private func utilityControls(compact: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 10) {
            if !expanded { StereoLevelMeter(meters: player.meters, width: compact ? 106 : 140) }
            HStack(spacing: compact ? 19 : 15) {
                if compact {
                    Button { volumeVisible.toggle() } label: {
                        Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }.buttonStyle(.plain).accessibilityLabel("Volume")
                        .popover(isPresented: $volumeVisible) { volumeSlider.padding(18) }
                } else {
                    Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 10)).foregroundStyle(.secondary).accessibilityHidden(true)
                    volumeSlider.frame(width: 48)
                }
                if !expanded {
                    Button { queueVisible.toggle() } label: {
                        Image(systemName: "list.bullet").font(.system(size: 14, weight: .medium))
                            .foregroundStyle(queueVisible ? WispSurface.cyan : Color.secondary)
                    }.buttonStyle(.plain).help("Queue").accessibilityLabel(queueVisible ? "Hide queue" : "Show queue")
                    Button { expanded = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 18, height: 24)
                    }.buttonStyle(.plain).help("Expand player").accessibilityLabel("Expand player")
                }
            }
        }
    }

    private var volumeSlider: some View {
        Slider(value: Binding(get: { player.volume }, set: { player.setVolume($0) }), in: 0...1)
            .controlSize(.mini).tint(WispSurface.cyan).frame(minWidth: 48, idealWidth: 77)
            .accessibilityLabel("Volume level")
    }

    private var identity: some View {
        HStack(spacing: 7) {
            PlayerCoverLink(track: player.currentTrack,
                            artworkURL: player.currentTrack.flatMap { store.artworkURL(for: $0) },
                            size: 46, showsPlaceholder: true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle().fill(player.isPlaying ? WispSurface.cyan : Color.secondary.opacity(0.5)).frame(width: 3, height: 3)
                    Text(player.currentTrack == nil ? "Ready" : player.isPlaying ? "Playing" : "Paused")
                        .font(WispType.ui(11))
                        .foregroundStyle(WispSurface.mutedText)
                }.accessibilityHidden(true)
                HStack(spacing: 4) {
                    Text(player.currentTrack?.displayTitle ?? "Your next track")
                        .font(WispType.ui(13, weight: .semibold))
                        .lineLimit(1).truncationMode(.tail)
                        .help(player.currentTrack?.displayTitle ?? "Your next track")
                    if let track = player.currentTrack {
                        Button { store.toggleFavorite(id: track.id) } label: {
                            Image(systemName: track.favorite ? "heart.fill" : "heart")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(track.favorite ? PaletteColor.coral.color : Color.secondary.opacity(0.7))
                                .frame(width: 24, height: 20).contentShape(Rectangle())
                        }.buttonStyle(.plain).fixedSize().disabled(!store.canEdit)
                            .help(track.favorite ? "Remove from Favorites" : "Add to Favorites")
                            .accessibilityLabel(track.favorite ? "Remove track from Favorites" : "Add track to Favorites")
                    }
                }
                if let track = player.currentTrack {
                    Text(trackSubtitle(track)).font(WispType.ui(11)).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Choose something to play.").font(WispType.ui(11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var transport: some View {
        HStack(spacing: 8) {
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(player.shuffle ? WispSurface.cyan : Color.secondary)
                    .frame(width: 26, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain)
                .help(player.shuffle ? "Turn shuffle off" : "Turn shuffle on")
                .accessibilityLabel(player.shuffle ? "Disable shuffle" : "Enable shuffle")
            Button { player.previous() } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 13))
                    .frame(width: 26, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(player.currentID == nil).help("Previous track").accessibilityLabel("Previous track")
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WispSurface.cyan)
                    .offset(x: player.isPlaying ? 0 : 1)
                    .frame(width: 42, height: 42)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(WispSurface.button)
                            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(WispSurface.divider.opacity(0.75), lineWidth: 0.75) }
                            .shadow(color: Color.black.opacity(0.045), radius: 1.5, y: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }.buttonStyle(.plain).disabled(store.tracks.isEmpty).help(player.isPlaying ? "Pause" : "Play")
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Button { player.next() } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 13))
                    .frame(width: 26, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(player.currentID == nil).help("Next track").accessibilityLabel("Next track")
            Button { player.cycleRepeat() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(player.repeatMode == .off ? Color.secondary : WispSurface.cyan)
                    .frame(width: 26, height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).help(repeatAction)
                .accessibilityLabel(repeatAction)
                .accessibilityValue("Repeat \(player.repeatMode.rawValue)")
        }
    }

    private var repeatAction: String {
        switch player.repeatMode.next {
        case .off: return "Turn repeat off"
        case .all: return "Repeat all tracks"
        case .one: return "Repeat current track"
        }
    }

    private var progress: some View {
        HStack(spacing: 11) {
            Text(clockText(isScrubbing ? scrubPosition : player.position)).frame(width: 34, alignment: .leading)
            Slider(value: Binding(get: { isScrubbing ? scrubPosition : player.position }, set: {
                scrubPosition = $0
                if !isScrubbing { player.seek(to: $0) }
            }), in: 0...max(1, player.duration), onEditingChanged: { editing in
                if editing { scrubPosition = player.position }
                isScrubbing = editing
                if !editing { player.seek(to: scrubPosition) }
            })
            .controlSize(.mini).tint(WispSurface.cyan)
            .disabled(player.currentID == nil || player.duration <= 0)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(clockText(player.position)) of \(clockText(player.duration))")
            Text(clockText(player.duration)).frame(width: 34, alignment: .trailing)
        }.font(WispType.readout(14)).monospacedDigit().foregroundStyle(.secondary)
    }
}

