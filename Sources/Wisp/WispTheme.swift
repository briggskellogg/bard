import AppKit
import Combine
import Observation
import SwiftUI

enum WispPalette: String, CaseIterable, Identifiable {
    case yellow, red, blue
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var accent: UInt32 {
        switch self {
        case .yellow: return 0xF4D35E
        case .red: return 0xFF5A61
        case .blue: return 0x46BFFF
        }
    }
    var lightAccent: UInt32 {
        switch self {
        case .yellow: return 0x876300
        case .red: return 0xB63448
        case .blue: return 0x00779F
        }
    }
    var secondary: UInt32 {
        switch self {
        case .yellow: return 0xE5A25D
        case .red: return 0xF1AA86
        case .blue: return 0xAAA8E8
        }
    }
    var lightSecondary: UInt32 {
        switch self {
        case .yellow: return 0x98551C
        case .red: return 0x9F4B25
        case .blue: return 0x6553A5
        }
    }
    var selection: UInt32 {
        switch self {
        case .yellow: return 0x2B281A
        case .red: return 0x302025
        case .blue: return 0x1A2932
        }
    }
    var lightSelection: UInt32 {
        switch self {
        case .yellow: return 0xEDE4C9
        case .red: return 0xF0DDE1
        case .blue: return 0xDCE9EF
        }
    }
    var lightCanvas: UInt32 {
        switch self {
        case .yellow: return 0xFCF8EA
        case .red: return 0xFCF1F0
        case .blue: return 0xEFF6FB
        }
    }
    var darkCanvas: UInt32 {
        switch self {
        case .yellow: return 0x14130F
        case .red: return 0x171114
        case .blue: return 0x10141A
        }
    }
    var lightSidebar: UInt32 {
        switch self {
        case .yellow: return 0xEFE8D1
        case .red: return 0xF0E1E0
        case .blue: return 0xDFEAF3
        }
    }
    var darkSidebar: UInt32 {
        switch self {
        case .yellow: return 0x0E0D0B
        case .red: return 0x100C0E
        case .blue: return 0x0B0F14
        }
    }
    var lightDivider: UInt32 {
        switch self {
        case .yellow: return 0xDFD6B8
        case .red: return 0xE7D0D1
        case .blue: return 0xCEDDE9
        }
    }
    var next: Self {
        switch self {
        case .yellow: return .red
        case .red: return .blue
        case .blue: return .yellow
        }
    }
}

enum WispBrightness: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// No override lets each native window follow macOS, including live changes.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    static func restored(from defaults: UserDefaults) -> Self {
        if let saved = defaults.string(forKey: "wisp.brightness.v4").flatMap(Self.init(rawValue:)) {
            return saved
        }
        let legacy = defaults.string(forKey: "wisp.theme.v3") ?? defaults.string(forKey: "wisp.appearance.v2")
        switch legacy {
        case "light", "daylight": return .light
        case "dark", "blue", "red", "yellow", "disco": return .dark
        default: return .system
        }
    }
}

/// Set the native window override directly: SwiftUI can retain a prior explicit
/// preferredColorScheme after it changes to nil. A nil NSWindow appearance truly
/// restores live inheritance from macOS for main, Data, and their attached sheets.
@MainActor
struct WispAppearancePolicy: ViewModifier {
    @Bindable var theme: WispTheme = .shared

