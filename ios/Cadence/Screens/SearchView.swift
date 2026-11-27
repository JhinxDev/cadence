import SwiftUI
import CadenceCore

struct SearchView: View {
    @Environment(AppState.self) private var appState
    @State private var query: String = ""
    @State private var results: SearchResults?
    @State private var isSearching = false

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
                        .foregroundStyle(CadencePalette.inkPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            Task { await performSearch() }
                        }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            results = nil
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

                if isSearching {
                    ProgressView("Searching library & catalog...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let results {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
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
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("Try searching or tap a vibe")
                            let suggestions = ["Zaho", "Niska", "Shay", "French Rap", "Lo-Fi", "R&B"]
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                ForEach(suggestions, id: \.self) { term in
                                    Button {
                                        query = term
                                        Task { await performSearch() }
                                    } label: {
                                        HStack {
                                            Text(term)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(CadencePalette.inkPrimary)
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
                    }
                    .scrollIndicators(.hidden)
                }

                Spacer(minLength: 0)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(CadencePalette.inkPrimary)
            .padding(.horizontal, 16)
    }

    private func performSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let account = appState.account else { return }
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
}
