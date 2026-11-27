import SwiftUI
import CadenceCore

enum LibrarySegment: String, CaseIterable {
    case playlists = "Playlists"
    case albums = "Albums"
    case artists = "Artists"
    case liked = "Liked"
    case offline = "Offline"
}

struct LibraryView: View {
    @Environment(AppState.self) private var appState
    @State private var segment: LibrarySegment = .playlists
    @State private var filterText: String = ""

    var body: some View {
        ZStack {
            AmbientObsidianBackdrop(tint: CadencePalette.accentPrimary)

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Library")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(CadencePalette.inkPrimary)

                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(LibrarySegment.allCases, id: \.self) { seg in
                                let active = seg == segment
                                Button {
                                    segment = seg
                                } label: {
                                    Text(seg.rawValue)
                                        .font(.system(size: 13, weight: .semibold))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            active ? CadencePalette.inkPrimary : CadencePalette.surfaceElevated,
                                            in: Capsule()
                                        )
                                        .foregroundStyle(active ? CadencePalette.canvasBase : CadencePalette.inkPrimary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        switch segment {
                        case .playlists:
                            ForEach(filteredPlaylists) { playlist in
                                NavigationLink {
                                    PlaylistDetailView(playlist: playlist)
                                } label: {
                                    HStack(spacing: 12) {
                                        ArtworkView(
                                            url: appState.artworkURL(for: playlist.artworkURL),
                                            title: playlist.name,
                                            subtitle: "\(playlist.songCount) songs",
                                            cornerRadius: 10
                                        )
                                        .frame(width: 56, height: 56)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(playlist.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(CadencePalette.inkPrimary)
                                            Text("\(playlist.songCount) tracks")
                                                .font(.system(size: 13))
                                                .foregroundStyle(CadencePalette.inkSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(CadencePalette.inkMuted)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        case .albums:
                            LazyVGrid(
                                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                                spacing: 16
                            ) {
                                ForEach(filteredAlbums) { album in
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
                                            .aspectRatio(1, contentMode: .fit)
                                            Text(album.title)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(CadencePalette.inkPrimary)
                                                .lineLimit(1)
                                            Text(album.artist)
                                                .font(.system(size: 12))
                                                .foregroundStyle(CadencePalette.inkSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        case .artists:
                            ForEach(filteredArtists) { artist in
                                Button {
                                    Task { await appState.startArtistRadio(artist.name, mode: .familiar) }
                                } label: {
                                    HStack(spacing: 12) {
                                        ArtworkView(
                                            url: appState.artworkURL(for: artist.artworkURL),
                                            title: artist.name,
                                            subtitle: artist.reason,
                                            cornerRadius: 28
                                        )
                                        .frame(width: 52, height: 52)
                                        .clipShape(Circle())

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(artist.name)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(CadencePalette.inkPrimary)
                                            Text(artist.reason)
                                                .font(.system(size: 13))
                                                .foregroundStyle(CadencePalette.inkSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "dot.radiowaves.left.and.right")
                                            .foregroundStyle(CadencePalette.accentPrimary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        case .liked:
                            ForEach(Array(appState.starredTracks.enumerated()), id: \.element.id) { idx, track in
                                TrackRowView(
                                    track: track,
                                    onTap: {
                                        appState.player.play(tracks: appState.starredTracks, startAt: idx)
                                    },
                                    onStartRadio: {
                                        Task { await appState.playTrackAndStartRadio(track) }
                                    }
                                )
                            }
                        case .offline:
                            if appState.downloadedRecords.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 38))
                                        .foregroundStyle(CadencePalette.inkMuted)
                                    Text("No offline downloads yet")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(CadencePalette.inkPrimary)
                                    Text("Download any album, playlist, or song for zero-signal playback.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(CadencePalette.inkSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.top, 50)
                            } else {
                                let tracks = appState.downloadedRecords.map(\.track)
                                ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                                    TrackRowView(track: track) {
                                        appState.player.play(tracks: tracks, startAt: idx)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 130)
                }
                .scrollIndicators(.hidden)
                .refreshable {
                    await appState.loadLibrary()
                }
            }
        }
        .searchable(text: $filterText, prompt: "Filter \(segment.rawValue.lowercased())")
        .toolbar(.hidden, for: .navigationBar)
    }

    private var filteredPlaylists: [PlaylistSummary] {
        filterText.isEmpty ? appState.playlists : appState.playlists.filter { $0.name.localizedCaseInsensitiveContains(filterText) }
    }

    private var filteredAlbums: [AlbumCard] {
        filterText.isEmpty ? appState.albums : appState.albums.filter {
            $0.title.localizedCaseInsensitiveContains(filterText) || $0.artist.localizedCaseInsensitiveContains(filterText)
        }
    }

    private var filteredArtists: [ArtistCard] {
        filterText.isEmpty ? appState.artists : appState.artists.filter { $0.name.localizedCaseInsensitiveContains(filterText) }
    }
}

struct AlbumDetailView: View {
    @Environment(AppState.self) private var appState
    let album: AlbumCard
    @State private var tracks: [Track] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            AmbientObsidianBackdrop(tint: CadencePalette.accentPrimary)
            ScrollView {
                VStack(spacing: 16) {
                    ArtworkView(
                        url: appState.artworkURL(for: album.artworkURL),
                        title: album.title,
                        subtitle: album.artist,
                        cornerRadius: 18
                    )
                    .frame(width: 210, height: 210)
                    .shadow(color: .black.opacity(0.45), radius: 22, y: 10)

                    VStack(spacing: 4) {
                        Text(album.title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(CadencePalette.inkPrimary)
                            .multilineTextAlignment(.center)
                        Text(album.year.map { "\(album.artist) · \($0)" } ?? album.artist)
                            .font(.system(size: 14))
                            .foregroundStyle(CadencePalette.inkSecondary)
                    }

                    HStack(spacing: 12) {
                        Button {
                            guard !tracks.isEmpty else { return }
                            appState.player.play(tracks: tracks, startAt: 0)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(CadencePalette.accentPrimary, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        Button {
                            Task { await appState.downloadOffline(tracks) }
                        } label: {
                            Label("Offline", systemImage: "arrow.down.circle")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(CadencePalette.surfaceElevated, in: Capsule())
                                .foregroundStyle(CadencePalette.inkPrimary)
                        }
                    }

                    if isLoading {
                        ProgressView().padding(.top, 20)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                                TrackRowView(
                                    track: track,
                                    onTap: { appState.player.play(tracks: tracks, startAt: idx) },
                                    onStartRadio: { Task { await appState.playTrackAndStartRadio(track) } }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            defer { isLoading = false }
            guard let account = appState.account else { return }
            if account.isDemo {
                tracks = DemoCatalog.libraryTracks
            } else {
                tracks = (try? await appState.subsonicClient.fetchAlbumTracks(account: account, albumId: album.id)) ?? []
            }
        }
    }
}

struct PlaylistDetailView: View {
    @Environment(AppState.self) private var appState
    let playlist: PlaylistSummary
    @State private var tracks: [Track] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            AmbientObsidianBackdrop(tint: CadencePalette.accentDiscovery)
            ScrollView {
                VStack(spacing: 16) {
                    ArtworkView(
                        url: appState.artworkURL(for: playlist.artworkURL),
                        title: playlist.name,
                        subtitle: "\(playlist.songCount) tracks",
                        cornerRadius: 18
                    )
                    .frame(width: 200, height: 200)

                    Text(playlist.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(CadencePalette.inkPrimary)

                    HStack(spacing: 12) {
                        Button {
                            guard !tracks.isEmpty else { return }
                            appState.player.play(tracks: tracks, startAt: 0)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(CadencePalette.accentPrimary, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        Button {
                            guard !tracks.isEmpty else { return }
                            appState.player.play(tracks: tracks.shuffled(), startAt: 0)
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(CadencePalette.surfaceElevated, in: Capsule())
                                .foregroundStyle(CadencePalette.inkPrimary)
                        }
                    }

                    if isLoading {
                        ProgressView().padding(.top, 20)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(tracks.enumerated()), id: \.element.id) { idx, track in
                                TrackRowView(
                                    track: track,
                                    onTap: { appState.player.play(tracks: tracks, startAt: idx) },
                                    onStartRadio: { Task { await appState.playTrackAndStartRadio(track) } }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            defer { isLoading = false }
            guard let account = appState.account else { return }
            if account.isDemo {
                tracks = DemoCatalog.libraryTracks
            } else {
                tracks = (try? await appState.subsonicClient.fetchPlaylistTracks(account: account, playlistId: playlist.id)) ?? []
            }
        }
    }
}
