import AppKit
import CryptoKit
import Darwin
import Foundation

// Finder's supported per-file custom icon prevents macOS 26 from placing an
// irregular legacy application icon on its automatic rounded-rectangle canvas.
// This changes only metadata outside the signed Contents directory.
@main
struct WispCustomIcon {
    struct Manifest: Codable {
        let format: Int
        let signedContents: [String: String]
        let customIconResourceForkSHA256: String
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func signedContents(of app: URL) throws -> [String: String] {
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        var result: [String: String] = [:]
        // Build relative paths from names instead of absolute URL strings:
        // Foundation normalizes /private/tmp differently across its file APIs.
        func walk(_ directory: URL, prefix: String) throws {
            let files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys, options: [])
            for file in files {
                let relativePath = prefix + file.lastPathComponent
                let values = try file.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true {
                    let target = try FileManager.default.destinationOfSymbolicLink(atPath: file.path)
                    result[relativePath] = "symlink:" + digest(Data(target.utf8))
                } else if values.isRegularFile == true {
                    result[relativePath] = "sha256:" + digest(try Data(contentsOf: file))
                } else if values.isDirectory == true {
                    result[relativePath] = "directory"
                    try walk(file, prefix: relativePath + "/")
                } else {
                    throw Failure("Unexpected signed Contents entry: \(relativePath)")
                }
            }
        }
        try walk(contents, prefix: "")
        guard result["MacOS/Wisp"] != nil, result["_CodeSignature/CodeResources"] != nil,
              result["Resources/Wisp.icns"] != nil else {
            throw Failure("Expected signed Wisp executable, seal, or icon is missing")
        }
        return result
    }

    static func attribute(_ name: String, at url: URL) throws -> Data {
        let count = url.path.withCString { getxattr($0, name, nil, 0, 0, 0) }
        guard count > 0 else { throw Failure("Missing \(name) on \(url.lastPathComponent)") }
        var value = Data(count: count)
        let read = value.withUnsafeMutableBytes { bytes in
            url.path.withCString { getxattr($0, name, bytes.baseAddress, count, 0, 0) }
        }
        guard read == count else { throw Failure("Cannot read \(name)") }
        return value
    }

    static func customIconHash(of app: URL) throws -> String {
        let finderInfo = try attribute("com.apple.FinderInfo", at: app)
        // Finder's kHasCustomIcon flag is 0x0400 in the big-endian flags field.
        guard finderInfo.count == 32, finderInfo[8] & 0x04 != 0 else {
            throw Failure("Finder custom-icon flag is missing")
        }
        let iconFile = app.appendingPathComponent("Icon\r")
        guard FileManager.default.fileExists(atPath: iconFile.path) else {
            throw Failure("Finder custom-icon file is missing")
        }
        return digest(try attribute("com.apple.ResourceFork", at: iconFile))
    }

    static func verify(_ app: URL, manifest: Manifest) throws {
        guard manifest.format == 1 else { throw Failure("Unsupported manifest format") }
        guard try signedContents(of: app) == manifest.signedContents else {
            throw Failure("Signed Contents changed")
        }
        guard try customIconHash(of: app) == manifest.customIconResourceForkSHA256 else {
            throw Failure("Custom-icon resource fork changed")
        }
        print("Verified \(manifest.signedContents.count) signed Contents entries and the exact custom-icon resource fork")
    }

    @MainActor
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("Wisp custom icon: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    @MainActor
    static func run() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4, ["apply", "verify"].contains(arguments[1]) else {
            throw Failure("Usage: wisp-custom-icon apply|verify APP_PATH MANIFEST_PATH")
        }
        let app = URL(fileURLWithPath: arguments[2], isDirectory: true).standardizedFileURL
        let manifestURL = URL(fileURLWithPath: arguments[3])
        guard app.pathExtension == "app" else { throw Failure("Expected an app bundle") }
        let info = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: info, options: [], format: nil) as? [String: Any]
        guard plist?["CFBundleIdentifier"] as? String == "com.briggskellogg.wisp" else {
            throw Failure("Refusing to customize a non-Wisp bundle")
        }
        if arguments[1] == "verify" {
            try verify(app, manifest: JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL)))
            return
        }

        guard !FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw Failure("Refusing to replace an existing integrity manifest")
        }
        let before = try signedContents(of: app)
        let iconURL = app.appendingPathComponent("Contents/Resources/Wisp.icns")
        guard let icon = NSImage(contentsOf: iconURL), icon.isValid else {
            throw Failure("Cannot read the original transparent Wisp icon")
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard NSWorkspace.shared.setIcon(icon, forFile: app.path, options: []) else {
            throw Failure("macOS could not assign Wisp's custom icon")
        }
        let manifest = Manifest(format: 1, signedContents: before,
                                customIconResourceForkSHA256: try customIconHash(of: app))
        try verify(app, manifest: manifest)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        print("Applied the original transparent mark using Finder's per-app custom icon")
    }
}
