import Foundation

/// A deliberately narrow ZIP32 reader for imported audio albums. It does not
/// decompress data. It checks that the central directory and every local record
/// describe the same bounded set of ordinary files before a native extractor runs.
public enum ZIPPreflight {
    public struct Limits: Sendable {
        public var maximumEntries: Int
        public var maximumTotalBytes: UInt64
        public var maximumEntryBytes: UInt64
        public var maximumCompressionRatio: UInt64
        public var maximumPathBytes: Int
        public var maximumDepth: Int

        public init(maximumEntries: Int = 10_000,
                    maximumTotalBytes: UInt64 = 16 * 1024 * 1024 * 1024,
                    maximumEntryBytes: UInt64 = UInt64(UInt32.max) - 1,
                    maximumCompressionRatio: UInt64 = 250,
                    maximumPathBytes: Int = 1024,
                    maximumDepth: Int = 32) {
            self.maximumEntries = maximumEntries
            self.maximumTotalBytes = maximumTotalBytes
            self.maximumEntryBytes = maximumEntryBytes
            self.maximumCompressionRatio = maximumCompressionRatio
            self.maximumPathBytes = maximumPathBytes
            self.maximumDepth = maximumDepth
        }
    }

    public struct Entry: Equatable, Sendable {
        public let path: String
        public let isDirectory: Bool
        public let uncompressedBytes: UInt64
        public let compressedBytes: UInt64
        public var canonicalPath: String { ZIPPreflight.canonicalPath(path) }
    }

    public struct Report: Sendable {
        public let entries: [Entry]
        public let uncompressedBytes: UInt64
    }

    public enum Failure: LocalizedError, Equatable {
        case malformed
        case zip64
        case multipart
        case encrypted
        case unsafePath
        case symbolicLink
        case conflictingPaths
        case limit
        case unsupported

        public var errorDescription: String? {
            switch self {
            case .malformed: return "This ZIP archive is incomplete or has inconsistent file records. Download it again, or extract it in Finder first."
            case .zip64: return "This archive uses Zip64. Extract it in Finder first, then import its audio files or folder."
            case .multipart: return "Split ZIP archives are not supported. Join and extract the archive in Finder first."
            case .encrypted: return "This ZIP archive is encrypted. Unlock and extract it in Finder first."
            case .unsafePath: return "This ZIP archive contains a filename that cannot be safely imported. Extract the audio files in Finder first."
            case .symbolicLink: return "This ZIP archive contains links or special files. Import the audio files themselves instead."
            case .conflictingPaths: return "This ZIP archive contains conflicting filenames. Extract and review its audio files in Finder first."
            case .limit: return "This ZIP archive exceeds Bard’s extraction limits. Extract it in Finder first and import a smaller folder."
            case .unsupported: return "This ZIP format is not supported directly. Extract it in Finder first, then import its audio files."
            }
        }
    }

    private struct Record {
        let entry: Entry
        let rawName: Data
        let flags: UInt16
        let method: UInt16
        let crc: UInt32
        let compressed: UInt32
        let uncompressed: UInt32
        let localOffset: Int
    }

    public static func canonicalPath(_ value: String) -> String {
        value.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }

