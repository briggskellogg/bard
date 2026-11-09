import SwiftUI

@MainActor
struct PhoneSyncSettingsView: View {
    @EnvironmentObject private var phoneSync: PhoneSyncStore
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Phone Sync", systemImage: "iphone")
                    .font(WispType.ui(13, weight: .medium))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if phoneSync.isBusy {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Updating the shared folder")
                }
            }
            Text("Your Mac library, on your iPhone.")
                .font(WispType.ui(12))
            Text("All \(store.tracks.count.formatted()) current songs, covers, playlists, and their order. Edits stay on this Mac; the iPhone keeps a listening copy for offline playback. Older audio versions stay here.")
                .font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            if phoneSync.isConnected {
                HStack(spacing: 9) {
                    if let image = WispImageCache.image(at: WispResources.logoURL,
                                                       fitting: CGSize(width: 26, height: 34), scale: displayScale) {
                        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                            .frame(width: 26, height: 34).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(phoneSync.folderName).font(WispType.ui(13, weight: .medium))
                        Text("On iPhone, select this folder, then tap Open.")
                            .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                    }
                }.padding(.vertical, 3)
                VStack(alignment: .leading, spacing: 5) {
                    Text(status).font(WispType.ui(11))
                    if let folder = phoneSync.folderPath {
                        Text(folder.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                            .textSelection(.enabled).lineLimit(2)
                    }
                    if let date = phoneSync.lastUpdated, !phoneSync.isPublishing {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                    }
                }
            } else {
                Text(phoneSync.isPublishing ? "Preparing the shared folder…" : "Choose iCloud Drive or your existing shared folder. Existing Wisp and Wisp Phone Sync folders keep working with Bard.")
                    .font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = phoneSync.errorMessage {
                Text(message).font(WispType.ui(11)).foregroundStyle(WispSurface.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 16) {
                if phoneSync.isConnected {
                    Button("Sync Now") { phoneSync.requestSync() }
                        .disabled(phoneSync.isBusy || !store.canEdit)
                    Button("Show Folder") { phoneSync.revealFolder() }
                        .disabled(phoneSync.isRenaming)
                    if phoneSync.canRename {
                        Button("Rename to Wisp…") { phoneSync.renameFolder() }
                            .disabled(phoneSync.isBusy)
                    }
                    Button("Disconnect") { phoneSync.disconnect() }
                        .foregroundStyle(WispSurface.mutedText).disabled(phoneSync.isRenaming)
                } else {
                    Button("Connect…") { phoneSync.chooseFolder() }
                        .disabled(phoneSync.isBusy || !store.canEdit)
                }
            }
            .buttonStyle(.plain).font(WispType.ui(11)).foregroundStyle(WispSurface.cyan)
            Text("Select the shared folder, not Assets or Library.json inside it. The logo appears in Finder; Files on iPhone may show a standard folder. iCloud delivers updates while Bard is open.")
                .font(WispType.ui(10)).foregroundStyle(WispSurface.mutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var status: String {
        if phoneSync.isRenaming { return "Renaming shared folder…" }
        if phoneSync.isPublishing { return "Updating shared folder…" }
        if phoneSync.errorMessage != nil { return "Update needs attention" }
        if let count = phoneSync.publishedSongCount { return "Updated shared folder · \(count.formatted()) songs" }
        return "Connected · Waiting for the first update"
    }
}
