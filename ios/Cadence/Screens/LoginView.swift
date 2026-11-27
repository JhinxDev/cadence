import SwiftUI
import CadenceCore

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var serverURL: String = (Bundle.main.object(forInfoDictionaryKey: "CadenceDefaultServerURL") as? String) ?? ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var detectedStatus: String?

    var body: some View {
        ZStack {
            AmbientObsidianBackdrop(tint: CadencePalette.accentPrimary)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(CadencePalette.accentPrimary)
                            Text("Cadence")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(CadencePalette.inkPrimary)
                        }

                        Text("Your self-hosted Navidrome library, reimagined with YouTube Music-style mixes, mood discovery, and infinite radio.")
                            .font(.system(size: 15))
                            .foregroundStyle(CadencePalette.inkSecondary)
                    }
                    .padding(.top, 28)

                    VStack(spacing: 14) {
                        fieldBlock(title: "SERVER URL") {
                            TextField("https://music.example.com", text: $serverURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        }

                        fieldBlock(title: "USERNAME") {
                            TextField("Navidrome username", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        fieldBlock(title: "PASSWORD") {
                            SecureField("Navidrome password", text: $password)
                        }
                    }

                    if let detectedStatus {
                        Label(detectedStatus, systemImage: "checkmark.seal.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CadencePalette.accentSuccess)
                    }

                    if let authError = appState.authError {
                        Text(authError)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CadencePalette.accentPrimary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(CadencePalette.accentPrimary.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(spacing: 12) {
                        Button {
                            Task {
                                await appState.signIn(serverURL: serverURL, username: username, password: password)
                            }
                        } label: {
                            HStack {
                                if appState.isCheckingAuth {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Connect Library")
                                        .font(.system(size: 16, weight: .bold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(CadencePalette.accentPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                        }
                        .disabled(appState.isCheckingAuth || serverURL.isEmpty || username.isEmpty || password.isEmpty)

                        Button {
                            appState.loadDemoSession()
                        } label: {
                            Text("Preview Offline Demo")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(CadencePalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(CadencePalette.inkPrimary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(CadencePalette.surfaceStroke, lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .task {
            if let caps = await appState.apiClient.probeCapabilities(serverURL: serverURL) {
                detectedStatus = "Cadence Discovery v\(caps.version) detected"
            }
        }
    }

    private func fieldBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(CadencePalette.inkSecondary)
            content()
                .font(.system(size: 15))
                .foregroundStyle(CadencePalette.inkPrimary)
                .padding(14)
                .background(CadencePalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CadencePalette.surfaceStroke, lineWidth: 1)
                )
        }
    }
}
