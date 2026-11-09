import Foundation

/// A permanent, explicitly chosen collection. Its identity never depends on
/// a display name, so an existing user playlist called Mixtape stays separate.
public enum MixtapeCollection {
    public static let id = UUID(uuidString: "0B9AC497-BCF4-4CA3-A6A3-9B5827EA03A7")!
    public static let name = "Mixtape"
    public static let symbol = "wisp.mixtape"

    /// Returns true only when a migration is required. Never chooses tracks.
    @discardableResult
    public static func ensure(in document: inout LibraryDocument) -> Bool {
        guard let index = document.playlists.firstIndex(where: \.isMixtape) else {
            document.playlists.append(Playlist(id: id, name: name, symbol: symbol))
            return true
        }
        let previous = document.playlists[index]
        document.playlists[index].name = name
        document.playlists[index].symbol = symbol
        document.playlists[index].folderID = nil
        return previous != document.playlists[index]
    }
}

public extension Playlist {
    var isMixtape: Bool { id == MixtapeCollection.id }
}

public extension LibraryDocument {
    /// SwiftUI move semantics, implemented in the model so ordered membership
    /// survives relaunch and is shared by local playback and Music sync.
    mutating func moveTracks(fromOffsets offsets: IndexSet, toOffset destination: Int, in playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let ids = playlists[index].trackIDs
        guard !offsets.isEmpty, offsets.allSatisfy(ids.indices.contains),
              (0...ids.count).contains(destination) else { return }
        let moved = offsets.map { ids[$0] }
        var remaining = ids.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.filter { $0 < destination }.count
        remaining.insert(contentsOf: moved, at: insertion)
        playlists[index].trackIDs = remaining
    }
}
