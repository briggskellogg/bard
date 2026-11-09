import Foundation
import XCTest
@testable import WispCore

final class ListeningHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/Phoenix")!
        return result
    }
    private func date(_ year: Int = 2026, _ month: Int = 10, _ day: Int = 31,
                      _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0,
                      calendar: Calendar? = nil) -> Date {
        (calendar ?? self.calendar).date(from: DateComponents(year: year, month: month, day: day,
                                                               hour: hour, minute: minute, second: second))!
    }
    private func track(_ title: String = "First", artist: String = "Artist", origin: String = "Origin", genre: String = "Ambient") -> Track {
        Track(title: title, artist: artist, fileName: "file.mp3", fingerprint: UUID().uuidString,
              duration: 180, origin: origin, genre: genre)
    }

    func testEmptyHistoryDoesNotInventListening() {
        let history = ListeningHistory(trackingStartedAt: date())
        let summary = history.summary(period: .month, now: date(), calendar: calendar)
        XCTAssertEqual(summary.totalSeconds, 0)
        XCTAssertEqual(summary.totalPlays, 0)
        XCTAssertEqual(summary.uniqueTracks, 0)
        XCTAssertTrue(summary.tracks.isEmpty)
        XCTAssertEqual(summary.days.count, 30)
        XCTAssertTrue(summary.days.allSatisfy { $0.seconds == 0 && $0.plays == 0 })
    }

    func testMidnightSplitsTimeAndCreditsPlayOnQualificationDay() {
        var history = ListeningHistory(trackingStartedAt: date(2026, 10, 30))
        history.record(track: track(), seconds: 2, qualifiedPlay: true, at: date(2026, 10, 31, 0, 0, 1), calendar: calendar)
        XCTAssertEqual(history.entries.count, 2)
        let yesterday = history.summary(period: .today, now: date(2026, 10, 30), calendar: calendar)
        let today = history.summary(period: .today, now: date(), calendar: calendar)
        XCTAssertEqual(yesterday.totalSeconds, 1, accuracy: 0.0001)
        XCTAssertEqual(yesterday.totalPlays, 0)
        XCTAssertEqual(today.totalSeconds, 1, accuracy: 0.0001)
        XCTAssertEqual(today.totalPlays, 1)
    }

    func testMidnightDSTUsesCalendarBoundariesRatherThanFixedDayLength() {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = TimeZone(identifier: "America/New_York")!
        let now = date(2026, 11, 2, 0, 0, 1, calendar: eastern)
        var history = ListeningHistory(trackingStartedAt: now.addingTimeInterval(-100_000))
        history.record(track: track(), seconds: 2, qualifiedPlay: false, at: now, calendar: eastern)
        let prior = date(2026, 11, 1, 12, calendar: eastern)
        XCTAssertEqual(history.summary(period: .today, now: prior, calendar: eastern).totalSeconds, 1)
        XCTAssertEqual(history.summary(period: .today, now: now, calendar: eastern).totalSeconds, 1)
        XCTAssertEqual(history.summary(period: .week, now: now, calendar: eastern).days.count, 7)
    }

    func testLastSevenDaysIncludesTodayAndSixPreviousCalendarDays() {
        var history = ListeningHistory(trackingStartedAt: date(2026, 10, 1))
        let song = track()
        history.record(track: song, seconds: 10, qualifiedPlay: false, at: date(2026, 10, 24), calendar: calendar)
        history.record(track: song, seconds: 20, qualifiedPlay: true, at: date(2026, 10, 25), calendar: calendar)
        history.record(track: song, seconds: 30, qualifiedPlay: true, at: date(), calendar: calendar)
        history.record(track: song, seconds: 40, qualifiedPlay: true, at: date(2026, 11, 1), calendar: calendar)
        let result = history.summary(period: .week, now: date(), calendar: calendar)
        XCTAssertEqual(result.totalSeconds, 50)
        XCTAssertEqual(result.totalPlays, 2)
        XCTAssertEqual(result.uniqueTracks, 1)
        XCTAssertEqual(result.days.count, 7)
        XCTAssertEqual(result.days.first?.date, date(2026, 10, 25, 0))
        XCTAssertEqual(result.days.last?.date, date(2026, 10, 31, 0))
    }

    func testThirtyDaysAndYearBoundaries() {
        var history = ListeningHistory(trackingStartedAt: date(2025, 12, 31))
        let song = track()
        for (instant, seconds) in [(date(2025, 12, 31), 1.0), (date(2026, 1, 1), 2.0),
                                   (date(2026, 10, 1), 4.0), (date(2026, 10, 2), 8.0), (date(), 16.0)] {
            history.record(track: song, seconds: seconds, qualifiedPlay: false, at: instant, calendar: calendar)
        }
        XCTAssertEqual(history.summary(period: .month, now: date(), calendar: calendar).totalSeconds, 24)
        XCTAssertEqual(history.summary(period: .year, now: date(), calendar: calendar).totalSeconds, 30)
        XCTAssertEqual(history.summary(period: .all, now: date(), calendar: calendar).totalSeconds, 31)
    }

    func testRankingsUseActualTimeAndGroupCaseInsensitiveArtist() {
        var history = ListeningHistory(trackingStartedAt: date())
        let first = track("A", artist: "Creator")
        let second = track("B", artist: "creator")
        let third = track("C", artist: "Other", origin: "", genre: "")
        history.record(track: first, seconds: 20, qualifiedPlay: true, at: date(), calendar: calendar)
        history.record(track: second, seconds: 40, qualifiedPlay: false, at: date(), calendar: calendar)
        history.record(track: third, seconds: 10, qualifiedPlay: false, at: date(), calendar: calendar)
        let result = history.summary(period: .all, now: date(), calendar: calendar)
        XCTAssertEqual(result.tracks.map(\.id), [second.id, first.id, third.id])
        XCTAssertEqual(result.artists.count, 2)
        XCTAssertEqual(result.artists.first?.seconds, 60)
        XCTAssertEqual(result.artists.first?.plays, 1)
        XCTAssertEqual(result.origins.first?.seconds, 60)
        XCTAssertTrue(result.origins.contains { $0.name == "No origin" })
        XCTAssertTrue(result.genres.contains { $0.name == "Unspecified genre" })
    }

    func testMetadataUpdatesDoNotCreateDuplicateTrackOrLoseListening() {
        var history = ListeningHistory(trackingStartedAt: date(2026, 10, 30))
        var song = track("Old name", artist: "Old artist")
        history.record(track: song, seconds: 10, qualifiedPlay: false, at: date(2026, 10, 30), calendar: calendar)
        song.title = "New name"; song.artist = "New artist"
        history.record(track: song, seconds: 30, qualifiedPlay: true, at: date(), calendar: calendar)
        let result = history.summary(period: .all, now: date(), calendar: calendar)
        XCTAssertEqual(result.uniqueTracks, 1)
        XCTAssertEqual(result.tracks.first?.title, "New name")
        XCTAssertEqual(result.tracks.first?.seconds, 40)
        XCTAssertEqual(result.artists.map(\.name), ["New artist"])
    }

    func testInvalidSamplesCannotPoisonHistory() throws {
        var history = ListeningHistory(trackingStartedAt: date())
        for seconds in [-1.0, .nan, .infinity, 86_401] {
            history.record(track: track(), seconds: seconds, qualifiedPlay: true, at: date(), calendar: calendar)
        }
        history.record(track: track(), seconds: 1, qualifiedPlay: true, at: Date(timeIntervalSince1970: .nan), calendar: calendar)
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertNoThrow(try history.validate())
    }

    func testRepositoryRoundTripLeavesLibraryIndexAlone() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Wisp-listening-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = ListeningRepository(directory: directory)
        var history = try repository.load(now: date())
        let library = directory.appendingPathComponent("Library.json")
        let original = Data("original library index".utf8)
        try original.write(to: library)
        history.record(track: track(), seconds: 30, qualifiedPlay: true, at: date(), calendar: calendar)
        try repository.save(history)
        let reopened = try ListeningRepository(directory: directory).load(now: date(2026, 11, 1))
        XCTAssertEqual(reopened, history)
        XCTAssertEqual(reopened.trackingStartedAt, date())
        XCTAssertEqual(try Data(contentsOf: library), original)
    }

    func testCorruptHistoryIsNeverReplacedWithEmptyHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Wisp-listening-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = ListeningRepository(directory: directory)
        let corrupt = Data("{broken json".utf8)
        try corrupt.write(to: repository.fileURL)
        XCTAssertThrowsError(try repository.load())
        XCTAssertThrowsError(try repository.save(ListeningHistory()))
        XCTAssertEqual(try Data(contentsOf: repository.fileURL), corrupt)
    }

    func testUnsupportedHistoryAndConcurrentWritesArePreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Wisp-listening-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ListeningRepository(directory: directory)
        var history = try first.load(now: date())
        try first.save(history)
        let second = ListeningRepository(directory: directory)
        _ = try second.load()
        history.record(track: track(), seconds: 2, qualifiedPlay: false, at: date(), calendar: calendar)
        try first.save(history)
        let newerBytes = try Data(contentsOf: first.fileURL)
        XCTAssertThrowsError(try second.save(ListeningHistory()))
        XCTAssertEqual(try Data(contentsOf: first.fileURL), newerBytes)
        var object = try JSONSerialization.jsonObject(with: newerBytes) as! [String: Any]
        object["version"] = 99
        let future = try JSONSerialization.data(withJSONObject: object)
        try future.write(to: first.fileURL)
        XCTAssertThrowsError(try first.load())
        XCTAssertThrowsError(try first.save(ListeningHistory()))
        XCTAssertEqual(try Data(contentsOf: first.fileURL), future)
    }

    func testDuplicateAndNegativeRecordsFailValidation() throws {
        var history = ListeningHistory(trackingStartedAt: date())
        history.record(track: track(), seconds: 1, qualifiedPlay: false, at: date(), calendar: calendar)
        var object = try JSONSerialization.jsonObject(with: ListeningRepository.encode(history)) as! [String: Any]
        var entries = object["entries"] as! [[String: Any]]
        entries.append(entries[0]); object["entries"] = entries
        XCTAssertThrowsError(try ListeningRepository.decode(JSONSerialization.data(withJSONObject: object)))
        entries.removeLast(); entries[0]["seconds"] = -1; object["entries"] = entries
        XCTAssertThrowsError(try ListeningRepository.decode(JSONSerialization.data(withJSONObject: object)))
    }
}

