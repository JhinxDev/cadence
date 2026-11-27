import SwiftUI
import CadenceCore

public enum CadencePalette {
    public static let canvasBase = Color(hex: "#08080C")
    public static let surfaceElevated = Color(hex: "#12121B")
    public static let surfaceGlass = Color(hex: "#1B1B27")
    public static let surfaceStroke = Color.white.opacity(0.08)
    public static let inkPrimary = Color(hex: "#F7F7FA")
    public static let inkSecondary = Color(hex: "#9B9BA8")
    public static let inkMuted = Color(hex: "#666675")
    public static let accentPrimary = Color(hex: "#FF3B5C")
    public static let accentDiscovery = Color(hex: "#7C5CFF")
    public static let accentSuccess = Color(hex: "#2BD984")

    public static func moodTint(for mood: String) -> Color {
        switch mood {
        case "Energize": return Color(hex: "#FF5E3A")
        case "Chill": return Color(hex: "#3B82F6")
        case "Focus": return Color(hex: "#14B8A6")
        case "Workout": return Color(hex: "#F59E0B")
        case "Late Night": return Color(hex: "#8B5CF6")
        case "Discover": return Color(hex: "#EC4899")
        default: return accentPrimary
        }
    }
}

public extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

struct AmbientObsidianBackdrop: View {
    let tint: Color

    var body: some View {
        ZStack {
            CadencePalette.canvasBase.ignoresSafeArea()
            RadialGradient(
                colors: [tint.opacity(0.28), tint.opacity(0.07), Color.clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [CadencePalette.accentDiscovery.opacity(0.14), Color.clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 340
            )
            .ignoresSafeArea()
        }
    }
}

struct ArtworkView: View {
    let url: URL?
    let title: String
    let subtitle: String
    var cornerRadius: CGFloat = 10
    var accent: Color = CadencePalette.accentPrimary

    var body: some View {
        ZStack {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallbackArt
                    }
                }
            } else {
                fallbackArt
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(CadencePalette.surfaceStroke, lineWidth: 1)
        )
    }

    private var fallbackArt: some View {
        let seed = abs(title.hashValue ^ subtitle.hashValue)
        let colors: [Color] = [
            accent,
            CadencePalette.accentDiscovery,
            Color(hex: "#14B8A6"),
            Color(hex: "#F59E0B"),
            Color(hex: "#3B82F6"),
        ]
        let c1 = colors[seed % colors.count]
        let c2 = colors[(seed + 2) % colors.count]
        return LinearGradient(
            colors: [c1.opacity(0.85), c2.opacity(0.55), CadencePalette.surfaceElevated],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "waveform")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}

struct MixCollageArtwork: View {
    @Environment(AppState.self) private var appState
    let mix: MixCard
    var size: CGFloat = 160

    var body: some View {
        let accent = Color(hex: mix.accentHex)
        ZStack(alignment: .bottomLeading) {
            if mix.artworkURLs.count >= 4 {
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        tile(mix.artworkURLs[0], accent: accent)
                        tile(mix.artworkURLs[1], accent: accent)
                    }
                    HStack(spacing: 2) {
                        tile(mix.artworkURLs[2], accent: accent)
                        tile(mix.artworkURLs[3], accent: accent)
                    }
                }
            } else {
                LinearGradient(
                    colors: [accent.opacity(0.92), CadencePalette.surfaceElevated, CadencePalette.canvasBase],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "sparkles")
                        .font(.system(size: size * 0.24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.22))
                        .padding(14)
                }
            }

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(mix.badge)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.0)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accent.opacity(0.92), in: Capsule())
                    .foregroundStyle(.white)
                Text(mix.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CadencePalette.inkPrimary)
                    .lineLimit(2)
            }
            .padding(12)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CadencePalette.surfaceStroke, lineWidth: 1)
        )
    }

    private func tile(_ raw: String, accent: Color) -> some View {
        ArtworkView(
            url: appState.artworkURL(for: raw),
            title: mix.title,
            subtitle: mix.subtitle,
            cornerRadius: 0,
            accent: accent
        )
    }
}

struct TrackRowView: View {
    @Environment(AppState.self) private var appState
    let track: Track
    let onTap: () -> Void
    var onStartRadio: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    ArtworkView(
                        url: appState.artworkURL(for: track.artworkURL),
                        title: track.title,
                        subtitle: track.artist,
                        cornerRadius: 8
                    )
                    .frame(width: 50, height: 50)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(track.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(CadencePalette.inkPrimary)
                                .lineLimit(1)
                            if !track.inLibrary {
                                Text("NEW")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(CadencePalette.accentDiscovery.opacity(0.26), in: Capsule())
                                    .foregroundStyle(CadencePalette.accentDiscovery)
                            }
                        }

                        Text(track.reason.map { "\(track.artist) · \($0)" } ?? track.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(CadencePalette.inkSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)

            if !track.inLibrary {
                Button {
                    Task { await appState.saveToLibrary(track, star: false) }
                } label: {
                    if appState.savingTrackIds.contains(track.id) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 34, height: 34)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(CadencePalette.inkPrimary)
                            .frame(width: 34, height: 34)
                    }
                }
                .accessibilityLabel("Save \(track.title) to library")
            } else {
                Menu {
                    if let onStartRadio {
                        Button("Start Radio", systemImage: "dot.radiowaves.left.and.right", action: onStartRadio)
                    }
                    Button(
                        track.isStarred ? "Remove Like" : "Like Song",
                        systemImage: track.isStarred ? "heart.slash" : "heart"
                    ) {
                        Task { await appState.toggleStar(track) }
                    }
                    Button("Download Offline", systemImage: "arrow.down.circle") {
                        Task { await appState.downloadOffline([track]) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CadencePalette.inkSecondary)
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("More options for \(track.title)")
            }
        }
    }
}
