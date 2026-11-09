import Foundation
import XCTest
@testable import WispCore

final class AudioVersionTests: XCTestCase {
    private let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let secondDate = Date(timeIntervalSince1970: 1_700_000_100)
    private func track() -> Track {
        Track(title: "User title", artist: "Artist", album: "Legacy album", fileName: "original.wav",
              fingerprint: "original-hash", artworkFileName: "art.png", duration: 120, byteCount: 1000,
              addedAt: firstDate, favorite: true, origin: "Named origin", remix: .classic,
              originalFileName: "Original mix.wav", sourceURL: "https://example.com/source",
              originMediaKind: .music, genre: "Trip hop")
    }
    private func payload(_ name: String = "second") -> TrackAudioPayload {
        TrackAudioPayload(fileName: "\(name).wav", fingerprint: "\(name)-hash", duration: 150,
                          byteCount: 2000, originalFileName: "\(name) mix.wav", addedAt: secondDate)
    }

    func testLegacyDocumentsDecodeWithoutInventingVersions() throws {
        let song = track()
        let original = LibraryDocument(tracks: [song])
        var object = try JSONSerialization.jsonObject(with: LibraryRepository.encode(original)) as! [String: Any]
        var songs = object["tracks"] as! [[String: Any]]
        songs[0].removeValue(forKey: "audioVersions")
        songs[0].removeValue(forKey: "currentAudioAddedAt")
        songs[0].removeValue(forKey: "currentAudioVersionID")
        object["tracks"] = songs
        let decoded = try LibraryRepository.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.tracks[0].currentAudioDate, firstDate)
        XCTAssertTrue(decoded.tracks[0].audioVersions.isEmpty)
    }

    func testReplaceKeepsSongIdentityMetadataAndPlaylistOrder() throws {
        let song = track()
        let list = Playlist(name: "Mixtape", description: "My description", trackIDs: [song.id])
        var document = LibraryDocument(tracks: [song], playlists: [list])
        let replacement = payload()
        try document.replaceAudio(trackID: song.id, with: replacement, at: secondDate)
        let changed = document.tracks[0]
        XCTAssertEqual(document.schemaVersion, 2)
        XCTAssertEqual(document.playlists, [list])
        XCTAssertEqual(changed.id, song.id)
        XCTAssertEqual(changed.title, song.title)
        XCTAssertEqual(changed.artist, song.artist)
        XCTAssertEqual(changed.album, song.album)
        XCTAssertEqual(changed.genre, song.genre)
        XCTAssertEqual(changed.origin, song.origin)
        XCTAssertEqual(changed.originMediaKind, song.originMediaKind)
        XCTAssertEqual(changed.remix, song.remix)
        XCTAssertEqual(changed.sourceURL, song.sourceURL)
        XCTAssertEqual(changed.favorite, song.favorite)
        XCTAssertEqual(changed.artworkFileName, song.artworkFileName)
        XCTAssertEqual(changed.addedAt, song.addedAt)
        XCTAssertEqual(changed.fileName, replacement.fileName)
        XCTAssertEqual(changed.fingerprint, replacement.fingerprint)
        XCTAssertEqual(changed.duration, replacement.duration)
        XCTAssertEqual(changed.byteCount, replacement.byteCount)
        XCTAssertEqual(changed.currentAudioVersionID, replacement.id)
        XCTAssertEqual(changed.currentAudioAddedAt, replacement.addedAt)
        XCTAssertEqual(changed.audioVersions.count, 1)
        XCTAssertEqual(changed.audioVersions[0].fileName, song.fileName)
        XCTAssertEqual(changed.audioVersions[0].fingerprint, song.fingerprint)
        XCTAssertEqual(changed.audioVersions[0].duration, song.duration)
        XCTAssertEqual(changed.audioVersions[0].originalFileName, song.originalFileName)
        XCTAssertEqual(changed.audioVersions[0].addedAt, song.addedAt)
        XCTAssertEqual(changed.audioVersions[0].archivedAt, secondDate)
    }

    func testRestoreCyclesKeepExactlyOneCopyAndStableVersionIdentity() throws {
        let song = track()
        var document = LibraryDocument(tracks: [song])
        let replacement = payload()
        try document.replaceAudio(trackID: song.id, with: replacement, at: secondDate)
        let originalVersion = document.tracks[0].audioVersions[0]
        for _ in 0..<3 {
            try document.restoreAudioVersion(trackID: song.id, versionID: originalVersion.id)
            XCTAssertEqual(document.tracks[0].fileName, song.fileName)
            XCTAssertEqual(document.tracks[0].currentAudioVersionID, originalVersion.id)
            XCTAssertEqual(document.tracks[0].audioVersions.map(\.id), [replacement.id])
            try document.restoreAudioVersion(trackID: song.id, versionID: replacement.id)
            XCTAssertEqual(document.tracks[0].currentAudioVersionID, replacement.id)
            XCTAssertEqual(document.tracks[0].audioVersions.map(\.id), [originalVersion.id])
            XCTAssertEqual(document.tracks[0].audioVersions.count, 1)
            try document.validate()
        }
    }

    func testRejectedReplacementAndRestoreLeaveDocumentUnchanged() throws {
        let song = track()
        var document = LibraryDocument(tracks: [song])
        var same = payload(); same.fingerprint = song.fingerprint
        XCTAssertThrowsError(try document.replaceAudio(trackID: song.id, with: same))
        XCTAssertEqual(document, LibraryDocument(tracks: [song]))
        try document.replaceAudio(trackID: song.id, with: payload())
        let saved = document
        XCTAssertThrowsError(try document.replaceAudio(trackID: song.id, with: same))
        XCTAssertThrowsError(try document.restoreAudioVersion(trackID: song.id, versionID: UUID()))
        XCTAssertThrowsError(try document.replaceAudio(trackID: UUID(), with: payload("other")))
        XCTAssertEqual(document, saved)
    }

    func testOtherSongsCurrentAudioCannotBeReplacedOrRestoredIntoAnotherSong() throws {
        let song = track()
        var other = track(); other.id = UUID(); other.fileName = "other.wav"; other.fingerprint = "other-hash"
        var document = LibraryDocument(tracks: [song, other])
        var duplicate = payload(); duplicate.fingerprint = other.fingerprint
        let before = document
        XCTAssertThrowsError(try document.replaceAudio(trackID: song.id, with: duplicate))
        XCTAssertEqual(document, before)
        try document.replaceAudio(trackID: song.id, with: payload())
        document.tracks[1].fingerprint = song.fingerprint
        try document.validate() // A separate imported copy may match archived bytes.
        let prior = document
        XCTAssertThrowsError(try document.restoreAudioVersion(trackID: song.id, versionID: document.tracks[0].audioVersions[0].id))
        XCTAssertEqual(document, prior)
    }

    func testArchiveValidationRejectsUnsafeReferencesAndDuplicates() throws {
        let song = track()
        var document = LibraryDocument(tracks: [song])
        try document.replaceAudio(trackID: song.id, with: payload())
        var bad = document
        bad.tracks[0].audioVersions[0].fileName = "../outside.wav"
        XCTAssertThrowsError(try bad.validate())
        bad = document; bad.tracks[0].audioVersions[0].fileName = document.tracks[0].fileName
        XCTAssertThrowsError(try bad.validate())
        bad = document; bad.tracks[0].audioVersions.append(bad.tracks[0].audioVersions[0])
        XCTAssertThrowsError(try bad.validate())
        bad = document; bad.tracks[0].audioVersions[0].fingerprint = document.tracks[0].fingerprint
        XCTAssertThrowsError(try bad.validate())
        bad = document; bad.schemaVersion = 1
        XCTAssertThrowsError(try bad.validate())
        bad = document; bad.tracks[0].currentAudioVersionID = nil
        XCTAssertThrowsError(try bad.validate())
    }

    func testInvalidNewAudioCannotMutateDocument() throws {
        let song = track()
        var document = LibraryDocument(tracks: [song])
        let before = document
        var invalid = payload(); invalid.duration = .nan
        XCTAssertThrowsError(try document.replaceAudio(trackID: song.id, with: invalid))
        invalid = payload(); invalid.byteCount = 0
        XCTAssertThrowsError(try document.replaceAudio(trackID: song.id, with: invalid))
        invalid = payload(); invalid.fileName = "/outside.wav"
        XCTAssertThrowsError(try document.replaceAudio(trackID: song.id, with: invalid))
        XCTAssertEqual(document, before)
    }

    func testVersionedRoundTripAndPreviousIndexRetainRecoverableHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Wisp-audio-version-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LibraryRepository(directory: directory)
        _ = try repository.load()
        let song = track()
        var document = LibraryDocument(tracks: [song])
        try repository.save(document)
        let originalBytes = try Data(contentsOf: repository.manifestURL)
        try document.replaceAudio(trackID: song.id, with: payload(), at: secondDate)
        try repository.save(document)
        XCTAssertEqual(try Data(contentsOf: repository.previousURL), originalBytes)
        XCTAssertEqual(try LibraryRepository(directory: directory).load(), document)
        XCTAssertEqual(try LibraryRepository.decode(LibraryRepository.encode(document)), document)
        let originalVersion = document.tracks[0].audioVersions[0]
        try document.restoreAudioVersion(trackID: song.id, versionID: originalVersion.id, at: secondDate)
        try repository.save(document)
        let reloaded = try repository.load()
        XCTAssertEqual(reloaded.tracks[0].fileName, song.fileName)
        XCTAssertEqual(reloaded.tracks[0].audioVersions.map(\.fileName), ["second.wav"])
    }
}