final class ListeningSessionAccumulatorTests: XCTestCase {
    func testPlayQualifiesOnceAfterThirtyActualSeconds() {
        var session = ListeningSessionAccumulator(duration: 180)
        session.resetBaseline(position: 0, uptime: 100)
        var qualifications = 0
        for index in 1...160 {
            let seconds = Double(index) / 4
            let sample = session.sample(position: seconds, uptime: 100 + seconds)
            qualifications += sample.qualifiedPlay ? 1 : 0
        }
        XCTAssertEqual(session.accumulatedSeconds, 40)
        XCTAssertTrue(session.hasQualifiedPlay)
        XCTAssertEqual(qualifications, 1)
    }

    func testShortTrackQualifiesAfterHalfAndNewRunStartsFresh() {
        var session = ListeningSessionAccumulator(duration: 8)
        session.resetBaseline(position: 0, uptime: 0)
        for second in 1...3 { XCTAssertFalse(session.sample(position: Double(second), uptime: Double(second)).qualifiedPlay) }
        XCTAssertTrue(session.sample(position: 4, uptime: 4).qualifiedPlay)
        session = ListeningSessionAccumulator(duration: 8)
        session.resetBaseline(position: 0, uptime: 5)
        XCTAssertFalse(session.sample(position: 1, uptime: 6).qualifiedPlay)
        XCTAssertEqual(session.accumulatedSeconds, 1)
    }

