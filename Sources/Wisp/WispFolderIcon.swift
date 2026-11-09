import AppKit
import CryptoKit
import Darwin
import UniformTypeIdentifiers

/// A Finder folder with a small brand badge, rather than a replacement app icon.
/// Applying it is cosmetic: a failed icon update never interrupts music sync.
@MainActor
enum WispFolderIcon {
    // Bump this when the composition or the supplied insignia changes.
    static let revision = "native-folder-badge-bard-1"
    private static var checkedFolders: Set<String> = []
    private static var cachedImage: NSImage?

    /// A native 1024px folder with the original, wordless mark centered on its
    /// front face. Drawing never modifies the approved source artwork.
    static func makeImage(logoURL: URL? = WispResources.logoURL) -> NSImage? {
        guard let logoURL, let mark = NSImage(contentsOf: logoURL),
              mark.size.width > 0, mark.size.height > 0,
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024,
                  pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4,
                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                  bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
        bitmap.size = canvas.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.cgContext.clear(canvas)
        NSWorkspace.shared.icon(for: UTType.folder)
            .draw(in: canvas, from: .zero, operation: .sourceOver, fraction: 1)

        // The native folder face occupies the lower two thirds of the canvas.
        // At roughly one third of the folder's height, the insignia remains a
        // recognizable stamp while the folder silhouette stays dominant.
        let badgeHeight: CGFloat = 288
        let badgeWidth = badgeHeight * mark.size.width / mark.size.height
        let badge = NSRect(x: (canvas.width - badgeWidth) / 2,
                           y: 278, width: badgeWidth, height: badgeHeight)
        mark.draw(in: badge, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: canvas.size)
        image.addRepresentation(bitmap)
        return image
    }

    /// Call only for an approved, successfully published sync destination.
    /// The stored signature allows a later launch to repair an old or removed
    /// custom icon without rewriting current icons at every library update.
    @discardableResult
    static func apply(to folder: URL, defaults: UserDefaults = .standard,
                      logoURL: URL? = WispResources.logoURL) -> Bool {
        guard folder.isFileURL else { return false }
        let access = folder.startAccessingSecurityScopedResource()
        defer { if access { folder.stopAccessingSecurityScopedResource() } }
        guard let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { return false }
        let canonical = folder.standardizedFileURL.resolvingSymlinksInPath()
        // Finder uses this reserved file for custom folder icons. Refuse an
        // unexpected link or directory before asking AppKit to write it.
        var iconStatus = stat()
        let iconPath = canonical.appendingPathComponent("Icon\r").path
        let exists = iconPath.withCString { lstat($0, &iconStatus) }
        if exists == 0 {
            guard iconStatus.st_mode & S_IFMT == S_IFREG else { return false }
        } else if errno != ENOENT { return false }
        let pathDigest = SHA256.hash(data: Data(canonical.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let key = "wisp.folderIcon.\(pathDigest)"
        if checkedFolders.contains(key) { return true }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let currentRevision = "\(revision)-macOS\(os.majorVersion).\(os.minorVersion)"
        if let saved = defaults.dictionary(forKey: key) as? [String: String],
           saved["revision"] == currentRevision,
           let actual = signature(of: canonical), saved["signature"] == actual {
            checkedFolders.insert(key)
            return true
        }

        // Production uses one shared asset. An explicitly supplied preview URL
        // is rendered independently so the compositor remains testable.
        let image: NSImage?
        if logoURL == WispResources.logoURL {
            if cachedImage == nil { cachedImage = makeImage(logoURL: logoURL) }
            image = cachedImage
        } else { image = makeImage(logoURL: logoURL) }
        guard let image, NSWorkspace.shared.setIcon(image, forFile: canonical.path, options: []),
              let actual = signature(of: canonical) else { return false }
        defaults.set(["revision": currentRevision, "signature": actual], forKey: key)
        checkedFolders.insert(key)
        return true
    }

    private static func signature(of folder: URL) -> String? {
        guard let finderInfo = attribute("com.apple.FinderInfo", at: folder, maximumBytes: 32),
              finderInfo.count == 32, finderInfo[8] & 0x04 != 0 else { return nil }
        let iconFile = folder.appendingPathComponent("Icon\r", isDirectory: false)
        guard let values = try? iconFile.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let resourceFork = attribute("com.apple.ResourceFork", at: iconFile,
                                           maximumBytes: 8 * 1024 * 1024) else { return nil }
        return SHA256.hash(data: resourceFork).map { String(format: "%02x", $0) }.joined()
    }

    private static func attribute(_ name: String, at url: URL, maximumBytes: Int) -> Data? {
        url.path.withCString { path in
            name.withCString { name in
                let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
                guard size > 0, size <= maximumBytes else { return nil }
                var bytes = Data(count: size)
                let count = bytes.withUnsafeMutableBytes { buffer in
                    getxattr(path, name, buffer.baseAddress, buffer.count, 0, XATTR_NOFOLLOW)
                }
                return count == size ? bytes : nil
            }
        }
    }
}
