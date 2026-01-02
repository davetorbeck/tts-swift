import SwiftUI

struct MainContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Input/Output Areas
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Input")
                        .font(.headline)
                    TextEditor(text: $state.text)
                        .frame(minHeight: 200)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.2)))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Output")
                        .font(.headline)
                    HighlightedTextView(
                        text: state.text,
                        wordTimings: state.wordTimings,
                        currentWordIndex: state.currentWordIndex
                    )
                    .frame(minHeight: 200)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.2)))
                }
            }

            // Action Buttons
            HStack(spacing: 12) {
                Button {
                    state.speak()
                } label: {
                    Label("Speak", systemImage: "play.fill")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    state.isRunning
                        || state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .buttonStyle(.borderedProminent)

                Button {
                    state.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(state.isRunning == false && state.status != "Playing audio")
                .buttonStyle(.bordered)

                Spacer()
            }

            // Debug Logs (if enabled)
            if KokoroLogger.isEnabled, !state.setupLog.isEmpty {
                Text(state.setupLog)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(.quaternary.opacity(0.5))
                    .cornerRadius(6)
            }

            Spacer()
        }
        .padding(20)
    }
}
