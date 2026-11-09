import Foundation

/// SwiftPM's generated Bundle.module accessor searches beside the app bundle,
/// whereas packaged macOS resources live inside Contents/Resources. Resolve the
/// packaged layout directly so an installed app never depends on a build folder.
enum WispResources {
    static var makerMarkURL: URL? { url(forResource: "maker-mark", withExtension: "png") }
    static var logoURL: URL? { url(forResource: "wisp-insignia", withExtension: "png") }
    static var mixtapeCoverURL: URL? { url(forResource: "mixtape-cover", withExtension: "png") }

    static func url(forResource name: String, withExtension ext: String?, subdirectory: String? = nil) -> URL? {
        let mainURL = Bundle.main.bundleURL
        if mainURL.pathExtension.lowercased() == "app" {
            let resources = mainURL.appendingPathComponent("Contents/Resources", isDirectory: true)
            // A missing packaged asset returns nil; do not fall through to the
            // developer's absolute SwiftPM path, even when the bundle is damaged.
            return existingURL(name: name, ext: ext, subdirectory: subdirectory,
                               roots: [resources.appendingPathComponent("Wisp_Wisp.bundle", isDirectory: true), resources])
        }
        #if SWIFT_PACKAGE
        // Only unpackaged SwiftPM runs may use the generated development accessor.
        return existingURL(name: name, ext: ext, subdirectory: subdirectory, roots: [Bundle.module.bundleURL])
        #else
        return existingURL(name: name, ext: ext, subdirectory: subdirectory, roots: [mainURL])
        #endif
    }

    private static func existingURL(name: String, ext: String?, subdirectory: String?, roots: [URL]) -> URL? {
        for root in roots {
            var candidate = root
            if let subdirectory { candidate.appendPathComponent(subdirectory, isDirectory: true) }
            candidate.appendPathComponent(name)
            if let ext, !ext.isEmpty { candidate.appendPathExtension(ext) }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }
}
