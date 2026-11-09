import AppKit
import SwiftUI

@MainActor
struct WispApp: App {
    @NSApplicationDelegateAdaptor(WispDelegate.self) private var delegate
    @StateObject private var store: LibraryStore
    @StateObject private var player: PlayerStore
    @StateObject private var mixtapeSync: MixtapeSyncStore
    @StateObject private var phoneSync: PhoneSyncStore
    @StateObject private var driveSync: DriveSyncStore
    private let theme = WispTheme.shared

    init() {
        WispType.registerFonts()
        let store = LibraryStore()
        _store = StateObject(wrappedValue: store)
        let player = PlayerStore(store: store)
        _player = StateObject(wrappedValue: player)
        _mixtapeSync = StateObject(wrappedValue: MixtapeSyncStore(store: store))
        _phoneSync = StateObject(wrappedValue: PhoneSyncStore(store: store))
        _driveSync = StateObject(wrappedValue: DriveSyncStore(store: store))
        theme.connect(to: player, store: store)
    }

    var body: some Scene {
        Window("Bard", id: "main") {
            RootView()
                .environmentObject(store)
                .environmentObject(player)
                .environmentObject(mixtapeSync)
                .frame(minWidth: 850, minHeight: 560)
                .onAppear { delegate.player = player; delegate.store = store }
        }
        .defaultSize(width: 1120, height: 760)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Bard") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .applicationName: "Bard",
                        .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.3",
                        .version: "Personal build"
                    ])
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Import") { post(WispAction.importFiles) }
                    .keyboardShortcut("o")
                    .disabled(!store.canEdit || store.isImporting)
                Button("New Playlist") { post(WispAction.newPlaylist) }
                    .keyboardShortcut("n")
                    .disabled(!store.canEdit)
                Divider()
                Button("Artwork…") { post(WispAction.editArtwork) }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(!store.canEdit || store.isImporting || store.tracks.isEmpty)
                Button("Review All Artwork…") { post(WispAction.findArtwork) }
                    .disabled(!store.canEdit || store.isImporting || store.tracks.isEmpty)
            }
            CommandGroup(after: .textEditing) {
                Divider()
                Button("Search") { post(WispAction.search) }
                    .keyboardShortcut("f")
            }
            CommandMenu("Playback") {
                Group {
                Button(player.isPlaying ? "Pause" : "Play") { player.toggle() }
                    .disabled(store.tracks.isEmpty)
                Button("Previous") { player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(player.queueIDs.isEmpty)
                Button("Next") { player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(player.queueIDs.isEmpty)
                Divider()
                Toggle("Shuffle", isOn: Binding(get: { player.shuffle }, set: { player.setShuffle($0) }))
                Button("Repeat") { player.cycleRepeat() }
                }.disabled(WispInput.instrumentPresented)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(player)
                .environmentObject(player.listening)
                .environmentObject(phoneSync)
                .environmentObject(driveSync)
        }
    }

    private func post(_ name: Notification.Name) {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: name, object: nil)
    }
}
