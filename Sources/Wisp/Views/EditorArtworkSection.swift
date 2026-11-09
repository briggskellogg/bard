import AppKit
import SwiftUI
import WispCore

/// Shared by saved songs, saved selections, and import drafts. Choosing a cover
/// changes this draft only; the enclosing form owns Save and Cancel.
@MainActor
struct EditorArtworkSection: View {
    @ObservedObject var draft: EditorArtworkDraft
    let tracks: [Track]
    let current: [EditorArtworkCurrent]
    var enabled = true
    @Environment(\.displayScale) private var displayScale
    @State private var searchOverride: String?
    @FocusState private var searchFocused: Bool

    private var common: EditorArtworkCurrent? {
        guard let first = current.first,
              current.allSatisfy({ $0.identity == first.identity }) else { return nil }
        return first
    }
    private var hasCurrent: Bool { current.contains { $0.identity != nil } }
    private var subject: String { searchOverride ?? EditorArtworkSearch.subject(for: tracks) }
    private var previewSide: CGFloat { draft.image == nil ? 76 : 148 }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Artwork").font(WispType.ui(13, weight: .medium))
                Spacer()
                if draft.hasChanges {
                    Button("Reset") { draft.reset() }.buttonStyle(.plain)
                        .font(WispType.ui(10)).foregroundStyle(.secondary)
                        .help("Keep the artwork this form started with")
                }
            }
            HStack(alignment: .top, spacing: 18) {
                preview.frame(width: previewSide, height: previewSide)
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Search for artwork", text: Binding(get: { subject }, set: { searchOverride = $0 }))
                        .textFieldStyle(.plain).font(WispType.ui(11)).focused($searchFocused)
                        .accessibilityLabel("Artwork search")
                        .onSubmit(search)
                    HStack(spacing: 16) {
                        Button("Search", systemImage: "magnifyingglass", action: search)
                            .help("Search images in your browser · ⌘⇧F")
                        Button("Upload", systemImage: "arrow.up.doc", action: upload)
                            .help("Choose an image · ⌘O")
                        Button("Paste", systemImage: "doc.on.clipboard", action: paste)
                            .help("Paste a copied image · ⌘V outside a text field")
                    }
                    .buttonStyle(.plain).font(WispType.ui(11)).foregroundStyle(.tint)
                    if draft.isLoading {
                        HStack(spacing: 7) { ProgressView().controlSize(.mini); Text("Preparing image…") }
                            .font(WispType.ui(10)).foregroundStyle(.secondary)
                    } else {
                        Text(status).font(WispType.ui(10)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let image = draft.image {
                        HStack(spacing: 9) {
                            Text("Zoom").font(WispType.ui(10)).foregroundStyle(.secondary)
                            Slider(value: Binding(get: { draft.selection.zoom }, set: {
                                draft.selection.zoom = $0
                                draft.selection = draft.selection.clamped(sourceWidth: image.pixelWidth, sourceHeight: image.pixelHeight)
                            }), in: 1...ArtworkCropSelection.maximumZoom)
                            .accessibilityLabel("Artwork crop zoom")
                            Button("Reset crop") { draft.selection = ArtworkCropSelection() }
                                .buttonStyle(.plain).font(WispType.ui(10)).foregroundStyle(.secondary)
                        }
                        Text("Drag to crop · arrow keys to fine-tune").font(WispType.ui(9)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 14) {
                        if draft.image == nil, draft.change != .remove, let common,
                           common.image != nil || common.url != nil {
                            Button("Crop current") { draft.cropCurrent(common) }
                                .help("Adjust this cover without saving yet")
                        }
                        if (hasCurrent || draft.image != nil) && draft.change != .remove {
                            Button("Remove") { draft.remove() }
                                .help(tracks.count > 1 ? "Remove covers from these songs when you save" : "Remove this cover when you save")
                        }
                    }.buttonStyle(.plain).font(WispType.ui(10)).foregroundStyle(.secondary)
                }
            }
            if let error = draft.error {
                Text(error).font(WispType.ui(10)).foregroundStyle(WispSurface.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(!enabled)
        .background(ArtworkKeyboardShortcuts(enabled: enabled, paste: paste, upload: upload, search: search))
        .onDisappear { draft.cancelLoading() }
    }

    @ViewBuilder private var preview: some View {
        if let image = draft.image {
            ArtworkCropPreview(source: image, selection: $draft.selection, side: previewSide)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if draft.change != .remove, let common, let image = common.image {
            Image(decorative: image, scale: 1).resizable().interpolation(.high).scaledToFill()
                .frame(width: previewSide, height: previewSide).clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityLabel("Current artwork")
        } else if draft.change != .remove, let common,
                  let image = WispImageCache.image(at: common.url, fitting: CGSize(width: previewSide, height: previewSide), scale: displayScale, fill: true) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                .frame(width: previewSide, height: previewSide).clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityLabel("Current artwork")
        } else {
            Image(systemName: draft.change == .remove ? "photo.badge.minus" : common == nil && hasCurrent ? "photo.on.rectangle" : "photo")
                .font(.system(size: 22, weight: .ultraLight)).foregroundStyle(.tertiary)
                .accessibilityLabel(draft.change == .remove ? "Artwork will be removed" : common == nil && hasCurrent ? "Different covers" : "No artwork")
        }
    }

    private var status: String {
        let count = tracks.count
        switch draft.change {
        case .replace: return count > 1 ? "This cover replaces artwork for all \(count) songs when you save." : "This crop is applied when you save."
        case .remove: return count > 1 ? "Covers will be removed from all \(count) songs when you save." : "This cover will be removed when you save."
        case .unchanged:
            if count > 1 { return "\(common == nil && hasCurrent ? "Different covers. " : "")Choose one cover for all \(count) songs, or leave their artwork unchanged." }
            return "Choose an image and crop it here. Changes apply when you save."
        }
    }

    private func search() {
        guard enabled, let request = EditorArtworkSearch.request(tracks: tracks, subject: subject),
              !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        searchFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
        if !NSWorkspace.shared.open(ArtworkSearch.googleImagesURL(for: request)) {
            draft.error = "The browser couldn’t open. Try again or upload a saved image."
        }
    }

    private func upload() {
        guard enabled, let url = NativeFiles.chooseCover() else { return }
        searchFocused = false
        draft.load(name: url.lastPathComponent) { try EditorArtworkDraft.readFile(url) }
    }

    private func paste() {
        guard enabled else { return }
        do {
            let data = try ArtworkClipboard.imageData()
            searchFocused = false
            draft.load(name: "Pasted image", maximumBytes: ArtworkCrop.maximumClipboardBytes) { data }
        } catch { draft.error = error.localizedDescription }
    }
}
