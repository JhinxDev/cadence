import Foundation
import Observation

#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(MediaPlayer)
import MediaPlayer
#endif
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
public final class AudioPlaybackController {
    public var queue = QueueEngine()
    public private(set) var isPlaying: Bool = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var isBuffering: Bool = false

    public var onRequestMoreRadio: (@MainActor () async -> Void)?
    public var onScrobble: (@MainActor (Track, Bool) async -> Void)?
    public var onToggleLike: (@MainActor (Track) async -> Void)?

    #if canImport(AVFoundation)
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var scrobbleSubmittedForId: String?
    #endif

    private let cacheManager: OfflineCacheManager
    private let apiClient: CadenceAPIClient
    private let subsonicClient: OpenSubsonicClient
    private var activeAccount: UserAccount?

    public init(
        cacheManager: OfflineCacheManager,
        apiClient: CadenceAPIClient = CadenceAPIClient(),
        subsonicClient: OpenSubsonicClient = OpenSubsonicClient()
    ) {
        self.cacheManager = cacheManager
        self.apiClient = apiClient
        self.subsonicClient = subsonicClient
        #if os(iOS)
        configureAudioSession()
        configureRemoteCommands()
        #endif
    }

    public func setAccount(_ account: UserAccount?) {
        self.activeAccount = account
    }

    public func play(
        tracks: [Track],
        startAt index: Int = 0,
        radioSessionId: String? = nil,
        radioMode: RadioMode = .balanced
    ) {
        queue.load(
            tracks: tracks,
            startAt: index,
            radioSessionId: radioSessionId,
            radioMode: radioMode
        )
        startCurrentTrack()
    }

    public func togglePlayPause() {
        #if canImport(AVFoundation)
        guard let player else {
            if queue.currentTrack != nil {
                startCurrentTrack()
            }
            return
        }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(true)
            #endif
            player.play()
            isPlaying = true
        }
        updateNowPlayingInfo()
        #endif
    }

    public func next() {
        guard queue.advance() != nil else {
            pause()
            return
        }
        startCurrentTrack()
        if queue.shouldFetchMoreRadio() {
            Task { await onRequestMoreRadio?() }
        }
    }

    public func previous() {
        if currentTime > 4 {
            seek(to: 0)
            return
        }
        guard queue.previous() != nil else { return }
        startCurrentTrack()
    }

    public func jump(to index: Int) {
        guard queue.jump(to: index) != nil else { return }
        startCurrentTrack()
        if queue.shouldFetchMoreRadio() {
            Task { await onRequestMoreRadio?() }
        }
    }

    public func seek(to seconds: TimeInterval) {
        #if canImport(AVFoundation)
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player?.seek(to: target)
        currentTime = seconds
        updateNowPlayingInfo()
        #endif
    }

    public func pause() {
        #if canImport(AVFoundation)
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
        #endif
    }

    private func startCurrentTrack() {
        guard let track = queue.currentTrack else { return }
        currentTime = 0
        duration = TimeInterval(max(track.durationSec, 1))
        scrobbleSubmittedForId = nil

        if activeAccount?.isDemo == true {
            isPlaying = true
            isBuffering = false
            return
        }

        isBuffering = true
        Task {
            let localURL = await cacheManager.localFileURL(for: track.id)
            let streamURL: URL?
            if let localURL {
                streamURL = localURL
            } else if let account = activeAccount {
                streamURL = apiClient.streamURL(account: account, track: track, subsonic: subsonicClient)
            } else if let preview = track.previewURL {
                streamURL = URL(string: preview)
            } else {
                streamURL = nil
            }

            guard let streamURL else {
                isBuffering = false
                isPlaying = false
                return
            }

            await loadAndPlay(url: streamURL, track: track)
        }
    }

    private func loadAndPlay(url: URL, track: Track) async {
        #if canImport(AVFoundation)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        cleanupObservers()
        let item = AVPlayerItem(url: url)
        if player == nil {
            player = AVPlayer(playerItem: item)
            player?.automaticallyWaitsToMinimizeStalling = true
        } else {
            player?.replaceCurrentItem(with: item)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.next()
            }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let sec = time.seconds
                if sec.isFinite {
                    self.currentTime = sec
                }
                if let itemDur = self.player?.currentItem?.duration.seconds, itemDur.isFinite, itemDur > 0 {
                    self.duration = itemDur
                }
                self.isBuffering = self.player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.updateNowPlayingElapsedOnly()
                if let cur = self.queue.currentTrack,
                   self.scrobbleSubmittedForId != cur.id,
                   sec >= min(30, max(10, self.duration * 0.45)) {
                    self.scrobbleSubmittedForId = cur.id
                    await self.onScrobble?(cur, true)
                }
            }
        }

        player?.play()
        isPlaying = true
        isBuffering = false
        updateNowPlayingInfo()
        await onScrobble?(track, false)
        #endif
    }

    private func cleanupObservers() {
        #if canImport(AVFoundation)
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        #endif
    }

    #if os(iOS)
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            guard
                let info = notification.userInfo,
                let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: rawType)
            else { return }
            let optionsRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == .began {
                    self.player?.pause()
                    self.isPlaying = false
                } else if type == .ended, options.contains(.shouldResume) {
                    try? AVAudioSession.sharedInstance().setActive(true)
                    self.player?.play()
                    self.isPlaying = true
                    self.updateNowPlayingInfo()
                }
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            guard
                let info = notification.userInfo,
                let rawReason = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
                let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
            else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if reason == .oldDeviceUnavailable {
                    self.player?.pause()
                    self.isPlaying = false
                    self.updateNowPlayingInfo()
                } else if reason == .newDeviceAvailable, self.isPlaying {
                    try? AVAudioSession.sharedInstance().setActive(true)
                    self.player?.play()
                    self.updateNowPlayingInfo()
                }
            }
        }
    }

    private func configureRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.isEnabled = true
        cc.pauseCommand.isEnabled = true
        cc.togglePlayPauseCommand.isEnabled = true
        cc.nextTrackCommand.isEnabled = true
        cc.previousTrackCommand.isEnabled = true
        cc.changePlaybackPositionCommand.isEnabled = true

        cc.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.isPlaying { self.togglePlayPause() }
            }
            return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isPlaying { self.togglePlayPause() }
            }
            return .success
        }
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.togglePlayPause()
            }
            return .success
        }
        cc.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.next()
            }
            return .success
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.previous()
            }
            return .success
        }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let pos = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            Task { @MainActor [weak self] in
                self?.seek(to: pos)
            }
            return .success
        }
    }
    #endif

    private func updateNowPlayingElapsedOnly() {
        #if os(iOS)
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        #endif
    }

    private func updateNowPlayingInfo() {
        #if os(iOS)
        guard let track = queue.currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if let account = activeAccount,
           let artURL = apiClient.resolveURL(account: account, rawPathOrURL: track.artworkURL) {
            let trackId = track.id
            Task { @MainActor [weak self] in
                guard let self,
                      let (data, _) = try? await URLSession.shared.data(from: artURL),
                      let image = UIImage(data: data),
                      self.queue.currentTrack?.id == trackId else { return }
                var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
            }
        }
        #endif
    }
}
