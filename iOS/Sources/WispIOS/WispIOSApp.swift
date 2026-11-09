import SwiftUI

@main
struct WispIOSApp: App {
    @StateObject private var library = PhoneLibraryStore()
    @StateObject private var player = PhonePlayerStore()
    @Environment(\.scenePhase) private var phase
    @AppStorage private var appearance: PhoneAppearance

    init() {
        let initialAppearance = PhoneAppearance.migrateLegacyPreference()
        _appearance = AppStorage(wrappedValue: initialAppearance, PhoneAppearance.preferenceKey)
    }

    var body: some Scene {
        WindowGroup {
            PhoneLibraryView()
                .environmentObject(library)
                .environmentObject(player)
                .tint(PhoneStyle.blue)
                .preferredColorScheme(appearance.colorScheme)
                .onChange(of: phase, initial: true) { _, value in library.setActive(value == .active) }
        }
    }
}
