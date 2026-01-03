import Foundation

struct KokoroEnvironment: TTSEnvironmentProviding, Sendable {
    var isReady: Bool {
        KokoroRunner.hasCachedVenv()
    }

    func prepare(onProgress: @escaping ProgressCallback) async throws {
        try await KokoroRunner.prepareEnvironment(onProgress)
    }
}
