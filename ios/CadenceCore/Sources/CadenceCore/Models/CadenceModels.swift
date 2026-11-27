import Foundation

public enum RadioMode: String, Codable, CaseIterable, Sendable {
    case familiar
    case balanced
    case discover

    public var displayTitle: String {
        switch self {
        case .familiar: return "Familiar"
        case .balanced: return "Balanced"
        case .discover: return "Discover"
        }
    }

    public var subtitle: String {
        switch self {
        case .familiar: return "Mostly your library & Maestro picks"
        case .balanced: return "Half favorites, half fresh discoveries"
        case .discover: return "80%+ new music outside your library"
        }
    }
}

public enum TrackSource: String, Codable, Sendable {
    case library
    case discovery
}

public struct Track: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let durationSec: Int
    public let artworkURL: String?
    public let source: TrackSource
    public var inLibrary: Bool
    public var isPreview: Bool
    public var isStarred: Bool
    public let reason: String?
    public var navidromeId: String?
    public let year: Int?
    public let genre: String?
    public let bpm: Double?
    public let previewURL: String?
    public let deezerId: String?
    public let isrc: String?

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, source, reason, year, genre, bpm, isrc
        case durationSec = "duration_sec"
        case artworkURL = "artwork_url"
        case inLibrary = "in_library"
        case isPreview = "is_preview"
        case isStarred = "is_starred"
        case navidromeId = "navidrome_id"
        case previewURL = "preview_url"
        case deezerId = "deezer_id"
    }

    public init(
        id: String,
        title: String,
        artist: String,
        album: String = "",
        durationSec: Int = 0,
        artworkURL: String? = nil,
        source: TrackSource = .library,
        inLibrary: Bool = true,
        isPreview: Bool = false,
        isStarred: Bool = false,
        reason: String? = nil,
        navidromeId: String? = nil,
        year: Int? = nil,
        genre: String? = nil,
        bpm: Double? = nil,
        previewURL: String? = nil,
        deezerId: String? = nil,
        isrc: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSec = durationSec
        self.artworkURL = artworkURL
        self.source = source
        self.inLibrary = inLibrary
        self.isPreview = isPreview
        self.isStarred = isStarred
        self.reason = reason
        self.navidromeId = navidromeId
        self.year = year
        self.genre = genre
        self.bpm = bpm
        self.previewURL = previewURL
        self.deezerId = deezerId
        self.isrc = isrc
    }

    public var formattedDuration: String {
        let mins = max(0, durationSec) / 60
        let secs = max(0, durationSec) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

public struct SpeedDialItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let kind: String
    public let title: String
    public let subtitle: String
    public let artworkURL: String?
    public let targetId: String
    public let tracks: [Track]

    enum CodingKeys: String, CodingKey {
        case id, kind, title, subtitle, tracks
        case artworkURL = "artwork_url"
        case targetId = "target_id"
    }

    public init(
        id: String,
        kind: String,
        title: String,
        subtitle: String,
        artworkURL: String? = nil,
        targetId: String,
        tracks: [Track] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.artworkURL = artworkURL
        self.targetId = targetId
        self.tracks = tracks
    }
}

public struct MixCard: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let accentHex: String
    public let trackCount: Int
    public let mood: String?
    public let artworkURLs: [String]
    public let badge: String

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, mood, badge
        case accentHex = "accent_hex"
        case trackCount = "track_count"
        case artworkURLs = "artwork_urls"
    }

    public init(
        id: String,
        title: String,
        subtitle: String,
        accentHex: String,
        trackCount: Int,
        mood: String? = nil,
        artworkURLs: [String] = [],
        badge: String = "MADE FOR YOU"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.accentHex = accentHex
        self.trackCount = trackCount
        self.mood = mood
        self.artworkURLs = artworkURLs
        self.badge = badge
    }
}

public struct AlbumCard: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let year: Int?
    public let songCount: Int
    public let artworkURL: String?

    enum CodingKeys: String, CodingKey {
        case id, title, artist, year
        case songCount = "song_count"
        case artworkURL = "artwork_url"
    }

    public init(
        id: String,
        title: String,
        artist: String,
        year: Int? = nil,
        songCount: Int = 0,
        artworkURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.year = year
        self.songCount = songCount
        self.artworkURL = artworkURL
    }
}

public struct ArtistCard: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let reason: String
    public let artworkURL: String?
    public let inLibrary: Bool
    public let seedArtist: String?

    enum CodingKeys: String, CodingKey {
        case id, name, reason
        case artworkURL = "artwork_url"
        case inLibrary = "in_library"
        case seedArtist = "seed_artist"
    }

    public init(
        id: String,
        name: String,
        reason: String,
        artworkURL: String? = nil,
        inLibrary: Bool = false,
        seedArtist: String? = nil
    ) {
        self.id = id
        self.name = name
        self.reason = reason
        self.artworkURL = artworkURL
        self.inLibrary = inLibrary
        self.seedArtist = seedArtist
    }
}

public struct PlaylistSummary: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let songCount: Int
    public let durationSec: Int
    public let artworkURL: String?

    public init(
        id: String,
        name: String,
        songCount: Int,
        durationSec: Int = 0,
        artworkURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.songCount = songCount
        self.durationSec = durationSec
        self.artworkURL = artworkURL
    }
}

public struct HomeFeed: Codable, Sendable {
    public let mood: String
    public let moods: [String]
    public let speedDial: [SpeedDialItem]
    public let quickPicks: [Track]
    public let madeForYou: [MixCard]
    public let listenAgain: [AlbumCard]
    public let recommendedArtists: [ArtistCard]
    public let newInLibrary: [AlbumCard]

