import SwiftUI
import CadenceCore

struct MixDetailView: View {
    @Environment(AppState.self) private var appState
    let mix: MixCard
    @State private var tracks: [Track] = []
    @State private var isLoading = true

    var body: some View {
        let accent = Color(hex: mix.accentHex)
        ZStack {
            AmbientObsidianBackdrop(tint: accent)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 14) {
                        MixCollageArtwork(mix: mix, size: 220)
                            .shadow(color: accent.opacity(0.35), radius: 24, y: 12)

                        Text(mix.title)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(CadencePalette.inkPrimary)

                        Text(mix.subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(CadencePalette.inkSecondary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            Button {
                                guard !tracks.isEmpty else { return }
                                appState.player.play(tracks: tracks, startAt: 0)
                            } label: {
                                Label("Play Mix", systemImage: "play.fill")
                                    .font(.system(size: 15, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 46)
                                    .background(accent, in: Capsule())
                                    .foregroundStyle(.white)
                            }

                            Button {
                                guard !tracks.isEmpty else { return }
                                appState.player.play(tracks: tracks.shuffled(), startAt: 0)
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 46)
                                    .background(CadencePalette.surfaceElevated, in: Capsule())
                                    .foregroundStyle(CadencePalette.inkPrimary)
                                    .overlay(Capsule().stroke(CadencePalette.surfaceStroke, lineWidth: 1))
                            }
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                                TrackRowView(
                                    track: track,
                                    onTap: {
                                        appState.player.play(tracks: tracks, startAt: index)
                                    },
                                    onStartRadio: {
                                        Task { await appState.playTrackAndStartRadio(track) }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadMix()
        }
    }

    private func loadMix() async {
        defer { isLoading = false }
        guard let account = appState.account else { return }
        if account.isDemo || !appState.capabilities.discoveryEnabled {
            if mix.id == "discover-mix" || mix.id == "new-releases" {
                tracks = DemoCatalog.discoveryTracks
            } else if mix.id == "replay-mix" || mix.id == "forgotten-favorites" {
                tracks = DemoCatalog.libraryTracks
            } else {
                tracks = DemoCatalog.libraryTracks + DemoCatalog.discoveryTracks
            }
            return
        }
        if let detail = try? await appState.apiClient.fetchMix(
            account: account,
            mixId: mix.id,
            mood: appState.selectedMood
        ) {
            tracks = detail.tracks
        }
    }
}
