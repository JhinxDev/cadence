import Foundation

public enum DemoCatalog {
    public static let demoAccount = UserAccount(
        serverURL: "https://demo.cadence.local",
        username: "yassine",
        password: "demo",
        bearerToken: "demo-token",
        isDemo: true
    )

    public static let libraryTracks: [Track] = [
        Track(
            id: "demo-lib-1",
            title: "Iceberg",
            artist: "Zaho",
            album: "Résilience",
            durationSec: 204,
            source: .library,
            inLibrary: true,
            isPreview: false,
            isStarred: true,
            reason: "Heavy rotation",
            navidromeId: "demo-lib-1",
            year: 2023,
            genre: "Pop"
        ),
        Track(
            id: "demo-lib-2",
            title: "Bâtiment",
            artist: "Niska",
            album: "Mr Sal",
            durationSec: 210,
            source: .library,
            inLibrary: true,
            isPreview: false,
            isStarred: true,
            reason: "From your Liked songs",
            navidromeId: "demo-lib-2",
            year: 2019,
            genre: "Rap"
        ),
        Track(
            id: "demo-lib-3",
            title: "Fairytale",
            artist: "Alexander Rybak",
            album: "Fairytales",
            durationSec: 182,
            source: .library,
            inLibrary: true,
            isPreview: false,
            isStarred: true,
            reason: "Forgotten favorite",
            navidromeId: "demo-lib-3",
            year: 2009,
            genre: "Pop"
        ),
        Track(
            id: "demo-lib-4",
            title: "Tourner la page",
            artist: "Zaho",
            album: "Dima",
            durationSec: 225,
            source: .library,
            inLibrary: true,
            isPreview: false,
            isStarred: false,
            reason: "Similar sound via Maestro",
            navidromeId: "demo-lib-4",
            year: 2008,
            genre: "R&B"
        ),
    ]

    public static let discoveryTracks: [Track] = [
        Track(
            id: "ext:deezer:2001",
            title: "Nuit Blanche",
            artist: "Shay",
            album: "Pourvu qu'il pleuve",
            durationSec: 190,
            source: .discovery,
            inLibrary: false,
            isPreview: false,
            isStarred: false,
            reason: "Because you listen to Zaho",
            year: 2024,
            genre: "Rap"
        ),
        Track(
            id: "ext:deezer:2002",
            title: "Sans Réponse",
            artist: "Tayc",
            album: "Fleur Froide",
            durationSec: 210,
            source: .discovery,
            inLibrary: false,
            isPreview: false,
            isStarred: false,
            reason: "Radio from Iceberg",
            year: 2021,
            genre: "R&B"
        ),
        Track(
            id: "ext:deezer:2003",
            title: "À fleur de toi",
            artist: "Vitaa",
            album: "À fleur de toi",
            durationSec: 235,
            source: .discovery,
            inLibrary: false,
            isPreview: false,
            isStarred: false,
            reason: "Similar to Zaho",
            year: 2007,
            genre: "R&B"
        ),
        Track(
            id: "ext:deezer:2004",
            title: "Ça fait mal",
            artist: "Orelsan & L2B",
            album: "Sorties Rap",
            durationSec: 198,
            source: .discovery,
            inLibrary: false,
            isPreview: false,
            isStarred: false,
            reason: "New Release Mix",
            year: 2026,
            genre: "Rap"
        ),
    ]

    public static let albums: [AlbumCard] = [
        AlbumCard(id: "alb-1", title: "Résilience", artist: "Zaho", year: 2023, songCount: 21),
        AlbumCard(id: "alb-2", title: "Mr Sal", artist: "Niska", year: 2019, songCount: 18),
        AlbumCard(id: "alb-3", title: "VERSATILE", artist: "Zaho", year: 2017, songCount: 13),
        AlbumCard(id: "alb-4", title: "Hypnotic LoFi", artist: "Various Artists", year: 2025, songCount: 10),
    ]

