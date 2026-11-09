import XCTest
import CryptoKit
@testable import WispCore

final class PhoneFavoritesTests: XCTestCase {
    private let fm = FileManager.default
    private var root: URL!
    private var library: URL { root.appendingPathComponent("Mac") }
    private var shared: URL { root.appendingPathComponent("Wisp") }
    private var cache: URL { root.appendingPathComponent("Phone") }
    private var identity = UUID()
    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("WispFavorites-\(UUID())")
        try fm.createDirectory(at: library.appendingPathComponent("Media"), withIntermediateDirectories: true)
        try fm.createDirectory(at: library.appendingPathComponent("Artwork"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: root) }
    private func fixture() throws -> (LibraryDocument, PhoneLibraryManifest, PhoneLibrarySnapshot) {
        let bytes = Data("immutable audio bytes".utf8)
        try bytes.write(to: library.appendingPathComponent("Media/song.wav"))
        let track = Track(title:"Song", artist:"Artist",fileName:"song.wav",
            fingerprint:SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined(),
            duration:3,byteCount:Int64(bytes.count),addedAt:Date(timeIntervalSince1970:1000),origin:"",remix:.basic)
        let doc = LibraryDocument(tracks:[track])
        let manifest = try PhoneLibraryPublisher.publish(document:doc,libraryDirectory:library,destination:shared,sourceLibraryID:identity)
        return (doc,manifest,try PhoneLibraryReceiver.receive(source:shared,cacheDirectory:cache))
    }
    private func revision(_ value:Int64, snapshot:PhoneLibrarySnapshot) -> PhoneLibrarySnapshot {
        PhoneLibrarySnapshot(document:snapshot.document,mediaDirectory:snapshot.mediaDirectory,artworkDirectory:snapshot.artworkDirectory,sourceLibraryID:snapshot.sourceLibraryID,revision:value)
    }
    func testOfflineIntentSurvivesEncodingAndOnlyChangesFavorite() throws {
        let (doc,_,_) = try fixture()
        var outbox=PhoneFavoriteOutbox(sourceLibraryID:identity,deviceID:UUID())
        try outbox.set(true,for:doc.tracks[0].id)
        let restored=try JSONDecoder().decode(PhoneFavoriteOutbox.self,from:JSONEncoder().encode(outbox))
        try restored.validate()
        var expected=doc;expected.tracks[0].favorite=true
        XCTAssertEqual(restored.applying(to:doc),expected)
        XCTAssertEqual(outbox.changes.count,1)
        XCTAssertFalse(doc.tracks[0].favorite)
    }
    func testAcknowledgementWaitsForItsPublishedRevision() throws {
        let (doc,_,snapshot)=try fixture()
        var outbox=PhoneFavoriteOutbox(sourceLibraryID:identity,deviceID:UUID())
        try outbox.set(true,for:doc.tracks[0].id)
        let ack=PhoneFavoriteAcknowledgement(sourceLibraryID:identity,deviceID:outbox.deviceID,sequence:1,publishedRevision:snapshot.revision+1)
        try outbox.acknowledge(ack,snapshot:snapshot)
        XCTAssertTrue(outbox.applying(to:doc).tracks[0].favorite)
        XCTAssertEqual(outbox.changes.count,1)
        try outbox.acknowledge(ack,snapshot:revision(snapshot.revision+1,snapshot:snapshot))
        XCTAssertTrue(outbox.changes.isEmpty)
        XCTAssertNil(outbox.batch)
        XCTAssertEqual(outbox.sequence,1)
        // A later Mac change is no longer overridden by acknowledged intent.
        XCTAssertEqual(outbox.applying(to:doc),doc)
    }
    func testNewTapSurvivesAnOlderReceiptAndRelaunch() throws {
        let (doc,_,snapshot)=try fixture()
        var outbox=PhoneFavoriteOutbox(sourceLibraryID:identity,deviceID:UUID())
        try outbox.set(true,for:doc.tracks[0].id)
        try outbox.set(false,for:doc.tracks[0].id)
        XCTAssertEqual(outbox.changes.count,1)
        try outbox.acknowledge(PhoneFavoriteAcknowledgement(sourceLibraryID:identity,deviceID:outbox.deviceID,sequence:1,publishedRevision:snapshot.revision),snapshot:snapshot)
        XCTAssertEqual(outbox.changes.first?.sequence,2)
        let restored=try JSONDecoder().decode(PhoneFavoriteOutbox.self,from:JSONEncoder().encode(outbox))
        try restored.validate();XCTAssertEqual(restored.sequence,2)
        XCTAssertFalse(restored.applying(to:doc).tracks[0].favorite)
    }
    func testBatchRejectsIdentityDuplicatesAndInvalidSequence() throws {
        let id=UUID(),device=UUID(),song=UUID()
        var batch=PhoneFavoriteBatch(sourceLibraryID:id,deviceID:device,sequence:1,changes:[.init(sequence:1,trackID:song,isFavorite:true)])
        XCTAssertThrowsError(try batch.validate(sourceLibraryID:UUID()))
        batch.changes.append(batch.changes[0]);XCTAssertThrowsError(try batch.validate(sourceLibraryID:id))
        batch.changes.removeLast();batch.sequence=2;XCTAssertThrowsError(try batch.validate(sourceLibraryID:id))
        batch.sequence=0;XCTAssertThrowsError(try batch.validate(sourceLibraryID:id))
    }
    func testSeparateDevicesAndIdempotentOutboxNeverChangeAudioOrManifest() throws {
        let (doc,manifest,_)=try fixture()
        let before=try Data(contentsOf:shared.appendingPathComponent("Library.json"))
        let audio=try Data(contentsOf:shared.appendingPathComponent(manifest.assets[0].relativePath))
        var a=PhoneFavoriteOutbox(sourceLibraryID:identity,deviceID:UUID()),b=PhoneFavoriteOutbox(sourceLibraryID:identity,deviceID:UUID())
        try a.set(true,for:doc.tracks[0].id);try b.set(false,for:doc.tracks[0].id)
        try PhoneFavoritesSync.publish(a.batch!,to:shared);try PhoneFavoritesSync.publish(b.batch!,to:shared)
        try PhoneFavoritesSync.publish(a.batch!,to:shared)
        XCTAssertEqual(Set(try PhoneFavoritesSync.batches(in:shared,sourceLibraryID:identity).map(\.deviceID)),Set([a.deviceID,b.deviceID]))
        XCTAssertEqual(try Data(contentsOf:shared.appendingPathComponent("Library.json")),before)
        XCTAssertEqual(try Data(contentsOf:shared.appendingPathComponent(manifest.assets[0].relativePath)),audio)
    }
    func testOlderOrConflictingOutboxCannotOverwriteNewerIntent() throws {
        let (doc,_,_)=try fixture()
        var outbox=PhoneFavoriteOutbox(sourceLibraryID:identity,deviceID:UUID())
        try outbox.set(true,for:doc.tracks[0].id);let old=outbox.batch!
        try outbox.set(false,for:doc.tracks[0].id);let latest=outbox.batch!
        try PhoneFavoritesSync.publish(latest,to:shared)
        XCTAssertThrowsError(try PhoneFavoritesSync.publish(old,to:shared))
        var conflict=latest;conflict.changes[0].isFavorite=true
        XCTAssertThrowsError(try PhoneFavoritesSync.publish(conflict,to:shared))
        XCTAssertEqual(try PhoneFavoritesSync.batches(in:shared,sourceLibraryID:identity),[latest])
    }
    func testPartialAcknowledgementCanRepublishSubsetAtSameSequence() throws {
        let (doc,_,snapshot)=try fixture()
        var outbox=PhoneFavoriteOutbox(sourceLibraryID:identity,deviceID:UUID())
        try outbox.set(true,for:doc.tracks[0].id)
        try outbox.set(true,for:UUID())
        let full=outbox.batch!
        try PhoneFavoritesSync.publish(full,to:shared)
        try outbox.acknowledge(.init(sourceLibraryID:identity,deviceID:outbox.deviceID,sequence:1,publishedRevision:snapshot.revision),snapshot:snapshot)
        XCTAssertEqual(outbox.changes.count,1)
        try PhoneFavoritesSync.publish(outbox.batch!,to:shared)
        XCTAssertEqual(try PhoneFavoritesSync.batches(in:shared,sourceLibraryID:identity),[full])
        try outbox.acknowledge(.init(sourceLibraryID:identity,deviceID:outbox.deviceID,sequence:2,publishedRevision:snapshot.revision),snapshot:snapshot)
        XCTAssertTrue(outbox.changes.isEmpty)
    }
    func testAckMustReferToAnAlreadyPublishedRevisionAndNeverRegresses() throws {
        let (_,manifest,_)=try fixture();let device=UUID()
        let premature=PhoneFavoriteAcknowledgement(sourceLibraryID:identity,deviceID:device,sequence:2,publishedRevision:manifest.revision+1)
        XCTAssertThrowsError(try PhoneFavoritesSync.acknowledge(premature,in:shared))
        XCTAssertFalse(fm.fileExists(atPath:shared.appendingPathComponent("Favorites").path))
        let ack=PhoneFavoriteAcknowledgement(sourceLibraryID:identity,deviceID:device,sequence:2,publishedRevision:manifest.revision)
        try PhoneFavoritesSync.acknowledge(ack,in:shared)
        var older=ack;older.sequence=1;try PhoneFavoritesSync.acknowledge(older,in:shared)
        XCTAssertEqual(try PhoneFavoritesSync.acknowledgement(in:shared,sourceLibraryID:identity,deviceID:device),ack)
    }
    func testWrongLibraryAndSymlinkCannotReceiveFavoriteWrites() throws {
        let (doc,_,_)=try fixture()
        var outbox=PhoneFavoriteOutbox(sourceLibraryID:UUID(),deviceID:UUID())
        try outbox.set(true,for:doc.tracks[0].id)
        XCTAssertThrowsError(try PhoneFavoritesSync.publish(outbox.batch!,to:shared))
        XCTAssertFalse(fm.fileExists(atPath:shared.appendingPathComponent("Favorites").path))
        let outside=root.appendingPathComponent("Outside")
        try fm.createDirectory(at:outside,withIntermediateDirectories:false)
        try fm.createSymbolicLink(at:shared.appendingPathComponent("Favorites"),withDestinationURL:outside)
        var owned=PhoneFavoriteOutbox(sourceLibraryID:identity,deviceID:UUID());try owned.set(true,for:doc.tracks[0].id)
        XCTAssertThrowsError(try PhoneFavoritesSync.publish(owned.batch!,to:shared))
        XCTAssertTrue(try fm.contentsOfDirectory(atPath:outside.path).isEmpty)
    }
    func testDeviceFileLinksAndOversizedDataAreRejected() throws {
        let (doc,_,_)=try fixture();let device=UUID()
        var outbox=PhoneFavoriteOutbox(sourceLibraryID:identity,deviceID:device);try outbox.set(true,for:doc.tracks[0].id)
        let directory=shared.appendingPathComponent("Favorites"),outside=root.appendingPathComponent("outside.json")
        try fm.createDirectory(at:directory,withIntermediateDirectories:false)
        try Data("untouched".utf8).write(to:outside)
        let target=directory.appendingPathComponent(device.uuidString+".json")
        try fm.createSymbolicLink(at:target,withDestinationURL:outside)
        XCTAssertThrowsError(try PhoneFavoritesSync.publish(outbox.batch!,to:shared))
        XCTAssertEqual(try Data(contentsOf:outside),Data("untouched".utf8))
        try fm.removeItem(at:target);try Data(repeating:0,count:2*1024*1024+1).write(to:target)
        XCTAssertThrowsError(try PhoneFavoritesSync.batches(in:shared,sourceLibraryID:identity))
    }
    func testMacReceiptsAreNotPublishedToPhone() throws {
        var (doc,_,_)=try fixture()
        doc.phoneFavoriteReceipts[UUID().uuidString]=4
        let manifest=try PhoneLibraryPublisher.publish(document:doc,libraryDirectory:library,destination:shared,sourceLibraryID:identity)
        XCTAssertTrue(manifest.document.phoneFavoriteReceipts.isEmpty)
        XCTAssertTrue(try PhoneLibraryReceiver.receive(source:shared,cacheDirectory:cache).document.phoneFavoriteReceipts.isEmpty)
        XCTAssertEqual(doc.phoneFavoriteReceipts.count,1)
    }
}
