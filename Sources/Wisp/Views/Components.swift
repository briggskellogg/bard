import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WispCore

/// The approved flat symbol with the app name in the standard interface face.
@MainActor
struct WispBrandSignature: View {
    @Environment(\.displayScale) private var displayScale
    var height: CGFloat = 23

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            if let image = WispImageCache.image(at: WispResources.logoURL,
                                               fitting: CGSize(width: height * 0.81, height: height),
                                               scale: displayScale) {
                Image(nsImage: image).resizable().renderingMode(.original)
                    .interpolation(.high).scaledToFit()
                    .frame(width: height * 0.81, height: height)
                    .accessibilityHidden(true)
            }
            Text("Bard")
                .font(WispType.ui(min(20, height * 0.87), weight: .bold))
                .foregroundStyle(WispSurface.ink)
                .fixedSize()
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bard")
    }
}

/// A quiet maker's signature. Its supplied gold is fixed in both appearances.
@MainActor
struct WispMakerMark: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let image = WispImageCache.image(at: WispResources.makerMarkURL,
                                           fitting: CGSize(width: 14, height: 18),
                                           scale: displayScale) {
            Image(nsImage: image).resizable().renderingMode(.original)
                .interpolation(.high).scaledToFit()
                .frame(width: 14, height: 18)
                .accessibilityLabel("Made by Briggs Kellogg")
                .help("Made by Briggs Kellogg")
        }
    }
}

extension PaletteColor {
    var color: Color {
        switch self {
        case .blue: return WispSurface.cyan
        case .amber: return WispSurface.amber
        case .coral: return WispSurface.adaptive(light: 0xE45B7E, dark: 0xF38AA6)
        case .teal: return WispSurface.adaptive(light: 0x2F9C98, dark: 0x70C9BB)
        case .violet: return WispSurface.magenta
        case .graphite: return WispSurface.secondaryIcon
        }
    }
}

/// A shared, quiet application palette. Color belongs to meaningful icons and
/// active controls; the audio-driven Aura keeps its own expressive palette.
enum WispSurface {
    static let sidebar = adaptive(light: 0xF3F4F6, dark: 0x23252A)
    static let main = adaptive(light: 0xFCFCFD, dark: 0x1B1D21)
    static let divider = adaptive(light: 0xE1E4E9, dark: 0x363940)
    static let selection = adaptive(light: 0xE1E4E9, dark: 0x353940)
    static let button = adaptive(light: 0xFFFFFF, dark: 0x30343B)
    static let primaryButton = adaptive(light: 0x2179BE, dark: 0x69B8FA)
    static let primaryButtonText = adaptive(light: 0xFFFFFF, dark: 0x14263B)
    static let cyan = adaptive(light: 0x278FDB, dark: 0x69B8FA)
    static let magenta = adaptive(light: 0x8971C7, dark: 0xB9A2EA)
    static let amber = adaptive(light: 0xC19A35, dark: 0xE8C56C)
    static let ink = adaptive(light: 0x30343A, dark: 0xF1F2F5)
    static let mutedText = adaptive(light: 0x777D87, dark: 0xA0A6B1)
    static let secondaryIcon = adaptive(light: 0x9BA2AD, dark: 0x858E9D)

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

/// A small amount of depth makes actions feel tangible without boxing in the
/// content. This is shared by collection actions and the transport control.
struct WispActionButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WispType.ui(12, weight: .medium))
            .foregroundStyle(primary ? WispSurface.primaryButtonText : WispSurface.ink)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(primary ? WispSurface.primaryButton : WispSurface.button,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(primary ? Color.clear : WispSurface.divider.opacity(0.75), lineWidth: 0.75)
            }
            .shadow(color: Color.black.opacity(enabled ? 0.045 : 0), radius: 1.5, y: 1)
            .opacity(enabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .offset(y: configuration.isPressed ? 0.5 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: configuration.isPressed)
    }
}

enum Destination: Hashable {
    case music, favorites, recent, basic, classic
    case artist(String), origin(artist: String, origin: String)
    case media(OriginMediaKind), sharedOrigin(String)
    case playlist(UUID), folder(UUID)

    var savedValue: String {
        switch self {
        case .music: return "music"
        case .favorites: return "favorites"
        case .recent: return "recent"
        case .basic: return "basic"
        case .classic: return "classic"
        case .artist(let artist): return "artist:\(Self.encode(artist))"
        case .origin(let artist, let origin): return "origin:\(Self.encode(artist)):\(Self.encode(origin))"
        case .media(let kind): return "media:\(kind.rawValue)"
        case .sharedOrigin(let origin): return "shared-origin:\(Self.encode(origin))"
        case .playlist(let id): return "playlist:\(id.uuidString)"
        case .folder(let id): return "folder:\(id.uuidString)"
        }
    }

