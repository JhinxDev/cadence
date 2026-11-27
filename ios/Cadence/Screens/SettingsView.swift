import SwiftUI
import CadenceCore

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var cacheBytes: Int64 = 0

    var body: some View {
        @Bindable var bindableState = appState
        NavigationStack {
            Form {
                Section("Server Connection") {
                    LabeledContent("Server", value: appState.account?.serverURL ?? "Demo")
                    LabeledContent("User", value: appState.account?.username ?? "-")
                    LabeledContent(
                        "Discovery Engine",
                        value: appState.capabilities.discoveryEnabled
                            ? (appState.capabilities.fullDiscoveryStreaming ? "Full Discovery + Save" : "Catalog Preview Mode")
                            : "Standard OpenSubsonic"
                    )
                }

                Section("Discovery & Radio") {
                    Toggle("Auto-save liked discovery songs", isOn: $bindableState.autoSaveOnLike)
                    Picker("Default Radio Mode", selection: $bindableState.preferredRadioMode) {
                        ForEach(RadioMode.allCases, id: \.self) { mode in
                            Text(mode.displayTitle).tag(mode)
                        }
                    }
                }

                Section("Offline Cache") {
                    LabeledContent("Downloaded Storage", value: ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file))
                    Button("Clear Offline Downloads", role: .destructive) {
                        Task {
                            await appState.cacheManager.clearAll()
                            cacheBytes = await appState.cacheManager.totalBytes()
                            appState.downloadedRecords = []
                        }
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        appState.signOut()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                cacheBytes = await appState.cacheManager.totalBytes()
            }
        }
    }
}
