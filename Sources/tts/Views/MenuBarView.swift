import SwiftUI

/// Menu bar dropdown content with quick actions.
struct MenuBarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Speak Selected Text") {
                state.speakSelectedText()
            }
            .keyboardShortcut("a", modifiers: [.command, .control])

            Toggle("Always on top (⌃⌘T)", isOn: $state.alwaysOnTop)
                .keyboardShortcut("t", modifiers: [.command, .control])

            #if DEBUG
                Toggle("Debug setup logs", isOn: $state.debugSetupLogs)
            #endif

            Divider()

            Button("Open Window") {
                state.openMainWindow()
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .task {
            // Auto-open the main window when the app launches
            state.openMainWindow()
        }
    }
}
