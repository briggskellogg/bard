import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A square window into an oriented source image. Coordinates start at its top-left.
public struct ArtworkCropSelection: Equatable, Sendable {
    public static let maximumZoom = 4.0
    public var centerX: Double
    public var centerY: Double
    public var zoom: Double

    public init(centerX: Double = 0.5, centerY: Double = 0.5, zoom: Double = 1) {
        self.centerX = centerX; self.centerY = centerY; self.zoom = zoom
    }

    public func clamped(sourceWidth: Int, sourceHeight: Int) -> ArtworkCropSelection {
        guard sourceWidth > 0, sourceHeight > 0 else { return ArtworkCropSelection() }
        let safeZoom = zoom.isFinite ? min(Self.maximumZoom, max(1, zoom)) : 1
        let side = max(1, floor(Double(min(sourceWidth, sourceHeight)) / safeZoom))
        let halfX = side / (2 * Double(sourceWidth)), halfY = side / (2 * Double(sourceHeight))
        let x = centerX.isFinite ? centerX : 0.5, y = centerY.isFinite ? centerY : 0.5
        return ArtworkCropSelection(centerX: min(1 - halfX, max(halfX, x)),
                                    centerY: min(1 - halfY, max(halfY, y)), zoom: safeZoom)
    }

    /// Integer coordinates ensure the preview and approved PNG select the same pixels.
    public func pixelRect(sourceWidth: Int, sourceHeight: Int) -> CGRect {
        guard sourceWidth > 0, sourceHeight > 0 else { return .zero }
        let value = clamped(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        let side = max(1, floor(Double(min(sourceWidth, sourceHeight)) / value.zoom))
        let x = min(Double(sourceWidth) - side, max(0, (value.centerX * Double(sourceWidth) - side / 2).rounded()))
        let y = min(Double(sourceHeight) - side, max(0, (value.centerY * Double(sourceHeight) - side / 2).rounded()))
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// Positive drag moves the image right/down, revealing pixels on its left/top.
    /// Pass a translation relative to the selection captured at the drag's start.
    public func panned(dx: Double, dy: Double, viewportSide: Double,
                       sourceWidth: Int, sourceHeight: Int) -> ArtworkCropSelection {
        let base = clamped(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        guard viewportSide.isFinite, viewportSide > 0, sourceWidth > 0, sourceHeight > 0 else { return base }
        let side = base.pixelRect(sourceWidth: sourceWidth, sourceHeight: sourceHeight).width
        let x = dx.isFinite ? dx : 0, y = dy.isFinite ? dy : 0
        return ArtworkCropSelection(centerX: base.centerX - x * side / (viewportSide * Double(sourceWidth)),
                                    centerY: base.centerY - y * side / (viewportSide * Double(sourceHeight)),
                                    zoom: base.zoom).clamped(sourceWidth: sourceWidth, sourceHeight: sourceHeight)
    }
}
