import SwiftUI

@MainActor
struct DriveSyncSettingsView: View {
    @EnvironmentObject private var driveSync: DriveSyncStore

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Label("Proton Drive", systemImage: "externaldrive")
                    .font(WispType.ui(13, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if driveSync.isPublishing {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Copying music to the Proton Drive folder")
                }
            }
            Text("An automatic copy of your music.")
                .font(WispType.ui(12))
            Text("Songs, artwork, playlists, and older audio versions stay in your connected Proton Drive folder. New imports and edits are copied while Bard is open.")
                .font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            if driveSync.isConnected {
                VStack(alignment: .leading, spacing: 5) {
                    Text(status).font(WispType.ui(11))
                    if let folder = driveSync.folderPath {
                        Text(folder.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                            .textSelection(.enabled).lineLimit(3)
                    }
                    if let date = driveSync.lastUpdated, !driveSync.isPublishing {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                    }
                }
            } else if driveSync.isPublishing {
                Text("Preparing your library folder…")
                    .font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
            }
            if let message = driveSync.errorMessage {
                Text(message).font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 16) {
                if driveSync.isConnected {
                    Button("Update Now") { driveSync.requestSync() }
                        .disabled(driveSync.isPublishing || !driveSync.canPublish)
                    Button("Show Folder") { driveSync.revealFolder() }
                    Button("Disconnect") { driveSync.disconnect() }
                        .foregroundStyle(WispSurface.mutedText)
                } else {
                    Button("Connect Proton Drive…") { driveSync.chooseFolder() }
                        .disabled(driveSync.isPublishing || !driveSync.canPublish)
                }
            }
            .buttonStyle(.plain).font(WispType.ui(11)).foregroundStyle(WispSurface.cyan)
            Text("Proton Drive uploads the folder. Removing a song from Bard keeps its Drive copy; disconnecting also leaves your files in place.")
                .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var status: String {
        if driveSync.isPublishing { return "Updating the Proton Drive folder…" }
        if driveSync.errorMessage != nil { return "Update needs attention · Will retry automatically" }
        if let count = driveSync.publishedSongCount { return "Automatic copying on · \(count.formatted()) songs" }
        return "Automatic copying on · Waiting for the first update"
    }
}
