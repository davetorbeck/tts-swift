import Foundation

typealias ProgressCallback = @MainActor @Sendable (String, String) async -> Void

// MARK: - Environment

protocol TTSEnvironmentProviding: Sendable {
    func prepare(onProgress: @escaping ProgressCallback) async throws
    var isReady: Bool { get }
}

// MARK: - Synthesis

struct SynthesisResult: Sendable {
    let audioURL: URL
    let timingsURL: URL
}

protocol TTSSynthesizing: Sendable {
    func synthesize(text: String, voice: String, language: String) throws -> SynthesisResult
    func loadTimings(from url: URL) throws -> [TimedWord]
}

// MARK: - Voice Management

struct VoiceListResult: Sendable {
    let available: [String]
    let downloaded: [String]
}

protocol VoiceRepositoryProviding: Sendable {
    func listRemote() throws -> VoiceListResult
    func download(_ voice: String, onProgress: @escaping ProgressCallback) async throws
    func prefetchRepo(message: String, onProgress: @escaping ProgressCallback) async throws
}

// MARK: - Output Window

@MainActor
protocol OutputWindowControlling {
    func show()
    func hide()
    var isVisible: Bool { get }
}

// MARK: - Text Provider

protocol TextProviding: Sendable {
    func getSelectedText() -> String?
}
