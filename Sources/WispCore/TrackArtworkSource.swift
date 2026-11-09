import Foundation

/// The reference kept with an explicitly approved cover. It records where the
/// image came from, without treating the provider's description as ownership.
public struct TrackArtworkSource: Codable, Equatable, Sendable {
    public var provider: String
    public var sourcePageURL: String
    public var imageURL: String?
    public var credit: String?
    public var title: String?
    public var appliedAt: Date

    public init(provider: String, sourcePageURL: String, imageURL: String? = nil,
                credit: String? = nil, title: String? = nil, appliedAt: Date = Date()) {
        self.provider = provider
        self.sourcePageURL = sourcePageURL
        self.imageURL = imageURL
        self.credit = credit
        self.title = title
        self.appliedAt = appliedAt
    }

    public func validate() throws {
        guard !provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              provider.count <= 160, (credit?.count ?? 0) <= 2048,
              (title?.count ?? 0) <= 1024,
              appliedAt.timeIntervalSinceReferenceDate.isFinite,
              Self.isReferenceURL(sourcePageURL),
              imageURL.map(Self.isReferenceURL) ?? true else {
            throw LibraryError.invalidData("The artwork source is not a valid website reference.")
        }
    }

    private static func isReferenceURL(_ value: String) -> Bool {
        guard value.count <= 8192,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else { return false }
        return true
    }
}
