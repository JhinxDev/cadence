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

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14))
                            .foregroundStyle(CadencePalette.inkMuted)
                        TextField("Filter \(segment.rawValue.lowercased())", text: $filterText)
                            .font(.system(size: 14))
                            .foregroundStyle(CadencePalette.inkPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !filterText.isEmpty {
                            Button {
                                filterText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(CadencePalette.inkMuted)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(CadencePalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CadencePalette.surfaceStroke, lineWidth: 1))

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
                        if segment != .offline && appState.isLoadingLibrary && isCurrentSegmentEmpty {
                            ProgressView("Loading your Navidrome library...")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 50)
                        } else if segment != .offline, let err = appState.libraryError, isCurrentSegmentEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 32))
                                    .foregroundStyle(CadencePalette.accentPrimary)
                                Text("Could not load library")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(CadencePalette.inkPrimary)
                                Text(err)
                                    .font(.system(size: 13))
                                    .foregroundStyle(CadencePalette.inkSecondary)
                                    .multilineTextAlignment(.center)
                                Button("Retry") {
                                    Task { await appState.loadLibrary() }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 46)
                        } else {
                            switch segment {
                            case .playlists:
                                if filteredPlaylists.isEmpty {
                                    emptyState(icon: "music.note.list", title: "No playlists yet", subtitle: "Create a playlist in Navidrome or pull down to refresh.")
                                } else {
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
                                }
                            case .albums:
                                if filteredAlbums.isEmpty {
                                    emptyState(icon: "square.stack", title: "No albums found", subtitle: "Try clearing the filter or pull down to refresh.")
                                } else {
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
                                }
                            case .artists:
                                if filteredArtists.isEmpty {
                                    emptyState(icon: "music.mic", title: "No artists found", subtitle: "Artists in your Navidrome library will appear here.")
                                } else {
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
                                }
                            case .liked:
                                if filteredLiked.isEmpty {
                                    emptyState(icon: "heart", title: "No liked songs yet", subtitle: "Tap the heart on any song to save it to your liked rotation.")
                                } else {
                                    ForEach(Array(filteredLiked.enumerated()), id: \.element.id) { idx, track in
                                        TrackRowView(
                                            track: track,
                                            onTap: {
                                                appState.player.play(tracks: filteredLiked, startAt: idx)
                                            },
                                            onStartRadio: {
                                                Task { await appState.playTrackAndStartRadio(track) }
                                            }
                                        )
                                    }
                                }
                            case .offline:
                                if appState.downloadedRecords.isEmpty {
                                    emptyState(icon: "arrow.down.circle", title: "No offline downloads yet", subtitle: "Download any album, playlist, or song for zero-signal playback.")
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
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if appState.playlists.isEmpty && appState.albums.isEmpty && appState.artists.isEmpty && !appState.isLoadingLibrary {
                await appState.loadLibrary()
            }
        }
    }

    private var isCurrentSegmentEmpty: Bool {
        switch segment {
        case .playlists: return appState.playlists.isEmpty
        case .albums: return appState.albums.isEmpty
        case .artists: return appState.artists.isEmpty
        case .liked: return appState.starredTracks.isEmpty
        case .offline: return appState.downloadedRecords.isEmpty
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 38))
                .foregroundStyle(CadencePalette.inkMuted)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CadencePalette.inkPrimary)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(CadencePalette.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
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

    private var filteredLiked: [Track] {
        filterText.isEmpty ? appState.starredTracks : appState.starredTracks.filter {
            $0.title.localizedCaseInsensitiveContains(filterText) || $0.artist.localizedCaseInsensitiveContains(filterText)
        }
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