    public static func validate(_ data: Data, limits: Limits = Limits()) throws -> Report {
        let reader = Reader(data: data)
        guard data.count >= 22 else { throw Failure.malformed }
        let minimum = max(0, data.count - 22 - 65_535)
        var endOffset: Int?
        for offset in stride(from: data.count - 22, through: minimum, by: -1) {
            if try reader.u32(offset) == 0x06054b50,
               offset + 22 + Int(try reader.u16(offset + 20)) == data.count {
                endOffset = offset
                break
            }
        }
        guard let end = endOffset else { throw Failure.malformed }
        if end >= 20, try reader.u32(end - 20) == 0x07064b50 { throw Failure.zip64 }
        let disk = try reader.u16(end + 4)
        let directoryDisk = try reader.u16(end + 6)
        let diskCount = try reader.u16(end + 8)
        let count = try reader.u16(end + 10)
        let directorySize = try reader.u32(end + 12)
        let directoryOffset = try reader.u32(end + 16)
        if diskCount == UInt16.max || count == UInt16.max || directorySize == UInt32.max || directoryOffset == UInt32.max {
            throw Failure.zip64
        }
        guard disk == 0, directoryDisk == 0, diskCount == count else { throw Failure.multipart }
        guard Int(count) <= limits.maximumEntries else { throw Failure.limit }
        let start = Int(directoryOffset)
        let directoryEnd = start + Int(directorySize)
        guard start <= end, directoryEnd == end else { throw Failure.malformed }
        var cursor = start
        var records: [Record] = []
        records.reserveCapacity(Int(count))
        var seenPaths = Set<String>()
        var regularPaths = Set<String>()
        var total: UInt64 = 0

        for _ in 0..<Int(count) {
            guard cursor + 46 <= directoryEnd, try reader.u32(cursor) == 0x02014b50 else { throw Failure.malformed }
            let version = try reader.u16(cursor + 6)
            let flags = try reader.u16(cursor + 8)
            let method = try reader.u16(cursor + 10)
            let crc = try reader.u32(cursor + 16)
            let compressed = try reader.u32(cursor + 20)
            let uncompressed = try reader.u32(cursor + 24)
            let nameLength = Int(try reader.u16(cursor + 28))
            let extraLength = Int(try reader.u16(cursor + 30))
            let commentLength = Int(try reader.u16(cursor + 32))
            let startDisk = try reader.u16(cursor + 34)
            let attributes = try reader.u32(cursor + 38)
            let local = try reader.u32(cursor + 42)
            if compressed == UInt32.max || uncompressed == UInt32.max || local == UInt32.max || startDisk == UInt16.max {
                throw Failure.zip64
            }
            guard startDisk == 0 else { throw Failure.multipart }
            try validateFlags(flags, method: method, version: version)
            let recordEnd = cursor + 46 + nameLength + extraLength + commentLength
            guard recordEnd <= directoryEnd, nameLength > 0, nameLength <= limits.maximumPathBytes else { throw Failure.malformed }
            let rawName = try reader.bytes(cursor + 46, length: nameLength)
            let name = try decodeName(rawName)
            let path = try validatePath(name, limits: limits)
            let isDirectory = name.hasSuffix("/")
            let mode = (attributes >> 16) & 0xf000
            if mode == 0xa000 { throw Failure.symbolicLink }
            if mode != 0 && mode != 0x8000 && mode != 0x4000 { throw Failure.symbolicLink }
            if mode == 0x4000 && !isDirectory { throw Failure.malformed }
            if mode == 0x8000 && isDirectory { throw Failure.malformed }
            if attributes & 0x10 != 0 && !isDirectory { throw Failure.malformed }
            if isDirectory && (compressed != 0 || uncompressed != 0) { throw Failure.malformed }
            if method == 0 && compressed != uncompressed { throw Failure.malformed }
            try validateExtra(reader, offset: cursor + 46 + nameLength, length: extraLength, name: name)

            let key = canonicalPath(path)
            guard seenPaths.insert(key).inserted else { throw Failure.conflictingPaths }
            if !isDirectory { regularPaths.insert(key) }
            let bytes = UInt64(uncompressed)
            guard bytes <= limits.maximumEntryBytes else { throw Failure.limit }
            guard total <= limits.maximumTotalBytes, bytes <= limits.maximumTotalBytes - total else { throw Failure.limit }
            total += bytes
            if bytes > 1024 * 1024 {
                let denominator = max(UInt64(compressed), 1)
                guard (bytes + denominator - 1) / denominator <= limits.maximumCompressionRatio else { throw Failure.limit }
            }
            records.append(Record(
                entry: Entry(path: path, isDirectory: isDirectory, uncompressedBytes: bytes, compressedBytes: UInt64(compressed)),
                rawName: rawName, flags: flags, method: method, crc: crc,
                compressed: compressed, uncompressed: uncompressed, localOffset: Int(local)
            ))
            cursor = recordEnd
        }
        guard cursor == directoryEnd else { throw Failure.malformed }
        for record in records {
            let parts = record.entry.canonicalPath.split(separator: "/")
            if parts.count > 1 {
                for depth in 1..<parts.count {
                    guard !regularPaths.contains(parts.prefix(depth).joined(separator: "/")) else { throw Failure.conflictingPaths }
                }
            }
        }

        // Require a complete, contiguous set of local records. This also rejects
        // self-extracting stubs and unlisted local files some extractors would read.
        let physical = records.sorted { $0.localOffset < $1.localOffset }
        var expectedOffset = 0
        for (index, record) in physical.enumerated() {
            guard record.localOffset == expectedOffset else { throw Failure.malformed }
            let boundary = index + 1 < physical.count ? physical[index + 1].localOffset : start
            expectedOffset = try validateLocal(record, reader: reader, boundary: boundary)
        }
        guard expectedOffset == start else { throw Failure.malformed }
        return Report(entries: records.map(\.entry), uncompressedBytes: total)
    }

    private static func validateFlags(_ flags: UInt16, method: UInt16, version: UInt16) throws {
        if flags & 0x2041 != 0 { throw Failure.encrypted }
        if version >= 45 { throw Failure.zip64 }
        guard method == 0 || method == 8, version <= 20 else { throw Failure.unsupported }
        guard flags & ~UInt16(0x080e) == 0 else { throw Failure.unsupported }
        if method == 0 && flags & 0x0006 != 0 { throw Failure.malformed }
    }

    private static func decodeName(_ data: Data) throws -> String {
        // UTF-8 (including ASCII) avoids locale-dependent filename interpretation.
        // Legacy encodings can still be opened explicitly in Finder.
        guard let value = String(data: data, encoding: .utf8) else { throw Failure.unsupported }
        return value
    }

