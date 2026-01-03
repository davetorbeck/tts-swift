import AVFoundation

@MainActor
protocol AudioPlayable: AnyObject {
    var currentTime: TimeInterval { get }
    var isPlaying: Bool { get }
    var rate: Float { get set }
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

    var rate: Float {
        get { player?.rate ?? 1.0 }
        set { player?.rate = newValue }
    }

    func play(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        player?.prepareToPlay()
        player?.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
