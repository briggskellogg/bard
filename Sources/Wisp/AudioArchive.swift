import Foundation
import Darwin
import WispCore

/// Expands an ordinary downloaded album into a private, disposable directory.
/// The caller owns the returned directory and removes it after importing audio.
enum AudioArchive {
    static func expand(_ url: URL) async throws -> URL {
        let operation = Task.detached(priority: .userInitiated) {
            try expandSynchronously(url)
        }
        return try await withTaskCancellationHandler(operation: {
            try await operation.value
        }, onCancel: {
            operation.cancel()
        })
    }

    private static func expandSynchronously(_ source: URL) throws -> URL {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()

        let manager = FileManager.default
        let sourceValues = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard source.isFileURL, sourceValues.isRegularFile == true, sourceValues.isSymbolicLink != true else {
            throw ArchiveError.invalidFile
        }
        // A normal ZIP32 audio download is below this bound. Check before copying
        // so an arbitrary input cannot fill the temporary volume before preflight.
        guard let size = sourceValues.fileSize, size >= 0, UInt64(size) <= 5 * 1024 * 1024 * 1024 else {
            throw ZIPPreflight.Failure.limit
        }

        let root = manager.temporaryDirectory.appendingPathComponent("Wisp-Archive-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var succeeded = false
        defer { if !succeeded { try? manager.removeItem(at: root) } }

        // Validate and extract the same owned copy, even if the user's download
        // changes while import is running. No audio is read into a single buffer.
        let archive = root.appendingPathComponent(".source.zip")
        try manager.copyItem(at: source, to: archive)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archive.path)
        try Task.checkCancellation()
        let report: ZIPPreflight.Report
        do {
            let mapped = try Data(contentsOf: archive, options: .mappedIfSafe)
            report = try ZIPPreflight.validate(mapped)
        }

        let destination = root.appendingPathComponent("Files", isDirectory: true)
        try manager.createDirectory(at: destination, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let inventory = Inventory(report: report)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // Do not restore archive-supplied ACLs, resource forks, or extended
        // metadata. Quarantine is explicitly preserved; it is never stripped.
        process.arguments = ["-x", "-k", "--norsrc", "--noextattr", "--noacl", "--qtn", archive.path, destination.path]
        process.currentDirectoryURL = root
        process.standardInput = FileHandle.nullDevice
        // An archive can cause unbounded diagnostics. Discard both streams
        // instead of accumulating a Pipe or temporary log in memory/on disk.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        defer { terminateIfNeeded(process) }

        try process.run()
        let deadline = Date().addingTimeInterval(15 * 60)
        while process.isRunning {
            try Task.checkCancellation()
            guard Date() < deadline else { throw ArchiveError.timedOut }
            // Declared sizes were bounded in preflight. Check actual output too,
            // so a dishonest compressed stream cannot expand without a bound.
            try inspect(destination, inventory: inventory, complete: false)
            Thread.sleep(forTimeInterval: 0.15)
        }
        process.waitUntilExit()
        try Task.checkCancellation()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw ArchiveError.extraction
        }
        try inspect(destination, inventory: inventory, complete: true)
        try manager.removeItem(at: archive)
        succeeded = true
        return root
    }

    private struct Inventory {
        let files: [String: ZIPPreflight.Entry]
        let directories: Set<String>
        let totalBytes: UInt64

        init(report: ZIPPreflight.Report) {
            var files: [String: ZIPPreflight.Entry] = [:]
            var directories = Set<String>()
            for entry in report.entries {
                let key = entry.canonicalPath
                if entry.isDirectory { directories.insert(key) }
                else { files[key] = entry }
                let parts = key.split(separator: "/")
                if parts.count > 1 {
                    for depth in 1..<parts.count {
                        directories.insert(parts.prefix(depth).joined(separator: "/"))
                    }
                }
            }
            self.files = files
            self.directories = directories
            totalBytes = report.uncompressedBytes
        }
    }

    private static func inspect(_ root: URL, inventory: Inventory, complete: Bool) throws {
        let manager = FileManager.default
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = resolvedRoot.path + "/"
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        var enumerationError: Error?
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, error in
            enumerationError = error
            return false
        }) else { throw ArchiveError.extraction }
        var total: UInt64 = 0
        var filesSeen = Set<String>()
        var pathsSeen = Set<String>()

        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true else { throw ZIPPreflight.Failure.symbolicLink }
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard resolved.hasPrefix(rootPath) else { throw ZIPPreflight.Failure.unsafePath }
            let relative = String(resolved.dropFirst(rootPath.count))
            let key = ZIPPreflight.canonicalPath(relative)
            guard pathsSeen.insert(key).inserted else { throw ZIPPreflight.Failure.conflictingPaths }

            if values.isDirectory == true {
                guard inventory.directories.contains(key) else { throw ZIPPreflight.Failure.unsafePath }
            } else if values.isRegularFile == true {
                guard let entry = inventory.files[key], let size = values.fileSize, size >= 0 else {
                    throw ZIPPreflight.Failure.unsafePath
                }
                let bytes = UInt64(size)
                guard bytes <= entry.uncompressedBytes,
                      total <= inventory.totalBytes,
                      bytes <= inventory.totalBytes - total else { throw ZIPPreflight.Failure.limit }
                if complete && bytes != entry.uncompressedBytes { throw ZIPPreflight.Failure.malformed }
                total += bytes
                filesSeen.insert(key)
            } else { throw ZIPPreflight.Failure.symbolicLink }
        }
        if let enumerationError { throw enumerationError }
        if complete {
            for (key, entry) in inventory.files where !filesSeen.contains(key) {
                // ditto can consume or omit AppleDouble resource-fork records.
                // They are not audio and metadata preservation is disabled.
                guard URL(fileURLWithPath: entry.path).lastPathComponent.hasPrefix("._") else {
                    throw ZIPPreflight.Failure.malformed
                }
            }
        }
    }

    private static func terminateIfNeeded(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }

    private enum ArchiveError: LocalizedError {
        case invalidFile
        case extraction
        case timedOut

        var errorDescription: String? {
            switch self {
            case .invalidFile: return "Choose a downloaded ZIP file to import."
            case .extraction: return "This ZIP archive could not be extracted. Download it again, or extract it in Finder and import its audio files."
            case .timedOut: return "This archive took too long to extract. Extract it in Finder first, then import its audio files."
            }
        }
    }
}
