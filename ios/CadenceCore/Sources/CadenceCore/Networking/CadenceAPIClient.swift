import Foundation

public enum CadenceAPIError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .unauthorized: return "Session expired or invalid credentials"
        case .serverError(let msg): return msg
        }
    }
}

public struct LoginResult: Codable, Sendable {
    public let token: String
    public let username: String
    public let expiresAt: Int
    public let capabilities: ServerCapabilities

    enum CodingKeys: String, CodingKey {
        case token, username, capabilities
        case expiresAt = "expires_at"
    }
}

public struct SaveTrackResult: Codable, Sendable {
    public let status: String
    public let trackId: String
    public let navidromeId: String?

    enum CodingKeys: String, CodingKey {
        case status
        case trackId = "track_id"
        case navidromeId = "navidrome_id"
    }
}

public struct StarTrackResult: Codable, Sendable {
    public let trackId: String
    public let starred: Bool
    public let savedNavidromeId: String?

    enum CodingKeys: String, CodingKey {
        case starred
        case trackId = "track_id"
        case savedNavidromeId = "saved_navidrome_id"
    }
}

public final class CadenceAPIClient: Sendable {
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    public static func normalizedBaseURL(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if !trimmed.lowercased().hasPrefix("http://") && !trimmed.lowercased().hasPrefix("https://") {
            trimmed = "https://\(trimmed)"
        }
        return trimmed
    }

