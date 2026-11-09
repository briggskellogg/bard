import XCTest
@testable import WispCore

final class ImportSuggestionTests: XCTestCase {
    func testUntaggedRACRemixProposesArtistAndKeepsRemixCreditInTitle() {
        let proposal = ImportSuggestion.propose(filename: "Edward Sharpe & The Magnetic Zeros - Home - RAC Mix.mp3",
            title: nil, artist: nil, album: nil, genre: nil)
        XCTAssertEqual(proposal.title, "Home: RAC Mix")
        XCTAssertEqual(proposal.artist, "Edward Sharpe & The Magnetic Zeros")
        XCTAssertEqual(proposal.remix, .basic)
        XCTAssertEqual(proposal.origin, "")
        XCTAssertEqual(proposal.genre, "")
        XCTAssertNil(proposal.originMediaKind)
        XCTAssertTrue(proposal.needsReview)
        XCTAssertTrue(proposal.notes.contains { $0.contains("inferred") })
    }

    func testBSBDTagRetainsItsCreditAndUsesEvidenceToCleanFilenameTitle() {
        let proposal = ImportSuggestion.propose(filename: "Blue Sky Black Death - Farewell To The Former World - Aquatic Reverie.mp3",
            title: nil, artist: "BSBD", album: "Aquatic Reverie", genre: nil)
        XCTAssertEqual(proposal.title, "Farewell To The Former World")
        XCTAssertEqual(proposal.artist, "BSBD")
        XCTAssertEqual(proposal.album, "Aquatic Reverie")
        XCTAssertEqual(proposal.origin, "")
        XCTAssertTrue(proposal.notes.contains { $0.contains("exact album suffix") })
        XCTAssertTrue(proposal.needsReview)
    }

    func testSourceLookingFilenameOffersContextWithoutInventingOrigin() {
        let proposal = ImportSuggestion.propose(filename: "Sea Power - Whirling-In-Rags - Disco Elysium for Gameboy.mp3",
            title: nil, artist: nil, album: nil, genre: nil)
        XCTAssertEqual(proposal.title, "Whirling-In-Rags: Disco Elysium for Gameboy")
        XCTAssertEqual(proposal.artist, "Sea Power")
        XCTAssertEqual(proposal.origin, "")
        XCTAssertNil(proposal.originMediaKind)
        XCTAssertTrue(proposal.notes.contains { $0.contains("Disco Elysium for Gameboy") && $0.contains("Origin is blank") })
        XCTAssertTrue(proposal.needsReview)
    }

    func testTaggedExamplesKeepTitlesArtistsAndAlbumsWithoutConvertingAlbumToOrigin() {
        let examples: [(String, String, String, String)] = [
            ("C418 - Minecraft - Volume Alpha - 18 Sweden.mp3", "Sweden", "C418", "Minecraft - Volume Alpha"),
            ("Mikel - Poké & Chill - 01 Pokémon Gym.mp3", "Pokémon Gym", "Mikel", "Poké & Chill"),
            ("Mikel - Zelda & Chill - 01 Fairy Fountain.mp3", "Fairy Fountain", "Mikel", "Zelda & Chill"),
            ("Mikel & Jokabi - The Ghibli Tape - 01 Merry Go Round of Life.mp3", "Merry Go Round of Life", "Mikel & Jokabi", "The Ghibli Tape")
        ]
        for (filename, title, artist, album) in examples {
            let proposal = ImportSuggestion.propose(filename: filename, title: title, artist: artist, album: album, genre: nil)
            XCTAssertEqual(proposal.title, title)
            XCTAssertEqual(proposal.artist, artist)
            XCTAssertEqual(proposal.album, album)
            XCTAssertEqual(proposal.origin, "")
            XCTAssertNil(proposal.originMediaKind)
            XCTAssertEqual(proposal.remix, .basic)
            XCTAssertTrue(proposal.needsReview)
            XCTAssertTrue(proposal.notes.contains { $0.contains("Possible source context") })
        }
    }

    func testNumberedEmbeddedTitleHasReviewableCleanupButPreservesEmbeddedWords() {
        let proposal = ImportSuggestion.propose(filename: "08. NO IMAGE 2006.mp3",
            title: "08. NO IMAGE", artist: "BSBD", album: "Aquatic Reverie", genre: nil)
        XCTAssertEqual(proposal.title, "NO IMAGE")
        XCTAssertEqual(proposal.artist, "BSBD")
        XCTAssertEqual(proposal.album, "Aquatic Reverie")
        XCTAssertTrue(proposal.notes.contains { $0.contains("leading track number") })
        XCTAssertFalse(proposal.title.contains("2006"))
    }

