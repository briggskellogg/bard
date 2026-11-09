import Foundation
import XCTest
@testable import WispCore

final class EnergyShuffleTests: XCTestCase {
    private func tracks(_ count: Int) -> [Track] {
        (0..<count).map { Track(title: "Song \($0)", artist: "Artist \($0)", fileName: "\($0).wav", fingerprint: "\($0)") }
    }

    func testCurveKeepsFiveFiniteClampedMarkers() throws {
        var curve = EnergyCurve(levels: [-1, 2, .nan])
        XCTAssertEqual(curve.levels, [0, 1, 0.5, 0.5, 0.5])
        curve.set(0, to: 0.25); curve.set(99, to: 0); curve.set(1, to: .infinity)
        XCTAssertEqual(curve.levels, [0.25, 1, 0.5, 0.5, 0.5])
        XCTAssertEqual(curve.value(at: -3), 0.25)
        XCTAssertEqual(curve.value(at: 4), 0.5)
        XCTAssertEqual(curve.value(at: 0.25), 1)
        XCTAssertEqual(try JSONDecoder().decode(EnergyCurve.self, from: JSONEncoder().encode(curve)), curve)
        let short = try JSONDecoder().decode(EnergyCurve.self, from: Data("{\"levels\":[0.2]}".utf8))
        XCTAssertEqual(short.levels, Array(repeating: 0.2, count: 5))
    }

