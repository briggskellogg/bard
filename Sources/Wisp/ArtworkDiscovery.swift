import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision
import WispCore

enum ArtworkTextCheck: String, Equatable, Sendable { case clear, detected, unavailable }

struct PreparedArtwork: Sendable {
    let candidate: ArtworkCandidate
    let fileURL: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let detectedText: [String]
    let textCheck: ArtworkTextCheck
    fileprivate let ownedDirectory: URL?
    init(candidate: ArtworkCandidate, fileURL: URL, pixelWidth: Int, pixelHeight: Int,
         detectedText: [String], textCheck: ArtworkTextCheck) {
        self.candidate = candidate; self.fileURL = fileURL; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.detectedText = detectedText; self.textCheck = textCheck; self.ownedDirectory = nil
    }
    fileprivate init(candidate: ArtworkCandidate, fileURL: URL, pixelWidth: Int, pixelHeight: Int,
                     detectedText: [String], textCheck: ArtworkTextCheck, ownedDirectory: URL) {
        self.candidate = candidate; self.fileURL = fileURL; self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight
        self.detectedText = detectedText; self.textCheck = textCheck; self.ownedDirectory = ownedDirectory
    }
}

enum ArtworkDiscoveryError: LocalizedError {
    case unsafeURL, unavailable, busy, oversized, invalidImage, tooManyPixels, saveFailed, notSquare, unverifiedCreator
    var errorDescription: String? {
        switch self {
        case .unsafeURL: return "That image is outside Bard’s supported artwork sources."
        case .unavailable, .busy: return "The artwork source could not be reached. Try again, refine the subject, or choose a file."
        case .oversized: return "That artwork is too large to preview safely. Choose another image."
        case .invalidImage: return "That source did not return a supported still image."
        case .tooManyPixels: return "That image’s dimensions are too large to preview safely."
        case .saveFailed: return "Bard could not prepare that artwork for review."
        case .notSquare: return "Choose square artwork from the creator. Bard will not crop or pad a landscape or portrait image."
        case .unverifiedCreator: return "Only original square artwork from a verified creator or publisher can be suggested."
        }
    }
}

/// Public metadata searches only. Every result must be explicitly approved in the review UI.
enum ArtworkDiscovery {
    static let maximumImageBytes = 12 * 1024 * 1024
    static let maximumImagePixels = 40_000_000
    private static let maximumJSONBytes = 1_048_576

    static func search(_ request: ArtworkRequest) async throws -> [ArtworkCandidate] {
        try Task.checkCancellation()
        if let source = soundtrackSource(request) {
            return [try await creatorCover(page: source.page, expectedTitle: source.title,
                expectedArtist: source.artist, publisher: source.publisher, match: .originOnly,
                explanation: "Official soundtrack cover for the origin. It is not verified as artwork for your exact remix or song.")]
        }
        return ArtworkMatch.ranked(try await musicSearch(request))
    }

    private struct SoundtrackSource {
        let page: URL; let title: String; let artist: String; let publisher: String
    }
    private static func soundtrackSource(_ request: ArtworkRequest) -> SoundtrackSource? {
        guard (request.mediaKind ?? OriginMediaKind.infer(from: request.origin)) == .game else { return nil }
        let origin = ArtworkMatch.normalized(request.origin)
        let title = ArtworkMatch.normalized(request.subjectOverride ?? request.title)
        var base = request; base.subjectOverride = nil
        let defaultSubjects = ([base.title] + ArtworkMatch.subjects(for: base)).map(ArtworkMatch.normalized)
        let nightmares = ["nightmare king", "nightmare king grimm", "hollow knight gods nightmares", "gods nightmares"]
        if let override = request.subjectOverride, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !defaultSubjects.contains(ArtworkMatch.normalized(override)),
           !(origin == "hollow knight" && nightmares.contains(ArtworkMatch.normalized(override))) { return nil }
        let entry: (String, String, String, String)?
        if origin == "hollow knight", title.contains("nightmare king") || nightmares.contains(title) {
            entry = ("christopherlarkin.bandcamp.com/album/hollow-knight-gods-nightmares", "Hollow Knight: Gods & Nightmares", "Christopher Larkin", "Christopher Larkin")
        } else if origin == "hollow knight" {
            entry = ("christopherlarkin.bandcamp.com/album/hollow-knight-original-soundtrack", "Hollow Knight (Original Soundtrack)", "Christopher Larkin", "Christopher Larkin")
        } else if origin == "hollow knight silksong" {
            entry = ("christopherlarkin.bandcamp.com/album/hollow-knight-silksong-original-soundtrack", "Hollow Knight: Silksong (Original Soundtrack)", "Christopher Larkin", "Christopher Larkin")
        } else if origin == "hades" {
            entry = ("supergiantgames.bandcamp.com/album/hades-original-soundtrack", "Hades: Original Soundtrack", "Darren Korb", "Supergiant Games")
        } else if origin == "hades ii" {
            entry = ("supergiantgames.bandcamp.com/album/hades-ii-original-soundtrack", "Hades II: Original Soundtrack", "Darren Korb", "Supergiant Games")
        } else if origin == "disco elysium" || origin == "disco elysium for gameboy" {
            entry = ("seapower.bandcamp.com/album/disco-elysium", "Disco Elysium", "Sea Power (Golden Chariot Records)", "Sea Power / Golden Chariot Records")
        } else { entry = nil }
        guard let entry else { return nil }
        return SoundtrackSource(page: URL(string: "https://" + entry.0)!, title: entry.1, artist: entry.2, publisher: entry.3)
    }