    func testExplicitBasicAndClassicConventionsStayCompatible() {
        for (suffix, kind) in [("Basic", RemixKind.basic), ("Classic", RemixKind.classic)] {
            let proposal = ImportSuggestion.propose(filename: "Bonebottom - Descent (Hollow Knight - Silksong) [\(suffix) Remix].mp3",
                title: nil, artist: nil, album: nil, genre: nil)
            XCTAssertEqual(proposal.title, "Bonebottom: Descent")
            XCTAssertEqual(proposal.origin, "Hollow Knight: Silksong")
            XCTAssertEqual(proposal.artist, "")
            XCTAssertEqual(proposal.remix, kind)
            XCTAssertFalse(proposal.needsReview)
            XCTAssertTrue(proposal.notes.isEmpty)
        }
    }

    func testOrdinaryParentheticalRemixAndLiveNamesRemainPartOfTitle() {
        for title in ["Home (RAC Remix)", "Home (Live)", "Home (2024 Remaster)"] {
            let proposal = ImportSuggestion.propose(filename: title + ".mp3", title: title, artist: "Credited Artist", album: nil, genre: "Electronic")
            XCTAssertEqual(proposal.title, title)
            XCTAssertEqual(proposal.origin, "")
            XCTAssertEqual(proposal.artist, "Credited Artist")
            XCTAssertEqual(proposal.genre, "Electronic")
            XCTAssertEqual(proposal.remix, .basic)
        }
    }

    func testEmbeddedTagsWinWhenFilenameDisagreesAndCollectionConflictIsFlagged() {
        let proposal = ImportSuggestion.propose(filename: "Other Title (Other Game) [Basic Remix].mp3",
            title: "Tagged Title (Tagged Origin) [Classic Remix]", artist: "Tagged Artist", album: "Tagged Album", genre: "  Trip-hop  ")
        XCTAssertEqual(proposal.title, "Tagged Title")
        XCTAssertEqual(proposal.origin, "Tagged Origin")
        XCTAssertEqual(proposal.remix, .classic)
        XCTAssertEqual(proposal.artist, "Tagged Artist")
        XCTAssertEqual(proposal.album, "Tagged Album")
        XCTAssertEqual(proposal.genre, "Trip-hop")
        XCTAssertTrue(proposal.needsReview)
        XCTAssertTrue(proposal.notes.contains { $0.contains("confirm the collection") })
        XCTAssertTrue(proposal.notes.contains { $0.contains("different origins") })
    }

    func testNumericPrefixIsNeverAnArtistAndMeaningfulBareNumbersArePreserved() {
        let numbered = ImportSuggestion.propose(filename: "08 - The Surface.mp3", title: nil, artist: nil, album: nil, genre: nil)
        XCTAssertEqual(numbered.artist, "")
        XCTAssertEqual(numbered.title, "The Surface")
        let numberedRemix = ImportSuggestion.propose(filename: "08. NO IMAGE - Late Mix.mp3", title: nil, artist: nil, album: nil, genre: nil)
        XCTAssertEqual(numberedRemix.artist, "")
        XCTAssertEqual(numberedRemix.title, "NO IMAGE: Late Mix")
        let meaningful = ImportSuggestion.propose(filename: "99 Problems.mp3", title: "99 Problems", artist: "Artist", album: nil, genre: nil)
        XCTAssertEqual(meaningful.title, "99 Problems")
        let year = ImportSuggestion.propose(filename: "1984 - Reprise.mp3", title: nil, artist: nil, album: nil, genre: nil)
        XCTAssertEqual(year.artist, "")
        XCTAssertEqual(year.title, "1984: Reprise")
    }

    func testFilenameDoesNotReplaceNonmatchingEmbeddedArtistOrKnownTitle() {
        let proposal = ImportSuggestion.propose(filename: "Wrong Artist - Filename Song - Collection.mp3",
            title: "Embedded Song (Remix)", artist: "Correct Artist", album: "Collection", genre: nil)
        XCTAssertEqual(proposal.title, "Embedded Song (Remix)")
        XCTAssertEqual(proposal.artist, "Correct Artist")
        XCTAssertEqual(proposal.genre, "")
        XCTAssertEqual(proposal.origin, "")
        let missingArtist = ImportSuggestion.propose(filename: "Hollow Knight - Silksong.mp3",
            title: "Hollow Knight - Silksong", artist: nil, album: nil, genre: nil)
        XCTAssertEqual(missingArtist.title, "Hollow Knight: Silksong")
        XCTAssertEqual(missingArtist.artist, "")
    }
}
