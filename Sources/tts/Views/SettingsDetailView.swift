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

            GroupBox("Status") {
                VStack(alignment: .leading, spacing: 8) {
                    if state.isSettingUp {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(state.setupState.label)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(state.setupState == .ready ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(state.status)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(state.permissionStatus)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
