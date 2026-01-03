import KeyboardShortcuts
import SwiftUI

struct SettingsDetailView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings")
                .font(.system(size: 24, weight: .semibold, design: .rounded))

            GroupBox("Window") {
                Toggle("Always on top", isOn: $state.alwaysOnTop)
                    .toggleStyle(.checkbox)
                    .padding(8)
            }

            GroupBox("Hotkey") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        KeyboardShortcuts.Recorder("Speak selected text:", name: .speakSelectedText)
                    }
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
