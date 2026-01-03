import SwiftUI

struct PlaybackControlsView: View {
    @EnvironmentObject private var state: AppState

    private var canSpeak: Bool {
        !state.isRunning && !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canStop: Bool {
        state.isRunning || state.status == "Playing audio"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                state.speak()
            } label: {
                Label("Speak", systemImage: "play.fill")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSpeak)
            .buttonStyle(.borderedProminent)

            Button {
                state.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!canStop)
            .buttonStyle(.bordered)

            PlaybackSpeedView()
        }
    }
}

struct PlaybackSpeedView: View {
    @EnvironmentObject private var state: AppState
    @State private var isHovering = false

    private let speedOptions: [Double] = stride(from: 0.25, through: 2.0, by: 0.25).map { $0 }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                state.playbackSpeed = max(0.25, state.playbackSpeed - 0.1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
            }
            .buttonStyle(.bordered)

            Menu {
                ForEach(speedOptions, id: \.self) { speed in
                    Button {
                        state.playbackSpeed = speed
                    } label: {
                        HStack {
                            Text(String(format: "%.2gx", speed))
                            if abs(state.playbackSpeed - speed) < 0.01 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(String(format: "%.2gx", state.playbackSpeed))
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .frame(minWidth: 44)
                    .foregroundStyle(isHovering ? Color.accentColor : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isHovering = hovering
                    }
            }
            .menuIndicator(.hidden)
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                state.playbackSpeed = min(2.0, state.playbackSpeed + 0.1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
            }
            .buttonStyle(.bordered)
        }
    }
}
