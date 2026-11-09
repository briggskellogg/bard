import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import WispCore

enum ArtworkCropError: LocalizedError {
    case oversized, invalidImage, tooManyPixels, renderFailed
    var errorDescription: String? {
        switch self {
        case .oversized: return "That image is too large to crop. Choose a smaller file."
        case .invalidImage: return "Choose a PNG, JPEG, HEIC, WebP or TIFF still image."
        case .tooManyPixels: return "That image’s dimensions are too large to crop safely."
        case .renderFailed: return "Bard could not prepare this crop. Choose another image."
        }
    }
}

/// Immutable, correctly oriented pixels. No filesystem or library state is owned here.
struct ArtworkCropSource: @unchecked Sendable {
    let image: CGImage
    var pixelWidth: Int { image.width }
    var pixelHeight: Int { image.height }
}

/// Display `image` and approve `data`; both describe the exact same square pixels.
struct ArtworkCropOutput: @unchecked Sendable {
    let image: CGImage
    let data: Data
    var pixelWidth: Int { image.width }
    var pixelHeight: Int { image.height }
}

enum ArtworkCrop {
    static let maximumImageBytes = 12 * 1024 * 1024
    static let maximumClipboardBytes = 64 * 1024 * 1024
    static let maximumImagePixels = 40_000_000
    static let maximumOutputSide = 1600

    /// Call outside the main actor. The larger allowance is only needed for raw clipboard TIFF.
    static func prepare(_ data: Data, maximumBytes: Int = maximumImageBytes) throws -> ArtworkCropSource {
        try Task.checkCancellation()
        guard data.count <= min(maximumClipboardBytes, max(0, maximumBytes)) else { throw ArtworkCropError.oversized }
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let identifier = CGImageSourceGetType(source),
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier,
               UTType.webP.identifier, UTType.tiff.identifier].contains(identifier as String),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw ArtworkCropError.invalidImage }
        guard width > 0, height > 0, width <= 20_000, height <= 20_000,
              width <= maximumImagePixels / height else { throw ArtworkCropError.tooManyPixels }
        // Keep source detail for a later crop; ImageIO applies rotations and mirrors once.
        // The dimensions above bound the full decoded allocation to forty megapixels.
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { throw ArtworkCropError.invalidImage }
        try Task.checkCancellation()
        return ArtworkCropSource(image: image)
    }

    /// The square is cropped without stretching and downsampled only if it exceeds 1600 px.
    static func render(source: ArtworkCropSource, selection: ArtworkCropSelection) throws -> ArtworkCropOutput {
        try Task.checkCancellation()
        let rect = selection.pixelRect(sourceWidth: source.pixelWidth, sourceHeight: source.pixelHeight)
        guard rect.width >= 1, let cropped = source.image.cropping(to: rect) else { throw ArtworkCropError.renderFailed }
        let image: CGImage
        if cropped.width <= maximumOutputSide { image = cropped }
        else {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: maximumOutputSide, height: maximumOutputSide,
                    bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ArtworkCropError.renderFailed }
            context.interpolationQuality = .high
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: maximumOutputSide, height: maximumOutputSide))
            guard let resized = context.makeImage() else { throw ArtworkCropError.renderFailed }
            image = resized
        }
        try Task.checkCancellation()
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil) else {
            throw ArtworkCropError.renderFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ArtworkCropError.renderFailed }
        try Task.checkCancellation()
        // Decode the encoded result once so the preview is exactly the approved representation,
        // including ImageIO's treatment of colour profiles and transparent pixels.
        let data = bytes as Data
        guard let encoded = CGImageSourceCreateWithData(data as CFData, nil),
              let preview = CGImageSourceCreateImageAtIndex(encoded, 0, nil) else { throw ArtworkCropError.renderFailed }
        return ArtworkCropOutput(image: preview, data: data)
    }
}
