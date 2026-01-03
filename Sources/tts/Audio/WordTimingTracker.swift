import Foundation
import Combine

@MainActor
final class WordTimingTracker: ObservableObject {
    @Published private(set) var currentWordIndex: Int?

    private var timings: [TimedWord] = []
    private var timer: Timer?
    private weak var audioPlayer: AudioPlayable?

    func start(timings: [TimedWord], audioPlayer: AudioPlayable) {
        self.timings = timings
        self.audioPlayer = audioPlayer
        self.currentWordIndex = timings.isEmpty ? nil : 0

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateCurrentWord()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        timings = []
        currentWordIndex = nil
    }

    func indexForTime(_ time: TimeInterval, in timings: [TimedWord]) -> Int? {
        for (index, timing) in timings.enumerated() {
            if time >= timing.start && time < timing.end {
                return index
            }
        }
        return nil
    }

    private func updateCurrentWord() {
        guard let player = audioPlayer else { return }
        let currentTime = player.currentTime

        let newIndex = indexForTime(currentTime, in: timings)
        if newIndex != currentWordIndex {
            currentWordIndex = newIndex
        }
    }
}
