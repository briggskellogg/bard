import SwiftUI

enum PhoneAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let preferenceKey = "Bard.phone.appearance"
    static let legacyLightKey = "Wisp.phone.light"

    var id: String { rawValue }
    var title: String {
        switch self { case .system: return "System"; case .light: return "Light"; case .dark: return "Dark" }
    }
    var symbol: String {
        switch self { case .system: return "circle.lefthalf.filled"; case .light: return "sun.max"; case .dark: return "moon" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }

    /// Keep explicit choices made before the System option existed. The old
    /// key is retained for update continuity; it cannot override a new choice.
    @discardableResult
    static func migrateLegacyPreference(in defaults: UserDefaults = .standard) -> Self {
        if let saved = defaults.object(forKey: preferenceKey) {
            return (saved as? String).flatMap(Self.init(rawValue:)) ?? .system
        }
        guard let oldLight = defaults.object(forKey: legacyLightKey) as? Bool else { return .system }
        let migrated: Self = oldLight ? .light : .dark
        defaults.set(migrated.rawValue, forKey: preferenceKey)
        return migrated
    }
}