    init?(savedValue: String) {
        switch savedValue {
        case "music": self = .music
        case "favorites": self = .favorites
        case "recent": self = .recent
        case "basic": self = .basic
        case "classic": self = .classic
        default:
            let parts = savedValue.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 2 else { return nil }
            switch parts[0] {
            case "media":
                guard parts.count == 2, let kind = OriginMediaKind(rawValue: parts[1]) else { return nil }
                self = .media(kind)
            case "shared-origin":
                guard parts.count == 2, let origin = Self.decode(parts[1]) else { return nil }
                self = .sharedOrigin(origin)
            case "playlist":
                guard let id = UUID(uuidString: parts[1]) else { return nil }
                self = .playlist(id)
            case "folder":
                guard let id = UUID(uuidString: parts[1]) else { return nil }
                self = .folder(id)
            case "artist":
                guard let artist = Self.decode(parts[1]) else { return nil }
                self = .artist(artist)
            case "origin":
                guard parts.count == 3, let artist = Self.decode(parts[1]), let origin = Self.decode(parts[2]) else { return nil }
                self = .origin(artist: artist, origin: origin)
            default: return nil
            }
        }
    }

    private static func encode(_ value: String) -> String { Data(value.utf8).base64EncodedString() }
    private static func decode(_ value: String) -> String? {
        Data(base64Encoded: value).flatMap { String(data: $0, encoding: .utf8) }
    }
}

extension Track {
    var sidebarArtist: String { artist.trimmingCharacters(in: .whitespacesAndNewlines) }
    var sidebarOrigin: String { displayOrigin.trimmingCharacters(in: .whitespacesAndNewlines) }
}

enum TrackSort: String, CaseIterable, Identifiable {
    case recent = "Recent", title = "Title", artist = "Artist", origin = "Origin", genre = "Genre"
    var id: String { rawValue }
}

enum EditorRoute: Identifiable {
    case playlist(UUID?), folder(UUID?), track(UUID), trackSource(UUID), trackArtwork(UUID), bulkTracks([UUID]), bulkArtwork([UUID]), mixtape(UUID), addTracks(UUID), choosePlaylist([UUID]), source
    var id: String {
        switch self {
        case .playlist(let id): return "playlist-\(id?.uuidString ?? "new")"
        case .folder(let id): return "folder-\(id?.uuidString ?? "new")"
        case .track(let id): return "track-\(id)"
        case .trackSource(let id): return "track-source-\(id)"
        case .trackArtwork(let id): return "track-artwork-\(id)"
        case .bulkTracks(let ids): return "bulk-" + ids.map(\.uuidString).joined(separator: "-")
        case .bulkArtwork(let ids): return "bulk-artwork-" + ids.map(\.uuidString).joined(separator: "-")
        case .mixtape(let id): return "mixtape-\(id)"
        case .addTracks(let id): return "tracks-\(id)"
        case .choosePlaylist: return "choose"
        case .source: return "source"
        }
    }
}

enum DeletionRequest {
    case playlist(UUID), folder(UUID), tracks(Set<UUID>)
}

/// The same direct action in library lists and both playback queues.
@MainActor
struct AddToMixtapeButton: View {
    @EnvironmentObject private var store: LibraryStore
    let trackIDs: [UUID]

    var body: some View {
        Button("Add to Mixtape") { store.addToMixtape(trackIDs) }
            .disabled(!store.canEdit || trackIDs.isEmpty ||
                      Set(trackIDs).isSubset(of: Set(store.mixtape?.trackIDs ?? [])))
    }
}

enum PlaylistSymbols {
    static let choices: [(name: String, title: String)] = [
        ("music.note.list", "Music"), ("moon.fill", "Moon"),
        ("sun.max.fill", "Sun"), ("leaf.fill", "Leaf"),
        ("flame.fill", "Flame"), ("cloud.fill", "Cloud"),
        ("sparkles", "Spark"), ("waveform", "Wave"),
        ("heart.fill", "Heart"), ("pianokeys", "Piano"),
        ("headphones", "Headphones"), ("figure.walk", "Walk")
    ]
}

@MainActor
struct ArtworkView: View {
    @Environment(\.displayScale) private var displayScale
    let url: URL?
    var symbol = "music.note"
    var tint: PaletteColor = .graphite
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let image = WispImageCache.image(at: url, fitting: CGSize(width: size, height: size), scale: displayScale, fill: true) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: max(12, size * 0.43), weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint.color)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(4, size * 0.14)))
        .accessibilityHidden(true)
    }
}

@MainActor
struct StrongSymbol: View {
    let name: String
    var tint: PaletteColor = .blue
    var size: CGFloat = 14

