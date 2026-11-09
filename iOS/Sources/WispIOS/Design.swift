import SwiftUI
import ImageIO
import WispCore

enum PhoneTextRole {
    case title, body, caption, small
    var size: CGFloat {
        switch self { case .title: return 26; case .body: return 17; case .caption: return 15; case .small: return 12 }
    }
    var style: Font.TextStyle {
        switch self { case .title: return .title2; case .body: return .body; case .caption: return .subheadline; case .small: return .caption }
    }
}

extension Font {
    static func wispText(_ role: PhoneTextRole, medium: Bool = false) -> Font {
        let name: String
        switch role {
        case .title: name = "PPNeueYork-NormalExtrabold"
        default: name = medium ? "PPNeueMontreal-Bold" : "PPNeueMontreal-Regular"
        }
        return .custom(name, size: role.size, relativeTo: role.style)
    }
    static func wisp(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "PPNeueMontreal-Bold" : "PPNeueMontreal-Regular",
                size: max(11, size), relativeTo: size <= 12 ? .caption : size <= 15 ? .subheadline : .body)
    }
    static func wispTiming(_ size: CGFloat = 11) -> Font {
        .custom("IBMPlexMono-Regular", size: max(11, size), relativeTo: .caption).monospacedDigit()
    }
}

enum PhoneStyle {
    // Shared with the Mac: quiet neutral surfaces, color carried by meaning.
    static let blue = adaptive(0x278FDB, 0x69B8FA)
    static let gold = Color(red: 0.82, green: 0.64, blue: 0.23)
    static let rose = adaptive(0xDB5577, 0xF3829C)
    static let amber = adaptive(0xB58B36, 0xDABA70)
    static let teal = adaptive(0x329C98, 0x70C5BD)
    static let violet = adaptive(0x8C70C3, 0xB49ADB)
    static let muted = adaptive(0x787D87, 0x9EA4AF)
    static let background = adaptive(0xFCFCFD, 0x1B1D21)
    static let surface = adaptive(0xF3F4F6, 0x23252A)
    static let line = adaptive(0xE6E8EC, 0x373A41)
    static let selection = adaptive(0xEEF0F3, 0x30333A)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

/// Main destinations have confident, colored silhouettes. Browsing and utility
/// glyphs retain an outline and a neutral tone so emphasis stays meaningful.
struct PhoneNavigationGlyph: View {
    let symbol: String
    var color: Color = PhoneStyle.muted
    var prominent = false
    @ScaledMetric(relativeTo: .body) private var size = 19.0
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: prominent ? .semibold : .regular))
            .symbolRenderingMode(prominent ? .hierarchical : .monochrome)
            .foregroundStyle(color)
            .frame(minWidth: 26, minHeight: 26)
            .accessibilityHidden(true)
    }
}

struct PhoneActionButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.wispText(.caption, medium: true))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 13).frame(minHeight: 44)
            .background(prominent ? PhoneStyle.blue.opacity(0.10) : PhoneStyle.surface,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct PhoneCover: View {
    let url: URL?
    var size: CGFloat = 42
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var loadedKey: String?

    private var request: PhoneCoverCache.Request {
        PhoneCoverCache.Request(url: url, points: size, scale: displayScale)
    }

    var body: some View {
        Group {
            if loadedKey == request.key, let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    PhoneStyle.blue.opacity(0.08)
                    Image(systemName: "music.note").font(.system(size: size * 0.35, weight: .light)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.14))
        .accessibilityHidden(true)
        .task(id: request.key) {
            let selected = request
            image = nil; loadedKey = selected.key
            let worker = Task.detached(priority: .utility) { PhoneCoverCache.shared.load(selected) }
            let thumbnail = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            image = thumbnail; loadedKey = selected.key
        }
    }
}

/// Thread-safe, bounded thumbnails. Meter-driven view updates never read or
/// decode files; immutable snapshot URLs naturally invalidate changed artwork.
private final class PhoneCoverCache: @unchecked Sendable {
    struct Request: Sendable {
        let url: URL?
        let pixels: Int
        let key: String
        init(url: URL?, points: CGFloat, scale: CGFloat) {
            self.url = url
            let requested = points * scale
            pixels = requested.isFinite ? Int(min(1024, max(1, ceil(requested)))) : 128
            key = "\(url?.absoluteString ?? "none")@\(pixels)"
        }
    }

    private final class Entry: NSObject {
        let image: UIImage?
        init(_ image: UIImage?) { self.image = image }
    }
    static let shared = PhoneCoverCache()
    private let cache = NSCache<NSString, Entry>()

    private init() {
        cache.countLimit = 180
        cache.totalCostLimit = 24 * 1024 * 1024
    }

    func load(_ request: Request) -> UIImage? {
        if let existing = cache.object(forKey: request.key as NSString) { return existing.image }
        guard !Task.isCancelled else { return nil }
        let image = thumbnail(request)
        guard !Task.isCancelled else { return nil }
        let cost = image?.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(Entry(image), forKey: request.key as NSString, cost: cost)
        return image
    }

    private func thumbnail(_ request: Request) -> UIImage? {
        guard let url = request.url, url.isFileURL,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let bytes = values.fileSize, bytes > 0, bytes <= 32 * 1024 * 1024,
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = metadata[kCGImagePropertyPixelWidth] as? Int,
              let height = metadata[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20_000, height <= 20_000,
              width <= 40_000_000 / height, !Task.isCancelled else { return nil }
        // Enough pixels for square aspect-fill at the current 2x/3x screen scale,
        // bounded even if a malformed library supplies an extreme panorama.
        let fillSide = min(2048, Double(request.pixels) * Double(max(width, height)) / Double(min(width, height)))
        guard let pixels = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(ceil(fillSide)),
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary), !Task.isCancelled else { return nil }
        return UIImage(cgImage: pixels)
    }
}

struct PhoneAura: View {
    var level: Double
    var playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing || reduceMotion)) { context in
            Canvas { canvas, size in
                let time = playing && !reduceMotion ? context.date.timeIntervalSinceReferenceDate : 0
                let energy = playing ? max(0.05, min(level, 1)) : 0.04
                for strand in 0..<5 {
                    var path = Path()
                    for step in 0...180 {
                        let x = Double(step) / 180
                        let envelope = pow(sin(x * .pi), 1.3)
                        let frequency: Double = 3.0 + Double(strand) * 0.5
                        let speed: Double = 0.5 + Double(strand) * 0.06
                        let phase: Double = x * Double.pi * frequency + time * speed
                        let motion: Double = sin(phase)
                        let detail = sin(x * .pi * 11 - time * 0.9) * 0.18
                        let y = size.height * 0.5 + (motion + detail) * envelope * size.height * (0.045 + energy * 0.34)
                        let point = CGPoint(x: x * size.width, y: y + Double(strand - 2) * 4)
                        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    let colors = [PhoneStyle.blue, PhoneStyle.violet, Color.pink, PhoneStyle.blue]
                    canvas.stroke(path, with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), style: StrokeStyle(lineWidth: strand == 2 ? 1.7 : 0.8, lineCap: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
