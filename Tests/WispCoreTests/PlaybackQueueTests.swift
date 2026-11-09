import Foundation
import XCTest
@testable import WispCore

final class PlaybackQueueTests: XCTestCase {
    private let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let c = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let d = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

    func testStartDeduplicatesAndHonorsClickedTrack() {
        var queue = PlaybackQueue()
        XCTAssertEqual(queue.start(ids: [a, b, a, c], startID: b), b)
        XCTAssertEqual(queue.sourceIDs, [a, b, c])
        XCTAssertEqual(queue.orderedIDs, [a, b, c])
        XCTAssertEqual(queue.next(repeating: .off), c)
    }

    func testQueueEndDoesNotWrapOrLoseTheLastSelection() {
        var queue = PlaybackQueue()
        queue.start(ids: [a, b])
        XCTAssertEqual(queue.next(repeating: .off), b)
        XCTAssertNil(queue.next(repeating: .off, userInitiated: false))
        XCTAssertEqual(queue.currentID, b)
        XCTAssertEqual(queue.previous(repeating: .off), a)
        XCTAssertEqual(queue.previous(repeating: .off), a)
    }

    func testRepeatOneAffectsCompletionButNotManualSkipping() {
        var queue = PlaybackQueue()
        queue.start(ids: [a, b])
        XCTAssertEqual(queue.next(repeating: .one, userInitiated: false), a)
        XCTAssertEqual(queue.next(repeating: .one), b)
        XCTAssertNil(queue.next(repeating: .one))
        XCTAssertEqual(queue.previous(repeating: .one), a)
    }

    func testRepeatAllWrapsBothDirections() {
        var queue = PlaybackQueue()
        queue.start(ids: [a, b])
        XCTAssertEqual(queue.previous(repeating: .all), b)
        XCTAssertEqual(queue.next(repeating: .all), a)
    }

    func testShuffledExplicitStartKeepsEachTrackExactlyOnce() {
        var queue = PlaybackQueue()
        queue.start(ids: [a, b, c, d], startID: b, shuffled: true, randomize: { Array($0.reversed()) })
        XCTAssertEqual(queue.orderedIDs, [b, d, c, a])
        XCTAssertEqual(queue.currentID, b)
        XCTAssertEqual(Set(queue.orderedIDs).count, 4)
    }

    func testShuffleCycleDoesNotImmediatelyRepeatLastTrack() {
        var queue = PlaybackQueue()
        queue.start(ids: [a, b, c], shuffled: true, randomize: { $0 })
        XCTAssertEqual(queue.next(repeating: .all), b)
        XCTAssertEqual(queue.next(repeating: .all), c)
        XCTAssertEqual(queue.next(repeating: .all, randomize: { Array($0.reversed()) }), b)
        XCTAssertEqual(queue.orderedIDs, [b, c, a])
        XCTAssertEqual(Set(queue.orderedIDs), Set([a, b, c]))
    }

    func testEnablingShuffleKeepsHistoryAndCurrentTrack() {
        var queue = PlaybackQueue()
        queue.start(ids: [a, b, c, d], startID: b)
        queue.setShuffled(true, randomize: { Array($0.reversed()) })
        XCTAssertEqual(queue.orderedIDs, [a, b, d, c])
        XCTAssertEqual(queue.currentID, b)
        queue.setShuffled(false)
        XCTAssertEqual(queue.orderedIDs, [a, b, c, d])
        XCTAssertEqual(queue.currentID, b)
    }

    func testRemovingCurrentSelectsSurvivingSuccessor() {
        var queue = PlaybackQueue()
        queue.start(ids: [a, b, c, d], startID: b)
        XCTAssertEqual(queue.remove(Set([b, c]), repeating: .off), d)
        XCTAssertEqual(queue.sourceIDs, [a, d])
        XCTAssertEqual(queue.orderedIDs, [a, d])
        XCTAssertNil(queue.remove(Set([d]), repeating: .off))
        XCTAssertEqual(queue.orderedIDs, [a])
    }

