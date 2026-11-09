import AppKit
import SwiftUI
import WispCore

@MainActor
struct MixtapeEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let playlistID: UUID
    @State private var capacity: CassetteCapacity = .c90
    @State private var gap: MixtapeGap = .twoSeconds
    @State private var manualSplit: Int?
    @State private var working = false
    @State private var fraction = 0.0
    @State private var status = ""
    @State private var errorMessage: String?
    @State private var exportedURL: URL?
    @State private var operation: Task<Void, Never>?

    private var playlist: Playlist? { store.playlist(id: playlistID) }
    private var tracks: [Track] { playlist?.trackIDs.compactMap { store.track(id: $0) } ?? [] }
    private var plan: MixtapePlan { MixtapePlan(tracks: tracks, capacity: capacity, gap: gap, splitIndex: manualSplit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
          ScrollView {
           VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Mixtape").font(WispType.display(20))
                Text(playlist?.name ?? "Playlist").font(WispType.ui(13)).foregroundStyle(.secondary)
            }
            Text("Continuous audio for each cassette side, in playlist order.")
                .font(WispType.ui(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 24) {
                Picker("Cassette", selection: $capacity) {
                    ForEach(CassetteCapacity.allCases) { tape in
                        Text("\(tape.title) · \(tape.sideMinutes) min/side").tag(tape)
                    }
                }
                Picker("Gap", selection: $gap) {
                    ForEach(MixtapeGap.allCases) { value in Text(value.title).tag(value) }
                }.frame(width: 180)
            }.disabled(working)
            HStack {
                Stepper(value: Binding(get: { plan.splitIndex }, set: { manualSplit = $0 }), in: 0...tracks.count) {
                    Text(plan.splitIndex == 0 ? "Side A is empty" : "Side A ends after track \(plan.splitIndex)")
                        .font(WispType.ui(12))
                }
                Spacer(minLength: 20)
                Button("Automatic") { manualSplit = nil }.disabled(manualSplit == nil)
            }.disabled(working)
            HStack(alignment: .top, spacing: 16) {
                sideView(plan.sideA)
                sideView(plan.sideB)
            }
            if !plan.problems.isEmpty {
                Text(plan.problems.joined(separator: "\n"))
                    .font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Text("Downloads WAV sides, a timestamped tracklist, and your cover to Downloads/Wisp. Tracks stay complete.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if working {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: fraction)
                    Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if let exportedURL {
                HStack {
                    Label("Mixtape exported", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([exportedURL]) }
                }.font(.caption)
            }
           }
          }
            HStack {
                Spacer()
                Button(working ? "Cancel Export" : "Done") {
                    if working { operation?.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction)
                Button("Download", action: downloadMixtape)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(working || !plan.canExport || playlist == nil)
            }
        }
        .padding(20).frame(width: 620, height: 500)
        .interactiveDismissDisabled(working)
        .onChange(of: capacity) { _, _ in manualSplit = nil }
        .onChange(of: gap) { _, _ in manualSplit = nil }
        .onDisappear { operation?.cancel() }
    }

    private func sideView(_ side: MixtapeSide) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Side \(side.label)").font(WispType.ui(13, weight: .medium))
                Spacer()
                Text("\(MixtapePlan.time(side.duration)) / \(capacity.sideMinutes):00")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(side.duration > capacity.sideSeconds ? Color.red : Color.secondary)
            }
            ProgressView(value: min(side.duration, capacity.sideSeconds), total: capacity.sideSeconds)
                .tint(side.duration > capacity.sideSeconds ? .red : .accentColor)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if side.tracks.isEmpty { Text("Unused side").font(.caption).foregroundStyle(.tertiary) }
                    ForEach(Array(side.tracks.enumerated()), id: \.element.id) { index, track in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text("\(index + 1)").foregroundStyle(.tertiary).frame(width: 18, alignment: .trailing)
                            Text(track.displayTitle).lineLimit(2)
                            Spacer(minLength: 4)
                            Text(MixtapePlan.time(track.duration)).foregroundStyle(.secondary).monospacedDigit()
                        }.font(WispType.ui(11))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 130)
        }
        .frame(maxWidth: .infinity)
    }

    private func downloadMixtape() {
        guard let playlist else { return }
        let snapshot = plan
        guard snapshot.canExport else { return }
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            errorMessage = "Your Downloads folder could not be found."
            return
        }
        let destination = downloads.appendingPathComponent("Wisp", isDirectory: true)
        let request = MixtapeExportRequest(playlist: playlist, plan: snapshot,
            audioURLs: Dictionary(uniqueKeysWithValues: snapshot.tracks.map { ($0.id, store.audioURL(for: $0)) }),
            coverURL: store.coverURL(for: playlist), destination: destination)
        working = true
        fraction = 0
        status = "Preparing cassette sides…"
        errorMessage = nil
        exportedURL = nil
        operation = Task { @MainActor in
            let worker = Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                return try MixtapeExporter.export(request) { value, label in
                    Task { @MainActor in fraction = value; status = label }
                }
            }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                exportedURL = result
            } catch is CancellationError {
                errorMessage = "Export cancelled."
            } catch { errorMessage = error.localizedDescription }
            working = false
            operation = nil
        }
    }
}
