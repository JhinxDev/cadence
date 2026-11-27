import SwiftUI
import CadenceCore

struct ExploreRadioView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedMode: RadioMode = .discover
    @State private var seedMood: String = "Discover"

    private let moods = ["Discover", "Energize", "Chill", "Focus", "Workout", "Late Night"]

    var body: some View {
        ZStack {
            AmbientObsidianBackdrop(tint: CadencePalette.accentDiscovery)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("INFINITE DISCOVERY")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(CadencePalette.inkSecondary)
                        Text("Mixes & Radio")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(CadencePalette.inkPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    // Interactive Mix Tuner Card
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Tune your radio")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(CadencePalette.inkPrimary)

                        HStack(spacing: 8) {
                            ForEach(RadioMode.allCases, id: \.self) { mode in
                                let active = selectedMode == mode
                                Button {
                                    selectedMode = mode
                                } label: {
                                    Text(mode.displayTitle)
                                        .font(.system(size: 13, weight: .bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            active ? CadencePalette.accentDiscovery : CadencePalette.surfaceBaseFallback,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        )
                                        .foregroundStyle(active ? .white : CadencePalette.inkSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text(selectedMode.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(CadencePalette.inkSecondary)

                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(moods, id: \.self) { mood in
                                    let active = seedMood == mood
                                    Button {
                                        seedMood = mood
                                    } label: {
                                        Text(mood)
                                            .font(.system(size: 12, weight: .semibold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(
                                                active ? CadencePalette.moodTint(for: mood) : CadencePalette.surfaceGlass,
                                                in: Capsule()
                                            )
                                            .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)

                        Button {
                            Task {
                                if let first = appState.homeFeed?.quickPicks.first {
                                    await appState.playTrackAndStartRadio(first, mode: selectedMode)
                                } else {
                                    await appState.startArtistRadio(appState.homeFeed?.recommendedArtists.first?.name ?? "Zaho", mode: selectedMode)
                                }
                                appState.isNowPlayingPresented = true
                            }
                        } label: {
                            Label("Launch \(seedMood) Radio", systemImage: "dot.radiowaves.left.and.right")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(CadencePalette.accentPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(16)
                    .background(CadencePalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(CadencePalette.surfaceStroke, lineWidth: 1))
                    .padding(.horizontal, 16)

                    if let mixes = appState.homeFeed?.madeForYou {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("All Personalized Mixes")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(CadencePalette.inkPrimary)
                                .padding(.horizontal, 16)

                            ForEach(mixes) { mix in
                                NavigationLink {
                                    MixDetailView(mix: mix)
                                } label: {
                                    HStack(spacing: 14) {
                                        MixCollageArtwork(mix: mix, size: 72)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(mix.title)
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundStyle(CadencePalette.inkPrimary)
                                            Text(mix.subtitle)
                                                .font(.system(size: 13))
                                                .foregroundStyle(CadencePalette.inkSecondary)
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(CadencePalette.inkMuted)
                                    }
                                    .padding(12)
                                    .background(CadencePalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CadencePalette.surfaceStroke, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private extension CadencePalette {
    static let surfaceBaseFallback = Color(hex: "#181824")
}
