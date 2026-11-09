import AppKit
import Foundation
import CoreFoundation
import Darwin

/// Runs before Wisp creates a library or playback store. Installer copies may
/// hand off only to a verified, same-or-newer copy already in Applications.
enum MountedInstallerHandoff {
    static let identifier = "com.briggskellogg.wisp"
    static let cleanupArgument = "--wisp-finish-installer-handoff"
    static let installedPath = "/Applications/Bard.app"
    static let legacyInstalledPath = "/Applications/Wisp.app"

    static func isInstalledPath(_ path: String) -> Bool {
        path == installedPath || path == legacyInstalledPath
    }

    struct Release: Codable, Equatable {
        let version: String
        let build: String
        var valid: Bool { Self.parts(version) != nil && Self.parts(build) != nil }
        func isAtLeast(_ other: Release) -> Bool {
            guard valid, other.valid else { return false }
            let versionOrder = Self.compare(Self.parts(version)!, Self.parts(other.version)!)
            return versionOrder > 0 || (versionOrder == 0 && Self.compare(Self.parts(build)!, Self.parts(other.build)!) >= 0)
        }
        private static func parts(_ value: String) -> [UInt64]? {
            let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
            guard !pieces.isEmpty, pieces.count <= 6 else { return nil }
            let parsed = pieces.compactMap { piece -> UInt64? in
                guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
                return UInt64(piece)
            }
            return parsed.count == pieces.count ? parsed : nil
        }
        private static func compare(_ a: [UInt64], _ b: [UInt64]) -> Int {
            for index in 0..<max(a.count, b.count) {
                let x = index < a.count ? a[index] : 0
                let y = index < b.count ? b[index] : 0
                if x != y { return x > y ? 1 : -1 }
            }
            return 0
        }
    }
    struct App: Codable, Equatable {
        let path: String
        let executable: String
        let bundleID: String
        let release: Release
        let fileIdentity: String
    }
    struct DiskImage: Codable, Equatable {
        let mount: String
        let image: String
    }
    struct Parent: Codable, Equatable {
        let pid: Int32
        let start: String
        let executable: String
    }
    struct Ticket: Codable, Equatable {
        let created: Date
        let parent: Parent
        let source: App
        let installed: App
        let disk: DiskImage
    }
    enum Decision: Equatable {
        case normal
        case explain(String)
        case forward(App, DiskImage)
    }
    enum ParentState { case running, exited, different }

    static func contains(_ path: String, in directory: String) -> Bool {
        path == directory || path.hasPrefix(directory.hasSuffix("/") ? directory : directory + "/")
    }
    static func decision(source: App, images: [DiskImage], installed: App?, trusted: Bool,
                         installerLocation: Bool = false) -> Decision {
        guard source.bundleID == identifier else { return .normal }
        guard let disk = images.filter({ contains(source.path, in: $0.mount) }).max(by: { $0.mount.count < $1.mount.count }) else {
            return installerLocation
                ? .explain("Bard could not verify this installer disk. Eject it and open Bard from Applications. If Bard is not installed yet, drag it into Applications first.")
                : .normal
        }
        guard source.release.valid else { return .explain("This installer has invalid version information. Download a fresh copy of Bard.") }
        guard let installed, trusted, installed.bundleID == identifier,
              isInstalledPath(installed.path),
              !images.contains(where: { contains(installed.path, in: $0.mount) }),
              contains(installed.executable, in: installed.path + "/Contents/MacOS") else {
            return .explain("Drag Bard into Applications, eject this disk, then open Bard from Applications.")
        }
        guard installed.release.isAtLeast(source.release) else {
            return .explain("This disk contains a newer Bard. Quit the installed copy, drag this Bard into Applications and replace the older copy, then eject the disk.")
        }
        return .forward(installed, disk)
    }

