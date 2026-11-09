import XCTest
@testable import WispCore

final class TrackNameParserTests: XCTestCase {
    func testSpacedDashesBecomeSubtitleColonsInTitleAndOrigin() {
        XCTAssertEqual(
            TrackNameParser.parse("Bonebottom - Descent (Hollow Knight - Silksong) [Basic Remix].mp3"),
            ParsedTrackName(title: "Bonebottom: Descent", origin: "Hollow Knight: Silksong", remix: .basic)
        )
    }

    func testMultipleSpacedDashesPreserveHyphenatedWordsAndExistingColons() {
        XCTAssertEqual(
            TrackNameParser.parse("Spider-Man - Home - Reprise (Spider-Man: Across the Spider-Verse - Score) [Classic Remix].m4a"),
            ParsedTrackName(title: "Spider-Man: Home: Reprise", origin: "Spider-Man: Across the Spider-Verse: Score", remix: .classic)
        )
    }

    func testPlainImportedTitleIsNormalizedWithoutChangingParenthesisRules() {
        XCTAssertEqual(
            TrackNameParser.parse("Hollow Knight - Silksong (Live).flac"),
            ParsedTrackName(title: "Hollow Knight: Silksong (Live)")
        )
    }

    func testNameNormalizationIsReusableAndIdempotent() {
        let normalized = TrackNameParser.normalizeName("Hollow Knight - Silksong")
        XCTAssertEqual(normalized, "Hollow Knight: Silksong")
        XCTAssertEqual(TrackNameParser.normalizeName(normalized), normalized)
        XCTAssertEqual(TrackNameParser.normalizeName("Spider-Man — Home – Reprise"), "Spider-Man — Home – Reprise")
        XCTAssertEqual(TrackNameParser.normalizeName("Spider-Man: Home"), "Spider-Man: Home")
        XCTAssertEqual(TrackNameParser.normalizeName("https://example.com/hollow-knight-silksong"), "https://example.com/hollow-knight-silksong")
    }

    func testBriggsBasicConvention() {
        XCTAssertEqual(
            TrackNameParser.parse("Bonebottom (Hollow Knight Silksong) [Basic Remix]"),
            ParsedTrackName(title: "Bonebottom", origin: "Hollow Knight Silksong", remix: .basic)
        )
    }

    func testClassicMeansPersonalRemix() {
        let parsed = TrackNameParser.parse("Deep Sleep (Hades II) [Classic Remix].m4a")
        XCTAssertEqual(parsed.title, "Deep Sleep")
        XCTAssertEqual(parsed.origin, "Hades II")
        XCTAssertEqual(parsed.remix, .classic)
        XCTAssertEqual(parsed.remix?.attribution, "Created by you")
    }

    func testCaseSpacingUnicodeAndExtension() {
        XCTAssertEqual(
            TrackNameParser.parse("  Échos (Jeu — Chapitre 2) [  BASIC   remix ].FLAC  "),
            ParsedTrackName(title: "Échos", origin: "Jeu — Chapitre 2", remix: .basic)
        )
    }

    func testNestedOriginAndParenthesesInTitle() {
        XCTAssertEqual(
            TrackNameParser.parse("Home (Again) (Game (Original score)) [Classic Remix].wav"),
            ParsedTrackName(title: "Home (Again)", origin: "Game (Original score)", remix: .classic)
        )
    }

    func testMissingVersionRemainsUnspecified() {
        XCTAssertEqual(TrackNameParser.parse("On the Coast (Hades)"), ParsedTrackName(title: "On the Coast (Hades)"))
        XCTAssertNil(TrackNameParser.parse("Unlabelled.flac").remix)
    }

    func testOrdinaryPurchasedTitlesKeepParentheticalVersions() {
        XCTAssertEqual(TrackNameParser.parse("Song (Live).flac"), ParsedTrackName(title: "Song (Live)"))
        XCTAssertEqual(TrackNameParser.parse("Home (2024 Remaster)"), ParsedTrackName(title: "Home (2024 Remaster)"))
        XCTAssertEqual(TrackNameParser.parse("Song (Of Love)"), ParsedTrackName(title: "Song (Of Love)"))
    }

    func testUnknownVersionIsNotSilentlyDiscarded() {
        XCTAssertEqual(
            TrackNameParser.parse("Bonebottom (Silksong) [Live Mix].mp3"),
            ParsedTrackName(title: "Bonebottom (Silksong) [Live Mix]")
        )
        XCTAssertEqual(TrackNameParser.parse("Title [Basic]"), ParsedTrackName(title: "Title [Basic]"))
    }

    func testVersionWithoutOrigin() {
        XCTAssertEqual(TrackNameParser.parse("Bonebottom [Basic Remix].mp3"), ParsedTrackName(title: "Bonebottom", remix: .basic))
    }

    func testMalformedInputDoesNotLoseInformation() {
        XCTAssertEqual(TrackNameParser.parse("Bonebottom (Silksong"), ParsedTrackName(title: "Bonebottom (Silksong"))
        XCTAssertEqual(TrackNameParser.parse("Title ()"), ParsedTrackName(title: "Title ()"))
        XCTAssertEqual(TrackNameParser.parse("[Classic Remix]"), ParsedTrackName(title: "[Classic Remix]"))
        XCTAssertEqual(TrackNameParser.parse(" "), ParsedTrackName(title: "Untitled"))
        XCTAssertEqual(TrackNameParser.parse("I(Really)"), ParsedTrackName(title: "I(Really)"))
    }
}
