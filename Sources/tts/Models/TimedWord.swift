import Foundation

struct TimedWord: Codable, Sendable {
    let word: String
    let start: Double
    let end: Double
}
