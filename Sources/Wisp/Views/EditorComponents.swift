import SwiftUI
import WispCore

struct EditorFieldRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(title).font(WispType.ui(12)).foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct QuietFieldLine: ViewModifier {
    func body(content: Content) -> some View {
        content.textFieldStyle(.plain).font(WispType.ui(13)).padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.09)).frame(height: 0.5)
            }
    }
}

struct MediaKindPicker: View {
    @Binding var selection: OriginMediaKind?
    var body: some View {
        Picker("Category", selection: $selection) {
            Text("Automatic").tag(Optional<OriginMediaKind>.none)
            ForEach(OriginMediaKind.allCases) { kind in
                Label(kind.title, systemImage: kind.symbolName).tag(Optional(kind))
            }
        }.labelsHidden().pickerStyle(.menu).buttonStyle(.borderless)
            .help("Optional source category. Automatic recognizes familiar titles; standalone songs need no origin.")
    }
}

struct RemixPicker: View {
    @Binding var selection: RemixKind?
    var body: some View {
        Picker("Collection", selection: $selection) {
            Text("Unspecified").tag(Optional<RemixKind>.none)
            Text("Basic · External source").tag(Optional(RemixKind.basic))
            Text("Classic · Created by you").tag(Optional(RemixKind.classic))
        }.labelsHidden().pickerStyle(.menu).buttonStyle(.borderless)
    }
}

@MainActor
struct BulkTrackEditor: View {
    @EnvironmentObject private var store: LibraryStore
    let trackIDs: [UUID]
    var focusArtwork = false
    @State private var snapshots: [Track]?

    var body: some View {
        Group {
            if let snapshots {
                MetadataBatchSheet(tracks: snapshots,
                    currentArtwork: snapshots.map { EditorArtworkCurrent(track: $0, url: store.artworkURL(for: $0)) },
                    heading: "Edit \(snapshots.count) songs",
                    explanation: "Changes apply only to these selected songs.",
                    saveEnabled: store.canEdit, focusArtwork: focusArtwork) { patch, artwork in
                        store.updateTracks(ids: Set(snapshots.map(\.id)), patch: patch,
                                           artwork: artwork, expectedTracks: snapshots)
                    }
            } else { ProgressView().frame(width: 620, height: 700) }
        }
        .onAppear {
            if snapshots == nil { snapshots = trackIDs.compactMap { store.track(id: $0) } }
            store.errorMessage = nil
        }
    }
}
