import Foundation

/// Where a recording was obtained; independent of its origin and remix version.
public enum MusicSource: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case local, soundcloud, bandcamp, web

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .local: return "Local"
        case .soundcloud: return "SoundCloud"
        case .bandcamp: return "Bandcamp"
        case .web: return "Web"
        }
    }

    public static func detect(_ url: URL?) -> MusicSource {
        guard let url, let host = url.host?.lowercased(), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return .local }
        if host == "soundcloud.com" || host.hasSuffix(".soundcloud.com") || host == "snd.sc" { return .soundcloud }
        if host == "bandcamp.com" || host.hasSuffix(".bandcamp.com") { return .bandcamp }
        return .web
    }

    public static func validatedURL(_ text: String) -> URL? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: clean),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}
