import Foundation

/// Only descriptive metadata is sent to public artwork providers.
public struct ArtworkRequest: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var origin: String
    public var mediaKind: OriginMediaKind?
    public var subjectOverride: String?
    public init(title: String, artist: String = "", origin: String = "", mediaKind: OriginMediaKind? = nil, subjectOverride: String? = nil) {
        self.title = String(title.prefix(240)); self.artist = String(artist.prefix(240))
        self.origin = String(origin.prefix(240)); self.mediaKind = mediaKind
        self.subjectOverride = subjectOverride.map { String($0.prefix(240)) }
    }
    public init(track: Track, subjectOverride: String? = nil) {
        self.init(title: track.title, artist: track.artist, origin: track.origin,
                  mediaKind: track.resolvedMediaKind, subjectOverride: subjectOverride)
    }
}

public enum ArtworkMatchLevel: String, Codable, Sendable {
    case specificSubject, originOnly, uncertain
}

/// Discovery results are always proposals. Approval belongs to the user.
public struct ArtworkCandidate: Identifiable, Equatable, Sendable {
    public var id: String { sourceName + "|" + imageURL.absoluteString }
    public let title: String
    public let imageURL: URL
    public let pageURL: URL
    public let sourceName: String
    public let credit: String
    public let match: ArtworkMatchLevel
    public let explanation: String
    public let isOfficial: Bool
    public let sourcePixelWidth: Int?
    public let sourcePixelHeight: Int?
    public init(title: String, imageURL: URL, pageURL: URL, sourceName: String, credit: String,
                match: ArtworkMatchLevel, explanation: String, isOfficial: Bool = false,
                sourcePixelWidth: Int? = nil, sourcePixelHeight: Int? = nil) {
        self.title = title; self.imageURL = imageURL; self.pageURL = pageURL
        self.sourceName = sourceName; self.credit = credit; self.match = match
        self.explanation = explanation; self.isOfficial = isOfficial
        self.sourcePixelWidth = sourcePixelWidth; self.sourcePixelHeight = sourcePixelHeight
    }
}