    /// Retarget existing tiles of this bundle, including the former Wisp name.
    /// All unrelated keys, tile order, and applications survive.
    static func updatedDockEntries(_ original: [[String: Any]], destination: URL, bookmark: Data,
                                   bookmarkIsCurrent: ([String: Any]) -> Bool) -> [[String: Any]] {
        var entries = original
        for index in entries.indices {
            guard var data = entries[index]["tile-data"] as? [String: Any],
                  data["bundle-identifier"] as? String == identifier,
                  var file = data["file-data"] as? [String: Any] else { continue }
            let oldURL = (file["_CFURLString"] as? String).flatMap(URL.init(string:))
            if oldURL?.standardizedFileURL.path != destination.path || !bookmarkIsCurrent(data) {
                file["_CFURLString"] = destination.absoluteString
                data["file-data"] = file; data["book"] = bookmark
            }
            data["file-label"] = "Bard"
            entries[index]["tile-data"] = data
        }
        return entries
    }

    @MainActor
    protocol CleanupEffects {
        func validate(_ ticket: Ticket) -> Bool
        func parentState(_ parent: Parent) -> ParentState
        func pause()
        func installedIsRunning(_ app: App) -> Bool
        func repairReferences(_ ticket: Ticket) -> Bool
        func detach(_ disk: DiskImage) -> Bool
        func log(_ message: String)
    }
    /// The worker never signals the parent or any music process. A reused PID
    /// is a rejection, not a reason to kill or wait for an unrelated process.
    @MainActor
    static func cleanup(_ ticket: Ticket, effects: CleanupEffects) -> Bool {
        guard effects.validate(ticket) else { effects.log("Rejected invalid handoff ticket."); return false }
        var exited = false
        for _ in 0..<120 {
            switch effects.parentState(ticket.parent) {
            case .exited: exited = true
            case .different: effects.log("Parent identity changed; no cleanup performed."); return false
            case .running: effects.pause()
            }
            if exited { break }
        }
        guard exited else { effects.log("Installer process is still running; cleanup deferred."); return false }
        guard effects.validate(ticket), effects.installedIsRunning(ticket.installed), effects.repairReferences(ticket) else {
            effects.log("Installed launch/reference verification failed; installer left mounted."); return false
        }
        for attempt in 1...4 {
            guard effects.validate(ticket) else { effects.log("Handoff identity changed; no further cleanup performed."); return false }
            if effects.detach(ticket.disk) { effects.log("Installed Bard active; installer disk ejected normally."); return true }
            effects.log("Installer eject attempt \(attempt) was busy or unsuccessful.")
            effects.pause()
        }
        effects.log("Installer remains mounted because ordinary eject failed; no force eject used.")
        return false
    }

    /// True means the launcher must return without initializing SwiftUI stores.
    @MainActor
    static func runPreflight(arguments: [String] = CommandLine.arguments) -> Bool {
        let runtime = Runtime()
        if arguments.dropFirst().contains(cleanupArgument) {
            guard arguments.count == 3, arguments[1] == cleanupArgument,
                  let ticket = runtime.readTicket(arguments[2]) else { runtime.log("Rejected cleanup invocation."); return true }
            defer { runtime.removeTicket(arguments[2]) }
            _ = cleanup(ticket, effects: runtime)
            return true
        }
        guard let source = runtime.app(at: Bundle.main.bundleURL.path), source.bundleID == identifier else {
            if runtime.isInstallerLocation(Bundle.main.bundleURL.path) {
                runtime.explain("This installer could not be verified. Eject it and open Bard from Applications.")
                return true
            }
            return false
        }
        // Installed launches do no disk probing, Dock mutation or registration.
        if isInstalledPath(source.path) { return false }
        let images = runtime.diskImages()
        // Prefer Bard. The old path is accepted only as a compatibility fallback;
        // identity, signature and same-or-newer version checks still apply.
        let installed = runtime.app(at: installedPath) ?? runtime.app(at: legacyInstalledPath)
        let trusted = installed.map(runtime.trusted) ?? false
        switch decision(source: source, images: images, installed: installed, trusted: trusted,
                        installerLocation: runtime.isInstallerLocation(source.path)) {
        case .normal: return false
        case .explain(let message): runtime.explain(message); return true
        case .forward(let installed, let disk):
            guard let parent = runtime.currentParent(source), runtime.openInstalled(installed) else {
                runtime.explain("Bard could not open its installed copy. Open Applications and start Bard there. The installer copy has not opened your library.")
                return true
            }
            let ticket = Ticket(created: Date(), parent: parent, source: source, installed: installed, disk: disk)
            if !runtime.startCleanup(ticket) { runtime.log("Installed Bard opened, but automatic disk cleanup could not start.") }
            return true
        }
    }

