import Foundation

/// Owns only the index. Media is copied before a successful commit and never removed here.
public final class LibraryRepository: @unchecked Sendable {
    public let directory: URL
    public var manifestURL: URL { directory.appendingPathComponent("Library.json") }
    public var previousURL: URL { directory.appendingPathComponent("Library.previous.json") }
    public var mediaDirectory: URL { directory.appendingPathComponent("Media", isDirectory: true) }
    public var artworkDirectory: URL { directory.appendingPathComponent("Artwork", isDirectory: true) }
    private let lock = NSRecursiveLock()
    private let manager = FileManager.default
    private var loaded = false
    private var expectedData: Data?

    public init(directory: URL) { self.directory = directory.standardizedFileURL }

    public func load() throws -> LibraryDocument {
        lock.lock()
        defer { lock.unlock() }
        loaded = false
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        try manager.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
        guard manager.fileExists(atPath: manifestURL.path) else {
            let hasMedia = !(try manager.contentsOfDirectory(atPath: mediaDirectory.path)).isEmpty
            let hasArtwork = !(try manager.contentsOfDirectory(atPath: artworkDirectory.path)).isEmpty
            guard !hasMedia, !hasArtwork, !manager.fileExists(atPath: previousURL.path) else { throw LibraryError.missingManifest }
            loaded = true
            expectedData = nil
            return LibraryDocument()
        }
        do {
            let data = try Data(contentsOf: manifestURL)
            let document = try Self.decode(data)
            expectedData = data
            loaded = true
            return document
        } catch let error as LibraryError { throw error }
        catch { throw LibraryError.unreadable(error.localizedDescription) }
    }

    public func save(_ document: LibraryDocument) throws {
        lock.lock()
        defer { lock.unlock() }
        guard loaded else { throw LibraryError.notLoaded }
        try document.validate()
        let data = try Self.encode(document)
        let current = manager.fileExists(atPath: manifestURL.path) ? try Data(contentsOf: manifestURL) : nil
        guard current == expectedData else {
            loaded = false
            throw LibraryError.changedExternally
        }
        if let current {
            // The previous index is always a complete, validated state, never a failed write.
            _ = try Self.decode(current)
            try current.write(to: previousURL, options: .atomic)
        }
        try data.write(to: manifestURL, options: .atomic)
        expectedData = data
    }

    public func recoverPrevious() throws -> LibraryDocument {
        lock.lock()
        defer { lock.unlock() }
        guard manager.fileExists(atPath: previousURL.path),
              let data = try? Data(contentsOf: previousURL),
              let document = try? Self.decode(data) else { throw LibraryError.noRecovery }
        if manager.fileExists(atPath: manifestURL.path) {
            let preserved = directory.appendingPathComponent("Library-preserved-\(UUID().uuidString).json")
            try manager.copyItem(at: manifestURL, to: preserved)
        }
        try data.write(to: manifestURL, options: .atomic)
        expectedData = data
        loaded = true
        return document
    }

    public static func encode(_ document: LibraryDocument) throws -> Data {
        try document.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> LibraryDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let document = try decoder.decode(LibraryDocument.self, from: data)
        try document.validate()
        return document
    }
}
