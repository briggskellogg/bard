import Foundation

/// Browser search uses descriptive music metadata only, never a local file path.
public enum ArtworkSearch {
    public static func googleImagesURL(for request: ArtworkRequest) -> URL {
        let kind = request.mediaKind ?? OriginMediaKind.infer(from: request.origin)
        let subject = ArtworkMatch.subjects(for: request).first ?? request.title
        let values = [subject, request.origin, [.music, .unknown].contains(kind) ? request.artist : ""]
        var seen = Set<String>()
        let terms = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(ArtworkMatch.normalized($0)).inserted }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "tbm", value: "isch"),
                                URLQueryItem(name: "q", value: (terms + ["official square cover art"]).joined(separator: " "))]
        return components.url!
    }
}
