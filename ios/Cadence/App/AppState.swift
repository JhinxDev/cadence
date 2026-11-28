import Foundation
import Observation
import SwiftUI
import CadenceCore

@MainActor
@Observable
public final class AppState {
    public let apiClient = CadenceAPIClient()
    public let subsonicClient = OpenSubsonicClient()
    public let keychain = KeychainStore()
    public let cacheManager: OfflineCacheManager
    public let player: AudioPlaybackController

    public var account: UserAccount?
    public var capabilities: ServerCapabilities = .standaloneSubsonic
    public var isCheckingAuth: Bool = false
    public var authError: String?

    public var homeFeed: HomeFeed?
    public var selectedMood: String = "All"
    public var isLoadingHome: Bool = false
    public var homeError: String?

    public var playlists: [PlaylistSummary] = []
    public var albums: [AlbumCard] = []
    public var artists: [ArtistCard] = []
    public var starredTracks: [Track] = []
    public var downloadedRecords: [CachedTrackRecord] = []
    public var isLoadingLibrary: Bool = false
    public var libraryError: String?

    public var savingTrackIds: Set<String> = []
    public var activeToast: String?
    public var isNowPlayingPresented: Bool = false
    public var autoSaveOnLike: Bool = true
    public var preferredRadioMode: RadioMode = .balanced

    public init() {
        let cache = OfflineCacheManager()
        self.cacheManager = cache
        self.player = AudioPlaybackController(cacheManager: cache, apiClient: apiClient, subsonicClient: subsonicClient)
        wirePlayerCallbacks()

        if ProcessInfo.processInfo.arguments.contains("--demo-mode") {
            loadDemoSession()
        } else if let saved = keychain.loadAccount() {
            self.account = saved
            self.player.setAccount(saved)
            Task { await refreshSessionAndHome() }
        }
    }

    private func wirePlayerCallbacks() {
        player.onRequestMoreRadio = { [weak self] in
            await self?.appendMoreRadio()
        }
        player.onScrobble = { [weak self] track, isSubmission in
            guard let self, let account = self.account, !account.isDemo, let navId = track.navidromeId else { return }
            await self.subsonicClient.scrobble(account: account, songId: navId, submission: isSubmission)
        }
    }

    public func loadDemoSession() {
        account = DemoCatalog.demoAccount
        capabilities = ServerCapabilities(
            service: "cadence",
            version: "0.1.1",
            discoveryEnabled: true,
            fullDiscoveryStreaming: true,
            saveToLibraryEnabled: true,
            lyricsEnabled: true,
            subsonicProxyEnabled: true
        )
        player.setAccount(DemoCatalog.demoAccount)
        homeFeed = DemoCatalog.homeFeed
        playlists = DemoCatalog.playlists
        albums = DemoCatalog.albums
        artists = DemoCatalog.artists
        starredTracks = DemoCatalog.libraryTracks.filter(\.isStarred)
        player.play(
            tracks: DemoCatalog.libraryTracks + DemoCatalog.discoveryTracks,
            startAt: 0,
            radioSessionId: "demo-radio",
            radioMode: .balanced
        )
    }

    public func signIn(serverURL: String, username: String, password: String) async {
        isCheckingAuth = true
        authError = nil
        let normalized = CadenceAPIClient.normalizedBaseURL(serverURL)
        defer { isCheckingAuth = false }

        if let caps = await apiClient.probeCapabilities(serverURL: normalized) {
            do {
                let res = try await apiClient.login(serverURL: normalized, username: username, password: password)
                let acct = UserAccount(
                    serverURL: normalized,
                    username: res.username,
                    password: password,
                    bearerToken: res.token,
                    isDemo: false
                )
                self.capabilities = res.capabilities
                self.account = acct
                self.keychain.saveAccount(acct)
                self.player.setAccount(acct)
                await loadAllData()
                return
            } catch {
                self.authError = error.localizedDescription
                return
            }
        }

        // Fallback: Standard OpenSubsonic / Navidrome server
        let acct = UserAccount(serverURL: normalized, username: username, password: password, bearerToken: nil)
        do {
            _ = try await subsonicClient.ping(account: acct)
            self.capabilities = .standaloneSubsonic
            self.account = acct
            self.keychain.saveAccount(acct)
            self.player.setAccount(acct)
            await loadAllData()
        } catch {
            self.authError = error.localizedDescription
        }
    }

    public func signOut() {
        player.pause()
        keychain.clearAccount()
        account = nil
        homeFeed = nil
        playlists = []
        albums = []
        artists = []
        starredTracks = []
    }

