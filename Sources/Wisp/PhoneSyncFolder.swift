import Foundation
import WispCore

/// Naming and an explicit move of a user-owned shared folder. The wire format
/// stays unchanged so existing phones continue to read the same library.
enum PhoneSyncFolder {
    static let name = "Wisp"
    static let legacyName = "Wisp Phone Sync"

    enum Failure: LocalizedError {
        case occupied, wrongParent, missingLibrary, rollback(URL)
        var errorDescription: String? {
            switch self {
            case .occupied: return "A folder or file named Wisp already exists there. Nothing was changed. Choose a different containing folder or keep your current connection."
            case .wrongParent: return "Choose the folder that contains your current Bard library. Nothing was changed."
            case .missingLibrary: return "This folder is not the shared library connected to this Mac. Nothing was changed."
            case .rollback(let folder): return "The folder is now at \(folder.path), but its saved connection could not be updated. Choose that folder again to reconnect. Your songs were not deleted."
            }
        }
    }

    static func exists(_ url: URL) throws -> Bool {
        do { _ = try FileManager.default.attributesOfItem(atPath: url.path); return true }
        catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile { return false }
    }

    static func destination(in selected: URL, libraryID: UUID) throws -> URL {
        if selected.lastPathComponent == name || selected.lastPathComponent == legacyName { return selected }
        // Selecting a previously connected custom folder is also supported.
        if try exists(selected.appendingPathComponent("Library.json")) {
            try requireOwned(selected, libraryID: libraryID)
            return selected
        }
        let current = selected.appendingPathComponent(name, isDirectory: true)
        let legacy = selected.appendingPathComponent(legacyName, isDirectory: true)
        if try exists(current) {
            // An implicitly discovered Wisp folder is never claimed merely
            // because it is empty; it could be another application's container.
            do { try requireOwned(current, libraryID: libraryID) }
            catch { throw Failure.occupied }
            return current
        }
        if try exists(legacy) {
            try requireOwned(legacy, libraryID: libraryID)
            return legacy
        }
        return current
    }

    static func requireOwned(_ folder: URL, libraryID: UUID) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: folder.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw Failure.missingLibrary }
        let manifest = folder.appendingPathComponent("Library.json")
        let properties = try FileManager.default.attributesOfItem(atPath: manifest.path)
        guard properties[.type] as? FileAttributeType == .typeRegular,
              let size = properties[.size] as? NSNumber, size.intValue > 0,
              size.intValue <= 16 * 1024 * 1024 else { throw Failure.missingLibrary }
        let handle = try FileHandle(forReadingFrom: manifest)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: 16 * 1024 * 1024 + 1) ?? Data()
        guard bytes.count == size.intValue else { throw Failure.missingLibrary }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        let document = try decoder.decode(PhoneLibraryManifest.self, from: bytes)
        guard document.formatVersion == 1, document.sourceLibraryID == libraryID else { throw Failure.missingLibrary }
    }

    /// Caller holds security scope for both the source and its explicitly chosen
    /// parent. A failed move/bookmark renewal leaves the prior folder in place.
    static func rename(_ source: URL, inside parent: URL, libraryID: UUID,
                       bookmark: (URL) throws -> Data) throws -> (url: URL, bookmark: Data) {
        let authorizedParent = parent.standardizedFileURL.resolvingSymlinksInPath()
        let expectedParent = source.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
        guard authorizedParent == expectedParent else { throw Failure.wrongParent }
        let target = authorizedParent.appendingPathComponent(name, isDirectory: true)
        if source.standardizedFileURL == target {
            try requireOwned(source, libraryID: libraryID)
            return (source, try bookmark(source))
        }
        guard try !exists(target) else { throw Failure.occupied }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var failure: NSError?
        var result: Result<(URL, Data), Error>?
        coordinator.coordinate(writingItemAt: source, options: .forMoving,
                               writingItemAt: target, options: [], error: &failure) { old, new in
            result = Result {
                try requireOwned(old, libraryID: libraryID)
                guard try !exists(new) else { throw Failure.occupied }
                try FileManager.default.moveItem(at: old, to: new)
                do {
                    let updated = try bookmark(new)
                    coordinator.item(at: old, didMoveTo: new)
                    return (new, updated)
                } catch {
                    do { try FileManager.default.moveItem(at: new, to: old) }
                    catch { throw Failure.rollback(new) }
                    throw error
                }
            }
        }
        if let result { let value = try result.get(); return (value.0, value.1) }
        throw failure ?? NSError(domain: "WispPhoneSync", code: 1,
                                 userInfo: [NSLocalizedDescriptionKey: "The folder could not be renamed. Nothing was changed."])
    }
}
