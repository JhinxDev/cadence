import SwiftUI
import CadenceCore

enum AppTab: Hashable {
    case home
    case radio
    case library
    case search
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: AppTab = .home

    var body: some View {
        @Bindable var bindableState = appState
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView()
                }
                .tag(AppTab.home)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

                NavigationStack {
                    ExploreRadioView()
                }
                .tag(AppTab.radio)
                .tabItem {
                    Label("Mixes", systemImage: "dot.radiowaves.left.and.right")
                }

                NavigationStack {
                    LibraryView()
                }
                .tag(AppTab.library)
                .tabItem {
                    Label("Library", systemImage: "music.note.list")
                }

                NavigationStack {
                    SearchView()
                }
                .tag(AppTab.search)
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }

            if let current = appState.player.queue.currentTrack {
                MiniPlayerBar(track: current) {
                    appState.isNowPlayingPresented = true
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 72)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let toast = appState.activeToast {
                Text(toast)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(CadencePalette.surfaceElevated.opacity(0.96), in: Capsule())
                    .overlay(Capsule().stroke(CadencePalette.surfaceStroke, lineWidth: 1))
                    .padding(.bottom, appState.player.queue.currentTrack == nil ? 86 : 146)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.84), value: appState.player.queue.currentTrack?.id)
        .sheet(isPresented: $bindableState.isNowPlayingPresented) {
            NowPlayingView()
                .presentationDragIndicator(.visible)
        }
    }
}

struct MiniPlayerBar: View {
    @Environment(AppState.self) private var appState
    let track: Track
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 12) {
                ArtworkView(
                    url: appState.artworkURL(for: track.artworkURL),
                    title: track.title,
                    subtitle: track.artist,
                    cornerRadius: 8
                )
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(track.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(CadencePalette.inkPrimary)
                            .lineLimit(1)
                        if !track.inLibrary {
                            Text("NEW")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(CadencePalette.accentDiscovery.opacity(0.28), in: Capsule())
                                .foregroundStyle(CadencePalette.accentDiscovery)
                        }
                    }
                    Text(track.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(CadencePalette.inkSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if !track.inLibrary {
                    Button {
                        Task { await appState.saveToLibrary(track, star: false) }
                    } label: {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(CadencePalette.inkPrimary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Save to library")
                }

                Button {
                    appState.player.togglePlayPause()
                } label: {
                    Image(systemName: appState.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(CadencePalette.inkPrimary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appState.player.isPlaying ? "Pause" : "Play")

                Button {
                    appState.player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CadencePalette.inkSecondary)
                        .frame(width: 32, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next track")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(CadencePalette.surfaceGlass.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(CadencePalette.surfaceStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