    public func refreshSessionAndHome() async {
        guard let account else { return }
        if account.isDemo {
            loadDemoSession()
            return
        }
        if let caps = await apiClient.probeCapabilities(serverURL: account.serverURL) {
            capabilities = caps
            if account.bearerToken == nil,
               let login = try? await apiClient.login(
                   serverURL: account.serverURL,
                   username: account.username,
                   password: account.password
               ) {
                var updated = account
                updated.bearerToken = login.token
                self.account = updated
                keychain.saveAccount(updated)
                player.setAccount(updated)
            }
        } else {
            capabilities = .standaloneSubsonic
        }
        await loadAllData()
    }

    public func loadAllData() async {
        await loadHome(mood: selectedMood)
        await loadLibrary()
    }

    public func loadHome(mood: String) async {
        guard let account else { return }
        selectedMood = mood
        if account.isDemo {
            homeFeed = DemoCatalog.homeFeed
            return
        }
        isLoadingHome = true
        homeError = nil
        defer { isLoadingHome = false }

        do {
            if capabilities.discoveryEnabled, account.bearerToken != nil {
                homeFeed = try await apiClient.fetchHome(account: account, mood: mood)
            } else {
                homeFeed = try await subsonicClient.fetchStandaloneHome(account: account)
            }
        } catch {
            homeError = error.localizedDescription
        }
    }

