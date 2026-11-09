import AppKit
import SwiftUI
import WispCore

@MainActor
struct SourceImportView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let playlistID: UUID?
    @State private var source = ""
    @State private var download = ""
    @State private var working = false
    @State private var operation: Task<Void, Never>?
    @FocusState private var sourceFocused: Bool

    private var sourceURL: URL? { MusicSource.validatedURL(source) }
    private var downloadURL: URL? { MusicSource.validatedURL(download) }
    private var sourceValid: Bool { source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sourceURL != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Link").font(WispType.display(20))
            Text("Import downloaded music and keep its source link.")
                .font(WispType.ui(13)).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Source").font(WispType.ui(12, weight: .medium))
                    Spacer()
                    if let url = sourceURL {
                        Text(MusicSource.detect(url).title).font(.caption).foregroundStyle(.secondary)
                    }
                }
                TextField("Website URL", text: $source)
                    .modifier(QuietFieldLine()).focused($sourceFocused)
                    .accessibilityLabel("Source webpage URL")
                Text("SoundCloud, Bandcamp, or another source.").font(.caption).foregroundStyle(.secondary)
            }
            .disabled(working)

            HStack(spacing: 10) {
                Button("Open") { if let url = sourceURL { NSWorkspace.shared.open(url) } }
                    .disabled(sourceURL == nil || working)
                    .help("Open the source page to download music")
                Button("Files", action: chooseFiles)
                    .disabled(!sourceValid || working || store.isImporting || !store.canEdit)
                    .help("Import downloaded audio or a ZIP archive with this source link")
            }

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Download").font(WispType.ui(12, weight: .medium))
                TextField("Direct file URL", text: $download).modifier(QuietFieldLine())
                    .accessibilityLabel("Direct audio or ZIP archive download URL")
                Text("A direct audio or ZIP archive link. Website share links go in Source.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(working)
            if working {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(store.isImporting ? store.importLabel : "Downloading…").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let message = store.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel") { operation?.cancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(store.isImporting)
                Button("Import", action: importDownload)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(downloadURL == nil || !sourceValid || working || store.isImporting || !store.canEdit)
            }
        }
        .padding(30)
        .frame(width: 480)
        .interactiveDismissDisabled(working)
        .onAppear { sourceFocused = true }
        .onDisappear { operation?.cancel() }
    }

    private func chooseFiles() {
        let urls = NativeFiles.chooseAudio()
        guard !urls.isEmpty else { return }
        working = true
        operation = Task { @MainActor in
            store.errorMessage = nil
            await store.importFiles(urls, into: playlistID, sourceURL: sourceURL)
            working = false
            if store.errorMessage == nil { dismiss() }
        }
    }

    private func importDownload() {
        guard let downloadURL else { return }
        working = true
        operation = Task { @MainActor in
            let succeeded = await store.importDownload(from: downloadURL, sourceURL: sourceURL, into: playlistID)
            working = false
            if succeeded { dismiss() }
        }
    }
}
