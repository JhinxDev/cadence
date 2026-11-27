import AVKit
import SwiftUI
import CadenceCore

enum NowPlayingDrawerTab: String, CaseIterable {
    case upNext = "Up Next"
    case lyrics = "Lyrics"
    case related = "Related"
}

struct NowPlayingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawerTab: NowPlayingDrawerTab = .upNext
    @State private var lyrics: LyricsResult?
    @State private var relatedTracks: [Track] = []
    @State private var isDraggingScrubber = false
    @State private var scrubPosition: Double = 0

    var body: some View {
        let track = appState.player.queue.currentTrack
        ZStack {
            AmbientObsidianBackdrop(tint: track?.inLibrary == false ? CadencePalette.accentDiscovery : CadencePalette.accentPrimary)

            VStack(spacing: 12) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(CadencePalette.inkSecondary)
                            .frame(width: 40, height: 32)
                    }
                    .accessibilityLabel("Minimize player")
                    Spacer()
                    Text(appState.player.queue.isRadioActive ? "CADENCE RADIO" : "NOW PLAYING")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(CadencePalette.inkSecondary)
                    Spacer()
                    Color.clear.frame(width: 40, height: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                if let track {
                    ScrollView {
                        VStack(spacing: 16) {
                            ArtworkView(
                                url: appState.artworkURL(for: track.artworkURL),
                                title: track.title,
                                subtitle: track.artist,
                                cornerRadius: 20
                            )
                            .frame(width: 248, height: 248)
                            .shadow(color: CadencePalette.accentPrimary.opacity(0.28), radius: 28, y: 14)
                            .scaleEffect(appState.player.isPlaying ? 1.0 : 0.94)
                            .animation(
                                reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.8),
                                value: appState.player.isPlaying
                            )
                            .padding(.top, 4)

                            // Title + Artist + Save / Like bar
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(track.title)
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundStyle(CadencePalette.inkPrimary)
                                            .lineLimit(1)
                                        if !track.inLibrary {
                                            Text("DISCOVERY")
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(CadencePalette.accentDiscovery.opacity(0.28), in: Capsule())
                                                .foregroundStyle(CadencePalette.accentDiscovery)
                                        }
                                    }
                                    Text(track.artist)
                                        .font(.system(size: 15))
                                        .foregroundStyle(CadencePalette.inkSecondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                Button {
                                    Task { await appState.toggleStar(track) }
                                } label: {
                                    Image(systemName: track.isStarred ? "heart.fill" : "heart")
                                        .font(.system(size: 22))
                                        .foregroundStyle(track.isStarred ? CadencePalette.accentPrimary : CadencePalette.inkSecondary)
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel(track.isStarred ? "Unlike song" : "Like song")
                            }
                            .padding(.horizontal, 22)

                            // Instant Save-to-Library pill for discovery tracks
                            if !track.inLibrary {
                                Button {
                                    Task { await appState.saveToLibrary(track, star: true) }
                                } label: {
                                    HStack(spacing: 8) {
                                        if appState.savingTrackIds.contains(track.id) {
                                            ProgressView().tint(.white)
                                        } else {
                                            Image(systemName: "plus.circle.fill")
                                        }
                                        Text("Save permanently to Navidrome")
                                            .font(.system(size: 14, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(CadencePalette.accentDiscovery.opacity(0.26), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .foregroundStyle(CadencePalette.inkPrimary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(CadencePalette.accentDiscovery.opacity(0.6), lineWidth: 1)
                                    )
                                }
                                .padding(.horizontal, 22)
                            }

                            // Scrubber
                            VStack(spacing: 8) {
                                let total = max(appState.player.duration, 1)
                                let value = isDraggingScrubber ? scrubPosition : appState.player.currentTime
                                GeometryReader { geo in
                                    let ratio = min(max(value / total, 0), 1)
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.16))
                                            .frame(height: 4)
                                        Capsule()
                                            .fill(CadencePalette.inkPrimary)
                                            .frame(width: max(4, geo.size.width * ratio), height: 4)
                                        Circle()
                                            .fill(CadencePalette.inkPrimary)
                                            .frame(width: isDraggingScrubber ? 14 : 10, height: isDraggingScrubber ? 14 : 10)
                                            .offset(x: max(0, min(geo.size.width - 10, geo.size.width * ratio - 5)))
                                    }
                                    .frame(height: 24)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { drag in
                                                isDraggingScrubber = true
                                                let pct = min(max(drag.location.x / max(geo.size.width, 1), 0), 1)
                                                scrubPosition = pct * total
                                            }
                                            .onEnded { drag in
                                                let pct = min(max(drag.location.x / max(geo.size.width, 1), 0), 1)
                                                isDraggingScrubber = false
                                                appState.player.seek(to: pct * total)
                                            }
                                    )
                                }
                                .frame(height: 24)

                                HStack {
                                    Text(formatSeconds(value))
                                    Spacer()
                                    Text(formatSeconds(total))
                                }
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(CadencePalette.inkMuted)
                            }
                            .padding(.horizontal, 22)

                            // Transport Controls
                            HStack(spacing: 26) {
                                Button {
                                    appState.player.queue.isShuffled.toggle()
                                } label: {
                                    Image(systemName: "shuffle")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(appState.player.queue.isShuffled ? CadencePalette.accentPrimary : CadencePalette.inkSecondary)
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Toggle shuffle")

                                Button {
                                    appState.player.previous()
                                } label: {
                                    Image(systemName: "backward.fill")
                                        .font(.system(size: 26))
                                        .foregroundStyle(CadencePalette.inkPrimary)
                                        .frame(width: 48, height: 48)
                                }
                                .accessibilityLabel("Previous track")

                                Button {
                                    appState.player.togglePlayPause()
                                } label: {
                                    Image(systemName: appState.player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 64))
                                        .foregroundStyle(CadencePalette.inkPrimary)
                                }
                                .accessibilityLabel(appState.player.isPlaying ? "Pause" : "Play")

                                Button {
                                    appState.player.next()
                                } label: {
                                    Image(systemName: "forward.fill")
                                        .font(.system(size: 26))
                                        .foregroundStyle(CadencePalette.inkPrimary)
                                        .frame(width: 48, height: 48)
                                }
                                .accessibilityLabel("Next track")

                                AirPlayRouteButton()
                                    .frame(width: 44, height: 44)
                            }

                            // 3-Tab Bottom Drawer: Up Next | Lyrics | Related
                            VStack(spacing: 14) {
                                Picker("Drawer", selection: $drawerTab) {
                                    ForEach(NowPlayingDrawerTab.allCases, id: \.self) { tab in
                                        Text(tab.rawValue).tag(tab)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .padding(.horizontal, 20)

                                drawerContent(current: track)
                            }
                            .padding(.top, 6)
                            .padding(.bottom, 32)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .task(id: track.id) {
                        await loadTrackExtras(track)
                    }
                } else {
                    Text("Nothing playing")
                        .foregroundStyle(CadencePalette.inkSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func drawerContent(current: Track) -> some View {
        switch drawerTab {
        case .upNext:
            VStack(alignment: .leading, spacing: 12) {
                if appState.player.queue.isRadioActive {
                    HStack(spacing: 8) {
                        ForEach(RadioMode.allCases, id: \.self) { mode in
                            let active = appState.player.queue.radioMode == mode
                            Button {
                                Task { await appState.switchRadioMode(mode) }
                            } label: {
                                Text(mode.displayTitle)
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(active ? CadencePalette.accentDiscovery : CadencePalette.surfaceElevated, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                let upcoming = appState.player.queue.upNextTracks
                LazyVStack(spacing: 10) {
                    ForEach(Array(upcoming.enumerated()), id: \.element.id) { offset, nextTrack in
                        TrackRowView(track: nextTrack) {
                            appState.player.jump(to: appState.player.queue.currentIndex + 1 + offset)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

        case .lyrics:
            VStack(alignment: .leading, spacing: 10) {
                if let lyrics, !lyrics.lines.isEmpty {
                    ForEach(lyrics.lines) { line in
                        let isHighlighted = isLineActive(line, in: lyrics.lines)
                        Text(line.text)
                            .font(.system(size: isHighlighted ? 19 : 16, weight: isHighlighted ? .bold : .medium))
                            .foregroundStyle(isHighlighted ? CadencePalette.inkPrimary : CadencePalette.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("No lyrics found for \(current.title).")
                        .font(.system(size: 14))
                        .foregroundStyle(CadencePalette.inkSecondary)
                }
            }
            .padding(.horizontal, 22)

        case .related:
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    Task { await appState.playTrackAndStartRadio(current, mode: .discover) }
                } label: {
                    Label("Start Discover Radio from \(current.title)", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(CadencePalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(CadencePalette.inkPrimary)
                }
                .padding(.horizontal, 20)

                LazyVStack(spacing: 10) {
                    ForEach(relatedTracks) { rel in
                        TrackRowView(track: rel) {
                            Task { await appState.playTrackAndStartRadio(rel) }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func isLineActive(_ line: LyricsLine, in lines: [LyricsLine]) -> Bool {
        guard let timeMs = line.timeMs else { return false }
        let currentMs = Int(appState.player.currentTime * 1000)
        guard currentMs >= timeMs else { return false }
        if let idx = lines.firstIndex(of: line), idx + 1 < lines.count, let nextMs = lines[idx + 1].timeMs {
            return currentMs < nextMs
        }
        return true
    }

    private func loadTrackExtras(_ track: Track) async {
        guard let account = appState.account else { return }
        if account.isDemo {
            lyrics = DemoCatalog.sampleLyrics
            relatedTracks = DemoCatalog.discoveryTracks
            return
        }
        if appState.capabilities.discoveryEnabled, account.bearerToken != nil {
            lyrics = try? await appState.apiClient.fetchLyrics(account: account, track: track)
            if let batch = try? await appState.apiClient.startRadio(account: account, seedTrack: track, mode: .discover) {
                relatedTracks = Array(batch.tracks.prefix(10))
            }
        }
    }

    private func formatSeconds(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct AirPlayRouteButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor.white
        picker.activeTintColor = UIColor(CadencePalette.accentPrimary)
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
