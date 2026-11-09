import AppKit
import Foundation

enum WispAction {
    static let importFiles = Notification.Name("Wisp.import")
    static let newPlaylist = Notification.Name("Wisp.playlist")
    static let newFolder = Notification.Name("Wisp.folder")
    static let search = Notification.Name("Wisp.search")
    static let remix = Notification.Name("Wisp.remix")
    static let editArtwork = Notification.Name("Wisp.editArtwork")
    static let editTrack = Notification.Name("Wisp.editTrack")
    static let findArtwork = Notification.Name("Wisp.findArtwork")
    static let playback = Notification.Name("Wisp.playback")
    static let next = Notification.Name("Wisp.next")
    static let previous = Notification.Name("Wisp.previous")
}

@MainActor
enum WispInput {
    static var instrumentPresented = false
    static var playerCoverFocused = false
    static weak var remix: RemixStore?
}

@MainActor
final class WispDelegate: NSObject, NSApplicationDelegate {
    weak var player: PlayerStore?
    weak var store: LibraryStore?
    private var keyMonitor: Any?
    private var finishingRemix = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        // Finder and Dock both use the packaged transparent ICNS. Leaving the
        // application icon untouched also keeps it identical before/after launch.
        NSApplication.shared.activate(ignoringOtherApps: true)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Space remains ordinary text input in search fields, names and descriptions.
            guard event.keyCode == 49, !event.isARepeat,
                  !WispInput.instrumentPresented,
                  !WispInput.playerCoverFocused,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  NSApp.modalWindow == nil,
                  NSApp.keyWindow?.attachedSheet == nil,
                  NSApp.keyWindow?.sheetParent == nil,
                  !(NSApp.keyWindow?.firstResponder is NSTextView) else { return event }
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSControl && !(responder is NSTableView) { return event }
            self?.player?.toggle()
            return nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let remix = WispInput.remix
        guard remix?.isRecording == true || remix?.isFinalizing == true || RemixStore.hasPendingFinalizations else { return .terminateNow }
        if !finishingRemix {
            finishingRemix = true
            Task { @MainActor in
                await remix?.finishBeforeTermination()
                await RemixStore.finishPendingBeforeTermination()
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.cancelImportReview()
        WispInput.remix?.shutdown()
        player?.shutdown()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}
