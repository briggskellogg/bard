import Foundation
import XCTest
@testable import WispCore

final class LibraryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("Wisp-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
    }

    private func track(_ name: String = "One", fingerprint: String? = nil) -> Track {
        let id = UUID()
        return Track(id: id, title: name, artist: "Artist", album: "Album", fileName: "\(id.uuidString).m4a",
                     fingerprint: fingerprint ?? id.uuidString, duration: 123, byteCount: 12345,
                     addedAt: Date(timeIntervalSince1970: 1_700_000_000),
                     origin: "Hollow Knight Silksong", remix: .basic,
                     originalFileName: "Bonebottom (Hollow Knight Silksong) [Basic Remix].m4a",
                     sourceURL: "https://soundcloud.com/example/bonebottom")
    }

    func testNewLibraryIsEmptyAndCreatesOnlyManagedDirectories() throws {
        let repository = LibraryRepository(directory: directory)
        let document = try repository.load()
        XCTAssertTrue(document.tracks.isEmpty)
        XCTAssertTrue(document.playlists.isEmpty)
        XCTAssertTrue(document.folders.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repository.mediaDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.manifestURL.path))
        try repository.save(document)
        XCTAssertEqual(try repository.load(), document)
    }

    func testRoundTripPreservesNamesDescriptionsOrderAndMetadata() throws {
        let first = track("Bonebottom"), second = track("Quiet")
        let folder = PlaylistFolder(name: "Focus", tint: .teal, createdAt: Date(timeIntervalSince1970: 100))
        let playlist = Playlist(name: "Hearth", description: "A personal note.", symbol: "flame.fill", tint: .amber,
                                coverFileName: "cover.png", trackIDs: [second.id, first.id], folderID: folder.id,
                                createdAt: Date(timeIntervalSince1970: 101))
        let document = LibraryDocument(tracks: [first, second], playlists: [playlist], folders: [folder])
        let repository = LibraryRepository(directory: directory)
        _ = try repository.load()
        try repository.save(document)
        let reopened = try LibraryRepository(directory: directory).load()
        XCTAssertEqual(reopened, document)
        XCTAssertEqual(reopened.tracks[0].origin, "Hollow Knight Silksong")
        XCTAssertEqual(reopened.tracks[0].remix, .basic)
        XCTAssertEqual(reopened.tracks[0].originalFileName, first.originalFileName)
        XCTAssertEqual(reopened.tracks[0].sourceURL, first.sourceURL)
    }

    func testOlderTrackWithoutOriginFieldsDecodesWithDefaults() throws {
        var object = try JSONSerialization.jsonObject(with: LibraryRepository.encode(LibraryDocument(tracks: [track()]))) as! [String: Any]
        var tracks = object["tracks"] as! [[String: Any]]
        tracks[0].removeValue(forKey: "origin")
        tracks[0].removeValue(forKey: "remix")
        tracks[0].removeValue(forKey: "originalFileName")
        tracks[0].removeValue(forKey: "sourceURL")
        object["tracks"] = tracks
        let data = try JSONSerialization.data(withJSONObject: object)
        let document = try LibraryRepository.decode(data)
        XCTAssertEqual(document.tracks[0].origin, "")
        XCTAssertNil(document.tracks[0].remix)
        XCTAssertEqual(document.tracks[0].originalFileName, "")
        XCTAssertNil(document.tracks[0].sourceURL)
    }

    func testMergeDeduplicatesAudioAndPreservesExistingEdits() throws {
        var existing = track("My edited title", fingerprint: "same-bytes")
        existing.favorite = true
        let renamed = track("Different filename", fingerprint: "same-bytes")
        let another = track("Another")
        var document = LibraryDocument(tracks: [existing])
        let ids = document.mergeTracks([renamed, another, another])
        XCTAssertEqual(ids, [existing.id, another.id])
        XCTAssertEqual(document.tracks.count, 2)
        XCTAssertEqual(document.tracks[0], existing)
        try document.validate()
    }

    func testDuplicateImportCanFillMissingSourceWithoutReplacingExistingProvenance() throws {
        var missing = track("An edited title")
        missing.sourceURL = nil
        let known = track("Already attributed")
        var document = LibraryDocument(tracks: [missing, known])
        document.attachSource("https://example.bandcamp.com/track/song", to: [missing.id, known.id, UUID()])
        XCTAssertEqual(document.tracks[0].sourceURL, "https://example.bandcamp.com/track/song")
        XCTAssertEqual(document.tracks[0].title, "An edited title")
        XCTAssertEqual(document.tracks[1].sourceURL, known.sourceURL)
        try document.validate()
    }

    func testMembershipDeduplicatesAndRetainsInputOrder() throws {
        let one = track("One"), two = track("Two"), three = track("Three")
        let playlist = Playlist(name: "Focus", trackIDs: [two.id])
        var document = LibraryDocument(tracks: [one, two, three], playlists: [playlist])
        document.addTracks([three.id, two.id, UUID(), one.id, three.id], to: playlist.id)
        XCTAssertEqual(document.playlists[0].trackIDs, [two.id, three.id, one.id])
        try document.validate()
    }

    func testRemovingMembershipDoesNotDeleteTrackOrOtherMemberships() throws {
        let item = track()
        let a = Playlist(name: "A", trackIDs: [item.id])
        let b = Playlist(name: "B", trackIDs: [item.id])
        var document = LibraryDocument(tracks: [item], playlists: [a, b])
        document.removeTracks([item.id], from: a.id)
        XCTAssertEqual(document.tracks, [item])
        XCTAssertEqual(document.playlists[0].trackIDs, [])
        XCTAssertEqual(document.playlists[1].trackIDs, [item.id])
    }

    func testDeletingTrackRemovesEveryReference() throws {
        let one = track("One"), two = track("Two")
        var document = LibraryDocument(tracks: [one, two], playlists: [
            Playlist(name: "A", trackIDs: [one.id, two.id]), Playlist(name: "B", trackIDs: [one.id])
        ])
        document.deleteTracks([one.id])
        XCTAssertEqual(document.tracks.map(\.id), [two.id])
        XCTAssertEqual(document.playlists.map(\.trackIDs), [[two.id], []])
        try document.validate()
    }

    func testDeletingPlaylistLeavesMusicAndDeletingFolderUngroupsPlaylists() throws {
        let item = track()
        let folder = PlaylistFolder(name: "Calm")
        let a = Playlist(name: "A", trackIDs: [item.id], folderID: folder.id)
        let b = Playlist(name: "B", trackIDs: [item.id], folderID: folder.id)
        var document = LibraryDocument(tracks: [item], playlists: [a, b], folders: [folder])
        document.deletePlaylist(id: a.id)
        XCTAssertEqual(document.tracks, [item])
        document.deleteFolder(id: folder.id)
        XCTAssertEqual(document.playlists.count, 1)
        XCTAssertNil(document.playlists[0].folderID)
        XCTAssertTrue(document.folders.isEmpty)
        try document.validate()
    }

    func testTrackOrderingHasSafeBoundariesAndFolderMoveValidatesDestination() throws {
        let a = track("A"), b = track("B"), c = track("C")
        let folder = PlaylistFolder(name: "Reading")
        let playlist = Playlist(name: "Hearth", trackIDs: [a.id, b.id, c.id])
        var document = LibraryDocument(tracks: [a, b, c], playlists: [playlist], folders: [folder])
        document.moveTrack(id: a.id, in: playlist.id, offset: -1)
        document.moveTrack(id: a.id, in: playlist.id, offset: Int.max)
        XCTAssertEqual(document.playlists[0].trackIDs, [a.id, b.id, c.id])
        document.moveTrack(id: c.id, in: playlist.id, offset: -1)
        XCTAssertEqual(document.playlists[0].trackIDs, [a.id, c.id, b.id])
        document.movePlaylist(id: playlist.id, to: UUID())
        XCTAssertNil(document.playlists[0].folderID)
        document.movePlaylist(id: playlist.id, to: folder.id)
        XCTAssertEqual(document.playlists[0].folderID, folder.id)
    }

    func testUnsafeFilenamesAndDanglingReferencesAreRejected() throws {
        var item = track()
        item.fileName = "../../outside.m4a"
        XCTAssertThrowsError(try LibraryDocument(tracks: [item]).validate())
        item.fileName = "safe.m4a"
        item.artworkFileName = "..\\outside.png"
        XCTAssertThrowsError(try LibraryDocument(tracks: [item]).validate())
        item.artworkFileName = nil
        XCTAssertThrowsError(try LibraryDocument(tracks: [item], playlists: [Playlist(name: "Invalid", trackIDs: [UUID()])]).validate())
        XCTAssertThrowsError(try LibraryDocument(schemaVersion: 999).validate())
        item.duration = .infinity
        XCTAssertThrowsError(try LibraryDocument(tracks: [item]).validate())
        item.duration = 120
        item.sourceURL = "file:///etc/passwd"
        XCTAssertThrowsError(try LibraryDocument(tracks: [item]).validate())
    }

    func testInvalidSaveDoesNotReplaceCurrentIndex() throws {
        let repository = LibraryRepository(directory: directory)
        _ = try repository.load()
        let original = LibraryDocument(tracks: [track()])
        try repository.save(original)
        let data = try Data(contentsOf: repository.manifestURL)
        XCTAssertThrowsError(try repository.save(LibraryDocument(playlists: [Playlist(name: "", trackIDs: [UUID()])])))
        XCTAssertEqual(try Data(contentsOf: repository.manifestURL), data)
        XCTAssertEqual(try repository.load(), original)
    }

    func testCorruptLoadBlocksWritesAndKeepsBytesUntouched() throws {
        let repository = LibraryRepository(directory: directory)
        _ = try repository.load()
        let bad = Data("{broken".utf8)
        try bad.write(to: repository.manifestURL)
        XCTAssertThrowsError(try repository.load())
        XCTAssertThrowsError(try repository.save(LibraryDocument()))
        XCTAssertEqual(try Data(contentsOf: repository.manifestURL), bad)
    }

    func testExternalModificationPreventsLostUpdate() throws {
        let repository = LibraryRepository(directory: directory)
        _ = try repository.load()
        try repository.save(LibraryDocument())
        let other = LibraryDocument(tracks: [track("External")])
        let externalData = try LibraryRepository.encode(other)
        try externalData.write(to: repository.manifestURL, options: .atomic)
        XCTAssertThrowsError(try repository.save(LibraryDocument(tracks: [track("Local")])) )
        XCTAssertEqual(try Data(contentsOf: repository.manifestURL), externalData)
    }

    func testMissingIndexDoesNotDiscardManagedAudio() throws {
        let repository = LibraryRepository(directory: directory)
        _ = try repository.load()
        let media = repository.mediaDirectory.appendingPathComponent("saved.m4a")
        try Data([1, 2, 3]).write(to: media)
        XCTAssertThrowsError(try repository.load())
        XCTAssertThrowsError(try repository.save(LibraryDocument()))
        XCTAssertEqual(try Data(contentsOf: media), Data([1, 2, 3]))
    }

    func testExplicitRecoveryRestoresPreviousAndPreservesUnreadableIndex() throws {
        let repository = LibraryRepository(directory: directory)
        _ = try repository.load()
        let original = LibraryDocument(tracks: [track("Original")])
        try repository.save(original)
        var edited = original
        edited.tracks[0].title = "Updated"
        try repository.save(edited)
        XCTAssertEqual(try LibraryRepository.decode(Data(contentsOf: repository.previousURL)), original)
        let bad = Data("unreadable current index".utf8)
        try bad.write(to: repository.manifestURL)
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try repository.recoverPrevious(), original)
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Library-preserved-") }
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(try Data(contentsOf: preserved[0]), bad)
        XCTAssertEqual(try repository.load(), original)
    }
}