public enum ArtworkMatch {
    public static func catalogTitle(_ value: String) -> String {
        value.replacingOccurrences(of: #"\s*[\[(][^\])]*(?:remix|mix|cover|version|edit|instrumental|live)[^\])]*[\])]"#,
                                   with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s*[-:]\s*[^-:]*(?:remix|mix|cover|edit)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func artistMatches(_ expected: String, credited: [String]) -> Bool {
        func artistKey(_ value: String) -> String { normalized(value).split(separator: " ").filter { $0 != "and" }.joined(separator: " ") }
        let expected = artistKey(expected)
        guard !expected.isEmpty else { return false }
        return artistKey(credited.joined(separator: " ")) == expected
    }

    public static func catalogRecordingMatches(title: String, creditedArtists: [String], request: ArtworkRequest) -> Bool {
        let expectedTitle = request.subjectOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = expectedTitle.flatMap { $0.isEmpty ? nil : $0 } ?? request.title
        return artistMatches(request.artist, credited: creditedArtists)
            && normalized(catalogTitle(title)) == normalized(catalogTitle(subject))
            && !normalized(catalogTitle(subject)).isEmpty
    }

    public static func catalogReleaseMatchesArtist(creditedArtists: [String], secondaryTypes: [String], request: ArtworkRequest) -> Bool {
        if secondaryTypes.contains(where: { normalized($0) == "compilation" }) { return false }
        if secondaryTypes.contains(where: { normalized($0) == "live" }),
           !(" " + normalized(request.title + " " + (request.subjectOverride ?? "")) + " ").contains(" live ") { return false }
        return creditedArtists.isEmpty || artistMatches(request.artist, credited: creditedArtists)
    }

    public static func needsVersionReview(_ request: ArtworkRequest, catalogTitle title: String) -> Bool {
        let cues = ["remix", "mix", "cover", "edit", "live", "instrumental", "version", "acoustic", "remaster", "remastered"]
        let subject = request.subjectOverride ?? request.title
        if normalized(catalogTitle(subject)) != normalized(subject) || normalized(catalogTitle(title)) != normalized(title) { return true }
        let context = " " + normalized(request.title + " " + subject + " " + request.origin + " " + title) + " "
        return cues.contains { context.contains(" " + $0 + " ") }
    }

    public static func lucenePhrase(_ value: String) -> String {
        let special = CharacterSet(charactersIn: "+-!():^[]\"{}~*?|&/\\")
        return "\"" + String(value.prefix(240)).unicodeScalars.map { special.contains($0) ? "\\" + String($0) : String($0) }.joined() + "\""
    }

    public static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func subjects(for request: ArtworkRequest) -> [String] {
        if let override = request.subjectOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty { return [override] }
        let title = request.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = normalized(title)
        // A verified game entity alias, rather than a generic franchise fallback.
        if normalized(request.origin).contains("hollow knight"), normalizedTitle.contains("nightmare king") {
            return ["Nightmare King Grimm"]
        }
        var result: [String] = []
        let cleaned = title.replacingOccurrences(of: #"\s*[\[(][^\])]*(?:remix|mix|cover|version|edit|instrumental)[^\])]*[\])]"#,
                                                  with: "", options: [.regularExpression, .caseInsensitive])
        if !cleaned.isEmpty { result.append(cleaned) }
        let prefixes = ["bow to the ", "theme of ", "theme for ", "song of ", "battle with ", "battle against "]
        if let prefix = prefixes.first(where: { cleaned.lowercased().hasPrefix($0) }) {
            let subject = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if subject.count > 2 { result.insert(subject, at: 0) }
        }
        var seen = Set<String>()
        return result.filter { seen.insert(normalized($0)).inserted }.prefix(2).map { $0 }
    }

    public static func usesHollowKnightWiki(_ request: ArtworkRequest) -> Bool {
        let origin = normalized(request.origin)
        return origin.contains("hollow knight") || normalized(request.subjectOverride ?? "") == "nightmare king grimm"
    }

    public static func classify(pageTitle: String, request: ArtworkRequest) -> ArtworkMatchLevel {
        let page = normalized(pageTitle.replacingOccurrences(of: #"\s+\((?:film|TV series|television series|novel|video game|album|song)\)$"#,
                                                             with: "", options: [.regularExpression, .caseInsensitive]))
        guard !page.isEmpty else { return .uncertain }
        let origin = normalized(request.origin)
        if !origin.isEmpty && page == origin { return .originOnly }
        // A Wikipedia song title alone cannot verify the performer or recording.
        if request.mediaKind == .music || (origin.isEmpty && !request.artist.isEmpty) { return .uncertain }
        if subjects(for: request).contains(where: { normalized($0) == page }) { return .specificSubject }
        return .uncertain
    }

    public static func isCoverOrPoster(_ filename: String) -> Bool {
        let name = " " + normalized(filename) + " "
        return ["poster", "cover", "box art", "boxart"].contains { name.contains(" " + $0 + " ") }
    }

    public static func ranked(_ candidates: [ArtworkCandidate]) -> [ArtworkCandidate] {
        func rank(_ level: ArtworkMatchLevel) -> Int {
            switch level { case .specificSubject: return 0; case .originOnly: return 1; case .uncertain: return 2 }
        }
        var seen = Set<String>()
        return candidates.enumerated().sorted { lhs, rhs in
                let a = rank(lhs.element.match), b = rank(rhs.element.match)
                return a == b ? lhs.offset < rhs.offset : a < b
            }.filter { seen.insert($0.element.imageURL.absoluteString).inserted }.prefix(10).map(\.element)
    }

    public static func isLikelyTextAsset(_ filename: String) -> Bool {
        let name = normalized(filename)
        return ["logo", "wordmark", "poster", "capsule", "box art", "boxart", "cover art", "map", "achievement", "flag", "icon"]
            .contains { term in (" " + name + " ").contains(" " + term + " ") }
    }

    /// Providers and their image CDNs are explicitly allowed, including redirects.
    public static func allowsRemoteURL(_ url: URL) -> Bool {
        guard url.absoluteString.count <= 8192, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        if host == "musicbrainz.org" { return true }
        if host.range(of: #"^[a-z0-9-]+\.bandcamp\.com$"#, options: .regularExpression) != nil { return true }
        return isOriginalBandcampImage(url)
    }

    public static func isCreatorReleasePage(_ url: URL) -> Bool {
        allowsRemoteURL(url) && url.host?.hasSuffix(".bandcamp.com") == true
            && url.path.range(of: #"^/album/[a-zA-Z0-9-]+/?$"#, options: .regularExpression) != nil
    }

    public static func isOriginalBandcampImage(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              let host = url.host, host.range(of: #"^f[0-9]+\.bcbits\.com$"#, options: .regularExpression) != nil else { return false }
        return url.path.range(of: #"^/img/a[0-9]+_0\.(?:jpg|png)$"#, options: .regularExpression) != nil
    }

    public static func originalBandcampImage(from url: URL) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.host?.range(of: #"^f[0-9]+\.bcbits\.com$"#, options: .regularExpression) != nil,
              parts.path.range(of: #"^/img/a[0-9]+_[0-9]+\.(?:jpg|png)$"#, options: .regularExpression) != nil else { return nil }
        parts.scheme = "https"; parts.query = nil; parts.fragment = nil
        parts.path = parts.path.replacingOccurrences(of: #"_[0-9]+\."#, with: "_0.", options: .regularExpression)
        guard let original = parts.url, allowsRemoteURL(original) else { return nil }
        return original
    }

    /// A one-pixel export discrepancy is allowed; genuine landscape/portrait art is not.
    public static func isNearSquare(width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && Double(abs(width - height)) / Double(max(width, height)) <= 0.005
    }

    public static func allowsRedirect(from original: URL, to target: URL) -> Bool {
        guard allowsRemoteURL(original), allowsRemoteURL(target) else { return false }
        if isOriginalBandcampImage(original) {
            return isOriginalBandcampImage(target) && original.path == target.path
        }
        let left = original.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let right = target.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return original.host == target.host && left == right
    }
}
