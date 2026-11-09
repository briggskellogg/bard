import SwiftUI
import WispCore

struct TrackFilterMenu: View {
    @Binding var filter: TrackLibraryFilter
    let genres: [TrackFilterChoice]
    let origins: [TrackFilterChoice]
    @State private var presented = false

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 10))
                Text("Filter")
                if filter.isActive { Circle().fill(WispSurface.cyan).frame(width: 4, height: 4) }
            }.foregroundStyle(filter.isActive ? WispSurface.cyan : WispSurface.mutedText)
        }
        .buttonStyle(.plain).fixedSize()
        .help("Filter by genre or the work a song comes from")
        .accessibilityLabel("Filter by genre or origin")
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 19) {
                HStack {
                    Text("Filter").foregroundStyle(WispSurface.ink)
                    Spacer()
                    if filter.isActive {
                        Button("Clear") { filter = TrackLibraryFilter() }
                            .buttonStyle(.plain).foregroundStyle(WispSurface.cyan)
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 15) {
                    GridRow {
                        Text("Genre").foregroundStyle(WispSurface.mutedText)
                        Picker("Genre", selection: $filter.genre) {
                            Text("All genres").tag(String?.none)
                            ForEach(genres) { Text($0.label).tag(Optional($0.id)) }
                        }.labelsHidden()
                    }
                    GridRow {
                        Text("Origin").foregroundStyle(WispSurface.mutedText)
                        Picker("Origin", selection: $filter.origin) {
                            Text("All origins").tag(String?.none)
                            ForEach(origins) { Text($0.label).tag(Optional($0.id)) }
                        }.labelsHidden()
                    }
                }
                .pickerStyle(.menu).buttonStyle(.borderless).controlSize(.small)
            }
            .font(WispType.ui(12)).padding(20).frame(width: 320)
            .background(WispSurface.main)
        }
    }
}
