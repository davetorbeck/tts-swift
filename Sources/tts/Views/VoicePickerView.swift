import SwiftUI

struct VoicePickerView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedVoice: String = ""

    var body: some View {
        Picker("Voice", selection: $selectedVoice) {
            ForEach(state.availableVoices, id: \.self) { voice in
                HStack {
                    Text(voice)
                    Spacer()
                    if state.downloadedVoices.contains(voice) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(voice)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .onAppear { selectedVoice = state.voice }
        .onChange(of: selectedVoice) { _, newVoice in
            handleVoiceSelection(newVoice)
        }
    }

    private func handleVoiceSelection(_ voice: String) {
        if state.downloadedVoices.contains(voice) {
            state.voice = voice
        } else {
            state.downloadVoice(voice)
        }
    }
}