    public func probeCapabilities(serverURL: String) async -> ServerCapabilities? {
        let base = Self.normalizedBaseURL(serverURL)
        guard let url = URL(string: "\(base)/api/v1/capabilities") else { return nil }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let caps = try decoder.decode(ServerCapabilities.self, from: data)
            return caps.service == "cadence" ? caps : nil
        } catch {
            return nil
        }
    }

    public func login(serverURL: String, username: String, password: String) async throws -> LoginResult {
        let base = Self.normalizedBaseURL(serverURL)
        guard let url = URL(string: "\(base)/api/v1/auth/login") else { throw CadenceAPIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw CadenceAPIError.serverError("No HTTP response") }
        if http.statusCode == 401 { throw CadenceAPIError.unauthorized }
        guard http.statusCode == 200 else {
            throw CadenceAPIError.serverError("Login failed (\(http.statusCode))")
        }
        return try decoder.decode(LoginResult.self, from: data)
    }

    public func fetchHome(account: UserAccount, mood: String = "All") async throws -> HomeFeed {
        let encodedMood = mood.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "All"
        return try await get(account: account, path: "/api/v1/home?mood=\(encodedMood)")
    }

    public func fetchMix(account: UserAccount, mixId: String, mood: String = "All") async throws -> MixDetail {
        let encodedMood = mood.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "All"
        return try await get(account: account, path: "/api/v1/mixes/\(mixId)?mood=\(encodedMood)")
    }

    public func startRadio(
        account: UserAccount,
        seedTrack: Track?,
        seedArtist: String? = nil,
        mood: String? = nil,
        mode: RadioMode = .balanced
    ) async throws -> RadioBatch {
        struct Payload: Encodable {
            let seed_track: Track?
            let seed_artist: String?
            let mood: String?
            let mode: RadioMode
            let count: Int
        }
        return try await post(
            account: account,
            path: "/api/v1/radio/start",
            body: Payload(seed_track: seedTrack, seed_artist: seedArtist, mood: mood, mode: mode, count: 20)
        )
    }

    public func nextRadio(
        account: UserAccount,
        sessionId: String,
        mode: RadioMode? = nil
    ) async throws -> RadioBatch {
        struct Payload: Encodable {
            let session_id: String
            let mode: RadioMode?
            let count: Int
        }
        return try await post(
            account: account,
            path: "/api/v1/radio/next",
            body: Payload(session_id: sessionId, mode: mode, count: 15)
        )
    }

    public func search(account: UserAccount, query: String) async throws -> SearchResults {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await get(account: account, path: "/api/v1/search?q=\(q)")
    }

    public func fetchLyrics(account: UserAccount, track: Track) async throws -> LyricsResult {
        let artist = track.artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? track.artist
        let title = track.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? track.title
        return try await get(
            account: account,
            path: "/api/v1/lyrics?artist=\(artist)&title=\(title)&duration_sec=\(track.durationSec)"
        )
    }

    public func saveTrack(account: UserAccount, trackId: String, star: Bool = false) async throws -> SaveTrackResult {
        struct Payload: Encodable {
            let track_id: String
            let star: Bool
        }
        return try await post(
            account: account,
            path: "/api/v1/library/save",
            body: Payload(track_id: trackId, star: star)
        )
    }

    public func starTrack(
        account: UserAccount,
        trackId: String,
        starred: Bool,
        autoSave: Bool
    ) async throws -> StarTrackResult {
        struct Payload: Encodable {
            let track_id: String
            let starred: Bool
            let auto_save: Bool
        }
        return try await post(
            account: account,
            path: "/api/v1/library/star",
            body: Payload(track_id: trackId, starred: starred, auto_save: autoSave)
        )
    }

    public func resolveURL(account: UserAccount, rawPathOrURL: String?) -> URL? {
        guard let rawPathOrURL, !rawPathOrURL.isEmpty else { return nil }
        if rawPathOrURL.hasPrefix("http://") || rawPathOrURL.hasPrefix("https://") {
            return URL(string: rawPathOrURL)
        }
        let base = Self.normalizedBaseURL(account.serverURL)
        var components = URLComponents(string: "\(base)\(rawPathOrURL)")
        if let token = account.bearerToken, rawPathOrURL.hasPrefix("/api/v1/") {
            var items = components?.queryItems ?? []
            items.append(URLQueryItem(name: "token", value: token))
            components?.queryItems = items
        }
        return components?.url
    }

    public func streamURL(account: UserAccount, track: Track, subsonic: OpenSubsonicClient) -> URL? {
        if let token = account.bearerToken {
            let base = Self.normalizedBaseURL(account.serverURL)
            let encodedId = track.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? track.id
            var components = URLComponents(string: "\(base)/api/v1/stream/\(encodedId)")
            components?.queryItems = [URLQueryItem(name: "token", value: token)]
            return components?.url
        }
        if let navId = track.navidromeId ?? (track.source == .library ? track.id : nil) {
            return try? subsonic.buildURL(
                serverURL: account.serverURL,
                endpoint: "stream.view",
                username: account.username,
                password: account.password,
                extra: ["id": navId]
            )
        }
        if let preview = track.previewURL {
            return URL(string: preview)
        }
        return nil
    }

    private func get<T: Decodable>(account: UserAccount, path: String) async throws -> T {
        let base = Self.normalizedBaseURL(account.serverURL)
        guard let url = URL(string: "\(base)\(path)") else { throw CadenceAPIError.invalidURL }
        var req = URLRequest(url: url)
        if let token = account.bearerToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw CadenceAPIError.serverError("No response") }
        if http.statusCode == 401 { throw CadenceAPIError.unauthorized }
        guard http.statusCode < 400 else {
            throw CadenceAPIError.serverError("HTTP \(http.statusCode)")
        }
        return try decoder.decode(T.self, from: data)
    }

    private func post<B: Encodable, T: Decodable>(account: UserAccount, path: String, body: B) async throws -> T {
        let base = Self.normalizedBaseURL(account.serverURL)
        guard let url = URL(string: "\(base)\(path)") else { throw CadenceAPIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = account.bearerToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw CadenceAPIError.serverError("No response") }
        if http.statusCode == 401 { throw CadenceAPIError.unauthorized }
        guard http.statusCode < 400 else {
            throw CadenceAPIError.serverError("HTTP \(http.statusCode)")
        }
        return try decoder.decode(T.self, from: data)
    }
}
