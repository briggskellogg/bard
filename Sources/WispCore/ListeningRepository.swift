import Foundation

/// Never replaces unreadable history or another instance's more recent writes.
public final class ListeningRepository: @unchecked Sendable {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("Listening.json") }
    private let lock = NSRecursiveLock()
    private var loaded = false
    private var expectedData: Data?

    public init(directory: URL) { self.directory = directory.standardizedFileURL }

    public func load(now: Date = Date()) throws -> ListeningHistory {
        lock.lock(); defer { lock.unlock() }
        loaded = false
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            loaded = true
            expectedData = nil
            return ListeningHistory(trackingStartedAt: now)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let history = try Self.decode(data)
            expectedData = data
            loaded = true
            return history
        } catch let error as ListeningHistoryError { throw error }
        catch { throw ListeningHistoryError.unreadable(error.localizedDescription) }
    }

    public func save(_ history: ListeningHistory) throws {
        lock.lock(); defer { lock.unlock() }
        guard loaded else { throw ListeningHistoryError.notLoaded }
        let data = try Self.encode(history)
        let current = FileManager.default.fileExists(atPath: fileURL.path) ? try Data(contentsOf: fileURL) : nil
        guard current == expectedData else {
            loaded = false
            throw ListeningHistoryError.changedExternally
        }
        try data.write(to: fileURL, options: .atomic)
        expectedData = data
    }

    public static func encode(_ history: ListeningHistory) throws -> Data {
        try history.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(history)
    }

    public static func decode(_ data: Data) throws -> ListeningHistory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let history = try decoder.decode(ListeningHistory.self, from: data)
        try history.validate()
        return history
    }
}
