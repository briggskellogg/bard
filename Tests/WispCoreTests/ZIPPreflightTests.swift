import Foundation
import XCTest
@testable import WispCore

final class ZIPPreflightTests: XCTestCase {
    func testOrdinaryAlbumWithDirectoryAndUnicodeNames() throws {
        let zip = makeArchive([
            Item("Album/"),
            Item("Album/01 - Première.wav", bytes: [1, 2, 3, 4], flags: 0x0800),
            Item("Album/cover.jpg", bytes: [5, 6])
        ])
        let report = try ZIPPreflight.validate(zip.data)
        XCTAssertEqual(report.entries.map(\.path), ["Album", "Album/01 - Première.wav", "Album/cover.jpg"])
        XCTAssertTrue(report.entries[0].isDirectory)
        XCTAssertEqual(report.uncompressedBytes, 6)
    }

    func testEmptyArchiveAndEmptyFile() throws {
        XCTAssertTrue(try ZIPPreflight.validate(makeArchive([]).data).entries.isEmpty)
        let report = try ZIPPreflight.validate(makeArchive([Item("silent.wav")]).data)
        XCTAssertEqual(report.entries.count, 1)
        XCTAssertEqual(report.uncompressedBytes, 0)
    }

    func testDataDescriptorsWithAndWithoutSignatures() throws {
        for signed in [false, true] {
            let zip = makeArchive([Item("song.wav", bytes: [1, 2, 3], descriptor: true, signedDescriptor: signed)])
            XCTAssertEqual(try ZIPPreflight.validate(zip.data).uncompressedBytes, 3)
        }
    }

    func testTimestampExtraFieldAndArchiveComment() throws {
        var timestamp = Data([0x01])
        timestamp.appendLE32(0)
        let extra = field(0x5455, timestamp)
        let zip = makeArchive([Item("song.wav", bytes: [42], extra: extra)], comment: "album download")
        XCTAssertEqual(try ZIPPreflight.validate(zip.data).entries.first?.path, "song.wav")
    }

    func testTraversalAndPlatformPathSeparatorsAreRejected() {
        for name in ["../song.wav", "/song.wav", "a/../../song.wav", "a//song.wav", "a/./song.wav", "a\\song.wav", "C:/song.wav", "a\u{0000}b.wav", "//server/song.wav", "a/../"] {
            assertFailure(.unsafePath, makeArchive([Item(name)]).data, name)
        }
    }

    func testSymlinksAndSpecialFilesAreRejected() {
        for mode: UInt32 in [0o120777, 0o010600, 0o020600, 0o060600, 0o140600] {
            let zip = makeArchive([Item("song.wav", bytes: Array("/tmp/target".utf8), attributes: mode << 16)])
            assertFailure(.symbolicLink, zip.data)
        }
    }

    func testDirectoryAttributesMustAgreeWithNameAndContent() {
        assertFailure(.malformed, makeArchive([Item("folder", attributes: UInt32(0o040755) << 16)]).data)
        assertFailure(.malformed, makeArchive([Item("folder/", bytes: [42])]).data)
        assertFailure(.malformed, makeArchive([Item("folder/", attributes: UInt32(0o100644) << 16)]).data)
    }

    func testCaseAndUnicodeEquivalentNamesConflict() {
        for names in [["Song.wav", "song.wav"], ["café.wav", "cafe\u{0301}.wav"], ["song.wav", "song.wav"]] {
            assertFailure(.conflictingPaths, makeArchive(names.map { Item($0) }).data)
        }
    }

    func testFileCannotAlsoBeAnAncestorDirectory() {
        assertFailure(.conflictingPaths, makeArchive([Item("album"), Item("album/song.wav")]).data)
        assertFailure(.conflictingPaths, makeArchive([Item("album/song.wav"), Item("Album")]).data)
    }

    func testLocalFilenameMustMatchCentralDirectoryExactly() {
        let zip = makeArchive([Item("safe.wav", bytes: [42], localName: "../x.wav")])
        assertFailure(.malformed, zip.data)
    }

    func testLocalSizesFlagsMethodAndCRCDisagreementAreRejected() {
        let valid = makeArchive([Item("song.wav", bytes: [1, 2, 3])])
        var size = valid.data
        size.writeLE32(2, at: 18)
        assertFailure(.malformed, size)
        var flags = valid.data
        flags.writeLE16(0x0800, at: 6)
        assertFailure(.malformed, flags)
        var method = valid.data
        method.writeLE16(8, at: 8)
        assertFailure(.malformed, method)
        var crc = valid.data
        crc.writeLE32(1, at: 14)
        assertFailure(.malformed, crc)
    }

    func testDescriptorCannotDisagreeWithCentralDirectory() {
        let zip = makeArchive([Item("song.wav", bytes: [1, 2, 3], descriptor: true)])
        var wrongSize = zip.data
        wrongSize.writeLE32(1, at: zip.centralOffsets[0] - 4)
        assertFailure(.malformed, wrongSize)
    }

