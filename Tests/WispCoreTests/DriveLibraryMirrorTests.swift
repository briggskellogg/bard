import XCTest
import Foundation
import CryptoKit
@testable import WispCore

final class DriveLibraryMirrorTests: XCTestCase {
    private var root: URL!
    private var library: URL { root.appendingPathComponent("Mac") }
    private var drive: URL { root.appendingPathComponent("Wisp") }
    private let sourceID = UUID()
    private let fm = FileManager.default
    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("WispDriveTests-\(UUID())")
        try fm.createDirectory(at: library.appendingPathComponent("Media"), withIntermediateDirectories: true)
        try fm.createDirectory(at: library.appendingPathComponent("Artwork"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let root { try? fm.removeItem(at: root) } }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func audio(_ name: String, text: String) throws -> Track {
        let data = Data(text.utf8)
        try data.write(to: library.appendingPathComponent("Media/" + name))
        return Track(title: text, artist: "Artist", fileName: name, fingerprint: hash(data), duration: 4,
                     byteCount: Int64(data.count), origin: "Origin", remix: .basic)
    }
    private func document() throws -> LibraryDocument {
        var a = try audio("a.wav", text: "One")
        let b = try audio("b.mp3", text: "Two")
        a.artworkFileName = "cover.png"
        try Data("COVER".utf8).write(to: library.appendingPathComponent("Artwork/cover.png"))
        return LibraryDocument(tracks: [a, b], playlists: [Playlist(name: "Mixtape", coverFileName: "cover.png", trackIDs: [b.id, a.id])])
    }
    @discardableResult private func publish(_ document: LibraryDocument) throws -> DriveLibraryMirrorResult {
        try DriveLibraryMirror.publish(document: document, libraryDirectory: library, destination: drive, sourceLibraryID: sourceID)
    }
    private func manifestBytes() throws -> Data { try Data(contentsOf: drive.appendingPathComponent(DriveLibraryMirror.manifestName)) }
    private func data(_ path: String) throws -> Data { try Data(contentsOf: drive.appendingPathComponent(path)) }

    func testInitialReadableCopyWithExactBytesMetadataArtworkAndPlaylistOrder() throws {
        let doc = try document(), result = try publish(doc)
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.songCount, 2)
        XCTAssertEqual(result.copiedFileCount, 3)
        XCTAssertEqual(result.reusedFileCount, 0)
        XCTAssertEqual(result.manifest.document, doc)
        XCTAssertEqual(result.manifest.assets.count, 3)
        for asset in result.manifest.assets {
            let parent = asset.kind == .artwork ? "Artwork" : "Media"
            XCTAssertEqual(try data(asset.relativePath), try Data(contentsOf: library.appendingPathComponent(parent + "/" + asset.fileName)))
            XCTAssertEqual(asset.sha256, hash(try data(asset.relativePath)))
            XCTAssertNotNil(asset.destinationStamp)
        }
        XCTAssertTrue(result.manifest.assets[0].relativePath.hasPrefix("Music/Artist/One ["))
        let playlist = try String(decoding: data(result.manifest.playlists[0].relativePath), as: UTF8.self)
        let lines = playlist.components(separatedBy: "\n").filter { $0.hasPrefix("../") }
        XCTAssertEqual(lines, ["../" + result.manifest.assets[1].relativePath, "../" + result.manifest.assets[0].relativePath])
        XCTAssertTrue(fm.fileExists(atPath: drive.appendingPathComponent(DriveLibraryMirror.ownershipName).path))
        XCTAssertTrue(try DriveLibraryMirror.belongsToLibrary(drive, sourceLibraryID: sourceID))
    }
    func testUnchangedCopyDoesNotRewriteManifestOrAudio() throws {
        let doc = try document(), first = try publish(doc), bytes = try manifestBytes()
        let again = try publish(doc)
        XCTAssertFalse(again.changed)
        XCTAssertEqual(again.copiedFileCount, 0)
        XCTAssertEqual(again.reusedFileCount, 3)
        XCTAssertEqual(again.manifest.revision, first.manifest.revision)
        XCTAssertEqual(again.manifest.assets, first.manifest.assets)
        XCTAssertEqual(again.manifest.playlists, first.manifest.playlists)
        XCTAssertEqual(again.publishedAt.timeIntervalSince1970, first.publishedAt.timeIntervalSince1970, accuracy: 0.00001)
        XCTAssertEqual(try manifestBytes(), bytes)
    }
    func testMetadataAndReorderReuseAllAudioAndRefreshM3U() throws {
        var doc = try document()
        let first = try publish(doc)
        doc.tracks[0].title = "Updated"; doc.tracks[0].artist = "Updated Artist"; doc.tracks[0].favorite = true
        doc.playlists[0].trackIDs.reverse()
        let next = try publish(doc)
        XCTAssertTrue(next.changed)
        XCTAssertEqual(next.copiedFileCount, 0)
        XCTAssertEqual(next.manifest.assets.map(\.relativePath), first.manifest.assets.map(\.relativePath))
        XCTAssertEqual(next.manifest.document, doc)
        let playlist = try String(decoding: data(next.manifest.playlists[0].relativePath), as: UTF8.self)
        XCTAssertTrue(playlist.contains("Updated Artist — Updated"))
        XCTAssertTrue(playlist.components(separatedBy: "\n").first { $0.hasPrefix("../") }!.contains(next.manifest.assets[0].relativePath))
    }
    func testArchivedAudioReplacementAndRestorePreserveAllCopies() throws {
        var doc = try document()
        let first = try publish(doc), originalPath = first.manifest.assets[0].relativePath
        let replacement = try audio("new.wav", text: "New audio")
        try doc.replaceAudio(trackID: doc.tracks[0].id, with: TrackAudioPayload(fileName: replacement.fileName, fingerprint: replacement.fingerprint,
            duration: 5, byteCount: replacement.byteCount, originalFileName: "new.wav"))
        let next = try publish(doc)
        XCTAssertEqual(next.copiedFileCount, 1)
        XCTAssertEqual(next.manifest.assets.filter { $0.kind == .archivedAudio }.count, 1)
        XCTAssertEqual(try data(originalPath), Data("One".utf8))
        let newPath = next.manifest.assets[0].relativePath
        try doc.restoreAudioVersion(trackID: doc.tracks[0].id, versionID: doc.tracks[0].audioVersions[0].id)
        let restored = try publish(doc)
        XCTAssertEqual(restored.copiedFileCount, 0)
        XCTAssertEqual(restored.manifest.assets[0].relativePath, originalPath)
        XCTAssertEqual(try data(newPath), Data("New audio".utf8))
    }
    func testFirstCopyIncludesAlreadyArchivedAudioAndPlaylistOnlyCover() throws {
        var doc = try document()
        let replacement = try audio("new.wav", text: "New audio")
        try doc.replaceAudio(trackID: doc.tracks[0].id, with: TrackAudioPayload(fileName: replacement.fileName, fingerprint: replacement.fingerprint,
            duration: 5, byteCount: replacement.byteCount, originalFileName: "new.wav"))
        doc.tracks[0].artworkFileName = nil
        let result = try publish(doc)
        XCTAssertEqual(result.manifest.assets.count, 4)
        XCTAssertTrue(result.manifest.assets.first { $0.kind == .archivedAudio }!.relativePath.hasPrefix("Previous Versions/"))
        XCTAssertEqual(result.manifest.assets.filter { $0.kind == .artwork }.count, 1)
    }
    func testDeletedSongsPlaylistsAndUnrelatedFilesAreRetained() throws {
        var doc = try document()
        let first = try publish(doc)
        try Data("MY NOTES".utf8).write(to: drive.appendingPathComponent("Notes.txt"))
        doc.deleteTracks([doc.tracks[1].id]); doc.playlists = []
        let next = try publish(doc)
        XCTAssertEqual(next.songCount, 1)
        XCTAssertEqual(next.manifest.playlists.count, 0)
        for asset in first.manifest.assets { XCTAssertTrue(fm.fileExists(atPath: drive.appendingPathComponent(asset.relativePath).path)) }
        XCTAssertTrue(fm.fileExists(atPath: drive.appendingPathComponent(first.manifest.playlists[0].relativePath).path))
        XCTAssertEqual(try data("Notes.txt"), Data("MY NOTES".utf8))
    }
    func testMissingSourceLeavesPreviousCommitUntouched() throws {
        var doc = try document(); _ = try publish(doc)
        let baseline = try manifestBytes()
        let new = try audio("later.wav", text: "Later"); doc.tracks.append(new)
        try fm.removeItem(at: library.appendingPathComponent("Media/later.wav"))
        XCTAssertThrowsError(try publish(doc))
        XCTAssertEqual(try manifestBytes(), baseline)
    }
    func testChangedSameSizeSourceIsDetected() throws {
        let doc = try document(); _ = try publish(doc)
        let baseline = try manifestBytes()
        try Data("BAD".utf8).write(to: library.appendingPathComponent("Media/a.wav"), options: .atomic)
        XCTAssertThrowsError(try publish(doc))
        XCTAssertEqual(try manifestBytes(), baseline)
    }
    func testUserChangedDestinationAndPlaylistAreNotOverwritten() throws {
        var doc = try document(); let first = try publish(doc)
        let path = first.manifest.assets[0].relativePath, baseline = try manifestBytes()
        try Data("BAD".utf8).write(to: drive.appendingPathComponent(path), options: .atomic)
        XCTAssertThrowsError(try publish(doc))
        XCTAssertEqual(try data(path), Data("BAD".utf8))
        XCTAssertEqual(try manifestBytes(), baseline)
        try Data("One".utf8).write(to: drive.appendingPathComponent(path), options: .atomic)
        let playlist = first.manifest.playlists[0].relativePath
        try Data("MY PLAYLIST".utf8).write(to: drive.appendingPathComponent(playlist), options: .atomic)
        XCTAssertThrowsError(try publish(doc))
        XCTAssertEqual(try data(playlist), Data("MY PLAYLIST".utf8))
        doc.playlists[0].trackIDs.reverse()
        _ = try publish(doc)
        XCTAssertEqual(try data(playlist), Data("MY PLAYLIST".utf8))
    }
    func testMissingDestinationAssetIsRepairedWithoutChangingSnapshot() throws {
        let doc = try document(), first = try publish(doc)
        let path = first.manifest.assets[0].relativePath
        try fm.removeItem(at: drive.appendingPathComponent(path))
        let result = try publish(doc)
        XCTAssertEqual(result.copiedFileCount, 1)
        XCTAssertEqual(try data(path), Data("One".utf8))
        XCTAssertEqual(result.manifest.document, first.manifest.document)
    }
    func testUnownedAndOtherLibraryDestinationsRefuseMutation() throws {
        let doc = try document()
        try fm.createDirectory(at: drive, withIntermediateDirectories: false)
        try Data("USER FILE".utf8).write(to: drive.appendingPathComponent("User.txt"))
        XCTAssertThrowsError(try publish(doc))
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath: drive.path)), ["User.txt"])
        try fm.removeItem(at: drive.appendingPathComponent("User.txt")); _ = try publish(doc)
        let bytes = try manifestBytes()
        XCTAssertThrowsError(try DriveLibraryMirror.publish(document: doc, libraryDirectory: library, destination: drive, sourceLibraryID: UUID()))
        XCTAssertEqual(try manifestBytes(), bytes)
    }
    func testSymlinkDestinationsSourcesAndManagedSubfoldersRefused() throws {
        let doc = try document()
        let outside = root.appendingPathComponent("Outside"); try fm.createDirectory(at: outside, withIntermediateDirectories: false)
        try fm.createSymbolicLink(at: drive, withDestinationURL: outside)
        XCTAssertThrowsError(try publish(doc)); try fm.removeItem(at: drive)
        let a = library.appendingPathComponent("Media/a.wav"), hold = root.appendingPathComponent("hold")
        try fm.moveItem(at: a, to: hold); try fm.createSymbolicLink(at: a, withDestinationURL: hold)
        XCTAssertThrowsError(try publish(doc)); try fm.removeItem(at: a); try fm.moveItem(at: hold, to: a)
        _ = try publish(doc)
        let music = drive.appendingPathComponent("Music")
        try fm.moveItem(at: music, to: root.appendingPathComponent("savedMusic"))
        try fm.createSymbolicLink(at: music, withDestinationURL: outside)
        XCTAssertThrowsError(try publish(doc))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
    func testOverlappingLibrariesAndTraversalMetadataRefused() throws {
        var doc = try document()
        XCTAssertThrowsError(try DriveLibraryMirror.publish(document: doc, libraryDirectory: library, destination: library.appendingPathComponent("Copy"), sourceLibraryID: sourceID))
        XCTAssertFalse(fm.fileExists(atPath: library.appendingPathComponent("Copy").path))
        doc.tracks[0].fileName = "../outside.wav"
        XCTAssertThrowsError(try publish(doc))
    }
    func testUnsafeDisplayNamesAreSanitizedAndSameBasenamesAcrossKindsSupported() throws {
        var doc = try document()
        doc.tracks[0].title = "../../ BAD:\n\\ NAME"; doc.tracks[0].artist = " ../ Artist: / "
        doc.tracks[0].artworkFileName = "a.wav"
        try Data("COVER SAME NAME".utf8).write(to: library.appendingPathComponent("Artwork/a.wav"))
        let result = try publish(doc)
        XCTAssertEqual(result.manifest.assets.filter { $0.fileName == "a.wav" }.count, 2)
        XCTAssertTrue(result.manifest.assets.allSatisfy { !$0.relativePath.contains("../") && !$0.relativePath.contains("\\") && !$0.relativePath.contains(":") && !$0.relativePath.contains("\n") })
    }
    func testEmptyLibraryAndPrivateReceipts() throws {
        var empty = LibraryDocument()
        empty.phoneFavoriteReceipts[UUID().uuidString] = 5
        let result = try publish(empty)
        XCTAssertEqual(result.songCount, 0)
        XCTAssertEqual(result.copiedFileCount, 0)
        XCTAssertTrue(result.manifest.document.phoneFavoriteReceipts.isEmpty)
        XCTAssertTrue(try publish(empty).manifest.document.phoneFavoriteReceipts.isEmpty)
    }
    func testCorruptManifestAndOwnershipArePreserved() throws {
        let doc = try document(); _ = try publish(doc)
        let bad = Data("bad manifest".utf8)
        try bad.write(to: drive.appendingPathComponent(DriveLibraryMirror.manifestName), options: .atomic)
        XCTAssertThrowsError(try publish(doc))
        XCTAssertEqual(try manifestBytes(), bad)
    }
    func testInterruptedFirstCopyCanResumeWithOwnershipAndExistingAssets() throws {
        let doc = try document(), first = try publish(doc)
        try fm.removeItem(at: drive.appendingPathComponent(DriveLibraryMirror.manifestName))
        let resumed = try publish(doc)
        XCTAssertEqual(resumed.copiedFileCount, 0)
        XCTAssertEqual(resumed.reusedFileCount, first.manifest.assets.count)
        XCTAssertEqual(resumed.manifest.document, doc)
    }
}
