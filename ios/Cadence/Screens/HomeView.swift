import SwiftUI
import CadenceCore

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var isSettingsPresented = false

    var body: some View {
        let tint = CadencePalette.moodTint(for: appState.selectedMood)
        ZStack {
            AmbientObsidianBackdrop(tint: tint)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    headerBar

                    if let feed = appState.homeFeed {
                        moodChipRow(feed.moods, activeTint: tint)

                        if !feed.speedDial.isEmpty {
                            speedDialSection(feed.speedDial)
                        }

                        if !feed.quickPicks.isEmpty {
                            quickPicksSection(feed.quickPicks)
                        }

                        if !feed.madeForYou.isEmpty {
                            madeForYouSection(feed.madeForYou)
                        }

                        if !feed.recommendedArtists.isEmpty {
                            recommendedArtistsSection(feed.recommendedArtists)
                        }

                        if !feed.listenAgain.isEmpty {
                            albumShelfSection(title: "Listen again", kicker: "RECENTLY PLAYED", albums: feed.listenAgain)
                        }

                        if !feed.newInLibrary.isEmpty {
                            albumShelfSection(title: "New in Navidrome", kicker: "FRESHLY ADDED", albums: feed.newInLibrary)
                        }
                    } else if appState.isLoadingHome {
                        ProgressView("Building your personalized mixes...")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    } else if let err = appState.homeError {
                        VStack(spacing: 12) {
                            Text(err).foregroundStyle(CadencePalette.inkSecondary)
                            Button("Retry") {
                                Task { await appState.loadHome(mood: appState.selectedMood) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                }
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await appState.loadHome(mood: appState.selectedMood)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CadencePalette.inkSecondary)
                Text("Cadence")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(CadencePalette.inkPrimary)
            }

            Spacer()

            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(CadencePalette.inkPrimary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Account and settings")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 { return "Good morning" }
        if hour < 18 { return "Good afternoon" }
        return "Good evening"
    }

    private func moodChipRow(_ moods: [String], activeTint: Color) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(moods, id: \.self) { mood in
                    let isSelected = mood == appState.selectedMood
                    Button {
                        Task { await appState.loadHome(mood: mood) }
                    } label: {
                        Text(mood)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isSelected ? activeTint : CadencePalette.surfaceElevated,
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? .white : CadencePalette.inkPrimary)
                            .overlay(
                                Capsule()
                                    .stroke(CadencePalette.surfaceStroke, lineWidth: isSelected ? 0 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }

    private func speedDialSection(_ items: [SpeedDialItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(kicker: "JUMP BACK IN", title: "Speed dial")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(items.prefix(9)) { item in
                    Button {
                        Task { await openSpeedDial(item) }
                    } label: {
                        ZStack(alignment: .bottomLeading) {
                            ArtworkView(
                                url: appState.artworkURL(for: item.artworkURL),
                                title: item.title,
                                subtitle: item.subtitle,
                                cornerRadius: 12
                            )
                            .aspectRatio(1, contentMode: .fit)

                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.82)],
                                startPoint: .center,
                                endPoint: .bottom
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            Text(item.title)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .padding(8)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func quickPicksSection(_ tracks: [Track]) -> some View {
        let pages = stride(from: 0, to: tracks.count, by: 4).map {
            Array(tracks[$0..<min($0 + 4, tracks.count)])
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(kicker: "START RADIO FROM A SONG", title: "Quick picks")
                Spacer()
                Button("Play all") {
                    appState.player.play(tracks: tracks, startAt: 0)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CadencePalette.accentPrimary)
                .padding(.trailing, 16)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                        VStack(spacing: 10) {
                            ForEach(page) { track in
                                TrackRowView(
                                    track: track,
                                    onTap: {
                                        Task { await appState.playTrackAndStartRadio(track) }
                                    },
                                    onStartRadio: {
                                        Task { await appState.playTrackAndStartRadio(track) }
                                    }
                                )
                            }
                        }
                        .frame(width: 318)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func madeForYouSection(_ mixes: [MixCard]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(kicker: "PERSONALIZED MIXES", title: "Mixed for you")
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(mixes) { mix in
                        NavigationLink {
                            MixDetailView(mix: mix)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                MixCollageArtwork(mix: mix, size: 164)
                                Text(mix.subtitle)
                                    .font(.system(size: 12))
                                    .foregroundStyle(CadencePalette.inkSecondary)
                                    .lineLimit(2)
                                    .frame(width: 164, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func recommendedArtistsSection(_ artists: [ArtistCard]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(kicker: "OUTSIDE YOUR LIBRARY", title: "Discover new artists")
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(artists) { artist in
                        Button {
                            Task { await appState.startArtistRadio(artist.name, mode: .discover) }
                        } label: {
                            VStack(spacing: 8) {
                                ArtworkView(
                                    url: appState.artworkURL(for: artist.artworkURL),
                                    title: artist.name,
                                    subtitle: artist.reason,
                                    cornerRadius: 62,
                                    accent: CadencePalette.accentDiscovery
                                )
                                .frame(width: 112, height: 112)
                                .clipShape(Circle())

                                Text(artist.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(CadencePalette.inkPrimary)
                                    .lineLimit(1)

                                Text(artist.reason)
                                    .font(.system(size: 11))
                                    .foregroundStyle(CadencePalette.inkSecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 120)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func albumShelfSection(title: String, kicker: String, albums: [AlbumCard]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(kicker: kicker, title: title)
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(albums) { album in
                        NavigationLink {
                            AlbumDetailView(album: album)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                ArtworkView(
                                    url: appState.artworkURL(for: album.artworkURL),
                                    title: album.title,
                                    subtitle: album.artist,
                                    cornerRadius: 12
                                )
                                .frame(width: 148, height: 148)

                                Text(album.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(CadencePalette.inkPrimary)
                                    .lineLimit(1)

                                Text(album.artist)
                                    .font(.system(size: 12))
                                    .foregroundStyle(CadencePalette.inkSecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 148)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func sectionHeader(kicker: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(kicker)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .foregroundStyle(CadencePalette.inkSecondary)
            Text(title)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(CadencePalette.inkPrimary)
        }
        .padding(.horizontal, 16)
    }

    private func openSpeedDial(_ item: SpeedDialItem) async {
        if !item.tracks.isEmpty {
            appState.player.play(tracks: item.tracks, startAt: 0)
            return
        }
        guard let account = appState.account else { return }
        if item.kind == "album",
           let tracks = try? await appState.subsonicClient.fetchAlbumTracks(account: account, albumId: item.targetId),
           !tracks.isEmpty {
            appState.player.play(tracks: tracks, startAt: 0)
        } else if item.kind == "playlist",
                  let tracks = try? await appState.subsonicClient.fetchPlaylistTracks(account: account, playlistId: item.targetId),
                  !tracks.isEmpty {
            appState.player.play(tracks: tracks, startAt: 0)
        }
    }
}
