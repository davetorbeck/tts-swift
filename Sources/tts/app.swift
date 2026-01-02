import SwiftUI

/// Main application entry point.
/// Sets up the menu bar extra and view commands.
@main
struct TTSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        // Menu bar icon with dropdown menu
        MenuBarExtra("Kokoro TTS", systemImage: "waveform") {
            MenuBarView()
                .environmentObject(state)
        }
        // Global menu commands
        .commands {
            CommandMenu("View") {
                Toggle("Always on top", isOn: Binding(
                    get: { self.state.alwaysOnTop },
                    set: { self.state.alwaysOnTop = $0 }
                ))
            }
        }
    }
}