    func testRemovingLastCurrentWrapsOnlyForRepeatAll() {
        var queue = PlaybackQueue()
        queue.start(ids: [a, b], startID: b)
        XCTAssertEqual(queue.remove(Set([b]), repeating: .all), a)
        XCTAssertNil(queue.remove(Set([a]), repeating: .all))
        XCTAssertTrue(queue.orderedIDs.isEmpty)
    }

    func testReconcilePreservesCurrentAndRemovesDeletedTracks() {
        var queue = PlaybackQueue()
        queue.start(ids: [a, b, c], startID: b)
        XCTAssertEqual(queue.retainAvailable(Set([b, c, d]), repeating: .off), b)
        XCTAssertEqual(queue.sourceIDs, [b, c])
        XCTAssertEqual(queue.orderedIDs, [b, c])
    }

    func testRestoreRejectsDuplicateAndForeignOrderEntries() {
        let queue = PlaybackQueue(sourceIDs: [a, b, a, c], orderedIDs: [d, c, c, b], currentID: d, isShuffled: true)
        XCTAssertEqual(queue.sourceIDs, [a, b, c])
        XCTAssertEqual(queue.orderedIDs, [c, b, a])
        XCTAssertNil(queue.currentID)
    }

    func testBadRandomizerCannotLoseOrInjectTracks() {
        var queue = PlaybackQueue()
        queue.start(ids: [a, b, c], shuffled: true, randomize: { _ in [self.d, self.b, self.b] })
        XCTAssertEqual(queue.orderedIDs, [b, a, c])
    }

    func testSingleTrackRepeatingAndEmptyQueueAreFinite() {
        var queue = PlaybackQueue()
        XCTAssertNil(queue.next(repeating: .all))
        queue.start(ids: [a], shuffled: true)
        for _ in 0..<20 { XCTAssertEqual(queue.next(repeating: .all), a) }
        queue.clear()
        XCTAssertNil(queue.previous(repeating: .all))
        XCTAssertNil(queue.currentID)
    }

    func testFailedTracksCannotHideAValidTrackAtAShuffleBoundary() {
        var queue = PlaybackQueue(sourceIDs: [a, b, c], orderedIDs: [a, b, c], currentID: b, isShuffled: true)
        let next = queue.nextPlayable(repeating: .all, excluding: Set([b, c]), randomize: { _ in [self.c, self.b, self.a] })
        XCTAssertEqual(next, a)
    }

    func testFailedRepeatOneTrackAdvancesToAnotherTrack() {
        var queue = PlaybackQueue()
        queue.start(ids: [a, b])
        XCTAssertEqual(queue.nextPlayable(repeating: .one, userInitiated: false, excluding: Set([a])), b)
    }

    func testAllFailedFilesTerminateEvenWhenRepeatingAll() {
        var queue = PlaybackQueue()
        queue.start(ids: [a, b, c], shuffled: true, randomize: { $0 })
        var shuffleCalls = 0
        let result = queue.nextPlayable(repeating: .all, excluding: Set([a, b, c])) { ids in
            shuffleCalls += 1
            return ids
        }
        XCTAssertNil(result)
        XCTAssertLessThanOrEqual(shuffleCalls, 2)
    }

    func testFailureSkippingDoesNotWrapWithoutRepeatAll() {
        var queue = PlaybackQueue()
        queue.start(ids: [a, b, c], startID: b)
        XCTAssertNil(queue.nextPlayable(repeating: .off, excluding: Set([c])))
        XCTAssertEqual(queue.currentID, c)
    }

    func testQueueRoundTripPreservesOrderAndPosition() throws {
        var queue = PlaybackQueue()
        queue.start(ids: [a, b, c], startID: b, shuffled: true, randomize: { Array($0.reversed()) })
        let copy = try JSONDecoder().decode(PlaybackQueue.self, from: JSONEncoder().encode(queue))
        XCTAssertEqual(copy, queue)
    }
}
