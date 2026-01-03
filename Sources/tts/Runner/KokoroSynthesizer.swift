import Foundation

struct KokoroSynthesizer: TTSSynthesizing, Sendable {
    func synthesize(text: String, voice: String, language: String) throws -> SynthesisResult {
        let (audioURL, timingsURL) = try KokoroRunner.synthesize(
            text: text,
            voice: voice,
            language: language
        )
        return SynthesisResult(audioURL: audioURL, timingsURL: timingsURL)
    }

    func loadTimings(from url: URL) throws -> [TimedWord] {
        try KokoroRunner.loadTimings(from: url)
    }
}