    func body(content: Content) -> some View {
        content.background(WindowAppearanceBridge(brightness: theme.brightness)
            .frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

@MainActor
private struct WindowAppearanceBridge: NSViewRepresentable {
    let brightness: WispBrightness

    func makeNSView(context: Context) -> Attachment { Attachment(brightness: brightness) }
    func updateNSView(_ view: Attachment, context: Context) {
        view.brightness = brightness
        view.applyAppearance()
    }

    final class Attachment: NSView {
        var brightness: WispBrightness
        init(brightness: WispBrightness) {
            self.brightness = brightness
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyAppearance()
        }
        func applyAppearance() {
            guard let window else { return }
            let appearance = brightness.nativeAppearance
            if window.appearance?.name != appearance?.name { window.appearance = appearance }
        }
    }
}

/// RGB components stay separate from SwiftUI so interpolation and bounds can
/// be verified without rendering or changing a system appearance.
struct AuraRGB: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(_ hex: UInt32) {
        red = Double((hex >> 16) & 255) / 255
        green = Double((hex >> 8) & 255) / 255
        blue = Double(hex & 255) / 255
    }
    private init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
    func blended(with other: Self, amount: Double) -> Self {
        let t = min(1, max(0, amount))
        return Self(red: red + (other.red - red) * t,
                    green: green + (other.green - green) * t,
                    blue: blue + (other.blue - blue) * t)
    }
}

struct AuraColors: Equatable, Sendable {
    let darkPrimary: AuraRGB
    let darkSecondary: AuraRGB
    let lightPrimary: AuraRGB
    let lightSecondary: AuraRGB
}

/// A continuous seven-color orbit, driven only when real audio frames arrive.
/// There is no independent color timer and no abrupt palette-switch threshold.
struct AuraColorCycle {
    static let names = ["Blue", "Violet", "Red", "Coral", "Yellow", "Mint", "Teal"]
    private static let dark: [AuraRGB] = [0x46BFFF, 0xB69BF6, 0xFF5A61, 0xFFAF86,
                                        0xF4D35E, 0x9BD4A4, 0x64DACD].map(AuraRGB.init)
    private static let light: [AuraRGB] = [0x00779F, 0x7350B5, 0xB63448, 0xB44C2C,
                                         0x876300, 0x397A54, 0x007C7F].map(AuraRGB.init)
    private(set) var position = 0.0
    private var lastTime: TimeInterval?
    private var previousEnergy = 0.0
    private var impact = 0.0
    var colors: AuraColors { Self.colors(at: position) }

    static func colors(at position: Double) -> AuraColors {
        let phase = position.isFinite ? position - floor(position) : 0
        func sample(_ values: [AuraRGB], offset: Double) -> AuraRGB {
            let location = (phase + offset).truncatingRemainder(dividingBy: 1) * Double(values.count)
            let index = min(values.count - 1, Int(location))
            let fraction = location - Double(index)
            let smooth = fraction * fraction * (3 - 2 * fraction)
            return values[index].blended(with: values[(index + 1) % values.count], amount: smooth)
        }
        return AuraColors(darkPrimary: sample(dark, offset: 0), darkSecondary: sample(dark, offset: 1.0 / 7),
                          lightPrimary: sample(light, offset: 0), lightSecondary: sample(light, offset: 1.0 / 7))
    }

    mutating func suspend() { lastTime = nil; previousEnergy = 0; impact = 0 }

    mutating func consume(_ frame: MusicLightFrame, at time: TimeInterval, active: Bool) -> AuraColors {
        let raw = frame.energy
        guard active, time.isFinite, raw.isFinite, raw > 0.0005 else { suspend(); return colors }
        let energy = log1p(min(1, max(0, raw)) * 12) / log(13)
        defer { lastTime = time; previousEnergy = energy }
        guard let lastTime, time > lastTime, time - lastTime <= 1 else { impact = 0; return colors }
        let dt = min(0.25, time - lastTime)
        impact = max(min(1, max(0, energy - previousEnergy) * 2), impact * exp(-dt / 0.3))
        let step = dt * (sqrt(energy) * 0.045 + impact * 0.055)
        position = (position + step).truncatingRemainder(dividingBy: 1)
        return colors
    }
}

/// The interface has one steady blue identity. Only its brightness is a setting;
/// the player's automatic Aura owns its independent audio-reactive colors.
@Observable
final class WispTheme {
    static let shared = WispTheme()

    let palette: WispPalette = .blue
    var brightness: WispBrightness {
        didSet {
            guard brightness != oldValue else { return }
            defaults.set(brightness.rawValue, forKey: "wisp.brightness.v4")
        }
    }
    /// Read-only compatibility for older internal callers; Aura is always on.
    var pulseEnabled: Bool { true }
    var activePalette: WispPalette { .blue }
    private(set) var auraColors = AuraColorCycle.colors(at: 0)
    private(set) var reduceMotion: Bool
    private(set) var lightFrame: MusicLightFrame = .zero
    var preferredColorScheme: ColorScheme? { brightness.preferredColorScheme }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var cycle = AuraColorCycle()
    @ObservationIgnored private var observations = Set<AnyCancellable>()
    @ObservationIgnored private var accessibilityObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard, systemIsDark: Bool? = nil, systemReduceMotion: Bool? = nil) {
        self.defaults = defaults
        // Preserve explicit Light/Dark choices; System must never be snapshotted
        // into today's effective appearance. Fresh installations follow macOS.
        brightness = WispBrightness.restored(from: defaults)
        reduceMotion = systemReduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Retain brightness while retiring both color selection and Aura's toggle.
        defaults.set(WispPalette.blue.rawValue, forKey: "wisp.palette.v4")
        defaults.set(brightness.rawValue, forKey: "wisp.brightness.v4")
        defaults.set(true, forKey: "wisp.theme.pulse.v1")
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshAccessibility() }
    }

    deinit {
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
    }

    /// Connecting twice replaces old subscriptions; it never duplicates analysis.
    @MainActor
    func connect(to player: PlayerStore, store: LibraryStore) {
        observations.removeAll()
        cycle.suspend()
        let analysis = MusicLightAnalysis.shared
        analysis.connect(to: player, store: store)
        analysis.$frame.combineLatest(player.$isPlaying)
            .receive(on: RunLoop.main)
            .sink { [weak self] frame, playing in
                guard let self else { return }
                let active = playing && !self.reduceMotion
                self.lightFrame = active ? frame : .zero
                self.auraColors = self.cycle.consume(frame, at: ProcessInfo.processInfo.systemUptime, active: active)
            }.store(in: &observations)
        player.$currentID.removeDuplicates().dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.cycle.suspend() }
            .store(in: &observations)
    }

    func refreshAccessibility() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion { cycle.suspend(); lightFrame = .zero }
    }
}
