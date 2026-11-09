import Foundation
import ImageIO
import UniformTypeIdentifiers
import WispCore

/// Artwork stays in memory until the same Save that commits the metadata.
/// Import drafts keep this separately from their protected prepared-file identity.
enum TrackArtworkEdit: Equatable, Sendable {
    case unchanged
    case replace(data: Data, source: TrackArtworkSource?)
    case remove

    var changesArtwork: Bool { if case .unchanged = self { return false }; return true }

    /// Validate every proposed cover before any managed file is created.
    /// The editor supplies an explicit crop; this boundary never silently crops it.
    func normalized() throws -> TrackArtworkEdit {
        guard case .replace(let data, let source) = self else { return self }
        try source?.validate()
        guard !data.isEmpty, data.count <= 20 * 1_048_576,
              let image = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(image) == 1,
              let type = CGImageSourceGetType(image),
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier,
               UTType.webP.identifier, UTType.tiff.identifier].contains(type as String),
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20_000, height <= 20_000,
              width <= 40_000_000 / height else { throw TrackArtworkEditError.invalidImage }
        guard ArtworkMatch.isNearSquare(width: width, height: height) else { throw TrackArtworkEditError.squareRequired }
        guard let bytes = AudioImporter.normalizedArtwork(data) else { throw TrackArtworkEditError.invalidImage }
        return .replace(data: bytes, source: source)
    }
}

enum TrackArtworkEditError: LocalizedError {
    case invalidImage, squareRequired, missingSnapshot, changedTrack
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Choose a readable still image smaller than 20 MB. Nothing was saved."
        case .squareRequired: return "Crop this image to a square before saving."
        case .missingSnapshot: return "Reopen the selected songs before changing their artwork."
        case .changedTrack: return "A selected song changed while this editor was open. Reopen it to review the latest version."
        }
    }
}