    enum CodingKeys: String, CodingKey {
        case mood, moods
        case speedDial = "speed_dial"
        case quickPicks = "quick_picks"
        case madeForYou = "made_for_you"
        case listenAgain = "listen_again"
        case recommendedArtists = "recommended_artists"
        case newInLibrary = "new_in_library"
    }

    public init(
        mood: String,
        moods: [String],
        speedDial: [SpeedDialItem],
        quickPicks: [Track],
        madeForYou: [MixCard],
        listenAgain: [AlbumCard],
        recommendedArtists: [ArtistCard],
        newInLibrary: [AlbumCard]
    ) {
        self.mood = mood
        self.moods = moods
        self.speedDial = speedDial
        self.quickPicks = quickPicks
        self.madeForYou = madeForYou
        self.listenAgain = listenAgain
        self.recommendedArtists = recommendedArtists
        self.newInLibrary = newInLibrary
    }
}

public struct MixDetail: Codable, Sendable {
    public let mix: MixCard
    public let tracks: [Track]

    public init(mix: MixCard, tracks: [Track]) {
        self.mix = mix
        self.tracks = tracks
    }
}

public struct RadioBatch: Codable, Sendable {
    public let sessionId: String
    public let mode: RadioMode
    public let seedLabel: String
    public let tracks: [Track]

    enum CodingKeys: String, CodingKey {
        case mode, tracks
        case sessionId = "session_id"
        case seedLabel = "seed_label"
    }

    public init(sessionId: String, mode: RadioMode, seedLabel: String, tracks: [Track]) {
        self.sessionId = sessionId
        self.mode = mode
        self.seedLabel = seedLabel
        self.tracks = tracks
    }
}

public struct SearchResults: Codable, Sendable {
    public let query: String
    public let libraryTracks: [Track]
    public let discoveryTracks: [Track]
    public let libraryAlbums: [AlbumCard]
    public let artists: [ArtistCard]

    enum CodingKeys: String, CodingKey {
        case query, artists
        case libraryTracks = "library_tracks"
        case discoveryTracks = "discovery_tracks"
        case libraryAlbums = "library_albums"
    }

    public init(
        query: String,
        libraryTracks: [Track],
        discoveryTracks: [Track],
        libraryAlbums: [AlbumCard],
        artists: [ArtistCard]
    ) {
        self.query = query
        self.libraryTracks = libraryTracks
        self.discoveryTracks = discoveryTracks
        self.libraryAlbums = libraryAlbums
        self.artists = artists
    }
}

public struct LyricsLine: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(timeMs ?? -1)-\(text)" }
    public let timeMs: Int?
    public let text: String

    enum CodingKeys: String, CodingKey {
        case text
        case timeMs = "time_ms"
    }

    public init(timeMs: Int? = nil, text: String) {
        self.timeMs = timeMs
        self.text = text
    }
}

public struct LyricsResult: Codable, Sendable {
    public let title: String
    public let artist: String
    public let synced: Bool
    public let source: String
    public let lines: [LyricsLine]
    public let plainText: String?

    enum CodingKeys: String, CodingKey {
        case title, artist, synced, source, lines
        case plainText = "plain_text"
    }

    public init(
        title: String,
        artist: String,
        synced: Bool = false,
        source: String = "none",
        lines: [LyricsLine] = [],
        plainText: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.synced = synced
        self.source = source
        self.lines = lines
        self.plainText = plainText
    }
}

public struct ServerCapabilities: Codable, Sendable {
    public let service: String
    public let version: String
    public let discoveryEnabled: Bool
    public let fullDiscoveryStreaming: Bool
    public let saveToLibraryEnabled: Bool
    public let lyricsEnabled: Bool
    public let subsonicProxyEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case service, version
        case discoveryEnabled = "discovery_enabled"
        case fullDiscoveryStreaming = "full_discovery_streaming"
        case saveToLibraryEnabled = "save_to_library_enabled"
        case lyricsEnabled = "lyrics_enabled"
        case subsonicProxyEnabled = "subsonic_proxy_enabled"
    }

    public init(
        service: String = "cadence",
        version: String = "0.1.0",
        discoveryEnabled: Bool = true,
        fullDiscoveryStreaming: Bool = false,
        saveToLibraryEnabled: Bool = false,
        lyricsEnabled: Bool = true,
        subsonicProxyEnabled: Bool = true
    ) {
        self.service = service
        self.version = version
        self.discoveryEnabled = discoveryEnabled
        self.fullDiscoveryStreaming = fullDiscoveryStreaming
        self.saveToLibraryEnabled = saveToLibraryEnabled
        self.lyricsEnabled = lyricsEnabled
        self.subsonicProxyEnabled = subsonicProxyEnabled
    }

    public static let standaloneSubsonic = ServerCapabilities(
        service: "opensubsonic",
        version: "1.16.1",
        discoveryEnabled: false,
        fullDiscoveryStreaming: false,
        saveToLibraryEnabled: false,
        lyricsEnabled: true,
        subsonicProxyEnabled: true
    )
}

public struct UserAccount: Codable, Sendable, Equatable {
    public let serverURL: String
    public let username: String
    public let password: String
    public var bearerToken: String?
    public var isDemo: Bool

    public init(
        serverURL: String,
        username: String,
        password: String,
        bearerToken: String? = nil,
        isDemo: Bool = false
    ) {
        self.serverURL = serverURL
        self.username = username
        self.password = password
        self.bearerToken = bearerToken
        self.isDemo = isDemo
    }
}
