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
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var mediaResetObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var scrobbleSubmittedForId: String?
    private var lastNowPlayingSync: Date = .distantPast
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
        UIApplication.shared.beginReceivingRemoteControlEvents()
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

    public func resume() {
        #if canImport(AVFoundation)
        guard let player else {
            if queue.currentTrack != nil {
                startCurrentTrack()
            }
            return
        }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
        #endif
    }

    public func togglePlayPause() {
        #if canImport(AVFoundation)
        guard let player else {
            if queue.currentTrack != nil {
                startCurrentTrack()
            }
            return
        }
        let activelyPlaying = player.timeControlStatus != .paused
        if activelyPlaying {
            pause()
        } else {
            resume()
        }
        #endif
    }

    public func next() {
        guard queue.advance() != nil else {
            pause()
            return
        }
        startCurrentTrack()
        if queue.shouldFetchMoreRadio() {
            prefetchRadioInBackground()
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
            prefetchRadioInBackground()
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

    private func runWithBackgroundTask(name: String, _ operation: @escaping @MainActor () async -> Void) {
        #if os(iOS)
        final class TokenBox: @unchecked Sendable {
            var id: UIBackgroundTaskIdentifier = .invalid
        }
        let box = TokenBox()
        box.id = UIApplication.shared.beginBackgroundTask(withName: name) {
            DispatchQueue.main.async {
                if box.id != .invalid {
                    UIApplication.shared.endBackgroundTask(box.id)
                    box.id = .invalid
                }
            }
        }
        Task { @MainActor in
            defer {
                if box.id != .invalid {
                    UIApplication.shared.endBackgroundTask(box.id)
                    box.id = .invalid
                }
            }
            await operation()
        }
        #else
        Task { await operation() }
        #endif
    }

    private func prefetchRadioInBackground() {
        runWithBackgroundTask(name: "CadenceRadioPrefetch") { [weak self] in
            await self?.onRequestMoreRadio?()
        }
    }

    public func prefetchUpcoming(limit: Int = 3) {
        guard let account = activeAccount else { return }
        let ids = Array(
            queue.upNextTracks
                .filter { !$0.inLibrary && $0.id.hasPrefix("ext:") }
                .prefix(limit)
                .map(\.id)
        )
        guard !ids.isEmpty else { return }
        Task {
            await apiClient.prefetchStreams(account: account, trackIds: ids)
        }
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
        prefetchUpcoming(limit: 3)
        runWithBackgroundTask(name: "CadenceTrackTransition") { [weak self] in
            guard let self else { return }
            let localURL = await self.cacheManager.localFileURL(for: track.id)
            let streamURL: URL?
            if let localURL {
                streamURL = localURL
            } else if let account = self.activeAccount {
                streamURL = self.apiClient.streamURL(account: account, track: track, subsonic: self.subsonicClient)
            } else if let preview = track.previewURL {
                streamURL = URL(string: preview)
            } else {
                streamURL = nil
            }

            guard let streamURL else {
                self.isBuffering = false
                self.isPlaying = false
                return
            }

            await self.loadAndPlay(url: streamURL, track: track)
        }
    }

    private func loadAndPlay(url: URL, track: Track) async {
        #if canImport(AVFoundation)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        cleanupItemObservers()
        let item = AVPlayerItem(url: url)
        if player == nil {
            let created = AVPlayer(playerItem: item)
            created.automaticallyWaitsToMinimizeStalling = true
            created.allowsExternalPlayback = true
            #if os(iOS)
            created.usesExternalPlaybackWhileExternalScreenIsActive = false
            #endif
            player = created
            attachPlayerStatusObserver(created)
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

        failedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isBuffering = false
                if self.queue.currentIndex + 1 < self.queue.tracks.count {
                    self.next()
                } else {
                    self.isPlaying = false
                    self.updateNowPlayingInfo()
                }
            }
        }

        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                #if os(iOS)
                try? AVAudioSession.sharedInstance().setActive(true)
                #endif
                self.isBuffering = true
                if self.isPlaying {
                    self.player?.play()
                }
                self.updateNowPlayingInfo()
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
                if Date().timeIntervalSince(self.lastNowPlayingSync) >= 5.0 {
                    self.updateNowPlayingElapsedOnly()
                }
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

    private func attachPlayerStatusObserver(_ avPlayer: AVPlayer) {
        statusObserver?.invalidate()
        statusObserver = avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.isPlaying = true
                    self.isBuffering = false
                case .paused:
                    self.isPlaying = false
                    self.isBuffering = false
                case .waitingToPlayAtSpecifiedRate:
                    self.isBuffering = true
                @unknown default:
                    break
                }
                self.updateNowPlayingElapsedOnly()
            }
        }
    }

    private func cleanupItemObservers() {
        #if canImport(AVFoundation)
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failedObserver {
            NotificationCenter.default.removeObserver(failedObserver)
            self.failedObserver = nil
        }
        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
            self.stalledObserver = nil
        }
        #endif
    }

    #if os(iOS)
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)

        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
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
                    self.updateNowPlayingInfo()
                } else if type == .ended, options.contains(.shouldResume) {
                    self.resume()
                }
            }
        }

        if let routeChangeObserver { NotificationCenter.default.removeObserver(routeChangeObserver) }
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
                    self.pause()
                } else if reason == .newDeviceAvailable, self.isPlaying {
                    self.resume()
                }
            }
        }

        if let mediaResetObserver { NotificationCenter.default.removeObserver(mediaResetObserver) }
        mediaResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasPlaying = self.isPlaying
                self.configureAudioSession()
                self.configureRemoteCommands()
                UIApplication.shared.beginReceivingRemoteControlEvents()
                if wasPlaying {
                    self.resume()
                } else {
                    self.updateNowPlayingInfo()
                }
            }
        }

        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let player = self.player {
                    self.isPlaying = player.timeControlStatus == .playing
                    self.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                    let sec = player.currentTime().seconds
                    if sec.isFinite {
                        self.currentTime = sec
                    }
                }
                self.updateNowPlayingInfo()
            }
        }
    }

    private func configureRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        for cmd in [
            cc.playCommand,
            cc.pauseCommand,
            cc.togglePlayPauseCommand,
            cc.nextTrackCommand,
            cc.previousTrackCommand,
            cc.changePlaybackPositionCommand,
        ] {
            cmd.removeTarget(nil)
            cmd.isEnabled = true
        }

        cc.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resume()
            }
            return .success
        }
        cc.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pause()
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
        lastNowPlayingSync = Date()
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        #endif
    }

    private func updateNowPlayingInfo() {
        #if os(iOS)
        lastNowPlayingSync = Date()
        guard let track = queue.currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            return
        }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused

        if let account = activeAccount,
           let artURL = apiClient.resolveURL(account: account, rawPathOrURL: track.artworkURL) {
            let trackId = track.id
            Task { @MainActor [weak self] in
                guard let self,
                      let (data, _) = try? await URLSession.shared.data(from: artURL),
                      let rawImage = UIImage(data: data),
                      self.queue.currentTrack?.id == trackId else { return }
                let square = self.squareArtworkImage(rawImage)
                var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: square.size) { _ in square }
                MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
            }
        }
        #endif
    }

    #if os(iOS)
    private func squareArtworkImage(_ image: UIImage) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        guard w > 0, h > 0, abs(w - h) > 2 else { return image }
        let side = min(w, h)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let x = (side - w) / 2.0
            let y = (side - h) / 2.0
            image.draw(in: CGRect(x: x, y: y, width: w, height: h))
        }
    }
    #endif
}
