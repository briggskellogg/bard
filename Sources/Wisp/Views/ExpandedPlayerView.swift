import AppKit
import SwiftUI
import WispCore

/// A listening surface that shares the current queue and audio player. Entering
/// or leaving it changes only the presentation, never playback or queue order.
@MainActor
struct ExpandedPlayerView: View {
    @Environment(\.displayScale) private var displayScale
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var player: PlayerStore
    let collapse: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let queueWidth: CGFloat = geometry.size.width < 900 ? 280 : 300
            HStack(spacing: 0) {
                listeningArea(width: max(0, geometry.size.width - queueWidth - 1),
                              height: geometry.size.height)
                WispSurface.divider.opacity(0.5).frame(width: 1)
                QueueView(close: {}, embedded: true)
                    .frame(width: queueWidth)
            }
        }
        .foregroundStyle(WispSurface.ink)
        .background(WispSurface.main)
    }

    private func listeningArea(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            header
            DiscoAtmosphere(presentation: .expanded)
                .padding(.horizontal, 12)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            identity(compact: height < 460)
                .padding(.horizontal, width < 580 ? 32 : 42)
                .padding(.bottom, 28)
        }
        .frame(width: width, height: height)
    }

    private var header: some View {
        HStack(spacing: 18) {
            HStack(spacing: 11) {
                WispBrandSignature(height: 21)
                Text("Now playing")
                    .font(WispType.ui(11, weight: .medium))
                    .foregroundStyle(WispSurface.mutedText)
            }
            Spacer()
            if let track = player.currentTrack {
                Button {
                    NotificationCenter.default.post(name: WispAction.remix, object: track.id)
                } label: {
                    HStack(spacing: 6) {
                        Label("Remix", systemImage: "slider.horizontal.3")
                            .font(WispType.ui(11))
                        RemixAlphaBadge()
                    }
                }
                .buttonStyle(.plain).foregroundStyle(WispSurface.mutedText)
                .accessibilityLabel("Remix, Alpha")
                .help("Open the Remix station (Alpha) for this song")
                .disabled(!store.canEdit)
            }
            AppearanceMenu(iconSize: 13, height: 22)
            Button(action: collapse) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 12, weight: .regular))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).foregroundStyle(WispSurface.mutedText)
            .help("Back to library").accessibilityLabel("Collapse player")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 26).padding(.top, 17).padding(.bottom, 4)
    }

    @ViewBuilder
    private func identity(compact: Bool) -> some View {
        if let track = player.currentTrack {
            HStack(alignment: .top, spacing: 8) {
                if let url = store.artworkURL(for: track),
                   WispImageCache.image(at: url, fitting: CGSize(width: 44, height: 44), scale: displayScale, fill: true) != nil {
                    PlayerCoverLink(track: track, artworkURL: url, size: 44)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(track.displayTitle)
                        .font(WispType.ui(compact ? 19 : 21, weight: .medium))
                        .foregroundStyle(WispSurface.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(track.displayTitle)
                    if !artist(for: track).isEmpty {
                        Text(artist(for: track))
                            .font(WispType.ui(12)).foregroundStyle(WispSurface.mutedText)
                            .lineLimit(1).help(artist(for: track))
                    }
                    if !track.displayOrigin.isEmpty && track.displayOrigin != artist(for: track) {
                        OriginLabel(track: track)
                            .font(WispType.ui(11))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .contain)
        } else {
            VStack(spacing: 8) {
                Text("A little room to listen.")
                    .font(WispType.ui(compact ? 19 : 22, weight: .medium))
                    .foregroundStyle(WispSurface.ink)
                Button("Choose a track") { collapse() }
                    .font(WispType.ui(12))
                    .foregroundStyle(WispSurface.mutedText)
                    .buttonStyle(.plain)
                    .help("Return to your library")
            }
            .multilineTextAlignment(.center)
        }
    }

    private func artist(for track: Track) -> String {
        let value = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.lowercased() == "unknown artist" ? "" : value
    }
}