    public static let playlists: [PlaylistSummary] = [
        PlaylistSummary(id: "pl-1", name: "Liked Music", songCount: 472, durationSec: 94200),
        PlaylistSummary(id: "pl-2", name: "On Repeat", songCount: 25, durationSec: 5100),
        PlaylistSummary(id: "pl-3", name: "Rediscover Favorites", songCount: 25, durationSec: 4950),
        PlaylistSummary(id: "pl-4", name: "New in Navidrome", songCount: 17, durationSec: 3200),
    ]

    public static let artists: [ArtistCard] = [
        ArtistCard(id: "art-1", name: "Shay", reason: "Similar to Zaho", inLibrary: false, seedArtist: "Zaho"),
        ArtistCard(id: "art-2", name: "Tayc", reason: "Similar to Zaho", inLibrary: false, seedArtist: "Zaho"),
        ArtistCard(id: "art-3", name: "SDM", reason: "Similar to Niska", inLibrary: false, seedArtist: "Niska"),
        ArtistCard(id: "art-4", name: "Vitaa", reason: "Similar to Zaho", inLibrary: false, seedArtist: "Zaho"),
    ]

    public static let homeFeed = HomeFeed(
        mood: "All",
        moods: ["All", "Energize", "Chill", "Focus", "Workout", "Late Night", "Discover"],
        speedDial: [
            SpeedDialItem(id: "sd-1", kind: "album", title: "Résilience", subtitle: "Zaho", targetId: "alb-1", tracks: [libraryTracks[0]]),
            SpeedDialItem(id: "sd-2", kind: "album", title: "Mr Sal", subtitle: "Niska", targetId: "alb-2", tracks: [libraryTracks[1]]),
            SpeedDialItem(id: "sd-3", kind: "playlist", title: "Liked Music", subtitle: "472 songs", targetId: "pl-1", tracks: libraryTracks),
            SpeedDialItem(id: "sd-4", kind: "album", title: "VERSATILE", subtitle: "Zaho", targetId: "alb-3", tracks: [libraryTracks[0]]),
            SpeedDialItem(id: "sd-5", kind: "playlist", title: "On Repeat", subtitle: "25 songs", targetId: "pl-2", tracks: libraryTracks),
            SpeedDialItem(id: "sd-6", kind: "album", title: "Hypnotic LoFi", subtitle: "LoFi", targetId: "alb-4", tracks: [libraryTracks[2]]),
        ],
        quickPicks: libraryTracks + discoveryTracks + libraryTracks + discoveryTracks,
        madeForYou: [
            MixCard(id: "supermix", title: "My Supermix", subtitle: "Your heavy rotation blended with fresh finds", accentHex: "#FF3B5C", trackCount: 25, badge: "PERSONALIZED"),
            MixCard(id: "discover-mix", title: "Discover Mix", subtitle: "New artists & tracks tailored to your taste", accentHex: "#7C5CFF", trackCount: 25, badge: "NEW MUSIC"),
            MixCard(id: "replay-mix", title: "Replay Mix", subtitle: "The songs and albums you keep coming back to", accentHex: "#F59E0B", trackCount: 25, badge: "ON REPEAT"),
            MixCard(id: "new-releases", title: "New Release Mix", subtitle: "Recent drops from artists in your orbit", accentHex: "#EC4899", trackCount: 20, badge: "FRESH DROPS"),
            MixCard(id: "forgotten-favorites", title: "Forgotten Favorites", subtitle: "Starred tracks ready for a comeback", accentHex: "#14B8A6", trackCount: 25, badge: "REDISCOVER"),
        ],
        listenAgain: albums,
        recommendedArtists: artists,
        newInLibrary: Array(albums.reversed())
    )

    public static let sampleLyrics = LyricsResult(
        title: "Iceberg",
        artist: "Zaho",
        synced: true,
        source: "lrclib",
        lines: [
            LyricsLine(timeMs: 0, text: "Sous la surface, tout est calme"),
            LyricsLine(timeMs: 4200, text: "Mais l'iceberg cache ses failles"),
            LyricsLine(timeMs: 9100, text: "On avance dans la nuit froide"),
            LyricsLine(timeMs: 14500, text: "Sans jamais tourner la page"),
        ]
    )
}
