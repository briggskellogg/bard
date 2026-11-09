import SwiftUI
import WispCore

/// A player's cover leads to the song's original source, never the artwork's
/// provider. An unlinked song uses the same editor as the library's Edit action.
@MainActor
struct PlayerCoverLink: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    let track: Track?
    let artworkURL: URL?
    var size: CGFloat = 46
    var showsPlaceholder = false

    var sourceURL: URL? { track?.sourceURL.flatMap(validatedWebURL) }

    var body: some View {
        Group {
            if let track {
                if let sourceURL {
                    focusableAction(Link(destination: sourceURL) { artwork }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Open original source for \(track.displayTitle)")
                        .accessibilityHint("Opens \(sourceURL.host ?? "the song’s source") in your browser.")
                        .help("Open original source · \(sourceURL.host ?? sourceURL.absoluteString)"))
                } else {
                    focusableAction(Button(action: activate) { artwork }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Add original source for \(track.displayTitle)")
                    .accessibilityHint("Opens Edit song so you can add the original source link.")
                    .help("Add an original source link in Edit song"))
                }
            } else {
                artwork.allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovered)
        .onChange(of: track?.id) { _, _ in isHovered = false }
        .onChange(of: isFocused) { _, focused in WispInput.playerCoverFocused = focused }
        .onDisappear { WispInput.playerCoverFocused = false }
    }

    private func focusableAction<Content: View>(_ content: Content) -> some View {
        content.focusable().focused($isFocused)
            .onKeyPress(.space, phases: .down) { press in
                guard press.modifiers.isEmpty else { return .ignored }
                activate(); return .handled
            }
            .onKeyPress(.return, phases: .down) { press in
                guard press.modifiers.isEmpty else { return .ignored }
                activate(); return .handled
            }
    }

    private func activate() {
        guard let track else { return }
        if let sourceURL { openURL(sourceURL) }
        else { NotificationCenter.default.post(name: WispAction.editTrack, object: track.id) }
    }

    private var artwork: some View {
        TrackCoverArtwork(url: artworkURL, size: size, showsPlaceholder: showsPlaceholder,
                          isHovered: track != nil && isHovered, reduceMotion: reduceMotion)
            .contentShape(Rectangle())
    }
}