    private static func validatePath(_ name: String, limits: Limits) throws -> String {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw Failure.unsafePath
        }
        let path = name.hasSuffix("/") ? String(name.dropLast()) : name
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= limits.maximumDepth else { throw Failure.unsafePath }
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 }) else {
            throw Failure.unsafePath
        }
        return path
    }

    private static func validateExtra(_ reader: Reader, offset: Int, length: Int, name: String) throws {
        let end = offset + length
        var cursor = offset
        var seen = Set<UInt16>()
        while cursor < end {
            guard cursor + 4 <= end else { throw Failure.malformed }
            let tag = try reader.u16(cursor)
            let size = Int(try reader.u16(cursor + 2))
            guard cursor + 4 + size <= end, seen.insert(tag).inserted else { throw Failure.malformed }
            if tag == 0x0001 { throw Failure.zip64 }
            switch tag {
            case 0x5455, 0x7875, 0x6375:
                // Extended timestamps, UID/GID, and Unicode comments cannot redirect a path.
                break
            case 0x7075:
                guard size >= 5, try reader.u8(cursor + 4) == 1 else { throw Failure.malformed }
                let override = try decodeName(reader.bytes(cursor + 9, length: size - 5))
                guard override == name else { throw Failure.unsafePath }
            case 0x000a:
                // NTFS timestamp extension; unknown NTFS attributes are not accepted.
                guard size >= 4 else { throw Failure.malformed }
                var field = cursor + 8
                while field < cursor + 4 + size {
                    guard field + 4 <= cursor + 4 + size,
                          try reader.u16(field) == 1,
                          try reader.u16(field + 2) == 24,
                          field + 28 <= cursor + 4 + size else { throw Failure.unsupported }
                    field += 28
                }
            default:
                // Unix link metadata and proprietary Macintosh/NTFS path extensions
                // must not be interpreted differently by the extractor.
                throw Failure.unsupported
            }
            cursor += 4 + size
        }
        guard cursor == end else { throw Failure.malformed }
    }

    private static func validateLocal(_ record: Record, reader: Reader, boundary: Int) throws -> Int {
        let start = record.localOffset
        guard start + 30 <= boundary, try reader.u32(start) == 0x04034b50 else { throw Failure.malformed }
        let version = try reader.u16(start + 4)
        let flags = try reader.u16(start + 6)
        let method = try reader.u16(start + 8)
        try validateFlags(flags, method: method, version: version)
        guard flags == record.flags, method == record.method else { throw Failure.malformed }
        let crc = try reader.u32(start + 14)
        let compressed = try reader.u32(start + 18)
        let uncompressed = try reader.u32(start + 22)
        if compressed == UInt32.max || uncompressed == UInt32.max { throw Failure.zip64 }
        let nameLength = Int(try reader.u16(start + 26))
        let extraLength = Int(try reader.u16(start + 28))
        let payload = start + 30 + nameLength + extraLength
        let payloadEnd = payload + Int(record.compressed)
        guard payload <= boundary, payloadEnd <= boundary,
              try reader.bytes(start + 30, length: nameLength) == record.rawName else { throw Failure.malformed }
        let name = try decodeName(record.rawName)
        try validateExtra(reader, offset: start + 30 + nameLength, length: extraLength, name: name)
        if flags & 0x0008 == 0 {
            guard crc == record.crc, compressed == record.compressed, uncompressed == record.uncompressed,
                  payloadEnd == boundary else { throw Failure.malformed }
        } else {
            guard (crc == 0 || crc == record.crc),
                  (compressed == 0 || compressed == record.compressed),
                  (uncompressed == 0 || uncompressed == record.uncompressed) else { throw Failure.malformed }
            let descriptor = boundary - payloadEnd
            let values: Int
            if descriptor == 16 {
                guard try reader.u32(payloadEnd) == 0x08074b50 else { throw Failure.malformed }
                values = payloadEnd + 4
            } else if descriptor == 12 { values = payloadEnd }
            else { throw Failure.malformed }
            guard try reader.u32(values) == record.crc,
                  try reader.u32(values + 4) == record.compressed,
                  try reader.u32(values + 8) == record.uncompressed else { throw Failure.malformed }
        }
        return boundary
    }

    private struct Reader {
        let data: Data
        func u8(_ offset: Int) throws -> UInt8 {
            guard offset >= 0, offset < data.count else { throw Failure.malformed }
            return data[data.startIndex + offset]
        }
        func u16(_ offset: Int) throws -> UInt16 {
            UInt16(try u8(offset)) | (UInt16(try u8(offset + 1)) << 8)
        }
        func u32(_ offset: Int) throws -> UInt32 {
            UInt32(try u8(offset)) | (UInt32(try u8(offset + 1)) << 8)
                | (UInt32(try u8(offset + 2)) << 16) | (UInt32(try u8(offset + 3)) << 24)
        }
        func bytes(_ offset: Int, length: Int) throws -> Data {
            guard offset >= 0, length >= 0, offset <= data.count, length <= data.count - offset else { throw Failure.malformed }
            return data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + length))
        }
    }
}
