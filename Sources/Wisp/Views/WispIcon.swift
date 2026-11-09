import AppKit
import SwiftUI
import WispCore

/// Quiet outline artwork identifies secondary destinations and actions.
/// Primary navigation has its own deliberate filled symbol treatment below.
/// Original SF names remain semantic aliases and safe fallbacks.
@MainActor
struct WispIcon: View {
    let name: String
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let image = WispIconResources.image(for: name) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(image.isTemplate ? .template : .original)
                    .scaledToFit()
            } else {
                Image(systemName: WispIconResources.fallback(for: name))
                    .font(.system(size: name == "gamecontroller" ? size * 0.88 : size,
                                  weight: name == "gamecontroller" ? .light : .regular))
                    .symbolRenderingMode(.monochrome)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Primary destinations keep their color and silhouette even when unselected;
/// hierarchy comes from a purposeful mix of filled and outlined symbols.
@MainActor
struct WispNavigationIcon: View {
    let name: String
    let tint: PaletteColor
    var prominent = false
    var usesTint = false
    var size: CGFloat = 16

    private var filledSymbol: String? {
        guard prominent else { return nil }
        switch name {
        case "wisp.music": return "music.note"
        case "heart.fill": return "heart.fill"
        case "clock.fill": return "clock.fill"
        case "wisp.external": return "tray.and.arrow.down.fill"
        case "wisp.original": return "pencil.tip.crop.circle.fill"
        default: return nil
        }
    }

    var body: some View {
        Group {
            if let filledSymbol {
                Image(systemName: filledSymbol)
                    .font(.system(size: size, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            } else {
                WispIcon(name: name, size: size - 1)
            }
        }
        .foregroundStyle(prominent || usesTint ? tint.color : WispSurface.secondaryIcon)
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }
}

@MainActor
enum WispIconResources {
    private static let cache = NSCache<NSString, NSImage>()
    private static let musicApplicationIcon: NSImage? = {
        let path = "/System/Applications/Music.app"
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        // Reading Music's declared icon avoids an IconServices placeholder in
        // isolated renderers while retaining Apple's actual installed artwork.
        let bundle = Bundle(path: path)
        let declaredName = bundle?.object(forInfoDictionaryKey: "CFBundleIconFile") as? String
        let iconURL = declaredName.flatMap { name -> URL? in
            let fileName = (name as NSString).pathExtension.isEmpty ? name + ".icns" : name
            return bundle?.resourceURL?.appendingPathComponent(fileName)
        }
        let systemIcon = iconURL.flatMap { NSImage(contentsOf: $0) }
            ?? NSWorkspace.shared.icon(forFile: path)
        guard let image = systemIcon.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 14, height: 14)
        image.isTemplate = false
        return image
    }()

    static let assets: [String: String] = [
        "wisp.music": "music-notes-simple",
        "heart.fill": "heart",
        "heart": "heart",
        "clock.fill": "clock-counter-clockwise",
        "wisp.external": "arrow-line-down",
        "wisp.original": "pen-nib",
        "music.note.list": "playlist",
        "person.crop.circle": "user-sound",
        "folder.fill": "folder-simple",
        "folder": "folder-simple",
        "slider.horizontal.3": "sliders-horizontal",
        "gearshape": "sliders-horizontal",
        "plus": "plus",
        "opticaldisc": "cassette-tape",
        "moon.fill": "moon",
        "sun.max.fill": "sun",
        "leaf.fill": "leaf",
        "flame.fill": "flame",
        "cloud.fill": "cloud",
        "sparkles": "sparkle",
        "waveform": "waveform",
        "pianokeys": "piano-keys",
        "headphones": "headphones",
        "figure.walk": "person-simple-walk",
        "gamecontroller": "lucide-gamepad-2",
        "film": "lucide-film",
        "tv": "lucide-tv",
        "book.closed": "lucide-book-open",
        "mic": "lucide-mic",
        "music.note": "lucide-eighth-notes",
        "square.stack": "lucide-layers"
    ]

    static func image(for name: String) -> NSImage? {
        if name == "wisp.mixtape" { return musicApplicationIcon }
        guard let asset = assets[name] else { return nil }
        if let image = cache.object(forKey: asset as NSString) { return image }
        guard let url = WispResources.url(forResource: asset, withExtension: "pdf", subdirectory: "Icons"),
              let image = NSImage(contentsOf: url) else { return nil }
        // Native menu labels can use the NSImage's intrinsic size instead of a
        // SwiftUI frame. Keep source vector artwork at an icon-sized scale.
        image.size = NSSize(width: 14, height: 14)
        image.isTemplate = true
        cache.setObject(image, forKey: asset as NSString)
        return image
    }

    static func fallback(for name: String) -> String {
        switch name {
        case "wisp.music": return "music.note"
        case "wisp.external": return "arrow.down.to.line"
        case "wisp.original": return "pencil.tip"
        case "wisp.mixtape": return "music.note"
        default: return name
        }
    }
}
