import AppKit

// Image decoding happens off the main thread in ArtworkCrop after explicit paste.
enum ArtworkClipboardError: LocalizedError {
    case noImage, oversized
    var errorDescription: String? {
        switch self {
        case .noImage: return "Copy the image itself in your browser, then press ⌘V here. You can also choose Upload Image."
        case .oversized: return "That clipboard image is too large. Save it as a smaller image, then choose Upload Image."
        }
    }
}

@MainActor
enum ArtworkClipboard {
    static let maximumClipboardBytes = 64 * 1024 * 1024
    /// Preserve rectangular pixels for an explicit crop. Never fetch a copied URL or read an unrelated file.
    static func imageData(from pasteboard: NSPasteboard = .general) throws -> Data {
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff, .init("public.jpeg")]
        guard let type = pasteboard.availableType(from: types),
              let data = pasteboard.data(forType: type), !data.isEmpty else { throw ArtworkClipboardError.noImage }
        guard data.count <= maximumClipboardBytes else { throw ArtworkClipboardError.oversized }
        return data
    }
}
