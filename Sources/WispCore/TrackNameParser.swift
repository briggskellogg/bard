import Foundation

/// Briggs's version names describe provenance, not licensing or rights.
public enum RemixKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case basic
    case classic

    public var id: String { rawValue }
    public var title: String { self == .basic ? "Basic" : "Classic" }
    public var attribution: String { self == .basic ? "External source" : "Created by you" }
}

public struct ParsedTrackName: Equatable, Sendable {
    public let title: String
    public let origin: String
    public let remix: RemixKind?

    public init(title: String, origin: String = "", remix: RemixKind? = nil) {
        self.title = title
        self.origin = origin
        self.remix = remix
    }
}

/// Parses the import convention: Title (Origin) [Basic Remix|Classic Remix].
/// Unrecognized square-bracket suffixes are retained as part of the title.
/// A final parenthesized group becomes the origin only with a recognized
/// remix suffix. Ordinary purchased titles such as Song (Live) stay intact.
public enum TrackNameParser {
    private static let extensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "wave", "flac", "aif", "aiff", "aifc",
        "ogg", "opus", "caf", "mp4", "alac", "webm"
    ]

    /// Treats a spaced filename dash as a subtitle separator in display names.
    /// Unspaced hyphens, en dashes, em dashes, and existing colons are preserved.
    /// Use for track titles and origins, not filenames, artists, or source URLs.
    public static func normalizeName(_ name: String) -> String {
        name.replacingOccurrences(of: " - ", with: ": ")
    }

    public static func parse(_ text: String) -> ParsedTrackName {
        var name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dot = name.lastIndex(of: "."), extensions.contains(String(name[name.index(after: dot)...]).lowercased()) {
            name = String(name[..<dot]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !name.isEmpty else { return ParsedTrackName(title: "Untitled") }
        let original = name
        var remix: RemixKind?

        if name.last == "]", let opening = name.lastIndex(of: "[") {
            let content = String(name[name.index(after: opening)..<name.index(before: name.endIndex)])
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
            switch content {
            case "basic remix": remix = .basic
            case "classic remix": remix = .classic
            default: break
            }
            if remix != nil {
                name = String(name[..<opening]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        var origin = ""
        if remix != nil, name.last == ")" {
            var depth = 0
            var cursor = name.endIndex
            var opening: String.Index?
            while cursor > name.startIndex {
                cursor = name.index(before: cursor)
                if name[cursor] == ")" { depth += 1 }
                if name[cursor] == "(" {
                    depth -= 1
                    if depth == 0 { opening = cursor; break }
                }
            }
            if let opening,
               opening > name.startIndex,
               name[name.index(before: opening)].isWhitespace {
                let candidate = String(name[name.index(after: opening)..<name.index(before: name.endIndex)])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let title = String(name[..<opening]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty && !title.isEmpty {
                    origin = candidate
                    name = title
                }
            }
        }

        guard !name.isEmpty else { return ParsedTrackName(title: normalizeName(original)) }
        return ParsedTrackName(title: normalizeName(name), origin: normalizeName(origin), remix: remix)
    }
}