    static func prepare(_ candidate: ArtworkCandidate) async throws -> PreparedArtwork {
        guard ArtworkMatch.isOriginalBandcampImage(candidate.imageURL), ArtworkMatch.isCreatorReleasePage(candidate.pageURL),
              candidate.isOfficial, await ArtworkRequestCache.shared.isVerified(candidate) else {
            throw ArtworkDiscoveryError.unverifiedCreator
        }
        let data = try await cachedImage(candidate.imageURL)
        try Task.checkCancellation()
        // Image decoding and OCR stay outside the main actor, including when called by SwiftUI.
        let worker = Task.detached(priority: .userInitiated) { try prepareImage(data, candidate: candidate) }
        return try await withTaskCancellationHandler {
            let prepared = try await worker.value
            if Task.isCancelled { discard(prepared); throw CancellationError() }
            return prepared
        } onCancel: { worker.cancel() }
    }

    static func discard(_ prepared: PreparedArtwork) {
        // The directory comes only from prepareImage; callers cannot supply an arbitrary path.
        guard let directory = prepared.ownedDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Internal seam for isolated validation; this does not mutate a library or apply a cover.
    static func prepareImage(_ data: Data, candidate: ArtworkCandidate) throws -> PreparedArtwork {
        try Task.checkCancellation()
        let image = try decodedImage(data)
        let text = checkText(image)
        try Task.checkCancellation()
        let cover = image
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WispArtwork-" + UUID().uuidString, isDirectory: true)
        var ownsDirectory = false
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            ownsDirectory = true
            let file = directory.appendingPathComponent("cover.png")
            try encodedPNG(cover).write(to: file, options: .atomic)
            try Task.checkCancellation()
            return PreparedArtwork(candidate: candidate, fileURL: file, pixelWidth: cover.width, pixelHeight: cover.height,
                                   detectedText: text.strings, textCheck: text.check, ownedDirectory: directory)
        } catch {
            if ownsDirectory { try? FileManager.default.removeItem(at: directory) }
            throw error
        }
    }

    /// Preserve the complete source proportions; never pad or crop artwork.
    static func coverData(from data: Data) throws -> Data {
        try encodedPNG(decodedImage(data))
    }

