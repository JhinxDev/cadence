import CryptoKit
import Foundation

public enum SubsonicError: LocalizedError {
    case invalidURL
    case serverError(String)
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .serverError(let msg): return msg
        case .decodingFailed: return "Unexpected Subsonic response"
        }
    }
}

public final class OpenSubsonicClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public static func makeAuthToken(password: String, salt: String) -> String {
        let digest = Insecure.MD5.hash(data: Data((password + salt).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func randomSalt(length: Int = 12) -> String {
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }

    public func buildURL(
        serverURL: String,
        endpoint: String,
        username: String,
        password: String,
        extra: [String: String] = [:]
    ) throws -> URL {
        let trimmed = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard var components = URLComponents(string: "\(trimmed)/rest/\(endpoint)") else {
            throw SubsonicError.invalidURL
        }
        let salt = Self.randomSalt()
        let token = Self.makeAuthToken(password: password, salt: salt)
        var items = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "s", value: salt),
            URLQueryItem(name: "v", value: "1.16.1"),
            URLQueryItem(name: "c", value: "Cadence"),
            URLQueryItem(name: "f", value: "json"),
        ]
        for (k, v) in extra {
            items.append(URLQueryItem(name: k, value: v))
        }
        components.queryItems = items
        guard let url = components.url else { throw SubsonicError.invalidURL }
        return url
    }

