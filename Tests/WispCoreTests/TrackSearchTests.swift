import XCTest
@testable import WispCore

final class TrackSearchTests: XCTestCase {
    private func track(_ title: String, id: UUID = UUID()) -> Track {
        Track(id: id, title: title, fileName: "audio.m4a", fingerprint: id.uuidString)
    }

    func testSearchAcceptsDisplayedColonAndFilenameDashInEitherDirection() {
        let raw = track("Hollow Knight - Silksong")
        let displayed = track("Hollow Knight: Silksong")
        for song in [raw, displayed] {
            XCTAssertTrue(TrackSearch.matches(song, query: "Hollow Knight: Silksong"))
            XCTAssertTrue(TrackSearch.matches(song, query: "Hollow Knight - Silksong"))
            XCTAssertFalse(TrackSearch.matches(song, query: "Unrelated title"))
        }
    }

    func testSearchIgnoresCaseAccentsAndSurroundingWhitespace() {
        let song = track("Espoir de Lumière")
        XCTAssertTrue(TrackSearch.matches(song, query: " \nLUMIERE\t "))
        XCTAssertTrue(TrackSearch.matches(song, query: ""))
        XCTAssertTrue(TrackSearch.matches(song, query: " \n\t "))
    }

    func testSearchUsesArtistOriginGenreAndCollectionButNotUnrelatedMetadata() {
        var song = track("First Light")
        song.artist = "Björk"
        song.origin = "Hollow Knight - Silksong"
        song.genre = "Hip-hop"
        song.remix = .classic
        song.album = "Legacy album"
        song.sourceURL = "https://example.com/private-path"
        for query in ["bjork", "Hollow Knight: Silksong", "hip-hop", "CLASSIC"] {
            XCTAssertTrue(TrackSearch.matches(song, query: query), query)
        }
        for query in ["Basic", "Legacy album", "private-path"] {
            XCTAssertFalse(TrackSearch.matches(song, query: query), query)
        }
    }

    func testSelectionsAcrossSearchesKeepTheFullDisplayedOrder() {
        let amber = track("Amber")
        let blue = track("Blue")
        let crimson = track("Crimson")
        let songs = TrackSearch.alphabetized([crimson, amber, blue])
        var selected = Set(songs.filter { TrackSearch.matches($0, query: "Crimson") }.map(\.id))
        selected.formUnion(songs.filter { TrackSearch.matches($0, query: "Amber") }.map(\.id))
        XCTAssertEqual(songs.map(\.id).filter(selected.contains), [amber.id, crimson.id])
    }

    func testEqualDisplayedTitlesHaveStableOrderIndependentOfLibraryStorage() {
        let first = track("Hollow Knight - Silksong", id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let second = track("Hollow Knight: Silksong", id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        XCTAssertEqual(TrackSearch.alphabetized([second, first]).map(\.id), [first.id, second.id])
        XCTAssertEqual(TrackSearch.alphabetized([first, second]).map(\.id), [first.id, second.id])
    }
}
