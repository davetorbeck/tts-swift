import Foundation

struct KokoroVoiceRepository: VoiceRepositoryProviding, Sendable {
    func listRemote() throws -> VoiceListResult {
        let result = try KokoroRunner.listRemoteVoices()
        return VoiceListResult(available: result.voices, downloaded: result.downloaded)
    }

    func download(_ voice: String, onProgress: @escaping ProgressCallback) async throws {
        try await KokoroRunner.downloadVoice(voice, update: onProgress)
    }

    func prefetchRepo(message: String, onProgress: @escaping ProgressCallback) async throws {
        try await KokoroRunner.prefetchRepo(message: message, update: onProgress)
    }
}