    public func loadLibrary() async {
        guard let account else { return }
        downloadedRecords = await cacheManager.allDownloaded()
        if account.isDemo { return }
        isLoadingLibrary = true
        libraryError = nil
        defer { isLoadingLibrary = false }

        var firstError: Error?
        var succeededCount = 0

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                do {
                    self.playlists = try await self.subsonicClient.fetchPlaylists(account: account)
                    succeededCount += 1
                } catch {
                    firstError = firstError ?? error
                }
            }
            group.addTask { @MainActor in
                do {
                    self.albums = try await self.subsonicClient.fetchAlbums(account: account, type: "alphabeticalByName", size: 60)
                    succeededCount += 1
                } catch {
                    firstError = firstError ?? error
                }
            }
            group.addTask { @MainActor in
                do {
                    self.artists = try await self.subsonicClient.fetchArtists(account: account)
                    succeededCount += 1
                } catch {
                    firstError = firstError ?? error
                }
            }
            group.addTask { @MainActor in
                do {
                    self.starredTracks = try await self.subsonicClient.fetchStarredTracks(account: account)
                    succeededCount += 1
                } catch {
                    firstError = firstError ?? error
                }
            }
        }

        if succeededCount == 0, let firstError {
            libraryError = firstError.localizedDescription
        }
    }

    public func playTrackAndStartRadio(_ track: Track, mode: RadioMode? = nil) async {
        let activeMode = mode ?? preferredRadioMode
        guard let account else { return }
        if account.isDemo || !capabilities.discoveryEnabled || account.bearerToken == nil {
            let pool = [track] + DemoCatalog.discoveryTracks + DemoCatalog.libraryTracks.filter { $0.id != track.id }
            player.play(tracks: pool, startAt: 0, radioSessionId: "local-radio", radioMode: activeMode)
            return
        }
        player.play(tracks: [track], startAt: 0, radioSessionId: nil, radioMode: activeMode)
        if let batch = try? await apiClient.startRadio(account: account, seedTrack: track, mode: activeMode) {
            if player.queue.currentTrack?.id == track.id {
                player.queue.attachRadio(sessionId: batch.sessionId, mode: batch.mode, upcomingTracks: batch.tracks)
                player.prefetchUpcoming(limit: 3)
            } else {
                player.play(
                    tracks: [track] + batch.tracks,
                    startAt: 0,
                    radioSessionId: batch.sessionId,
                    radioMode: batch.mode
                )
            }
        }
    }

    public func startMoodRadio(mood: String, mode: RadioMode? = nil) async {
        let activeMode = mode ?? preferredRadioMode
        guard let account else { return }
        if account.isDemo || !capabilities.discoveryEnabled || account.bearerToken == nil {
            player.play(
                tracks: DemoCatalog.discoveryTracks + DemoCatalog.libraryTracks,
                startAt: 0,
                radioSessionId: "demo-mood",
                radioMode: activeMode
            )
            return
        }
        let targetMood = mood == "Discover" ? nil : mood
        if let batch = try? await apiClient.startRadio(account: account, seedTrack: nil, seedArtist: nil, mood: targetMood, mode: activeMode),
           !batch.tracks.isEmpty {
            player.play(tracks: batch.tracks, startAt: 0, radioSessionId: batch.sessionId, radioMode: batch.mode)
            return
        }
        if let first = homeFeed?.quickPicks.first {
            await playTrackAndStartRadio(first, mode: activeMode)
        }
    }

    public func startArtistRadio(_ artistName: String, mode: RadioMode? = nil) async {
        let activeMode = mode ?? preferredRadioMode
        guard let account else { return }
        if account.isDemo || !capabilities.discoveryEnabled || account.bearerToken == nil {
            player.play(tracks: DemoCatalog.discoveryTracks + DemoCatalog.libraryTracks, startAt: 0, radioSessionId: "demo-artist", radioMode: activeMode)
            return
        }
        if let batch = try? await apiClient.startRadio(account: account, seedTrack: nil, seedArtist: artistName, mode: activeMode) {
            player.play(tracks: batch.tracks, startAt: 0, radioSessionId: batch.sessionId, radioMode: batch.mode)
        }
    }

    public func switchRadioMode(_ mode: RadioMode) async {
        preferredRadioMode = mode
        guard let account else { return }
        if account.isDemo {
            player.queue.replaceUpcoming(with: DemoCatalog.discoveryTracks.shuffled(), mode: mode)
            return
        }
        guard let sessionId = player.queue.radioSessionId,
              let batch = try? await apiClient.nextRadio(account: account, sessionId: sessionId, mode: mode) else {
            if let cur = player.queue.currentTrack {
                await playTrackAndStartRadio(cur, mode: mode)
            }
            return
        }
        player.queue.replaceUpcoming(with: batch.tracks, mode: mode)
        player.prefetchUpcoming(limit: 3)
    }

    public func appendMoreRadio() async {
        guard let account, let sessionId = player.queue.radioSessionId else { return }
        if account.isDemo { return }
        if let batch = try? await apiClient.nextRadio(account: account, sessionId: sessionId, mode: player.queue.radioMode) {
            player.queue.appendRadioTracks(batch.tracks)
            player.prefetchUpcoming(limit: 3)
        }
    }

    public func saveToLibrary(_ track: Track, star: Bool = false) async {
        guard let account, !savingTrackIds.contains(track.id) else { return }
        savingTrackIds.insert(track.id)
        defer { savingTrackIds.remove(track.id) }

        if account.isDemo {
            player.queue.markTrackSaved(extId: track.id, navidromeId: "demo-saved-\(track.id)")
            showToast("Saved \(track.title) to Navidrome")
            return
        }

        do {
            let res = try await apiClient.saveTrack(account: account, trackId: track.id, star: star)
            if let navId = res.navidromeId {
                player.queue.markTrackSaved(extId: track.id, navidromeId: navId)
            }
            showToast("Saved \(track.title) to Navidrome")
            await loadLibrary()
        } catch {
            showToast(error.localizedDescription)
        }
    }

    public func toggleStar(_ track: Track) async {
        guard let account else { return }
        let newStar = !track.isStarred
        player.queue.setStarred(trackId: track.id, starred: newStar)

        if account.isDemo {
            if newStar && !track.inLibrary && autoSaveOnLike {
                player.queue.markTrackSaved(extId: track.id, navidromeId: "demo-saved-\(track.id)")
                showToast("Liked & saved to library")
            }
            return
        }

        if capabilities.discoveryEnabled, account.bearerToken != nil {
            if let res = try? await apiClient.starTrack(
                account: account,
                trackId: track.id,
                starred: newStar,
                autoSave: autoSaveOnLike
            ), let navId = res.savedNavidromeId {
                player.queue.markTrackSaved(extId: track.id, navidromeId: navId)
                showToast("Saved & liked in Navidrome")
            }
        }
    }

    public func downloadOffline(_ tracks: [Track]) async {
        guard let account else { return }
        for track in tracks where !account.isDemo {
            guard let url = apiClient.streamURL(account: account, track: track, subsonic: subsonicClient) else {
                continue
            }
            _ = try? await cacheManager.download(track: track, from: url)
        }
        downloadedRecords = await cacheManager.allDownloaded()
        showToast("Downloaded \(tracks.count) track\(tracks.count == 1 ? "" : "s") for offline playback")
    }

    public func artworkURL(for raw: String?) -> URL? {
        guard let account else { return nil }
        return apiClient.resolveURL(account: account, rawPathOrURL: raw)
    }

    public func showToast(_ message: String) {
        activeToast = message
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            if activeToast == message {
                activeToast = nil
            }
        }
    }
}
