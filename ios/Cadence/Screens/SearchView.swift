import SwiftUI
import CadenceCore

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var isSearchFocused: Bool
    @State private var query: String = ""
    @State private var suggestions: SearchSuggestions?
    @State private var results: SearchResults?
    @State private var isSearching = false
    @State private var showingFullResults = false
    @State private var suggestTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            AmbientObsidianBackdrop(tint: CadencePalette.accentPrimary)

            VStack(alignment: .leading, spacing: 14) {
                Text("Search")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(CadencePalette.inkPrimary)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(CadencePalette.inkSecondary)
                    TextField("Songs, artists, or discover new music", text: $query)
                        .focused($isSearchFocused)
                        .foregroundStyle(CadencePalette.inkPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit {
                            Task { await submitSearch() }
                        }
                        .onChange(of: query) { _, newValue in
                            scheduleSuggestions(for: newValue)
                        }
                    if !query.isEmpty {
                        Button {
                            suggestTask?.cancel()
                            query = ""
                            suggestions = nil
                            results = nil
                            showingFullResults = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(CadencePalette.inkMuted)
                        }
                    }
                }
                .padding(12)
                .background(CadencePalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CadencePalette.surfaceStroke, lineWidth: 1))
                .padding(.horizontal, 16)

                if isSearching && showingFullResults {
                    ProgressView("Searching library & catalog...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if showingFullResults, let results {
                    fullResultsView(results)
                } else if !trimmedQuery.isEmpty {
                    liveSuggestionsView
                } else {
                    idleVibesView
                }

                Spacer(minLength: 0)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var liveSuggestionsView: some View {
        let localTracks = localMatchingTracks(for: trimmedQuery)
        let localArtists = localMatchingArtists(for: trimmedQuery)
        let mergedArtists = deduplicatedArtists(localArtists + (suggestions?.topArtists ?? []))
        let mergedTracks = deduplicatedTracks(localTracks + (suggestions?.topTracks ?? []))
        let queryRows = mergedQueryStrings(for: trimmedQuery)

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !queryRows.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(queryRows, id: \.self) { term in
                            HStack(spacing: 12) {
                                Button {
                                    query = term
                                    Task { await submitSearch() }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 14))
                                            .foregroundStyle(CadencePalette.inkSecondary)
                                        Text(term)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(CadencePalette.inkPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    query = term
                                    isSearchFocused = true
                                } label: {
                                    Image(systemName: "arrow.up.left")
                                        .font(.system(size: 13))
                                        .foregroundStyle(CadencePalette.inkMuted)
                                        .frame(width: 32, height: 32)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Fill \(term)")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                    }
                }

                if !mergedArtists.isEmpty {
                    sectionTitle("Artists")
                    LazyVStack(spacing: 10) {
                        ForEach(mergedArtists.prefix(3)) { artist in
                            Button {
                                isSearchFocused = false
                                Task { await appState.startArtistRadio(artist.name, mode: .balanced) }
                            } label: {
                                HStack(spacing: 12) {
                                    ArtworkView(
                                        url: appState.artworkURL(for: artist.artworkURL),
                                        title: artist.name,
                                        subtitle: artist.reason,
                                        cornerRadius: 24
                                    )
                                    .frame(width: 46, height: 46)
                                    .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(artist.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(CadencePalette.inkPrimary)
                                            .lineLimit(1)
                                        Text(artist.reason)
                                            .font(.system(size: 12))
                                            .foregroundStyle(CadencePalette.inkSecondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                        .font(.system(size: 14))
                                        .foregroundStyle(CadencePalette.accentPrimary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if !mergedTracks.isEmpty {
                    sectionTitle("Top songs")
                    LazyVStack(spacing: 10) {
                        ForEach(mergedTracks.prefix(5)) { track in
                            TrackRowView(
                                track: track,
                                onTap: {
                                    isSearchFocused = false
                                    Task { await appState.playTrackAndStartRadio(track) }
                                },
                                onStartRadio: {
                                    isSearchFocused = false
                                    Task { await appState.playTrackAndStartRadio(track) }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Button {
                    Task { await submitSearch() }
                } label: {
                    HStack {
                        Image(systemName: "sparkle.magnifyingglass")
                        Text("Search all for \"\(trimmedQuery)\"")
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(CadencePalette.inkMuted)
                    }
                    .padding(14)
                    .background(CadencePalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CadencePalette.surfaceStroke, lineWidth: 1))
                    .foregroundStyle(CadencePalette.inkPrimary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
    }

    private func fullResultsView(_ results: SearchResults) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !results.artists.isEmpty {
                    sectionTitle("Artists")
                    ScrollView(.horizontal) {
                        HStack(spacing: 14) {
                            ForEach(results.artists) { artist in
                                Button {
                                    Task { await appState.startArtistRadio(artist.name, mode: .balanced) }
                                } label: {
                                    VStack(spacing: 8) {
                                        ArtworkView(
                                            url: appState.artworkURL(for: artist.artworkURL),
                                            title: artist.name,
                                            subtitle: artist.reason,
                                            cornerRadius: 44
                                        )
                                        .frame(width: 88, height: 88)
                                        .clipShape(Circle())
                                        Text(artist.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(CadencePalette.inkPrimary)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 94)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                }

                if !results.libraryTracks.isEmpty {
                    sectionTitle("In your library")
                    LazyVStack(spacing: 12) {
                        ForEach(results.libraryTracks) { track in
                            TrackRowView(
                                track: track,
                                onTap: { Task { await appState.playTrackAndStartRadio(track) } },
                                onStartRadio: { Task { await appState.playTrackAndStartRadio(track) } }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if !results.libraryAlbums.isEmpty {
                    sectionTitle("Albums")
                    ScrollView(.horizontal) {
                        HStack(spacing: 14) {
                            ForEach(results.libraryAlbums) { album in
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
                                        .frame(width: 132, height: 132)
                                        Text(album.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(CadencePalette.inkPrimary)
                                            .lineLimit(1)
                                        Text(album.artist)
                                            .font(.system(size: 12))
                                            .foregroundStyle(CadencePalette.inkSecondary)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 132)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .scrollIndicators(.hidden)
                }

                if !results.discoveryTracks.isEmpty {
                    sectionTitle("Discover new music")
                    LazyVStack(spacing: 12) {
                        ForEach(results.discoveryTracks) { track in
                            TrackRowView(
                                track: track,
                                onTap: { Task { await appState.playTrackAndStartRadio(track) } }
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

    private var idleVibesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Try searching or tap a vibe")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(starterSuggestions, id: \.self) { term in
                        Button {
                            query = term
                            Task { await submitSearch() }
                        } label: {
                            HStack {
                                Text(term)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(CadencePalette.inkPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 12))
                                    .foregroundStyle(CadencePalette.inkMuted)
                            }
                            .padding(14)
                            .background(CadencePalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 130)
        }
        .scrollIndicators(.hidden)
    }

    private var starterSuggestions: [String] {
        var terms: [String] = []
        var seen: Set<String> = []
        func appendUnique(_ raw: String) {
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = clean.lowercased()
            if !clean.isEmpty, !seen.contains(key), terms.count < 8 {
                seen.insert(key)
                terms.append(clean)
            }
        }
        for artist in appState.artists.prefix(3) { appendUnique(artist.name) }
        for artist in (appState.homeFeed?.recommendedArtists ?? []).prefix(3) { appendUnique(artist.name) }
        for fallback in ["French Rap", "R&B", "Lo-Fi", "Workout", "Late Night", "Chill"] {
            appendUnique(fallback)
        }
        return terms
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(CadencePalette.inkPrimary)
            .padding(.horizontal, 16)
    }

    private func scheduleSuggestions(for raw: String) {
        suggestTask?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            suggestions = nil
            results = nil
            showingFullResults = false
            return
        }
        showingFullResults = false
        guard let account = appState.account else { return }

        suggestTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            if account.isDemo {
                let tracks = (DemoCatalog.libraryTracks + DemoCatalog.discoveryTracks).filter {
                    $0.title.localizedCaseInsensitiveContains(trimmed) || $0.artist.localizedCaseInsensitiveContains(trimmed)
                }
                let artists = DemoCatalog.artists.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
                suggestions = SearchSuggestions(
                    query: trimmed,
                    suggestions: tracks.prefix(4).map { "\($0.artist) - \($0.title)" },
                    topTracks: Array(tracks.prefix(5)),
                    topArtists: Array(artists.prefix(3))
                )
                return
            }
            if appState.capabilities.discoveryEnabled, account.bearerToken != nil {
                if let fetched = try? await appState.apiClient.searchSuggest(account: account, query: trimmed),
                   !Task.isCancelled {
                    suggestions = fetched
                }
            }
        }
    }

    private func submitSearch() async {
        let trimmed = trimmedQuery
        guard !trimmed.isEmpty, let account = appState.account else { return }
        suggestTask?.cancel()
        isSearchFocused = false
        showingFullResults = true
        isSearching = true
        defer { isSearching = false }

        if account.isDemo {
            let lib = DemoCatalog.libraryTracks.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed) || $0.artist.localizedCaseInsensitiveContains(trimmed)
            }
            let disc = DemoCatalog.discoveryTracks.filter {
                $0.title.localizedCaseInsensitiveContains(trimmed) || $0.artist.localizedCaseInsensitiveContains(trimmed)
            }
            results = SearchResults(
                query: trimmed,
                libraryTracks: lib.isEmpty ? DemoCatalog.libraryTracks : lib,
                discoveryTracks: disc.isEmpty ? DemoCatalog.discoveryTracks : disc,
                libraryAlbums: DemoCatalog.albums,
                artists: DemoCatalog.artists
            )
            return
        }

        if appState.capabilities.discoveryEnabled, account.bearerToken != nil {
            results = try? await appState.apiClient.search(account: account, query: trimmed)
        }
    }

    private func localMatchingTracks(for q: String) -> [Track] {
        let pool = appState.starredTracks + (appState.homeFeed?.quickPicks ?? [])
        return pool.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.artist.localizedCaseInsensitiveContains(q)
        }
    }

    private func localMatchingArtists(for q: String) -> [ArtistCard] {
        let pool = appState.artists + (appState.homeFeed?.recommendedArtists ?? [])
        return pool.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private func deduplicatedArtists(_ input: [ArtistCard]) -> [ArtistCard] {
        var seen: Set<String> = []
        var out: [ArtistCard] = []
        for artist in input {
            let key = artist.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !key.isEmpty, seen.insert(key).inserted {
                out.append(artist)
            }
        }
        return out
    }

    private func deduplicatedTracks(_ input: [Track]) -> [Track] {
        var seen: Set<String> = []
        var out: [Track] = []
        for track in input {
            let key = "\(track.artist.lowercased())::\(track.title.lowercased())"
            if seen.insert(key).inserted {
                out.append(track)
            }
        }
        return out
    }

    private func mergedQueryStrings(for q: String) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        func add(_ text: String) {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = clean.lowercased()
            if !clean.isEmpty, seen.insert(key).inserted, out.count < 6 {
                out.append(clean)
            }
        }
        for artist in localMatchingArtists(for: q).prefix(2) { add(artist.name) }
        for item in (suggestions?.suggestions ?? []) { add(item) }
        for track in localMatchingTracks(for: q).prefix(2) { add("\(track.artist) - \(track.title)") }
        return out
    }
}