    func testContinuousListeningBlendRetainsExactPresetStopsAndClamps() {
        XCTAssertEqual(EnergyCurve.listeningBlend(at: 0), .focus)
        XCTAssertEqual(EnergyCurve.listeningBlend(at: 1), .flow)
        XCTAssertEqual(EnergyCurve.listeningBlend(at: 2), .surge)
        XCTAssertEqual(EnergyCurve.listeningBlend(at: -100), .focus)
        XCTAssertEqual(EnergyCurve.listeningBlend(at: 100), .surge)
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(EnergyCurve.listeningBlend(at: invalid), .flow)
            XCTAssertEqual(EnergyCurve.clampListeningBlendPosition(invalid), 1)
        }
    }

    func testContinuousListeningBlendIntermediatesAndInverse() {
        let segments: [(Double, EnergyCurve, EnergyCurve)] = [(0.5, .focus, .flow), (1.5, .flow, .surge)]
        for (position, first, second) in segments {
            let expected = zip(first.levels, second.levels).map { ($0 + $1) / 2 }
            let result = EnergyCurve.listeningBlend(at: position)
            for (value, target) in zip(result.levels, expected) { XCTAssertEqual(value, target, accuracy: 1e-12) }
        }
        for step in 0...200 {
            let position = Double(step) / 100
            let curve = EnergyCurve.listeningBlend(at: position)
            XCTAssertEqual(curve.nearestListeningBlendPosition, position, accuracy: 1e-9)
            XCTAssertTrue(curve.levels.allSatisfy { $0.isFinite && (0...1).contains($0) })
        }
        // A custom saved curve maps to the best point on either preset segment,
        // not simply the nearest named preset.
        let custom = EnergyCurve(levels: [0.32, 0.48, 0.31, 0.52, 0.24])
        let position = custom.nearestListeningBlendPosition
        XCTAssertTrue((0...2).contains(position))
        func squaredError(_ curve: EnergyCurve) -> Double {
            zip(curve.levels, custom.levels).reduce(0) { $0 + pow($1.0 - $1.1, 2) }
        }
        let error = squaredError(.listeningBlend(at: position))
        for stop in stride(from: 0.0, through: 2.0, by: 0.01) {
            XCTAssertLessThanOrEqual(error, squaredError(.listeningBlend(at: stop)) + 1e-12)
        }
    }

    func testContinuousListeningBlendHasSmoothPresetJunctionAndMatchesQueue() {
        let epsilon = 0.0001
        for stop in [0.0, 1.0, 2.0] {
            let at = EnergyCurve.listeningBlend(at: stop)
            for nearby in [stop - epsilon, stop + epsilon] {
                for (value, expected) in zip(EnergyCurve.listeningBlend(at: nearby).levels, at.levels) {
                    XCTAssertLessThan(abs(value - expected), 0.000001)
                }
            }
        }
        let songs = tracks(60), ids = songs.map(\.id)
        let scores = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, Double($0.offset) / 59) })
        for position in [0.0, 0.5, 1.0, 1.5, 2.0] {
            let result = EnergyShuffle.order(ids: ids, tracks: songs, scores: scores, curve: .listeningBlend(at: position), count: 20, randomUnit: { 0.5 })!
            XCTAssertEqual(result.count, 20)
            XCTAssertEqual(Set(result).count, 20)
            XCTAssertTrue(Set(result).isSubset(of: Set(ids)))
        }
    }

    func testBuildAndSettleFollowMeasuredEnergy() {
        let songs = tracks(9), ids = songs.map(\.id)
        let scores = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, Double($0.offset) / 8) })
        let scrambled = Array(ids.reversed())
        XCTAssertEqual(EnergyShuffle.order(ids: scrambled, tracks: songs, scores: scores, curve: .build, randomUnit: { 0.5 }), ids)
        XCTAssertEqual(EnergyShuffle.order(ids: ids, tracks: songs, scores: scores, curve: .settle, randomUnit: { 0.5 }), scrambled)
    }

    func testWaveHasPeaksAndValleysWithoutExhaustingLowEnergyTracks() {
        let songs = tracks(5), ids = songs.map(\.id)
        let scores = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, Double($0.offset) / 4) })
        let result = EnergyShuffle.order(ids: ids, tracks: songs, scores: scores, curve: .wave, randomUnit: { 0.5 })!
        XCTAssertEqual(result, [ids[0], ids[3], ids[2], ids[4], ids[1]])
        XCTAssertEqual(Set(result), Set(ids))
    }

    func testArtistSpacingIsSecondaryToEnergy() {
        var songs = tracks(4)
        songs[0].artist = " Artist A "; songs[1].artist = "artist a"
        let ids = songs.map(\.id)
        let scores = [ids[0]: 0.0, ids[1]: 0.02, ids[2]: 0.04, ids[3]: 1.0]
        let result = EnergyShuffle.order(ids: ids, tracks: songs, scores: scores, curve: .build, randomUnit: { 0.5 })!
        XCTAssertEqual(result, [ids[0], ids[2], ids[1], ids[3]])
        songs[2].artist = "Artist A"
        XCTAssertEqual(EnergyShuffle.order(ids: ids, tracks: songs, scores: scores, curve: .build, randomUnit: { 0.5 }), ids)
    }

    func testUnmeasuredOrInvalidEnergyDoesNotPretendToBeSmartShuffle() {
        let songs = tracks(3), ids = songs.map(\.id)
        XCTAssertNil(EnergyShuffle.order(ids: ids, tracks: songs, scores: [ids[0]: 0.2], curve: .wave))
        XCTAssertNil(EnergyShuffle.order(ids: ids, tracks: songs, scores: [ids[0]: 0, ids[1]: .nan, ids[2]: 1], curve: .wave))
        XCTAssertNil(EnergyShuffle.order(ids: ids, tracks: songs, scores: [ids[0]: 0, ids[1]: 2, ids[2]: 1], curve: .wave))
    }

    func testPermutationsNeverLoseOrAddSongsAcrossCurves() {
        let songs = tracks(30), ids = songs.map(\.id)
        var scores = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, Double($0.offset) / 29) })
        scores[UUID()] = 1
        for curve in [EnergyCurve.build, .settle, .wave, EnergyCurve(levels: [0.5])] {
            for _ in 0..<20 {
                let result = EnergyShuffle.order(ids: ids + [ids[0]], tracks: songs, scores: scores, curve: curve)!
                XCTAssertEqual(result.count, ids.count)
                XCTAssertEqual(Set(result), Set(ids))
            }
        }
        XCTAssertEqual(EnergyShuffle.order(ids: [], tracks: songs, scores: scores, curve: .wave), [])
        XCTAssertEqual(EnergyShuffle.order(ids: [ids[0]], tracks: songs, scores: scores, curve: .wave), [ids[0]])
        XCTAssertEqual(Set(EnergyShuffle.order(ids: ids, tracks: songs, scores: scores, curve: .wave, randomUnit: { .nan })!), Set(ids))
    }

    func testCalmAndIntenseCurvesChooseDifferentMatchingSubsets() {
        let songs = tracks(30), ids = songs.map(\.id)
        let scores = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, Double($0.offset) / 29) })
        let calm = EnergyShuffle.order(ids: ids, tracks: songs, scores: scores, curve: EnergyCurve(levels: [0]), count: 10, randomUnit: { 0.5 })!
        let intense = EnergyShuffle.order(ids: ids, tracks: songs, scores: scores, curve: EnergyCurve(levels: [1]), count: 10, randomUnit: { 0.5 })!
        XCTAssertEqual(calm, Array(ids.prefix(10)))
        XCTAssertEqual(intense, Array(ids.suffix(10)))
        XCTAssertTrue(Set(calm).isDisjoint(with: Set(intense)))
        let wave = EnergyShuffle.order(ids: ids, tracks: songs, scores: scores, curve: .wave, count: 5, randomUnit: { 0.5 })!
        XCTAssertEqual(wave.count, 5)
        XCTAssertEqual(Set(wave).count, 5)
        XCTAssertTrue(scores[wave[1]]! > 0.75 && scores[wave[3]]! > 0.85)
        XCTAssertTrue(scores[wave[0]]! < 0.3 && scores[wave[4]]! < 0.3)
        XCTAssertEqual(EnergyShuffle.order(ids: ids, tracks: songs, scores: scores, curve: .wave, count: 0), [])
    }

    func testFixedListeningShapesCreateDistinctMeasuredSets() {
        let songs = tracks(60), ids = songs.map(\.id)
        let scores = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, Double($0.offset) / 59) })
        let focus = EnergyShuffle.order(ids: ids, tracks: songs, scores: scores, curve: .focus, count: 10, randomUnit: { 0.5 })!
        let surge = EnergyShuffle.order(ids: ids, tracks: songs, scores: scores, curve: .surge, count: 10, randomUnit: { 0.5 })!
        let flow = EnergyShuffle.order(ids: ids, tracks: songs, scores: scores, curve: .flow, count: 10, randomUnit: { 0.5 })!
        XCTAssertTrue(focus.allSatisfy { scores[$0]! < 0.35 })
        XCTAssertTrue(surge.contains { scores[$0]! > 0.9 })
        XCTAssertTrue(scores[surge.first!]! < 0.25 && scores[surge.last!]! < 0.35)
        XCTAssertTrue(flow.allSatisfy { scores[$0]! > 0.15 && scores[$0]! < 0.8 })
        XCTAssertEqual(Set(focus).count, 10)
        XCTAssertEqual(Set(surge).count, 10)
        XCTAssertEqual(Set(flow).count, 10)
    }

    func testChangingShuffleStrategyPreservesCurrentAndHistory() {
        let songs = tracks(5), ids = songs.map(\.id)
        var queue = PlaybackQueue()
        queue.start(ids: ids, startID: ids[1])
        queue.setShuffled(true, randomize: { $0 })
        queue.reshuffleUpcoming { _ in [ids[4], ids[4], UUID()] }
        XCTAssertEqual(queue.orderedIDs, [ids[0], ids[1], ids[4], ids[2], ids[3]])
        XCTAssertEqual(queue.currentID, ids[1])
        queue.setShuffled(false)
        XCTAssertEqual(queue.orderedIDs, ids)
    }
}