    func testOverlappingOrUnlistedLocalRecordsAreRejected() {
        let zip = makeArchive([Item("one.wav", bytes: [1]), Item("two.wav", bytes: [2])])
        var overlapping = zip.data
        overlapping.writeLE32(0, at: zip.centralOffsets[1] + 42)
        assertFailure(.malformed, overlapping)

        // A central directory listing only the second local record leaves an
        // unlisted first record that a streaming extractor could otherwise read.
        var unlisted = zip.data
        let firstCentralSize = zip.centralOffsets[1] - zip.centralOffsets[0]
        unlisted.removeSubrange(zip.centralOffsets[0]..<zip.centralOffsets[1])
        let end = zip.endOffset - firstCentralSize
        unlisted.writeLE16(1, at: end + 8)
        unlisted.writeLE16(1, at: end + 10)
        unlisted.writeLE32(UInt32(zip.endOffset - zip.centralOffsets[1]), at: end + 12)
        assertFailure(.malformed, unlisted)
    }

    func testEncryptionAndMultipartAreRejected() {
        for flags: UInt16 in [0x0001, 0x0040, 0x2000] {
            assertFailure(.encrypted, makeArchive([Item("song.wav", flags: flags)]).data)
        }
        let zip = makeArchive([Item("song.wav")])
        var split = zip.data
        split.writeLE16(1, at: zip.endOffset + 4)
        assertFailure(.multipart, split)
        var centralDisk = zip.data
        centralDisk.writeLE16(1, at: zip.centralOffsets[0] + 34)
        assertFailure(.multipart, centralDisk)
    }

    func testZip64SentinelsAndExtraFieldsHaveSpecificFallback() {
        let zip = makeArchive([Item("song.wav")])
        var sentinel = zip.data
        sentinel.writeLE16(UInt16.max, at: zip.endOffset + 10)
        assertFailure(.zip64, sentinel)
        let extra = field(0x0001, Data(repeating: 0, count: 16))
        assertFailure(.zip64, makeArchive([Item("song.wav", extra: extra)]).data)
        let description = ZIPPreflight.Failure.zip64.localizedDescription
        XCTAssertTrue(description.contains("Finder"))
    }

    func testUnicodePathOverrideCannotRedirectExtraction() {
        var unicode = Data([1])
        unicode.appendLE32(0)
        unicode.append(contentsOf: "../outside.wav".utf8)
        let extra = field(0x7075, unicode)
        assertFailure(.unsafePath, makeArchive([Item("song.wav", extra: extra)]).data)
    }

    func testUnknownLinkMetadataAndMalformedExtraFieldsAreRejected() {
        assertFailure(.unsupported, makeArchive([Item("song.wav", extra: field(0x000d, Data(repeating: 0, count: 12)))]).data)
        assertFailure(.malformed, makeArchive([Item("song.wav", extra: Data([0x55, 0x54, 0xff, 0xff]))]).data)
        let duplicate = field(0x5455, Data([0])) + field(0x5455, Data([0]))
        assertFailure(.malformed, makeArchive([Item("song.wav", extra: duplicate)]).data)
    }

    func testLocalExtraMetadataIsValidatedIndependently() {
        let zip = makeArchive([Item("song.wav", localExtra: field(0x000d, Data(repeating: 0, count: 12)))])
        assertFailure(.unsupported, zip.data)
    }

    func testEntryTotalCountDepthAndExpansionLimits() {
        let zip = makeArchive([Item("a.wav", bytes: [1, 2]), Item("b.wav", bytes: [3, 4])])
        assertFailure(.limit, zip.data, limits: .init(maximumEntries: 1))
        assertFailure(.limit, zip.data, limits: .init(maximumTotalBytes: 3))
        assertFailure(.limit, zip.data, limits: .init(maximumEntryBytes: 1))
        assertFailure(.unsafePath, makeArchive([Item("a/b/song.wav")]).data, limits: .init(maximumDepth: 2))
        // Only headers are inspected here: ditto performs actual decompression.
        let bomb = makeArchive([Item("huge.wav", bytes: [0], method: 8, uncompressed: 2 * 1024 * 1024)])
        assertFailure(.limit, bomb.data)
    }

    func testTruncationsAndGarbageFailWithoutOutOfBoundsAccess() {
        let valid = makeArchive([Item("song.wav", bytes: [1, 2, 3])]).data
        for count in 0..<valid.count {
            assertFailure(.malformed, Data(valid.prefix(count)))
        }
        for count in [0, 1, 21, 22, 255, 4096] {
            assertFailure(.malformed, Data(repeating: 0xff, count: count))
        }
    }

    func testDataSlicesWithNonzeroStartIndexAreSupported() throws {
        let valid = makeArchive([Item("song.wav", bytes: [1])]).data
        var padded = Data(repeating: 0, count: 17)
        padded.append(valid)
        let slice = padded.dropFirst(17)
        XCTAssertEqual(try ZIPPreflight.validate(slice).entries.count, 1)
    }