    private static func decodedImage(_ data: Data) throws -> CGImage {
        guard data.count <= maximumImageBytes else { throw ArtworkDiscoveryError.oversized }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let identifier = CGImageSourceGetType(source),
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.webP.identifier].contains(identifier as String),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw ArtworkDiscoveryError.invalidImage }
        guard width > 0, height > 0, width <= 20_000, height <= 20_000,
              width <= maximumImagePixels / height else { throw ArtworkDiscoveryError.tooManyPixels }
        guard ArtworkMatch.isNearSquare(width: width, height: height) else { throw ArtworkDiscoveryError.notSquare }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                      kCGImageSourceCreateThumbnailWithTransform: true,
                                      kCGImageSourceThumbnailMaxPixelSize: min(1600, max(width, height)),
                                      kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ArtworkDiscoveryError.invalidImage
        }
        return image
    }

    private static func encodedPNG(_ image: CGImage) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw ArtworkDiscoveryError.saveFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ArtworkDiscoveryError.saveFailed }
        return output as Data
    }

    private static func checkText(_ image: CGImage) -> (check: ArtworkTextCheck, strings: [String]) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            let strings = (request.results ?? []).compactMap { observation -> String? in
                guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.35 else { return nil }
                let value = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            return textAssessment(recognized: strings, succeeded: true)
        } catch { return textAssessment(recognized: [], succeeded: false) }
    }

    static func textAssessment(recognized: [String], succeeded: Bool) -> (check: ArtworkTextCheck, strings: [String]) {
        guard succeeded else { return (.unavailable, []) }
        return (recognized.isEmpty ? .clear : .detected, Array(recognized.prefix(20)))
    }

    /// MusicBrainz supplies identity links only. Images must come from the artist’s own release page.
    static func musicSearch(_ request: ArtworkRequest) async throws -> [ArtworkCandidate] {
        guard !request.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let deadline = Date().addingTimeInterval(20)
        let origin = request.origin.trimmingCharacters(in: .whitespacesAndNewlines)
        let override = request.subjectOverride?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let customSubject = !override.isEmpty && ArtworkMatch.normalized(override) != ArtworkMatch.normalized(request.title)
        func artists(_ object: [String: Any]) -> [String] {
            (object["artist-credit"] as? [[String: Any]] ?? []).compactMap {
                $0["name"] as? String ?? ($0["artist"] as? [String: Any])?["name"] as? String
            }
        }
        var found: [ArtworkCandidate] = []
        var sourceFailure: Error?
        if !origin.isEmpty && !customSubject {
            let query = "release:" + ArtworkMatch.lucenePhrase(origin) + " AND artist:" + ArtworkMatch.lucenePhrase(request.artist)
            let url = try endpoint("https://musicbrainz.org/ws/2/release/", ["query": query, "fmt": "json", "limit": "5"])
            let data = try await cachedJSON(url, deadline: deadline)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let releases = (json?["releases"] as? [[String: Any]] ?? []).filter {
                ArtworkMatch.normalized($0["title"] as? String ?? "") == ArtworkMatch.normalized(origin)
                    && ArtworkMatch.artistMatches(request.artist, credited: artists($0))
            }
            for release in releases.prefix(2) {
                do {
                    if let cover = try await catalogCover(release, artist: request.artist, match: .originOnly,
                        explanation: "The release title and artist match your source. Confirm this is the cover you want for this song.", deadline: deadline) {
                        found.append(cover)
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { if isAvailabilityFailure(error) { sourceFailure = error } }
            }
            // Shared artist+release queries and image listings are cached, so a
            // collection of fourteen songs does not repeat fourteen catalog calls.
            if !releases.isEmpty {
                if found.isEmpty, let sourceFailure { throw sourceFailure }
                return found
            }
        }
        let title = ArtworkMatch.catalogTitle(override.isEmpty ? request.title : override)
        guard !title.isEmpty, Date() < deadline else { return [] }
        let query = "recording:" + ArtworkMatch.lucenePhrase(title) + " AND artist:" + ArtworkMatch.lucenePhrase(request.artist)
        let url = try endpoint("https://musicbrainz.org/ws/2/recording/", ["query": query, "fmt": "json", "limit": "15"])
        let data = try await cachedJSON(url, deadline: deadline)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let recordings = (json?["recordings"] as? [[String: Any]] ?? []).enumerated().sorted { lhs, rhs in
            func penalty(_ value: [String: Any]) -> Int {
                let description = ArtworkMatch.normalized(value["disambiguation"] as? String ?? "")
                return description.contains("live") ? 2 : description.isEmpty ? 0 : 1
            }
            let a = penalty(lhs.element), b = penalty(rhs.element)
            return a == b ? lhs.offset < rhs.offset : a < b
        }.map(\.element)
        var seen = Set<String>()
        var attempted = 0
        for recording in recordings {
            let recordingTitle = recording["title"] as? String ?? ""
            guard ArtworkMatch.catalogRecordingMatches(title: recordingTitle, creditedArtists: artists(recording), request: request) else { continue }
            let variant = ArtworkMatch.needsVersionReview(request, catalogTitle: recordingTitle + " " + (recording["disambiguation"] as? String ?? ""))
            for release in recording["releases"] as? [[String: Any]] ?? [] {
                let secondaryTypes = (release["release-group"] as? [String: Any])?["secondary-types"] as? [String] ?? []
                guard ArtworkMatch.catalogReleaseMatchesArtist(creditedArtists: artists(release), secondaryTypes: secondaryTypes, request: request) else { continue }
                guard let id = release["id"] as? String, seen.insert(id).inserted, attempted < 3, Date() < deadline else { continue }
                attempted += 1
                do {
                    if let cover = try await catalogCover(release, artist: request.artist, match: variant ? .uncertain : .specificSubject,
                        explanation: variant ? "Artwork from a catalogued release of this song and artist. The exact remix or version is not verified."
                            : "The recording title and credited artist match. Review the release cover before using it.", deadline: deadline) {
                        found.append(cover)
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { if isAvailabilityFailure(error) { sourceFailure = error } }
                if found.count >= 2 { return found }
            }
        }
        if found.isEmpty, let sourceFailure { throw sourceFailure }
        return found
    }

    /// A reachable source without verified cover art is a no-match; a failed source is not.
    static func isAvailabilityFailure(_ error: Error) -> Bool {
        if error is URLError { return true }
        guard let error = error as? ArtworkDiscoveryError else { return false }
        switch error {
        case .unavailable, .busy: return true
        default: return false
        }
    }

    private static func catalogCover(_ release: [String: Any], artist: String, match: ArtworkMatchLevel,
                                     explanation: String, deadline: Date) async throws -> ArtworkCandidate? {
        guard let rawID = release["id"] as? String, let uuid = UUID(uuidString: rawID),
              let title = release["title"] as? String else { return nil }
        let id = uuid.uuidString.lowercased()
        let detailsURL = try endpoint("https://musicbrainz.org/ws/2/release/\(id)", ["inc": "url-rels+artist-credits", "fmt": "json"])
        let data = try await cachedJSON(detailsURL, deadline: deadline)
        guard let details = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let credits = details["artist-credit"] as? [[String: Any]] ?? []
        let names = credits.compactMap { $0["name"] as? String }
        guard ArtworkMatch.artistMatches(artist, credited: names) else { return nil }
        let pages = (details["relations"] as? [[String: Any]] ?? []).compactMap { relation -> URL? in
            guard let address = (relation["url"] as? [String: Any])?["resource"] as? String,
                  let url = URL(string: address), ArtworkMatch.isCreatorReleasePage(url) else { return nil }
            return url
        }
        guard !pages.isEmpty else { return nil }
        var creatorHosts = Set<String>()
        for credit in credits.prefix(2) {
            guard let identity = credit["artist"] as? [String: Any], let raw = identity["id"] as? String,
                  let artistID = UUID(uuidString: raw)?.uuidString.lowercased() else { continue }
            let url = try endpoint("https://musicbrainz.org/ws/2/artist/\(artistID)", ["inc": "url-rels", "fmt": "json"])
            let data = try await cachedJSON(url, deadline: deadline)
            guard let identity = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for relation in identity["relations"] as? [[String: Any]] ?? [] where relation["type"] as? String == "bandcamp" {
                if let address = (relation["url"] as? [String: Any])?["resource"] as? String,
                   let url = URL(string: address), ArtworkMatch.allowsRemoteURL(url), let host = url.host,
                   host.hasSuffix(".bandcamp.com") { creatorHosts.insert(host) }
            }
        }
        guard let page = pages.first(where: { creatorHosts.contains($0.host ?? "") }) else { return nil }
        return try await creatorCover(page: page, expectedTitle: title, expectedArtist: artist,
                                      publisher: artist, match: match, explanation: explanation, deadline: deadline)
    }

    private static func creatorCover(page: URL, expectedTitle: String, expectedArtist: String, publisher: String,
                                     match: ArtworkMatchLevel, explanation: String, deadline: Date? = nil) async throws -> ArtworkCandidate {
        guard ArtworkMatch.isCreatorReleasePage(page) else { throw ArtworkDiscoveryError.unverifiedCreator }
        let budget = deadline ?? Date().addingTimeInterval(20)
        let data: Data
        if let cached = await ArtworkRequestCache.shared.value(for: page) { data = cached }
        else {
            guard budget.timeIntervalSinceNow > 0 else { throw ArtworkDiscoveryError.unavailable }
            data = try await download(page, maximumBytes: maximumJSONBytes, image: false,
                                      timeout: min(15, budget.timeIntervalSinceNow), html: true)
            await ArtworkRequestCache.shared.store(data, for: page)
        }
        guard let html = String(data: data, encoding: .utf8),
              let album = parseCreatorAlbum(html),
              ArtworkMatch.normalized(album.title) == ArtworkMatch.normalized(expectedTitle),
              ArtworkMatch.artistMatches(expectedArtist, credited: [album.artist]),
              let image = ArtworkMatch.originalBandcampImage(from: album.image) else { throw ArtworkDiscoveryError.unverifiedCreator }
        let bytes = try await cachedImage(image, deadline: budget)
        let dimensions = try sourceDimensions(bytes)
        guard min(dimensions.width, dimensions.height) >= 300 else { throw ArtworkDiscoveryError.invalidImage }
        let candidate = ArtworkCandidate(title: album.title + " · " + album.artist, imageURL: image, pageURL: page,
            sourceName: publisher, credit: "Original cover published on \(publisher)’s own Bandcamp release page.",
            match: match, explanation: explanation, isOfficial: true,
            sourcePixelWidth: dimensions.width, sourcePixelHeight: dimensions.height)
        await ArtworkRequestCache.shared.verify(candidate)
        return candidate
    }

    static func parseCreatorAlbum(_ html: String) -> (title: String, artist: String, image: URL)? {
        guard let expression = try? NSRegularExpression(pattern: #"<script[^>]*type=["']application/ld\+json["'][^>]*>([\s\S]*?)</script>"#, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in expression.matches(in: html, range: range).prefix(5) {
            guard let body = Range(match.range(at: 1), in: html), let data = String(html[body]).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["@type"] as? String == "MusicAlbum", let title = object["name"] as? String,
                  let artist = (object["byArtist"] as? [String: Any])?["name"] as? String,
                  let raw = object["image"] as? String, let image = URL(string: raw) else { continue }
            return (title, artist, image)
        }
        return nil
    }

    private static func cachedImage(_ url: URL, deadline: Date? = nil) async throws -> Data {
        if let cached = await ArtworkRequestCache.shared.value(for: url) { return cached }
        let remaining = deadline?.timeIntervalSinceNow ?? 15
        guard remaining > 0 else { throw ArtworkDiscoveryError.unavailable }
        let data = try await download(url, maximumBytes: maximumImageBytes, image: true, timeout: min(15, remaining))
        _ = try sourceDimensions(data)
        await ArtworkRequestCache.shared.store(data, for: url)
        return data
    }

    static func sourceDimensions(_ data: Data) throws -> (width: Int, height: Int) {
        guard data.count <= maximumImageBytes else { throw ArtworkDiscoveryError.oversized }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source),
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.webP.identifier].contains(type as String),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw ArtworkDiscoveryError.invalidImage }
        guard width > 0, height > 0, width <= 20_000, height <= 20_000,
              width <= maximumImagePixels / height else { throw ArtworkDiscoveryError.tooManyPixels }
        guard ArtworkMatch.isNearSquare(width: width, height: height) else { throw ArtworkDiscoveryError.notSquare }
        return (width, height)
    }

    private static func cachedJSON(_ url: URL, deadline: Date? = nil) async throws -> Data {
        try Task.checkCancellation()
        if let data = await ArtworkRequestCache.shared.value(for: url) { return data }
        let budget = deadline ?? Date().addingTimeInterval(15)
        for attempt in 0...1 {
            if url.host == "musicbrainz.org" { try await ArtworkRequestCache.shared.waitForMusicBrainz(deadline: budget) }
            let remaining = budget.timeIntervalSinceNow
            guard remaining > 0 else { throw ArtworkDiscoveryError.unavailable }
            do {
                let data = try await download(url, maximumBytes: maximumJSONBytes, image: false, timeout: min(15, remaining))
                await ArtworkRequestCache.shared.store(data, for: url)
                return data
            } catch ArtworkDiscoveryError.busy {
                guard attempt == 0, url.host == "musicbrainz.org", budget.timeIntervalSinceNow > 1.1 else { throw ArtworkDiscoveryError.busy }
                try await Task.sleep(nanoseconds: 1_100_000_000)
            }
        }
        throw ArtworkDiscoveryError.unavailable
    }

    private static func endpoint(_ base: String, _ parameters: [String: String]) throws -> URL {
        guard var components = URLComponents(string: base) else { throw ArtworkDiscoveryError.unsafeURL }
        components.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url, ArtworkMatch.allowsRemoteURL(url) else { throw ArtworkDiscoveryError.unsafeURL }
        return url
    }

    static func download(_ url: URL, maximumBytes: Int, image: Bool, timeout: TimeInterval = 15, html: Bool = false) async throws -> Data {
        guard ArtworkMatch.allowsRemoteURL(url) else { throw ArtworkDiscoveryError.unsafeURL }
        try Task.checkCancellation()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = min(10, max(0.1, timeout))
        configuration.timeoutIntervalForResource = max(0.1, timeout)
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("Bard/1.3.1 (https://briggskellogg.com)", forHTTPHeaderField: "User-Agent")
        request.setValue(image ? "image/png,image/jpeg,image/webp,image/heic" : html ? "text/html" : "application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request, delegate: ArtworkRedirectGuard(original: url))
        guard let response = response as? HTTPURLResponse,
              let finalURL = response.url, ArtworkMatch.allowsRedirect(from: url, to: finalURL) else { throw ArtworkDiscoveryError.unavailable }
        if response.statusCode == 429 || response.statusCode == 503 { throw ArtworkDiscoveryError.busy }
        guard response.statusCode == 200 else { throw ArtworkDiscoveryError.unavailable }
        if response.expectedContentLength > Int64(maximumBytes) { throw ArtworkDiscoveryError.oversized }
        let mime = response.mimeType?.lowercased() ?? ""
        guard image ? mime.hasPrefix("image/") : html ? mime == "text/html" : (mime == "application/json" || mime == "text/json") else {
            throw image ? ArtworkDiscoveryError.invalidImage : ArtworkDiscoveryError.unavailable
        }
        var data = Data()
        data.reserveCapacity(min(maximumBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            if data.count >= maximumBytes { throw ArtworkDiscoveryError.oversized }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }
}

private actor ArtworkRequestCache {
    static let shared = ArtworkRequestCache()
    private struct Entry { let data: Data; let date: Date }
    private var entries: [URL: Entry] = [:]
    private var verified: [String: (ArtworkCandidate, Date)] = [:]
    func verify(_ candidate: ArtworkCandidate) {
        verified[candidate.id] = (candidate, Date())
        if verified.count > 32, let oldest = verified.min(by: { $0.value.1 < $1.value.1 })?.key { verified[oldest] = nil }
    }
    func isVerified(_ candidate: ArtworkCandidate) -> Bool {
        guard let value = verified[candidate.id] else { return false }
        return value.0 == candidate && Date().timeIntervalSince(value.1) < 900
    }
    private var nextMusicBrainzRequest = Date.distantPast

    func value(for url: URL) -> Data? {
        guard let entry = entries[url], Date().timeIntervalSince(entry.date) < 900 else {
            entries[url] = nil; return nil
        }
        return entry.data
    }
    func store(_ data: Data, for url: URL) {
        entries[url] = Entry(data: data, date: Date())
        while entries.count > 32 || entries.values.reduce(0, { $0 + $1.data.count }) > 16 * 1024 * 1024 {
            guard let oldest = entries.min(by: { $0.value.date < $1.value.date })?.key else { break }
            entries[oldest] = nil
        }
    }
    func waitForMusicBrainz(deadline: Date?) async throws {
        while true {
            try Task.checkCancellation()
            let wait = nextMusicBrainzRequest.timeIntervalSinceNow
            if let deadline, deadline.timeIntervalSinceNow <= max(0, wait) { throw ArtworkDiscoveryError.unavailable }
            if wait <= 0 {
                nextMusicBrainzRequest = Date().addingTimeInterval(1.1)
                return
            }
            // Waiting tasks reserve nothing. Cancelling a search therefore cannot
            // leave a queue of unused future slots that delays subsequent songs.
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }
}

private final class ArtworkRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let original: URL
    init(original: URL) { self.original = original }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, ArtworkMatch.allowsRedirect(from: original, to: url) else { completionHandler(nil); return }
        completionHandler(request)
    }
}
