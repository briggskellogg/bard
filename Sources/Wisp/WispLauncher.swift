import SwiftUI

/// Installer preflight must finish before WispApp initializes the real library,
/// player, Music connection, or any SwiftUI window.
@main
@MainActor
enum WispLauncher {
    static func main() {
        guard !MountedInstallerHandoff.runPreflight() else { return }
        WispApp.main()
    }
}
