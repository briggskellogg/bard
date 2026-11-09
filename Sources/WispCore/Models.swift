import Foundation

public struct Track: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var artist: String
    public var genre: String
    public var album: String
    public var fileName: String
    public var fingerprint: String
    public var artworkFileName: String?
    public var artworkSource: TrackArtworkSource?
    public var duration: Double
    public var byteCount: Int64
    public var addedAt: Date
    public var favorite: Bool
    public var origin: String
    public var remix: RemixKind?
    public var originalFileName: String
    public var sourceURL: String?
    public var originMediaKind: OriginMediaKind?
    public var audioVersions: [TrackAudioVersion]
    public var currentAudioAddedAt: Date?
    public var currentAudioVersionID: UUID?
    public var remixSource: RemixSource?

    public init(id: UUID = UUID(), title: String, artist: String = "", album: String = "",
                fileName: String, fingerprint: String, artworkFileName: String? = nil,
                duration: Double = 0, byteCount: Int64 = 0, addedAt: Date = Date(), favorite: Bool = false,
                origin: String = "", remix: RemixKind? = nil, originalFileName: String = "", sourceURL: String? = nil,
                originMediaKind: OriginMediaKind? = nil, genre: String = "",
                audioVersions: [TrackAudioVersion] = [], currentAudioAddedAt: Date? = nil,
                currentAudioVersionID: UUID? = nil, remixSource: RemixSource? = nil,
                artworkSource: TrackArtworkSource? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.genre = genre
        self.album = album
        self.fileName = fileName
        self.fingerprint = fingerprint
        self.artworkFileName = artworkFileName
        self.artworkSource = artworkSource
        self.duration = duration
        self.byteCount = byteCount
        self.addedAt = addedAt
        self.favorite = favorite
        self.origin = origin
        self.remix = remix
        self.originalFileName = originalFileName
        self.sourceURL = sourceURL
        self.originMediaKind = originMediaKind
        self.audioVersions = audioVersions
        self.currentAudioAddedAt = currentAudioAddedAt
        self.currentAudioVersionID = currentAudioVersionID
        self.remixSource = remixSource
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, genre, album, fileName, fingerprint, artworkFileName, duration, byteCount, addedAt, favorite
        case origin, remix, originalFileName, sourceURL, originMediaKind
        case audioVersions, currentAudioAddedAt, currentAudioVersionID
        case remixSource
        case artworkSource
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        artist = try values.decodeIfPresent(String.self, forKey: .artist) ?? ""
        genre = try values.decodeIfPresent(String.self, forKey: .genre) ?? ""
        album = try values.decodeIfPresent(String.self, forKey: .album) ?? ""
        fileName = try values.decode(String.self, forKey: .fileName)
        fingerprint = try values.decode(String.self, forKey: .fingerprint)
        artworkFileName = try values.decodeIfPresent(String.self, forKey: .artworkFileName)
        artworkSource = try values.decodeIfPresent(TrackArtworkSource.self, forKey: .artworkSource)
        duration = try values.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        byteCount = try values.decodeIfPresent(Int64.self, forKey: .byteCount) ?? 0
        addedAt = try values.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date(timeIntervalSince1970: 0)
        favorite = try values.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        origin = try values.decodeIfPresent(String.self, forKey: .origin) ?? ""
        remix = try values.decodeIfPresent(RemixKind.self, forKey: .remix)
        originalFileName = try values.decodeIfPresent(String.self, forKey: .originalFileName) ?? ""
        sourceURL = try values.decodeIfPresent(String.self, forKey: .sourceURL)
        originMediaKind = try values.decodeIfPresent(OriginMediaKind.self, forKey: .originMediaKind)
        audioVersions = try values.decodeIfPresent([TrackAudioVersion].self, forKey: .audioVersions) ?? []
        currentAudioAddedAt = try values.decodeIfPresent(Date.self, forKey: .currentAudioAddedAt)
        currentAudioVersionID = try values.decodeIfPresent(UUID.self, forKey: .currentAudioVersionID)
        remixSource = try values.decodeIfPresent(RemixSource.self, forKey: .remixSource)
    }
}

public enum PaletteColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue, amber, coral, teal, violet, graphite
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct Playlist: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var description: String
    public var symbol: String
    public var tint: PaletteColor
    public var coverFileName: String?
    public var trackIDs: [UUID]
    public var folderID: UUID?
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, description: String = "",
                symbol: String = "music.note.list", tint: PaletteColor = .blue,
                coverFileName: String? = nil, trackIDs: [UUID] = [], folderID: UUID? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.description = description
        self.symbol = symbol
        self.tint = tint
        self.coverFileName = coverFileName
        self.trackIDs = trackIDs
        self.folderID = folderID
        self.createdAt = createdAt
    }
}