    var body: some View {
        WispIcon(name: name, size: size)
            .foregroundStyle(tint.color)
            .frame(width: size + 4, height: size + 4)
            .accessibilityHidden(true)
    }
}

/// Two small marks specific to Wisp's source/original distinction.
struct WispVersionGlyph: Shape {
    let original: Bool
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width / 16, y: rect.minY + y * rect.height / 16)
        }
        return Path { path in
            if original {
                // A fountain nib: a personal, authored mark with a single slit.
                path.move(to: point(2, 14)); path.addLine(to: point(4.5, 5))
                path.addLine(to: point(10.5, 2)); path.addLine(to: point(14, 5.5))
                path.addLine(to: point(11, 11.5)); path.closeSubpath()
                path.move(to: point(2, 14)); path.addLine(to: point(8, 8))
                path.addEllipse(in: CGRect(x: point(7, 6).x, y: point(7, 6).y,
                                          width: rect.width * 2 / 16, height: rect.height * 2 / 16))
            } else {
                // An incoming signal resting on a quiet, open shelf.
                path.move(to: point(8, 2)); path.addLine(to: point(8, 10))
                path.move(to: point(4.5, 6.5)); path.addLine(to: point(8, 10)); path.addLine(to: point(11.5, 6.5))
                path.move(to: point(3, 14)); path.addLine(to: point(13, 14))
            }
        }
    }
}

struct OriginLabel: View {
    let track: Track

    var body: some View {
        HStack(spacing: 6) {
            if !track.displayOrigin.isEmpty {
                WispIcon(name: track.resolvedMediaKind.symbolName, size: 12)
                    .frame(width: 15)
                    .help(track.resolvedMediaKind.title)
            }
            Text(track.displayOrigin.isEmpty ? "—" : track.displayOrigin)
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .help(track.displayOrigin)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(track.displayOrigin.isEmpty ? "No origin" : "\(track.resolvedMediaKind.title), \(track.displayOrigin)")
    }
}

struct SectionTitle: View {
    let title: String
    var count: Int? = nil

    var body: some View {
        HStack(spacing: 7) {
            Text(title).font(WispType.ui(12, weight: .medium)).foregroundStyle(WispSurface.mutedText)
            if let count { Text(count.formatted()).font(WispType.readout(16)).foregroundStyle(WispSurface.cyan) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct EmptyMessage: View {
    let title: String
    let message: String
    var symbol = "music.note"
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 27, weight: .semibold)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 17, weight: .semibold))
            Text(message).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(PaletteColor.blue.color).padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

func clockText(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let whole = max(0, Int(seconds))
    return "\(whole / 60):\(String(format: "%02d", whole % 60))"
}

func validatedWebURL(_ text: String) -> URL? {
    MusicSource.validatedURL(text)
}

func collectionDuration(_ tracks: [Track]) -> String {
    let total = tracks.reduce(0) { $0 + ($1.duration.isFinite ? max(0, $1.duration) : 0) }
    if total < 60 { return "\(Int(total)) sec" }
    let minutes = Int(total / 60)
    if minutes < 60 { return "\(minutes) min" }
    return "\(minutes / 60) hr \(minutes % 60) min"
}

@MainActor
enum NativeFiles {
    static var audioContentTypes: [UTType] {
        [.audio] + AudioImporter.extensions.sorted().compactMap { UTType(filenameExtension: $0) }
    }

    static func chooseAudio() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Import"
        panel.prompt = "Import"
        panel.message = "Choose audio files, ZIP archives, or folders. Bard keeps its own copies."
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = audioContentTypes + [.zip]
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseCover() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Cover"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func loadURLs(from providers: [NSItemProvider], completion: @escaping @MainActor @Sendable ([URL]) -> Void) {
        guard !providers.isEmpty else { completion([]); return }
        let batch = DroppedFileBatch(count: providers.count, completion: completion)
        for (index, provider) in providers.enumerated() {
            // Begin every load before onDrop returns; access to its payload is scoped to that callback.
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                let url = data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                batch.receive(url, at: index)
            }
        }
    }
}

/// Provider callbacks may arrive on different queues. Keep the drop's original order.
private final class DroppedFileBatch: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL?]
    private var remaining: Int
    private let completion: @MainActor @Sendable ([URL]) -> Void

    init(count: Int, completion: @escaping @MainActor @Sendable ([URL]) -> Void) {
        urls = Array(repeating: nil, count: count)
        remaining = count
        self.completion = completion
    }

    func receive(_ url: URL?, at index: Int) {
        lock.lock()
        urls[index] = url?.isFileURL == true ? url : nil
        remaining -= 1
        let result = remaining == 0 ? urls.compactMap { $0 } : nil
        lock.unlock()
        if let result {
            Task { @MainActor in self.completion(result) }
        }
    }
}
