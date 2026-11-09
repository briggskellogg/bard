import SwiftUI
import WispCore

/// A quiet cover beside a song title. Its reserved footprint keeps title and
/// metadata columns aligned, while the tilt fits inside the existing row insets.
@MainActor
struct TrackCoverBadge: View {
    let url: URL?
    var size: CGFloat = 32
    var showsPlaceholder = false

    var body: some View {
        TrackCoverArtwork(url: url, size: size, showsPlaceholder: showsPlaceholder)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Shared pixels only; the list is decorative and the player supplies its own
/// native link or button semantics around this fixed-size presentation.
@MainActor
struct TrackCoverArtwork: View {
    @Environment(\.displayScale) private var displayScale
    let url: URL?
    var size: CGFloat = 32
    var showsPlaceholder = false
    var isHovered = false
    var reduceMotion = false

    private var lifted: Bool { isHovered && !reduceMotion }

    var body: some View {
        Group {
            if let image = WispImageCache.image(at: url, fitting: CGSize(width: size, height: size),
                                               scale: displayScale, fill: true) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: max(3, size * 0.1), style: .continuous))
                    .rotationEffect(.degrees(lifted ? -3 : -6))
                    .scaleEffect(lifted ? 1.03 : 1)
                    .offset(y: lifted ? -2.5 : -1)
            } else if showsPlaceholder {
                Image(systemName: "music.note")
                    .font(.system(size: max(12, size * 0.43), weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(PaletteColor.graphite.color)
            } else {
                Color.clear
            }
        }
        .frame(width: size + 6, height: size)
    }
}
