import SwiftUI
import UniformTypeIdentifiers

struct PhoneSyncView: View {
    @EnvironmentObject private var library: PhoneLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var choosingFolder = false
    private var folderName: String { library.selectedFolderName ?? "Shared library" }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Your Mac library, on iPhone.")
                        .font(.wispText(.title, medium: true)).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 15) {
                        ZStack {
                            Image(systemName: "folder.fill").font(.system(size: 42, weight: .regular))
                                .foregroundStyle(PhoneStyle.blue.opacity(0.18))
                            Image("wisp-insignia").resizable().scaledToFit()
                                .frame(width: 19, height: 24).offset(y: 3)
                        }.frame(width: 48, height: 46).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(folderName).font(.wispText(.body, medium: true))
                            Text("iCloud Drive · Your shared library")
                                .font(.wispText(.small)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.padding(.vertical, 6)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select your shared library folder, then tap Open.")
                            .font(.wispText(.caption, medium: true))
                        Text("Choose it in iCloud Drive, not On My iPhone. If you see Assets or Library.json, those are the contents—connect their containing folder.")
                            .font(.wispText(.caption)).foregroundStyle(.secondary)
                        Text("Check Bard → Data → Phone Sync on your Mac for the folder’s exact name. Existing folders named Wisp or Wisp Phone Sync still work.")
                            .font(.wispText(.caption)).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        if library.isSyncing { ProgressView(library.status).font(.wispText(.caption)) }
                        else { Text(library.status).font(.wispText(.caption, medium: true)) }
                        if let error = library.errorMessage {
                            Text(error).font(.wispText(.caption)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                        if let note = library.favoriteStatus {
                            Text(note).font(.wispText(.caption)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let date = library.lastSynced {
                            Text("Last downloaded \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.wispText(.small)).foregroundStyle(.secondary)
                        }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { connectionButtons }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 8) { connectionButtons }
                    }.disabled(library.isSyncing)
                    if library.hasPendingConnection {
                        Button { library.cancelPendingConnection() } label: { secondaryAction("Cancel connection") }
                            .buttonStyle(.plain).disabled(library.isSyncing)
                    } else if library.isConnected {
                        Button { library.disconnect() } label: { secondaryAction("Disconnect") }
                            .buttonStyle(.plain).disabled(library.isSyncing)
                    }
                    Text("Use the same Apple Account on both devices. Keep Bard open for the first download. Favorite changes sync back while Bard is open on your Mac. Songs stay available offline.")
                        .font(.wispText(.caption)).foregroundStyle(.secondary).lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(26)
            }
            .background(PhoneStyle.background).navigationTitle("Phone Sync").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let folder): library.connect(to: folder)
                case .failure(let error): library.errorMessage = error.localizedDescription
                }
            }
        }
    }

    @ViewBuilder private var connectionButtons: some View {
        Button { choosingFolder = true } label: {
            Text(library.isConnected || library.hasPendingConnection ? "Choose folder…" : "Connect folder…")
                .fixedSize(horizontal: false, vertical: true)
        }.buttonStyle(PhoneActionButtonStyle(prominent: true))
        if library.isConnected || library.hasPendingConnection {
            Button { library.refresh() } label: {
                Text(library.hasPendingConnection ? "Retry now" : "Sync now")
                    .font(.wispText(.caption, medium: true))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(PhoneStyle.blue)
        }
    }

    private func secondaryAction(_ title: String) -> some View {
        Text(title).font(.wispText(.caption)).foregroundStyle(PhoneStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}