    private func assertFailure(_ expected: ZIPPreflight.Failure, _ data: Data, _ message: String = "",
                               limits: ZIPPreflight.Limits = .init(), file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try ZIPPreflight.validate(data, limits: limits), message, file: file, line: line) { error in
            XCTAssertEqual(error as? ZIPPreflight.Failure, expected, message, file: file, line: line)
        }
    }

    private struct Item {
        var name: String
        var bytes: [UInt8]
        var flags: UInt16
        var method: UInt16
        var attributes: UInt32
        var extra: Data
        var localName: String?
        var localExtra: Data?
        var descriptor: Bool
        var signedDescriptor: Bool
        var uncompressed: UInt32?

        init(_ name: String, bytes: [UInt8] = [], flags: UInt16 = 0, method: UInt16 = 0,
             attributes: UInt32? = nil, extra: Data = Data(), localName: String? = nil,
             localExtra: Data? = nil, descriptor: Bool = false, signedDescriptor: Bool = true,
             uncompressed: UInt32? = nil) {
            self.name = name
            self.bytes = bytes
            self.flags = flags
            self.method = method
            self.attributes = attributes ?? (name.hasSuffix("/") ? (UInt32(0o040755) << 16) | 0x10 : UInt32(0o100644) << 16)
            self.extra = extra
            self.localName = localName
            self.localExtra = localExtra
            self.descriptor = descriptor
            self.signedDescriptor = signedDescriptor
            self.uncompressed = uncompressed
        }
        var effectiveFlags: UInt16 { flags | (descriptor ? 0x0008 : 0) }
        var size: UInt32 { uncompressed ?? UInt32(bytes.count) }
        var crc: UInt32 {
            var value = UInt32.max
            for byte in bytes {
                value ^= UInt32(byte)
                for _ in 0..<8 { value = (value >> 1) ^ (value & 1 == 1 ? 0xedb88320 : 0) }
            }
            return value ^ UInt32.max
        }
    }

    private struct Fixture {
        var data: Data
        var centralOffsets: [Int]
        var endOffset: Int
    }

    private func makeArchive(_ items: [Item], comment: String = "") -> Fixture {
        var data = Data()
        var localOffsets: [Int] = []
        for item in items {
            localOffsets.append(data.count)
            let name = Data((item.localName ?? item.name).utf8)
            let extra = item.localExtra ?? item.extra
            data.appendLE32(0x04034b50)
            data.appendLE16(20)
            data.appendLE16(item.effectiveFlags)
            data.appendLE16(item.method)
            data.appendLE16(0)
            data.appendLE16(0)
            data.appendLE32(item.descriptor ? 0 : item.crc)
            data.appendLE32(item.descriptor ? 0 : UInt32(item.bytes.count))
            data.appendLE32(item.descriptor ? 0 : item.size)
            data.appendLE16(UInt16(name.count))
            data.appendLE16(UInt16(extra.count))
            data.append(name)
            data.append(extra)
            data.append(contentsOf: item.bytes)
            if item.descriptor {
                if item.signedDescriptor { data.appendLE32(0x08074b50) }
                data.appendLE32(item.crc)
                data.appendLE32(UInt32(item.bytes.count))
                data.appendLE32(item.size)
            }
        }
        let centralStart = data.count
        var centralOffsets: [Int] = []
        for (index, item) in items.enumerated() {
            centralOffsets.append(data.count)
            let name = Data(item.name.utf8)
            data.appendLE32(0x02014b50)
            data.appendLE16(0x0314)
            data.appendLE16(20)
            data.appendLE16(item.effectiveFlags)
            data.appendLE16(item.method)
            data.appendLE16(0)
            data.appendLE16(0)
            data.appendLE32(item.crc)
            data.appendLE32(UInt32(item.bytes.count))
            data.appendLE32(item.size)
            data.appendLE16(UInt16(name.count))
            data.appendLE16(UInt16(item.extra.count))
            data.appendLE16(0)
            data.appendLE16(0)
            data.appendLE16(0)
            data.appendLE32(item.attributes)
            data.appendLE32(UInt32(localOffsets[index]))
            data.append(name)
            data.append(item.extra)
        }
        let endOffset = data.count
        data.appendLE32(0x06054b50)
        data.appendLE16(0)
        data.appendLE16(0)
        data.appendLE16(UInt16(items.count))
        data.appendLE16(UInt16(items.count))
        data.appendLE32(UInt32(endOffset - centralStart))
        data.appendLE32(UInt32(centralStart))
        data.appendLE16(UInt16(comment.utf8.count))
        data.append(contentsOf: comment.utf8)
        return Fixture(data: data, centralOffsets: centralOffsets, endOffset: endOffset)
    }

    private func field(_ tag: UInt16, _ payload: Data) -> Data {
        var result = Data()
        result.appendLE16(tag)
        result.appendLE16(UInt16(payload.count))
        result.append(payload)
        return result
    }
}

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }
    mutating func appendLE32(_ value: UInt32) {
        appendLE16(UInt16(truncatingIfNeeded: value))
        appendLE16(UInt16(truncatingIfNeeded: value >> 16))
    }
    mutating func writeLE16(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(truncatingIfNeeded: value)
        self[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }
    mutating func writeLE32(_ value: UInt32, at offset: Int) {
        writeLE16(UInt16(truncatingIfNeeded: value), at: offset)
        writeLE16(UInt16(truncatingIfNeeded: value >> 16), at: offset + 2)
    }
}
