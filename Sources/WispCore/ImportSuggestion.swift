import Foundation

/// Proposes editable library metadata without changing the imported audio.
/// Basic/Classic describes authorship; it does not imply a game or other origin.
public struct ImportSuggestion: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var genre: String
    public var origin: String
    public var remix: RemixKind
    public var originMediaKind: OriginMediaKind?
    public var notes: [String]
    public var needsReview: Bool

    public static func propose(filename: String, title: String?, artist: String?, album: String?, genre: String?) -> Self {
        let file = URL(fileURLWithPath: filename).lastPathComponent
        let fileName = stem(file)
        let fromFile = TrackNameParser.parse(file)
        let embeddedTitle = clean(title)
        let fromTag = embeddedTitle.map(TrackNameParser.parse)
        let embeddedArtist = clean(artist)
        let album = clean(album) ?? ""
        let explicitCollection = fromTag?.remix ?? fromFile.remix
        let usesWispConvention = explicitCollection != nil
        var proposedTitle = fromTag?.title ?? fromFile.title
        var proposedArtist = embeddedArtist ?? ""
        let origin = fromTag.flatMap { $0.origin.isEmpty ? nil : $0.origin } ?? fromFile.origin
        var notes: [String] = []

        if explicitCollection == nil {
            notes.append("Proposed Basic for an external source. Choose Classic only if you created it.")
        }
        if let tagged = fromTag?.remix, let named = fromFile.remix, tagged != named {
            notes.append("The title tag says \(tagged.title), but the filename says \(named.title). Kept the title tag; confirm the collection.")
        }
        if let tagged = fromTag?.origin, !tagged.isEmpty, !fromFile.origin.isEmpty,
           OriginMediaKind.originKey(tagged) != OriginMediaKind.originKey(fromFile.origin) {
            notes.append("The title tag and filename name different origins. Kept the title tag; confirm the origin.")
        }

        if !usesWispConvention {
            var fallbackTitle = fileName
            if let separator = fileName.range(of: " - ") {
                let prefix = String(fileName[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let remainder = String(fileName[separator.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty, !remainder.isEmpty, !isNumericPrefix(prefix) {
                    if let embeddedArtist, artistMatches(prefix, embeddedArtist), embeddedTitle == nil {
                        fallbackTitle = remainder
                        notes.append("Removed the filename artist prefix “\(prefix)” from the proposed title. Kept the embedded artist credit.")
                    } else if embeddedArtist == nil,
                              embeddedTitle == nil || sameName(remainder, fromTag?.title ?? "") {
                        proposedArtist = prefix
                        if embeddedTitle == nil { fallbackTitle = remainder }
                        notes.append("Artist “\(prefix)” was inferred from the filename. Confirm this split.")
                    }
                }
            }
            if embeddedTitle == nil {
                if let shortened = removingAlbumSuffix(from: fallbackTitle, album: album) {
                    fallbackTitle = shortened
                    notes.append("Removed the exact album suffix “\(album)” from the proposed title. Album metadata is retained.")
                }
                proposedTitle = TrackNameParser.normalizeName(fallbackTitle)
                notes.append("Title comes from the filename; no embedded title was found.")
            }
            if proposedArtist.isEmpty {
                notes.append("No artist credit was found. Add one if known, or leave it blank.")
            }
        }

        // Punctuated track numbers are a reviewable title cleanup, not an artist
        // guess. Bare numbers such as “1984” or “99 Problems” are left intact.
        if let shortened = removingTrackNumber(from: proposedTitle) {
            proposedTitle = shortened
            notes.append("Removed a leading track number from the proposed title. Confirm the name.")
        }
        if origin.isEmpty, let context = sourceContext(album: album, filename: fileName) {
            notes.append("Possible source context: “\(context)”. Origin is blank; choose a media type and origin only if appropriate.")
        }

        return Self(title: clean(proposedTitle) ?? "Untitled", artist: clean(proposedArtist) ?? "",
                    album: album, genre: clean(genre) ?? "", origin: origin,
                    remix: explicitCollection ?? .basic, originMediaKind: nil,
                    notes: notes, needsReview: !notes.isEmpty)
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(500))
    }

    private static func stem(_ filename: String) -> String {
        let extensions: Set<String> = ["mp3", "m4a", "aac", "wav", "wave", "flac", "aif", "aiff", "aifc", "ogg", "opus", "caf", "mp4", "alac", "webm"]
        let url = URL(fileURLWithPath: filename)
        return extensions.contains(url.pathExtension.lowercased()) ? url.deletingPathExtension().lastPathComponent : filename
    }

    private static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        TrackNameParser.normalizeName(lhs).compare(TrackNameParser.normalizeName(rhs),
            options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static func creditKey(_ credit: String) -> String {
        credit.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func artistMatches(_ prefix: String, _ artist: String) -> Bool {
        let artistKey = creditKey(artist)
        if creditKey(prefix) == artistKey { return true }
        let words = prefix.split { !$0.isLetter && !$0.isNumber }
        guard words.count > 1, (2...8).contains(artistKey.count) else { return false }
        let initials = words.compactMap(\.first).map(String.init).joined()
        return creditKey(initials) == artistKey
    }

    private static func isNumericPrefix(_ value: String) -> Bool {
        if value.range(of: #"^\d{1,3}[.)]\s+"#, options: .regularExpression) != nil { return true }
        let characters = value.filter { !$0.isWhitespace && $0 != "." && $0 != ")" }
        return !characters.isEmpty && characters.allSatisfy(\.isNumber)
    }

    private static func removingAlbumSuffix(from title: String, album: String) -> String? {
        guard !album.isEmpty,
              let suffix = title.range(of: " - " + album, options: [.anchored, .backwards, .caseInsensitive, .diacriticInsensitive]) else { return nil }
        return clean(String(title[..<suffix.lowerBound]))
    }

    private static func removingTrackNumber(from title: String) -> String? {
        guard let range = title.range(of: #"^\d{1,3}(?:[.)]\s+|:\s+)"#, options: .regularExpression) else { return nil }
        return clean(String(title[range.upperBound...]))
    }

    private static func sourceContext(album: String, filename: String) -> String? {
        let candidates = ([album] + filename.components(separatedBy: " - ")).filter { !$0.isEmpty }
        return candidates.first { candidate in
            if OriginMediaKind.infer(from: candidate) != .unknown { return true }
            let key = OriginMediaKind.originKey(candidate)
            return key.contains("ghibli") || key == "poke chill"
        }
    }
}
