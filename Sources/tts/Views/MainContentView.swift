import SwiftUI

struct MainContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            HStack {
                PlaybackControlsView()
                Spacer()
            }

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
