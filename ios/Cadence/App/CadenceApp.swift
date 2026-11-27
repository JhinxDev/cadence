import SwiftUI
import CadenceCore

@main
struct CadenceApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.account != nil {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .environment(appState)
            .preferredColorScheme(.dark)
            .tint(CadencePalette.accentPrimary)
        }
    }
}