    func testPauseAndSeekBaselineRetainEarnedTimeButAddNoIdleOrSkippedTime() {
        var session = ListeningSessionAccumulator(duration: 180)
        session.resetBaseline(position: 0, uptime: 0)
        for second in 1...29 { _ = session.sample(position: Double(second), uptime: Double(second)) }
        // Pause for ten minutes, then seek forward before resuming.
        session.resetBaseline(position: 100, uptime: 629)
        XCTAssertTrue(session.sample(position: 101, uptime: 630).qualifiedPlay)
        XCTAssertEqual(session.accumulatedSeconds, 30)
    }

    func testJumpsBackwardsStallsAndLongGapsDoNotCreateListeningTime() {
        var session = ListeningSessionAccumulator(duration: 180)
        session.resetBaseline(position: 0, uptime: 0)
        XCTAssertEqual(session.sample(position: 60, uptime: 1).seconds, 0)
        XCTAssertEqual(session.sample(position: 0, uptime: 2).seconds, 0)
        XCTAssertEqual(session.sample(position: 0, uptime: 3).seconds, 0)
        XCTAssertEqual(session.sample(position: 60, uptime: 63).seconds, 0)
        XCTAssertEqual(session.sample(position: 61, uptime: 64).seconds, 1)
        XCTAssertEqual(session.accumulatedSeconds, 1)
    }

    func testMonotonicElapsedCapsSmallPlayheadJitterAndBadInputsResetBaseline() {
        var session = ListeningSessionAccumulator(duration: 180)
        session.resetBaseline(position: 0, uptime: 1)
        XCTAssertEqual(session.sample(position: 1.1, uptime: 2).seconds, 1)
        XCTAssertEqual(session.sample(position: .nan, uptime: 3).seconds, 0)
        XCTAssertEqual(session.sample(position: 3, uptime: 4).seconds, 0)
        XCTAssertEqual(session.sample(position: 4, uptime: 3).seconds, 0)
        XCTAssertEqual(session.accumulatedSeconds, 1)
    }

    func testInvalidDurationDoesNotQualifyAutomatically() {
        for duration in [0.0, -1, .nan, .infinity] {
            var session = ListeningSessionAccumulator(duration: duration)
            session.resetBaseline(position: 0, uptime: 0)
            XCTAssertFalse(session.sample(position: 1, uptime: 1).qualifiedPlay)
        }
    }
}
