import AVFoundation

@MainActor
protocol AudioPlayable: AnyObject {
    var currentTime: TimeInterval { get }
    var isPlaying: Bool { get }
    func play(url: URL) throws
    func stop()
}

@MainActor
final class TTSAudioPlayer: AudioPlayable {
    private var player: AVAudioPlayer?

    var currentTime: TimeInterval {
        player?.currentTime ?? 0
    }

    var isPlaying: Bool {
        player?.isPlaying ?? false
    }

    func play(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