    private func call(
        account: UserAccount,
        endpoint: String,
        extra: [String: String] = [:]
    ) async throws -> [String: Any] {
        let url = try buildURL(
            serverURL: account.serverURL,
            endpoint: endpoint,
            username: account.username,
            password: account.password,
            extra: extra
        )
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw SubsonicError.serverError("Server returned an error for \(endpoint)")
        }
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sub = root["subsonic-response"] as? [String: Any]
        else {
            throw SubsonicError.decodingFailed
        }
        if (sub["status"] as? String) != "ok" {
            let err = sub["error"] as? [String: Any]
            let msg = (err?["message"] as? String) ?? "OpenSubsonic error"
            throw SubsonicError.serverError(msg)
        }
        return sub
    }

    public func ping(account: UserAccount) async throws -> Bool {
        _ = try await call(account: account, endpoint: "ping.view")
        return true
    }

    public func fetchPlaylists(account: UserAccount) async throws -> [PlaylistSummary] {
        let sub = try await call(account: account, endpoint: "getPlaylists.view")
        let playlists = (sub["playlists"] as? [String: Any])?["playlist"] as? [[String: Any]] ?? []
        return playlists.compactMap { row in
            guard let id = row["id"] as? String ?? (row["id"] as? Int).map(String.init) else {
                return nil
            }
            let coverId = (row["coverArt"] as? String) ?? id
            let artURL = try? buildURL(
                serverURL: account.serverURL,
                endpoint: "getCoverArt.view",
                username: account.username,
                password: account.password,
                extra: ["id": coverId, "size": "600"]
            ).absoluteString
            return PlaylistSummary(
                id: id,
                name: (row["name"] as? String) ?? "Playlist",
                songCount: (row["songCount"] as? Int) ?? 0,
                durationSec: (row["duration"] as? Int) ?? 0,
                artworkURL: artURL
            )
        }
    }

    public func fetchPlaylistTracks(account: UserAccount, playlistId: String) async throws -> [Track] {
        let sub = try await call(account: account, endpoint: "getPlaylist.view", extra: ["id": playlistId])
        let songs = (sub["playlist"] as? [String: Any])?["entry"] as? [[String: Any]] ?? []
        return songs.compactMap { parseSong($0, account: account) }
    }

    public func fetchAlbums(account: UserAccount, type: String = "newest", size: Int = 30) async throws -> [AlbumCard] {
        let sub = try await call(
            account: account,
            endpoint: "getAlbumList2.view",
            extra: ["type": type, "size": "\(size)"]
        )
        let albums = (sub["albumList2"] as? [String: Any])?["album"] as? [[String: Any]] ?? []
        return albums.compactMap { row in
            guard let id = row["id"] as? String ?? (row["id"] as? Int).map(String.init) else {
                return nil
            }
            let coverId = (row["coverArt"] as? String) ?? id
            let artURL = try? buildURL(
                serverURL: account.serverURL,
                endpoint: "getCoverArt.view",
                username: account.username,
                password: account.password,
                extra: ["id": coverId, "size": "600"]
            ).absoluteString
            return AlbumCard(
                id: id,
                title: (row["name"] as? String) ?? (row["title"] as? String) ?? "Album",
                artist: (row["artist"] as? String) ?? "Unknown Artist",
                year: row["year"] as? Int,
                songCount: (row["songCount"] as? Int) ?? 0,
                artworkURL: artURL
            )
        }
    }

    public func fetchAlbumTracks(account: UserAccount, albumId: String) async throws -> [Track] {
        let sub = try await call(account: account, endpoint: "getAlbum.view", extra: ["id": albumId])
        let songs = (sub["album"] as? [String: Any])?["song"] as? [[String: Any]] ?? []
        return songs.compactMap { parseSong($0, account: account) }
    }

    public func fetchArtists(account: UserAccount) async throws -> [ArtistCard] {
        let sub = try await call(account: account, endpoint: "getArtists.view")
        let indexes = (sub["artists"] as? [String: Any])?["index"] as? [[String: Any]] ?? []
        var cards: [ArtistCard] = []
        for idx in indexes {
            let artists = idx["artist"] as? [[String: Any]] ?? []
            for row in artists {
                guard let id = row["id"] as? String ?? (row["id"] as? Int).map(String.init) else {
                    continue
                }
                let coverId = row["coverArt"] as? String
                let artURL = coverId.flatMap {
                    try? buildURL(
                        serverURL: account.serverURL,
                        endpoint: "getCoverArt.view",
                        username: account.username,
                        password: account.password,
                        extra: ["id": $0, "size": "400"]
                    ).absoluteString
                }
                let albumCount = (row["albumCount"] as? Int) ?? 0
                cards.append(
                    ArtistCard(
                        id: id,
                        name: (row["name"] as? String) ?? "Artist",
                        reason: "\(albumCount) album\(albumCount == 1 ? "" : "s") in library",
                        artworkURL: artURL,
                        inLibrary: true
                    )
                )
            }
        }
        return cards
    }

    public func fetchStarredTracks(account: UserAccount) async throws -> [Track] {
        let sub = try await call(account: account, endpoint: "getStarred2.view")
        let songs = (sub["starred2"] as? [String: Any])?["song"] as? [[String: Any]] ?? []
        return songs.compactMap { parseSong($0, account: account) }
    }

    public func fetchStandaloneHome(account: UserAccount) async throws -> HomeFeed {
        async let recent = fetchAlbums(account: account, type: "recent", size: 9)
        async let newest = fetchAlbums(account: account, type: "newest", size: 10)
        async let starred = fetchStarredTracks(account: account)

        let (recentList, newestList, starredList) = try await (recent, newest, starred)
        let dial = recentList.prefix(9).map {
            SpeedDialItem(
                id: "album:\($0.id)",
                kind: "album",
                title: $0.title,
                subtitle: $0.artist,
                artworkURL: $0.artworkURL,
                targetId: $0.id
            )
        }
        let mixes = [
            MixCard(
                id: "replay-mix",
                title: "Liked Rotation",
                subtitle: "Your starred library favorites",
                accentHex: "#FF3B5C",
                trackCount: starredList.count,
                artworkURLs: Array(starredList.compactMap(\.artworkURL).prefix(4)),
                badge: "LIBRARY"
            ),
        ]
        return HomeFeed(
            mood: "All",
            moods: ["All"],
            speedDial: Array(dial),
            quickPicks: Array(starredList.prefix(16)),
            madeForYou: mixes,
            listenAgain: recentList,
            recommendedArtists: [],
            newInLibrary: newestList
        )
    }

    public func scrobble(account: UserAccount, songId: String, submission: Bool) async {
        _ = try? await call(
            account: account,
            endpoint: "scrobble.view",
            extra: ["id": songId, "submission": submission ? "true" : "false"]
        )
    }

    public func parseSong(_ row: [String: Any], account: UserAccount) -> Track? {
        guard let id = row["id"] as? String ?? (row["id"] as? Int).map(String.init) else {
            return nil
        }
        let coverId = (row["coverArt"] as? String) ?? id
        let artURL = try? buildURL(
            serverURL: account.serverURL,
            endpoint: "getCoverArt.view",
            username: account.username,
            password: account.password,
            extra: ["id": coverId, "size": "600"]
        ).absoluteString

        return Track(
            id: id,
            title: (row["title"] as? String) ?? "Untitled",
            artist: (row["artist"] as? String) ?? "Unknown Artist",
            album: (row["album"] as? String) ?? "",
            durationSec: (row["duration"] as? Int) ?? 0,
            artworkURL: artURL,
            source: .library,
            inLibrary: true,
            isPreview: false,
            isStarred: row["starred"] != nil,
            reason: nil,
            navidromeId: id,
            year: row["year"] as? Int,
            genre: row["genre"] as? String
        )
    }
}
