import Foundation

/// Represents a word with its timing information for synchronized playback highlighting.
struct TimedWord: Codable {
    /// The word text.
    let word: String
    /// Start time in seconds from the beginning of the audio.
    let start: Double
    /// End time in seconds from the beginning of the audio.
    let end: Double
}
