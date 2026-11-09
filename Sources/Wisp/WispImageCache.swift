import AppKit
import ImageIO

/// Prefilter large artwork to the actual display size before SwiftUI samples it.
/// Thin neon highlights otherwise alias when a 2K texture is shrunk to a tiny
/// layer. Source artwork remains untouched; each point size and display scale
/// gets its own cached representation.
@MainActor
enum WispImageCache {
    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 180
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func image(at url: URL?, fitting size: CGSize, scale: CGFloat, fill: Bool = false) -> NSImage? {
        guard let url, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0, scale.isFinite, scale > 0 else { return nil }
        let pixelWidth = ceil(size.width * scale)
        let pixelHeight = ceil(size.height * scale)
        let key = "\(url.absoluteString)|\(pixelWidth)x\(pixelHeight)|\(scale)|\(fill)" as NSString
        if let image = images.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        var sourceWidth = CGFloat(width.doubleValue), sourceHeight = CGFloat(height.doubleValue)
        if let orientation = properties[kCGImagePropertyOrientation] as? NSNumber,
           (5...8).contains(orientation.intValue) { swap(&sourceWidth, &sourceHeight) }
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }
        let ratio = fill ? max(pixelWidth / sourceWidth, pixelHeight / sourceHeight)
                         : min(pixelWidth / sourceWidth, pixelHeight / sourceHeight)
        let maximumPixels = max(1, Int(ceil(min(4096, max(sourceWidth, sourceHeight) * ratio))))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let representation = NSBitmapImageRep(cgImage: thumbnail)
        representation.size = CGSize(width: CGFloat(thumbnail.width) / scale,
                                     height: CGFloat(thumbnail.height) / scale)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        images.setObject(image, forKey: key, cost: thumbnail.bytesPerRow * thumbnail.height)
        return image
    }
}