    @MainActor
    final class Runtime: CleanupEffects {
        private let files = FileManager.default
        private var tokenDirectory: URL { files.temporaryDirectory.appendingPathComponent("WispInstallerHandoff", isDirectory: true) }
        private var logURL: URL { files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Wisp/InstallerHandoff.log") }

        func app(at path: String) -> App? {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            // Read Info.plist afresh: Bundle can cache metadata across replacement.
            guard url.path == url.resolvingSymlinksInPath().path,
                  let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
                  let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let name = info["CFBundleExecutable"] as? String, !name.isEmpty,
                  name == URL(fileURLWithPath: name).lastPathComponent,
                  let id = info["CFBundleIdentifier"] as? String,
                  let version = info["CFBundleShortVersionString"] as? String,
                  let build = info["CFBundleVersion"] as? String else { return nil }
            let executable = url.appendingPathComponent("Contents/MacOS").appendingPathComponent(name)
            guard executable.path == executable.resolvingSymlinksInPath().path,
                  files.isExecutableFile(atPath: executable.path),
                  let bundleIdentity = identity(url.path), let executableIdentity = identity(executable.path) else { return nil }
            return App(path: url.path, executable: executable.path, bundleID: id,
                       release: Release(version: version, build: build), fileIdentity: bundleIdentity + ":" + executableIdentity)
        }
        private func identity(_ path: String) -> String? {
            var value = stat()
            guard lstat(path, &value) == 0 else { return nil }
            return "\(value.st_dev):\(value.st_ino):\(value.st_size):\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec):\(value.st_ctimespec.tv_sec):\(value.st_ctimespec.tv_nsec)"
        }
        func isInstallerLocation(_ path: String) -> Bool {
            let components = URL(fileURLWithPath: path).pathComponents
            if components.count > 2, components[1] == "Volumes",
               ["Bard", "Wisp"].contains(where: { components[2] == $0 || components[2].hasPrefix($0 + " ") || components[2].hasPrefix($0 + "-") }) { return true }
            let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeIsReadOnlyKey])
            return values?.volumeIsReadOnly == true
        }
        func trusted(_ app: App) -> Bool {
            app.bundleID == identifier && app.release.valid && command("/usr/bin/codesign", ["--verify", "--deep", "--strict=symlinks", app.path]).status == 0
        }
        func diskImages() -> [DiskImage] {
            let result = command("/usr/bin/hdiutil", ["info", "-plist"])
            guard result.status == 0,
                  let root = try? PropertyListSerialization.propertyList(from: result.data, format: nil) as? [String: Any],
                  let images = root["images"] as? [[String: Any]] else { return [] }
            return images.flatMap { image -> [DiskImage] in
                guard let path = image["image-path"] as? String, path.hasPrefix("/"),
                      URL(fileURLWithPath: path).pathExtension.lowercased() == "dmg",
                      let entities = image["system-entities"] as? [[String: Any]] else { return [] }
                return entities.compactMap { entity in
                    guard let mount = entity["mount-point"] as? String, mount.hasPrefix("/"), mount != "/" else { return nil }
                    return DiskImage(mount: URL(fileURLWithPath: mount).standardizedFileURL.path,
                                     image: URL(fileURLWithPath: path).standardizedFileURL.path)
                }
            }
        }
        func currentParent(_ source: App) -> Parent? {
            let pid = ProcessInfo.processInfo.processIdentifier
            guard let start = processStart(pid), !start.isEmpty else { return nil }
            return Parent(pid: pid, start: start, executable: source.executable)
        }
        func processStart(_ pid: Int32) -> String? {
            guard pid > 1 else { return nil }
            let result = command("/bin/ps", ["-p", String(pid), "-o", "lstart="])
            guard result.status == 0, let text = String(data: result.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
        func parentState(_ parent: Parent) -> ParentState {
            guard kill(parent.pid, 0) == 0 else { return errno == ESRCH ? .exited : .different }
            guard processStart(parent.pid) == parent.start,
                  let running = NSRunningApplication(processIdentifier: parent.pid),
                  running.executableURL?.standardizedFileURL.path == parent.executable else { return .different }
            return running.isTerminated ? .exited : .running
        }
        func installedIsRunning(_ app: App) -> Bool {
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains {
                $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated && $0.bundleURL?.standardizedFileURL.path == app.path
                    && $0.executableURL?.standardizedFileURL.path == app.executable
            }
        }
        func openInstalled(_ app: App) -> Bool {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { !$0.isTerminated && $0.bundleURL?.path == app.path }) {
                running.activate(options: []); return true
            }
            // -n prevents Launch Services from merely activating this disk copy.
            guard command("/usr/bin/open", ["-n", "-a", app.path]).status == 0 else { return false }
            for _ in 0..<80 {
                if installedIsRunning(app) { return true }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            return false
        }
        func explain(_ message: String) {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Open Bard from Applications"
            alert.informativeText = message
            alert.addButton(withTitle: "Show Applications")
            alert.addButton(withTitle: "Quit")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
            }
        }
        func startCleanup(_ ticket: Ticket) -> Bool {
            do {
                if !files.fileExists(atPath: tokenDirectory.path) {
                    try files.createDirectory(at: tokenDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                }
                guard safeTokenDirectory() else { return false }
                let token = tokenDirectory.appendingPathComponent(UUID().uuidString + ".json")
                let data = try JSONEncoder().encode(ticket)
                guard files.createFile(atPath: token.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return false }
                let worker = Process(); worker.executableURL = URL(fileURLWithPath: ticket.installed.executable)
                worker.arguments = [cleanupArgument, token.path]
                worker.standardOutput = FileHandle.nullDevice; worker.standardError = FileHandle.nullDevice
                do { try worker.run(); return true } catch { try? files.removeItem(at: token); throw error }
            } catch { log("Could not start installer cleanup: \(error.localizedDescription)"); return false }
        }
        private func safeTokenDirectory() -> Bool {
            guard let attrs = try? files.attributesOfItem(atPath: tokenDirectory.path) else { return false }
            return attrs[.type] as? FileAttributeType == .typeDirectory
                && (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid()
                && (((attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077) == 0
        }
        func readTicket(_ path: String) -> Ticket? {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard safeTokenDirectory(), url.deletingLastPathComponent().path == tokenDirectory.path,
                  url.pathExtension == "json", UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
                  let attrs = try? files.attributesOfItem(atPath: path), attrs[.type] as? FileAttributeType == .typeRegular,
                  (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
                  (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                  ((attrs[.size] as? NSNumber)?.intValue ?? Int.max) <= 16_384,
                  let data = try? Data(contentsOf: url), let ticket = try? JSONDecoder().decode(Ticket.self, from: data),
                  Date().timeIntervalSince(ticket.created) >= -2, Date().timeIntervalSince(ticket.created) < 120 else { return nil }
            return ticket
        }
        func removeTicket(_ path: String) {
            guard URL(fileURLWithPath: path).deletingLastPathComponent().path == tokenDirectory.path else { return }
            try? files.removeItem(atPath: path)
        }
        func validate(_ ticket: Ticket) -> Bool {
            guard ticket.parent.pid > 1, ticket.parent.pid != ProcessInfo.processInfo.processIdentifier,
                  !ticket.parent.start.isEmpty, ticket.parent.executable == ticket.source.executable,
                  let own = app(at: Bundle.main.bundleURL.path), own == ticket.installed,
                  let source = app(at: ticket.source.path), source == ticket.source,
                  trusted(own), diskImages().contains(ticket.disk) else { return false }
            return decision(source: source, images: [ticket.disk], installed: own, trusted: true) == .forward(own, ticket.disk)
        }
        func pause() { Thread.sleep(forTimeInterval: 0.25) }
        func repairReferences(_ ticket: Ticket) -> Bool {
            guard validate(ticket), installedIsRunning(ticket.installed) else { return false }
            let registrar = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            let unregister = command(registrar, ["-u", ticket.source.path]).status
            let register = command(registrar, ["-f", ticket.installed.path]).status
            guard register == 0 else { log("Installed app registration failed."); return false }
            if unregister != 0 { log("Installer registration was already absent or could not be removed.") }
            return repairDock(destination: URL(fileURLWithPath: ticket.installed.path))
        }
        private func repairDock(destination: URL) -> Bool {
            let domain = "com.apple.dock"
            guard let preferences = UserDefaults(suiteName: domain), let before = preferences.persistentDomain(forName: domain) else { return true }
            do {
                let bookmark = try destination.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                var replacements: [String: [[String: Any]]] = [:]
                for group in ["persistent-apps", "recent-apps"] {
                    guard let original = before[group] as? [[String: Any]] else { continue }
                    let entries = updatedDockEntries(original, destination: destination, bookmark: bookmark) { data in
                        var stale = true
                        let resolved = (data["book"] as? Data).flatMap { try? URL(resolvingBookmarkData: $0, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) }
                        return resolved?.standardizedFileURL.path == destination.path && !stale
                    }
                    if !NSArray(array: entries).isEqual(to: original) { replacements[group] = entries }
                }
                guard !replacements.isEmpty else { return true }
                let backup = logURL.deletingLastPathComponent().appendingPathComponent("InstallerDockBackup-\(UUID().uuidString).plist")
                try files.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                try PropertyListSerialization.data(fromPropertyList: before, format: .binary, options: 0).write(to: backup, options: .atomic)
                for (group, entries) in replacements { CFPreferencesSetValue(group as CFString, entries as CFArray, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) }
                guard CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return false }
                // Reload only this user's existing Dock; no app or system caches.
                for dock in NSRunningApplication.runningApplications(withBundleIdentifier: domain) { dock.terminate() }
                log("Repaired existing Bard/Wisp Dock references; unrelated tiles preserved.")
                return true
            } catch { log("Dock reference repair failed: \(error.localizedDescription)"); return false }
        }
        func detach(_ disk: DiskImage) -> Bool {
            let images = diskImages()
            guard images.contains(disk) else { return !images.contains(where: { $0.mount == disk.mount }) && !files.fileExists(atPath: disk.mount) }
            return command("/usr/bin/hdiutil", ["detach", disk.mount], timeout: 8).status == 0
        }
        func log(_ message: String) {
            let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
            try? files.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let old = (try? Data(contentsOf: logURL)) ?? Data()
            var output = Data(old.suffix(64 * 1024)); output.append(Data(line.utf8))
            try? output.write(to: logURL, options: .atomic)
        }
        private final class Capture: @unchecked Sendable {
            let lock = NSLock(); var data = Data()
            func set(_ value: Data) { lock.lock(); data = value; lock.unlock() }
            func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
        }
        private func command(_ path: String, _ arguments: [String], timeout: TimeInterval = 10) -> (status: Int32, data: Data) {
            let process = Process(), pipe = Pipe(), capture = Capture(), group = DispatchGroup()
            process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
            process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return (-1, Data()) }
            group.enter()
            DispatchQueue.global().async { capture.set(pipe.fileHandleForReading.readDataToEndOfFile()); group.leave() }
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if process.isRunning { process.terminate(); return (-1, Data()) }
            group.wait()
            return (process.terminationStatus, capture.get())
        }
    }
}
