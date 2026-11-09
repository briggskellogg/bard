import XCTest
import Foundation
import CryptoKit
@testable import WispCore

final class PhoneLibrarySyncTests: XCTestCase {
    private var root: URL!
    private var library: URL { root.appendingPathComponent("Mac") }
    private var remote: URL { root.appendingPathComponent("Shared") }
    private var cache: URL { root.appendingPathComponent("Phone") }
    private let sourceID = UUID()
    private let fm = FileManager.default
    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("WispPhoneSyncTests-\(UUID())")
        try fm.createDirectory(at: library.appendingPathComponent("Media"), withIntermediateDirectories: true)
        try fm.createDirectory(at: library.appendingPathComponent("Artwork"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let root { try? fm.removeItem(at: root) } }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format:"%02x",$0) }.joined() }
    private func audio(_ name: String, text: String) throws -> Track {
        let data = Data(text.utf8)
        try data.write(to: library.appendingPathComponent("Media").appendingPathComponent(name))
        return Track(title: text, artist: "Fixture", fileName: name, fingerprint: hash(data), duration: 4,
                     byteCount: Int64(data.count), addedAt: Date(timeIntervalSince1970: 1000), origin: "Fixture origin", remix: .basic)
    }
    private func document() throws -> LibraryDocument {
        var a = try audio("a.wav", text: "first audio")
        let b = try audio("b.mp3", text: "second audio")
        a.artworkFileName = "cover.png"
        a.artworkSource = TrackArtworkSource(provider: "Fixture", sourcePageURL: "https://example.com/art", appliedAt: Date(timeIntervalSince1970:1000))
        try Data("exact cover fixture".utf8).write(to: library.appendingPathComponent("Artwork/cover.png"))
        let playlist = Playlist(name: "Mixtape", coverFileName: "cover.png", trackIDs: [b.id, a.id], createdAt: Date(timeIntervalSince1970:1000))
        return LibraryDocument(tracks: [a,b], playlists: [playlist])
    }
    private func publish(_ doc: LibraryDocument) throws -> PhoneLibraryManifest {
        try PhoneLibraryPublisher.publish(document: doc, libraryDirectory: library, destination: remote, sourceLibraryID: sourceID)
    }
    private func receive() throws -> PhoneLibrarySnapshot { try PhoneLibraryReceiver.receive(source: remote, cacheDirectory: cache) }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let e = JSONEncoder();e.outputFormatting = [.sortedKeys];e.dateEncodingStrategy = .millisecondsSince1970;return try e.encode(value)
    }
    private func write(_ manifest: PhoneLibraryManifest) throws { try encode(manifest).write(to: remote.appendingPathComponent("Library.json"),options:.atomic) }
    private func assertCurrent(_ snapshot: PhoneLibrarySnapshot, file: StaticString = #filePath, line: UInt = #line) throws {
        let current = try XCTUnwrap(PhoneLibraryReceiver.current(cacheDirectory: cache), file:file,line:line)
        XCTAssertEqual(current.revision, snapshot.revision, file:file,line:line)
        XCTAssertEqual(current.document, snapshot.document, file:file,line:line)
        XCTAssertEqual(current.mediaDirectory, snapshot.mediaDirectory, file:file,line:line)
    }

    func testInitialAndRepeatedTransferPreservesIdentityOrderArtworkAndBytes() throws {
        let doc = try document(), published = try publish(doc), first = try receive()
        XCTAssertEqual(first.document, doc)
        XCTAssertEqual(first.sourceLibraryID, sourceID)
        XCTAssertEqual(first.revision, published.revision)
        XCTAssertEqual(first.document.playlists[0].trackIDs, doc.playlists[0].trackIDs)
        for track in doc.tracks {
            XCTAssertEqual(try Data(contentsOf:first.mediaDirectory.appendingPathComponent(track.fileName)), try Data(contentsOf:library.appendingPathComponent("Media").appendingPathComponent(track.fileName)))
        }
        XCTAssertEqual(try Data(contentsOf:first.artworkDirectory.appendingPathComponent("cover.png")), Data("exact cover fixture".utf8))
        XCTAssertEqual(published.assets.count, 3) // shared song/playlist art is listed once
        let currentData = try Data(contentsOf:cache.appendingPathComponent("Current.json"))
        let repeated = try publish(doc)
        XCTAssertEqual(repeated, published)
        XCTAssertEqual(try receive().mediaDirectory, first.mediaDirectory)
        XCTAssertEqual(try Data(contentsOf:cache.appendingPathComponent("Current.json")), currentData)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath:cache.appendingPathComponent("Snapshots").path).count, 1)
    }
    func testArchivesRemainOnlyOnMacAndReceiptsAreNeverPublished() throws {
        var doc = try document()
        let old = try audio("old.wav", text: "archived old audio")
        doc.schemaVersion = 2
        doc.tracks[0].currentAudioVersionID = UUID(); doc.tracks[0].currentAudioAddedAt = Date(timeIntervalSince1970:2000)
        doc.tracks[0].audioVersions = [TrackAudioVersion(fileName: old.fileName, fingerprint: old.fingerprint, duration: old.duration,
            byteCount: old.byteCount, originalFileName: old.fileName, addedAt: old.addedAt)]
        try Data("private Music receipts".utf8).write(to:library.appendingPathComponent("MusicSync.json"))
        try Data("private preferences".utf8).write(to:library.appendingPathComponent("Preferences.json"))
        let published = try publish(doc), snapshot = try receive()
        XCTAssertTrue(snapshot.document.tracks.allSatisfy { $0.audioVersions.isEmpty && $0.currentAudioVersionID == nil && $0.currentAudioAddedAt == nil })
        XCTAssertEqual(doc.tracks[0].audioVersions.count, 1)
        XCTAssertTrue(fm.fileExists(atPath:library.appendingPathComponent("Media/old.wav").path))
        XCTAssertFalse(published.assets.contains { $0.fileName == "old.wav" })
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath:remote.path)), ["Assets","Library.json"])
    }
    func testMetadataReorderAndRemovalReuseAssetsAndRetainOldSnapshots() throws {
        var doc = try document(); _ = try publish(doc); let old = try receive()
        let before = Set(try fm.contentsOfDirectory(atPath:remote.appendingPathComponent("Assets").path))
        doc.tracks[0].title = "Updated title"; doc.playlists[0].trackIDs.reverse()
        let changed = try publish(doc), next = try receive()
        XCTAssertGreaterThan(next.revision, old.revision)
        XCTAssertEqual(next.document, doc)
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath:remote.appendingPathComponent("Assets").path)), before)
        XCTAssertTrue(fm.fileExists(atPath:old.mediaDirectory.appendingPathComponent("a.wav").path))
        doc.playlists[0].trackIDs = [doc.tracks[0].id]; doc.tracks.removeLast()
        let removed = try publish(doc), last = try receive()
        XCTAssertGreaterThan(removed.revision, changed.revision)
        XCTAssertEqual(last.document.tracks.count, 1)
        XCTAssertTrue(fm.fileExists(atPath:old.mediaDirectory.appendingPathComponent("b.mp3").path))
        XCTAssertEqual(Set(try fm.contentsOfDirectory(atPath:remote.appendingPathComponent("Assets").path)), before)
    }
    func testReplacementKeepsTrackIDAndOldPlayableFile() throws {
        var doc = try document(); _ = try publish(doc); let old = try receive()
        let oldURL = old.mediaDirectory.appendingPathComponent(doc.tracks[0].fileName), oldBytes = try Data(contentsOf:oldURL)
        let bytes = Data("new active audio".utf8)
        try bytes.write(to:library.appendingPathComponent("Media/a.wav"))
        doc.tracks[0].fingerprint = hash(bytes); doc.tracks[0].byteCount = Int64(bytes.count)
        _ = try publish(doc); let new = try receive()
        XCTAssertEqual(new.document.tracks[0].id, old.document.tracks[0].id)
        XCTAssertNotEqual(new.mediaDirectory, old.mediaDirectory)
        XCTAssertEqual(try Data(contentsOf:oldURL), oldBytes)
        XCTAssertEqual(try Data(contentsOf:new.mediaDirectory.appendingPathComponent("a.wav")), bytes)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath:remote.appendingPathComponent("Assets").path).count, 4)
    }
    func testManifestArrivingBeforeAssetsKeepsCurrentUntilComplete() throws {
        var doc = try document(); _ = try publish(doc); let old = try receive()
        let added = try audio("later.wav", text: "later audio");doc.tracks.append(added)
        let next = try publish(doc), entry = try XCTUnwrap(next.assets.first { $0.fileName == added.fileName })
        let file = remote.appendingPathComponent(entry.relativePath), held = root.appendingPathComponent("held")
        try fm.moveItem(at:file,to:held)
        XCTAssertThrowsError(try receive())
        try assertCurrent(old)
        try fm.moveItem(at:held,to:file)
        XCTAssertEqual(try receive().document, doc)
    }
    func testOldAndSameRevisionConflictingManifestsCannotRollBackCurrent() throws {
        var doc = try document(); let original = try publish(doc); _ = try receive()
        doc.tracks[0].title = "newest"; let latest = try publish(doc), current = try receive()
        try write(original)
        XCTAssertThrowsError(try receive()) { XCTAssertEqual($0 as? PhoneLibrarySyncError, .olderRevision) }
        try assertCurrent(current)
        var conflict = latest; conflict.document.tracks[0].title = "same revision, different data";try write(conflict)
        XCTAssertThrowsError(try receive()) { XCTAssertEqual($0 as? PhoneLibrarySyncError, .conflictingRevision) }
        try assertCurrent(current)
    }
    func testHashMismatchAndWrongSizeDoNotActivate() throws {
        var doc = try document();_ = try publish(doc);let old = try receive()
        let added = try audio("later.wav",text:"new extra audio");doc.tracks.append(added)
        let manifest = try publish(doc), asset = try XCTUnwrap(manifest.assets.first { $0.fileName == added.fileName })
        let file = remote.appendingPathComponent(asset.relativePath), bytes = try Data(contentsOf:file)
        try Data(repeating:0,count:bytes.count).write(to:file)
        XCTAssertThrowsError(try receive());try assertCurrent(old)
        try bytes.write(to:file)
        var wrongSize = manifest;let index = wrongSize.assets.firstIndex { $0.fileName == added.fileName }!;wrongSize.assets[index].byteCount += 1
        try write(wrongSize);XCTAssertThrowsError(try receive());try assertCurrent(old)
    }
    func testForeignPublisherAndReceiverOwnershipPreserveExistingFiles() throws {
        let doc = try document();_ = try publish(doc);let old = try receive()
        let bytes = try Data(contentsOf:remote.appendingPathComponent("Library.json"))
        XCTAssertThrowsError(try PhoneLibraryPublisher.publish(document:doc,libraryDirectory:library,destination:remote,sourceLibraryID:UUID())) { XCTAssertEqual($0 as? PhoneLibrarySyncError,.differentLibrary) }
        XCTAssertEqual(try Data(contentsOf:remote.appendingPathComponent("Library.json")),bytes)
        var other = try JSONDecoder.phone.decode(PhoneLibraryManifest.self,from:bytes);other.sourceLibraryID = UUID();try write(other)
        XCTAssertThrowsError(try receive()) { XCTAssertEqual($0 as? PhoneLibrarySyncError,.differentLibrary) };try assertCurrent(old)
    }
    func testUnsafePathsDuplicateAssetsAndUnsupportedVersionAreRejected() throws {
        let doc = try document(), good = try publish(doc), current = try receive()
        var bad = good; bad.revision += 1;bad.assets[0].relativePath = "../outside"
        try write(bad);XCTAssertThrowsError(try receive());try assertCurrent(current)
        bad = good;bad.revision += 1;bad.assets[0].fileName = "../escape.wav"
        try write(bad);XCTAssertThrowsError(try receive());try assertCurrent(current)
        bad = good;bad.revision += 1;bad.assets.append(bad.assets[0])
        try write(bad);XCTAssertThrowsError(try receive());try assertCurrent(current)
        bad = good;bad.formatVersion = 99
        try write(bad);XCTAssertThrowsError(try receive()) { XCTAssertEqual($0 as? PhoneLibrarySyncError,.unsupportedVersion) };try assertCurrent(current)
    }
    func testAssetAndDirectorySymlinksAreRejectedWithoutFollowingThem() throws {
        var doc = try document();_ = try publish(doc);let current = try receive()
        let added = try audio("later.wav",text:"separate bytes");doc.tracks.append(added)
        let next = try publish(doc), asset = try XCTUnwrap(next.assets.first { $0.fileName == added.fileName })
        let url = remote.appendingPathComponent(asset.relativePath), outside = root.appendingPathComponent("outside")
        try fm.moveItem(at:url,to:outside);try fm.createSymbolicLink(at:url,withDestinationURL:outside)
        XCTAssertThrowsError(try receive()) { XCTAssertEqual($0 as? PhoneLibrarySyncError,.unsafePath) };try assertCurrent(current)
        XCTAssertEqual(try Data(contentsOf:outside),Data("separate bytes".utf8))
        let media = library.appendingPathComponent("Media"), moved = root.appendingPathComponent("moved-media")
        try fm.moveItem(at:media,to:moved);try fm.createSymbolicLink(at:media,withDestinationURL:moved)
        XCTAssertThrowsError(try publish(doc)) { XCTAssertEqual($0 as? PhoneLibrarySyncError,.unsafePath) }
    }
    func testMissingSourceOrModifiedFingerprintDoesNotPublishNewManifest() throws {
        var doc = try document();_ = try publish(doc)
        let original = try Data(contentsOf:remote.appendingPathComponent("Library.json"))
        try fm.removeItem(at:library.appendingPathComponent("Media/a.wav"))
        doc.tracks[0].title = "must not publish"
        XCTAssertThrowsError(try publish(doc));XCTAssertEqual(try Data(contentsOf:remote.appendingPathComponent("Library.json")),original)
        try Data("changed behind library".utf8).write(to:library.appendingPathComponent("Media/a.wav"))
        XCTAssertThrowsError(try publish(doc));XCTAssertEqual(try Data(contentsOf:remote.appendingPathComponent("Library.json")),original)
    }
    func testFinderMetadataIsAllowedAndSnapshotsReuseImmutableCacheFiles() throws {
        let doc = try document()
        try fm.createDirectory(at:remote,withIntermediateDirectories:true)
        try Data("Finder metadata".utf8).write(to:remote.appendingPathComponent(".DS_Store"))
        let manifest = try publish(doc), snapshot = try receive()
        let asset = try XCTUnwrap(manifest.assets.first { $0.kind == .audio })
        let cached = cache.appendingPathComponent(asset.relativePath), local = snapshot.mediaDirectory.appendingPathComponent(asset.fileName)
        let cachedAttributes = try fm.attributesOfItem(atPath:cached.path), localAttributes = try fm.attributesOfItem(atPath:local.path)
        XCTAssertEqual(cachedAttributes[.systemFileNumber] as? NSNumber,localAttributes[.systemFileNumber] as? NSNumber)
        XCTAssertEqual(try Data(contentsOf:remote.appendingPathComponent(".DS_Store")),Data("Finder metadata".utf8))
    }
    func testEmptyLibraryAndMetadataOnlyUpdateDoNotRequireRemoteAssetHydration() throws {
        let empty = LibraryDocument();_ = try publish(empty)
        try fm.removeItem(at:remote.appendingPathComponent("Assets"))
        XCTAssertTrue(try receive().document.tracks.isEmpty)
        let doc = try document();_ = try publish(doc);_ = try receive()
        var changed = doc;changed.tracks[0].title = "Metadata only";_ = try publish(changed)
        try fm.removeItem(at:remote.appendingPathComponent("Assets"))
        XCTAssertEqual(try receive().document,changed)
    }
    func testTrackByteCountMustMatchInventoryAndSourceBytes() throws {
        var doc = try document();let good = try publish(doc), old = try receive()
        doc.tracks[0].byteCount += 1
        XCTAssertThrowsError(try publish(doc));try assertCurrent(old)
        var mismatched = good;mismatched.revision += 1;mismatched.document.tracks[0].byteCount += 1;try write(mismatched)
        XCTAssertThrowsError(try receive()) { XCTAssertEqual($0 as? PhoneLibrarySyncError,.invalidManifest) }
        try assertCurrent(old)
    }
    func testMalformedManifestAndCorruptPointerNeverDiscardOldSnapshotFiles() throws {
        let doc = try document();_ = try publish(doc);let old = try receive()
        try Data("half-transferred JSON".utf8).write(to:remote.appendingPathComponent("Library.json"))
        XCTAssertThrowsError(try receive());try assertCurrent(old)
        let oldAudio = try Data(contentsOf:old.mediaDirectory.appendingPathComponent("a.wav"))
        try Data("broken pointer".utf8).write(to:cache.appendingPathComponent("Current.json"))
        XCTAssertThrowsError(try PhoneLibraryReceiver.current(cacheDirectory:cache))
        XCTAssertEqual(try Data(contentsOf:old.mediaDirectory.appendingPathComponent("a.wav")),oldAudio)
    }
    func testUnownedFolderAndOverlappingRootsAreRejected() throws {
        let doc = try document();try fm.createDirectory(at:remote,withIntermediateDirectories:true)
        try Data("unrelated".utf8).write(to:remote.appendingPathComponent("Keep Me.txt"))
        XCTAssertThrowsError(try publish(doc)) { XCTAssertEqual($0 as? PhoneLibrarySyncError,.unownedDestination) }
        XCTAssertEqual(try Data(contentsOf:remote.appendingPathComponent("Keep Me.txt")),Data("unrelated".utf8))
        XCTAssertThrowsError(try PhoneLibraryPublisher.publish(document:doc,libraryDirectory:library,destination:library.appendingPathComponent("Nested"),sourceLibraryID:sourceID)) { XCTAssertEqual($0 as? PhoneLibrarySyncError,.unsafePath) }
        XCTAssertNil(try PhoneLibraryReceiver.current(cacheDirectory:cache))
    }
    func testCloudFirstConnectionStartsEveryUncachedDownloadBeforeWaiting() throws {
        let doc = try document(), manifest = try publish(doc)
        let urls = Set(manifest.assets.map { remote.appendingPathComponent($0.relativePath) })
        var requested: [URL] = []
        let waiting = PhoneLibraryDownloadAccess(state: { urls.contains($0) ? .notDownloaded : .local },
                                                start: { requested.append($0) })
        XCTAssertThrowsError(try PhoneLibraryReceiver.receive(source:remote,cacheDirectory:cache,downloads:waiting)) {
            guard case .waitingForDownload = $0 as? PhoneLibrarySyncError else { return XCTFail("Expected typed download wait, got \($0)") }
            XCTAssertTrue(($0 as? PhoneLibrarySyncError)?.isRetryable == true)
        }
        XCTAssertEqual(Set(requested),urls)
        XCTAssertEqual(requested.count,urls.count)
        XCTAssertNil(try PhoneLibraryReceiver.current(cacheDirectory:cache))
        XCTAssertFalse(fm.fileExists(atPath:cache.appendingPathComponent("Current.json").path))
        XCTAssertEqual(try fm.contentsOfDirectory(atPath:cache.appendingPathComponent("Assets").path),[])
        // The same approved folder activates after all requested originals arrive.
        let ready = PhoneLibraryDownloadAccess(state: { _ in .current },start: { _ in XCTFail("Current bytes do not need download") })
        XCTAssertEqual(try PhoneLibraryReceiver.receive(source:remote,cacheDirectory:cache,downloads:ready).document,doc)
    }
    func testCloudUpdateStartsAllNewDownloadsEvenWhenOneRequestFails() throws {
        var doc = try document();_ = try publish(doc);let old = try receive()
        doc.tracks.append(try audio("later-one.wav",text:"new cloud one"))
        doc.tracks.append(try audio("later-two.wav",text:"new cloud two"))
        let manifest = try publish(doc)
        let urls = Set(manifest.assets.filter { $0.fileName.hasPrefix("later-") }.map { remote.appendingPathComponent($0.relativePath) })
        var requested: [URL] = []
        let downloading = PhoneLibraryDownloadAccess(state: { urls.contains($0) ? .notDownloaded : .local }, start: {
            requested.append($0)
            if requested.count == 1 { throw NSError(domain:NSCocoaErrorDomain,code:256) }
        })
        XCTAssertThrowsError(try PhoneLibraryReceiver.receive(source:remote,cacheDirectory:cache,downloads:downloading)) {
            XCTAssertTrue(($0 as? PhoneLibrarySyncError)?.isRetryable == true)
        }
        XCTAssertEqual(Set(requested),urls)
        XCTAssertEqual(requested.count,2) // Cached songs/art are not requested again.
        try assertCurrent(old)
        XCTAssertEqual(try receive().document,doc)
    }
    func testAbsentPlaceholderCanRequestManifestBeforeNormalFileExists() throws {
        let doc = try document();_ = try publish(doc)
        let manifest = remote.appendingPathComponent("Library.json"), bytes = try Data(contentsOf:manifest)
        try fm.removeItem(at:manifest)
        var requested: [URL] = []
        let cloud = PhoneLibraryDownloadAccess(state: { $0 == manifest ? .notDownloaded : .local },start: { requested.append($0) })
        XCTAssertThrowsError(try PhoneLibraryReceiver.receive(source:remote,cacheDirectory:cache,downloads:cloud)) {
            XCTAssertEqual($0 as? PhoneLibrarySyncError,.waitingForDownload("Library.json"))
        }
        XCTAssertEqual(requested,[manifest])
        XCTAssertNil(try PhoneLibraryReceiver.current(cacheDirectory:cache))
        try bytes.write(to:manifest)
        XCTAssertEqual(try receive().document,doc)
    }
    func testStaleDownloadedManifestWaitsForCurrentCloudVersion() throws {
        var doc = try document();_ = try publish(doc);let old = try receive()
        doc.tracks[0].title = "New cloud title";_ = try publish(doc)
        let manifest = remote.appendingPathComponent("Library.json")
        var requested: [URL] = []
        let cloud = PhoneLibraryDownloadAccess(state: { $0 == manifest ? .stale : .local },start: { requested.append($0) })
        XCTAssertThrowsError(try PhoneLibraryReceiver.receive(source:remote,cacheDirectory:cache,downloads:cloud)) {
            XCTAssertEqual($0 as? PhoneLibrarySyncError,.waitingForDownload("Library.json"))
        }
        XCTAssertEqual(requested,[manifest]);try assertCurrent(old)
        XCTAssertEqual(try receive().document,doc)
    }
    func testMissingAssetDoesNotPreventRequestingOtherCloudAssets() throws {
        let doc = try document(), manifest = try publish(doc)
        let urls = manifest.assets.map { remote.appendingPathComponent($0.relativePath) }
        let missing = try XCTUnwrap(urls.first);try fm.removeItem(at:missing)
        var requested: [URL] = []
        let cloud = PhoneLibraryDownloadAccess(state: { url in
            urls.contains(url) && url != missing ? .notDownloaded : .local
        },start: { requested.append($0) })
        XCTAssertThrowsError(try PhoneLibraryReceiver.receive(source:remote,cacheDirectory:cache,downloads:cloud)) {
            XCTAssertTrue(($0 as? PhoneLibrarySyncError)?.isRetryable == true)
        }
        XCTAssertEqual(Set(requested),Set(urls.dropFirst()))
        XCTAssertNil(try PhoneLibraryReceiver.current(cacheDirectory:cache))
    }
    func testCloudPreflightNeverRequestsDownloadsThroughSymlinks() throws {
        let doc = try document(), manifest = try publish(doc)
        let asset = try XCTUnwrap(manifest.assets.first), file = remote.appendingPathComponent(asset.relativePath)
        let outside = root.appendingPathComponent("outside-cloud-file")
        try fm.moveItem(at:file,to:outside);try fm.createSymbolicLink(at:file,withDestinationURL:outside)
        var requested: [URL] = []
        let cloud = PhoneLibraryDownloadAccess(state: { $0 == file ? .notDownloaded : .local },start: { requested.append($0) })
        XCTAssertThrowsError(try PhoneLibraryReceiver.receive(source:remote,cacheDirectory:cache,downloads:cloud)) {
            XCTAssertEqual($0 as? PhoneLibrarySyncError,.unsafePath)
        }
        XCTAssertFalse(requested.contains(file));XCTAssertTrue(fm.fileExists(atPath:outside.path))
        XCTAssertNil(try PhoneLibraryReceiver.current(cacheDirectory:cache))
    }
    func testCloudHydrationStillHashesAdmittedBytesAndRetainsOldSnapshot() throws {
        var doc = try document();_ = try publish(doc);let old = try receive()
        let next = try audio("cloud-corrupt.wav",text:"new cloud data");doc.tracks.append(next)
        let manifest = try publish(doc), asset = try XCTUnwrap(manifest.assets.first { $0.fileName == next.fileName })
        let file = remote.appendingPathComponent(asset.relativePath)
        let original = try Data(contentsOf:file);try Data(repeating:0,count:original.count).write(to:file)
        let cloud = PhoneLibraryDownloadAccess(state: { _ in .current },start: { _ in XCTFail("Current file should not download") })
        XCTAssertThrowsError(try PhoneLibraryReceiver.receive(source:remote,cacheDirectory:cache,downloads:cloud)) {
            XCTAssertEqual($0 as? PhoneLibrarySyncError,.changedAsset(next.fileName))
            XCTAssertFalse(($0 as? PhoneLibrarySyncError)?.isRetryable ?? true)
        }
        try assertCurrent(old)
        XCTAssertFalse(fm.fileExists(atPath:cache.appendingPathComponent(asset.relativePath).path))
    }
    func testProviderMetadataFailureDoesNotBlockOtherDownloadRequests() throws {
        let doc = try document(), manifest = try publish(doc)
        let urls = manifest.assets.map { remote.appendingPathComponent($0.relativePath) }, unavailable = try XCTUnwrap(urls.first)
        var requested: [URL] = []
        let cloud = PhoneLibraryDownloadAccess(state: { url in
            if url == unavailable { throw NSError(domain:NSCocoaErrorDomain,code:256) }
            return urls.contains(url) ? .notDownloaded : .local
        },start: { requested.append($0) })
        XCTAssertThrowsError(try PhoneLibraryReceiver.receive(source:remote,cacheDirectory:cache,downloads:cloud)) {
            guard case .coordination = $0 as? PhoneLibrarySyncError else { return XCTFail("Expected typed provider retry") }
        }
        XCTAssertEqual(Set(requested),Set(urls.dropFirst()))
        XCTAssertNil(try PhoneLibraryReceiver.current(cacheDirectory:cache))
    }
    func testCancellationDuringDownloadRequestRetainsCurrentAndIsNotProviderFailure() throws {
        var doc = try document();_ = try publish(doc);let old = try receive()
        let added = try audio("cancelled.wav",text:"cancelled cloud bytes");doc.tracks.append(added)
        let manifest = try publish(doc), asset = try XCTUnwrap(manifest.assets.first { $0.fileName == added.fileName })
        let file = remote.appendingPathComponent(asset.relativePath)
        let cloud = PhoneLibraryDownloadAccess(state: { $0 == file ? .notDownloaded : .local },start: { _ in throw CancellationError() })
        XCTAssertThrowsError(try PhoneLibraryReceiver.receive(source:remote,cacheDirectory:cache,downloads:cloud)) {
            XCTAssertTrue($0 is CancellationError)
        }
        try assertCurrent(old)
    }
    func testWrongFolderWithoutManifestIsTerminalAndPreservesCurrentLibrary() throws {
        let doc = try document();_ = try publish(doc);let old = try receive()
        let wrong = root.appendingPathComponent("Unrelated custom folder")
        try fm.createDirectory(at:wrong,withIntermediateDirectories:true)
        try Data("unrelated content".utf8).write(to:wrong.appendingPathComponent("Keep Me.txt"))
        XCTAssertThrowsError(try PhoneLibraryReceiver.receive(source:wrong,cacheDirectory:cache)) {
            XCTAssertEqual($0 as? PhoneLibrarySyncError,.missingLibraryManifest)
            XCTAssertFalse(($0 as? PhoneLibrarySyncError)?.isRetryable ?? true)
        }
        try assertCurrent(old)
        XCTAssertEqual(try Data(contentsOf:wrong.appendingPathComponent("Keep Me.txt")),Data("unrelated content".utf8))
        // The valid fixture folder has a custom name; no name heuristic rejects it.
        XCTAssertEqual(try receive().document,doc)
    }
    func testCloudRetryClassificationDoesNotHideIntegrityOrOwnershipErrors() {
        for error in [PhoneLibrarySyncError.waitingForDownload("a"), .missingAsset("a"), .coordination("busy")] {
            XCTAssertTrue(error.isRetryable)
        }
        for error in [PhoneLibrarySyncError.invalidManifest, .missingLibraryManifest, .unsafePath, .changedAsset("a"), .differentLibrary,
                      .olderRevision, .conflictingRevision, .invalidCache, .unownedDestination, .limit, .unsupportedVersion] {
            XCTAssertFalse(error.isRetryable)
        }
    }

}

private extension JSONDecoder {
    static var phone: JSONDecoder { let d = JSONDecoder();d.dateDecodingStrategy = .millisecondsSince1970;return d }
}
