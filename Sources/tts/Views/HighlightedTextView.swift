import SwiftUI

/// Displays words with synchronized highlighting during audio playback.
/// Uses FlowLayout to wrap words naturally and auto-scrolls to keep the current word visible.
struct HighlightedTextView: View {
    /// The original input text (not currently used, kept for future reference).
    let text: String
    /// Word timing data from the synthesis output.
    let wordTimings: [TimedWord]
    /// Index of the currently playing word, or nil if not playing.
    let currentWordIndex: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if wordTimings.isEmpty {
                    // Placeholder when no synthesis has been performed
                    Text("Press Speak to see highlighted output")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                } else {
                    // Display words in a flowing layout with highlighting
                    FlowLayout(spacing: 4) {
                        ForEach(Array(wordTimings.enumerated()), id: \.offset) { index, timing in
                            Text(timing.word)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    index == currentWordIndex
                                        ? Color.accentColor.opacity(0.4) : Color.clear
                                )
                                .cornerRadius(4)
                                .font(.body)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
            }
            // Auto-scroll to keep current word visible
            .onChange(of: currentWordIndex) { newIndex in
                if let idx = newIndex {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }
}