public struct PlaylistFolder: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var tint: PaletteColor
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, tint: PaletteColor = .graphite, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.tint = tint
        self.createdAt = createdAt
    }
}

public struct LibraryDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var tracks: [Track]
    public var playlists: [Playlist]
    public var folders: [PlaylistFolder]
    /// Committed phone favorite sequences. These receipts live only in the Mac index.
    public var phoneFavoriteReceipts: [String: Int64]

    public init(schemaVersion: Int = 1, tracks: [Track] = [], playlists: [Playlist] = [], folders: [PlaylistFolder] = [],
                phoneFavoriteReceipts: [String: Int64] = [:]) {
        self.schemaVersion = schemaVersion
        self.tracks = tracks
        self.playlists = playlists
        self.folders = folders
        self.phoneFavoriteReceipts = phoneFavoriteReceipts
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, tracks, playlists, folders, phoneFavoriteReceipts
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        tracks = try values.decode([Track].self, forKey: .tracks)
        playlists = try values.decode([Playlist].self, forKey: .playlists)
        folders = try values.decode([PlaylistFolder].self, forKey: .folders)
        phoneFavoriteReceipts = try values.decodeIfPresent([String: Int64].self, forKey: .phoneFavoriteReceipts) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(tracks, forKey: .tracks)
        try values.encode(playlists, forKey: .playlists)
        try values.encode(folders, forKey: .folders)
        if !phoneFavoriteReceipts.isEmpty {
            try values.encode(phoneFavoriteReceipts, forKey: .phoneFavoriteReceipts)
        }
    }

    /// Reject inconsistent manifests instead of silently discarding saved information.
    public func validate() throws {
        guard (1...3).contains(schemaVersion) else { throw LibraryError.unsupportedVersion(schemaVersion) }
        guard phoneFavoriteReceipts.count <= 1_024,
              phoneFavoriteReceipts.allSatisfy({ id, sequence in
                  UUID(uuidString: id)?.uuidString == id && sequence > 0
              }) else {
            throw LibraryError.invalidData("Invalid phone favorite receipts.")
        }
        let trackIDs = Set(tracks.map(\.id))
        let folderIDs = Set(folders.map(\.id))
        guard trackIDs.count == tracks.count,
              Set(playlists.map(\.id)).count == playlists.count,
              folderIDs.count == folders.count else { throw LibraryError.invalidData("Duplicate identifiers.") }
        guard Set(tracks.map(\.fingerprint)).count == tracks.count else {
            throw LibraryError.invalidData("Duplicate audio fingerprints.")
        }
        guard Set(tracks.map(\.fileName)).count == tracks.count else {
            throw LibraryError.invalidData("More than one track uses the same managed file.")
        }
        var managedAudioFiles = Set<String>()
        var versionIDs = Set<UUID>()
        for track in tracks {
            guard !track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !track.fingerprint.isEmpty,
                  track.duration.isFinite, track.duration >= 0, track.byteCount >= 0 else {
                throw LibraryError.invalidData("A track has invalid metadata.")
            }
            try Self.validateFileName(track.fileName)
            guard managedAudioFiles.insert(track.fileName).inserted else {
                throw LibraryError.invalidData("More than one audio version uses the same managed file.")
            }
            if !track.audioVersions.isEmpty || track.currentAudioAddedAt != nil || track.currentAudioVersionID != nil {
                guard schemaVersion >= 2, let date = track.currentAudioAddedAt,
                      date.timeIntervalSinceReferenceDate.isFinite,
                      let id = track.currentAudioVersionID, versionIDs.insert(id).inserted else {
                    throw LibraryError.invalidData("Versioned audio requires a supported library format and valid identifiers.")
                }
            }
            if let source = track.remixSource {
                guard schemaVersion >= 3, source.trackID != track.id else {
                    throw LibraryError.invalidData("Remix relationships require a supported library format and a different source song.")
                }
                try source.validate()
            }
            var trackFingerprints = Set([track.fingerprint])
            for version in track.audioVersions {
                try version.validate()
                guard managedAudioFiles.insert(version.fileName).inserted,
                      versionIDs.insert(version.id).inserted,
                      trackFingerprints.insert(version.fingerprint).inserted else {
                    throw LibraryError.invalidData("An audio version has a duplicate identity, file, or fingerprint.")
                }
            }
            if let name = track.artworkFileName { try Self.validateFileName(name) }
            if let source = track.artworkSource {
                guard track.artworkFileName != nil else {
                    throw LibraryError.invalidData("Artwork source details require a saved cover.")
                }
                try source.validate()
            }
            if let source = track.sourceURL {
                guard source.count <= 8192, let url = URL(string: source),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                    throw LibraryError.invalidData("A track has an invalid source link.")
                }
            }
        }
        for playlist in playlists {
            guard !playlist.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LibraryError.invalidData("A playlist has no name.")
            }
            guard Set(playlist.trackIDs).count == playlist.trackIDs.count,
                  playlist.trackIDs.allSatisfy({ trackIDs.contains($0) }) else {
                throw LibraryError.invalidData("A playlist contains an invalid track reference.")
            }
            if let folderID = playlist.folderID, !folderIDs.contains(folderID) {
                throw LibraryError.invalidData("A playlist refers to an unknown folder.")
            }
            if let name = playlist.coverFileName { try Self.validateFileName(name) }
        }
        for folder in folders where folder.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LibraryError.invalidData("A folder has no name.")
        }
    }

    public static func validateFileName(_ name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
              name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              name.utf8.count <= 240 else { throw LibraryError.invalidData("An unsafe managed filename was rejected.") }
    }

    /// Returns the imported or already-present IDs in input order, once each.
    @discardableResult
    public mutating func mergeTracks(_ imported: [Track]) -> [UUID] {
        var fingerprints = Dictionary(uniqueKeysWithValues: tracks.map { ($0.fingerprint, $0.id) })
        var knownIDs = Set(tracks.map(\.id))
        var result: [UUID] = []
        for track in imported {
            let id: UUID
            if let existingID = fingerprints[track.fingerprint] {
                id = existingID
            } else if knownIDs.contains(track.id) {
                // UUID conflicts must never replace audio already owned by another track.
                continue
            } else {
                tracks.append(track)
                fingerprints[track.fingerprint] = track.id
                knownIDs.insert(track.id)
                id = track.id
            }
            if !result.contains(id) { result.append(id) }
        }
        return result
    }

    public mutating func addTracks(_ ids: [UUID], to playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let available = Set(tracks.map(\.id))
        var present = Set(playlists[index].trackIDs)
        for id in ids where available.contains(id) {
            if present.insert(id).inserted { playlists[index].trackIDs.append(id) }
        }
    }

    public mutating func attachSource(_ source: String, to ids: Set<UUID>) {
        for index in tracks.indices where ids.contains(tracks[index].id) && tracks[index].sourceURL == nil {
            tracks[index].sourceURL = source
        }
    }

    public mutating func removeTracks(_ ids: Set<UUID>, from playlistID: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        playlists[index].trackIDs.removeAll { ids.contains($0) }
    }

    public mutating func deleteTracks(_ ids: Set<UUID>) {
        tracks.removeAll { ids.contains($0.id) }
        for index in playlists.indices { playlists[index].trackIDs.removeAll { ids.contains($0) } }
    }

    public mutating func deletePlaylist(id: UUID) { playlists.removeAll { $0.id == id } }

    public mutating func deleteFolder(id: UUID) {
        folders.removeAll { $0.id == id }
        for index in playlists.indices where playlists[index].folderID == id { playlists[index].folderID = nil }
    }

    public mutating func movePlaylist(id: UUID, to folderID: UUID?) {
        guard folderID == nil || folders.contains(where: { $0.id == folderID }),
              let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].folderID = folderID
    }

    public mutating func moveTrack(id: UUID, in playlistID: UUID, offset: Int) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }),
              let source = playlists[index].trackIDs.firstIndex(of: id) else { return }
        let (destination, overflow) = source.addingReportingOverflow(offset)
        guard !overflow, playlists[index].trackIDs.indices.contains(destination) else { return }
        let track = playlists[index].trackIDs.remove(at: source)
        playlists[index].trackIDs.insert(track, at: destination)
    }
}

public enum LibraryError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidData(String)
    case unreadable(String)
    case notLoaded
    case changedExternally
    case missingManifest
    case noRecovery

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): return "This library uses version \(version). Open it with a newer version of Bard."
        case .invalidData(let reason): return "The library is inconsistent. \(reason) No saved data was changed."
        case .unreadable(let reason): return "The library could not be opened. \(reason) Your files have been kept intact."
        case .notLoaded: return "The library is locked until its saved data can be read."
        case .changedExternally: return "The library changed outside this window. Quit and reopen Bard before editing it."
        case .missingManifest: return "The library index is missing, but saved files remain. Restore its previous index or a backup before editing."
        case .noRecovery: return "No readable previous library index is available. Your existing files have not been changed."
        }
    }
}
