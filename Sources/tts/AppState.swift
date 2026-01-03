import AVFoundation
import Combine
import KeyboardShortcuts
import SwiftUI
@preconcurrency import ApplicationServices

enum KokoroLanguage: String, CaseIterable, Identifiable {
    case americanEnglish = "a"
    case britishEnglish = "b"
    case spanish = "e"
    case french = "f"
    case hindi = "h"
    case italian = "i"
    case japanese = "j"
    case korean = "k"
    case brazilianPortuguese = "p"
    case chinese = "z"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .americanEnglish: return "English (US)"
        case .britishEnglish: return "English (UK)"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .hindi: return "Hindi"
        case .italian: return "Italian"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .brazilianPortuguese: return "Portuguese (BR)"
        case .chinese: return "Chinese"
        }
    }
}

@MainActor
final class AppState: NSObject, ObservableObject {
    static let shared = AppState()

    enum SetupState: Equatable {
        case idle
        case creatingVenv
        case installingDeps
        case loadingVoices
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .idle:
                return Strings.setupIdle
            case .creatingVenv:
                return Strings.setupCreatingVenv
            case .installingDeps:
                return Strings.setupInstallingDeps
            case .loadingVoices:
                return Strings.setupLoadingVoices
            case .ready:
                return Strings.setupReady
            case .failed(let message):
                return "\(Strings.setupFailedPrefix)\(message)"
            }
        }
    }

    // MARK: - Dependencies

    private let audioPlayer: AudioPlayable
    private let wordTimingTracker: WordTimingTracker
    private let environment: TTSEnvironmentProviding
    private let synthesizer: TTSSynthesizing
    private let voiceRepository: VoiceRepositoryProviding
    private let textProvider: TextProviding

    // MARK: - Settings

    @AppStorage("alwaysOnTop") var alwaysOnTop: Bool = true {
        didSet {
            AppDelegate.shared?.setAlwaysOnTop(alwaysOnTop)
        }
    }

    #if DEBUG
    @AppStorage("debugSetupLogs") var debugSetupLogs: Bool = false
    #else
    let debugSetupLogs: Bool = false
    #endif

    // MARK: - State

    @Published var text: String = Strings.defaultText
    @Published var voice: String = "af_heart"
    @Published var availableVoices: [String] = []
    @Published var downloadedVoices: Set<String> = []
    @Published var isDownloadingVoice: Bool = false
    @Published var downloadingVoiceName: String?
    @Published var language: KokoroLanguage = .americanEnglish
    @Published var status: String = Strings.setupIdle
    @Published var isRunning: Bool = false
    @Published var isSettingUp: Bool = false
    @Published var setupState: SetupState = .idle
    @Published var setupLog: String = ""
    @Published var permissionStatus: String = Strings.accessibilityNotChecked
    @Published var wordTimings: [TimedWord] = []
    @Published var currentWordIndex: Int?
    @AppStorage("playbackSpeed") var playbackSpeed: Double = 1.0 {
        didSet { audioPlayer.rate = Float(playbackSpeed) }
    }

    private var wordIndexObserver: AnyCancellable?

    init(
        audioPlayer: AudioPlayable = TTSAudioPlayer(),
        wordTimingTracker: WordTimingTracker = WordTimingTracker(),
        environment: TTSEnvironmentProviding = KokoroEnvironment(),
        synthesizer: TTSSynthesizing = KokoroSynthesizer(),
        voiceRepository: VoiceRepositoryProviding = KokoroVoiceRepository(),
        textProvider: TextProviding = SystemTextProvider()
    ) {
        self.audioPlayer = audioPlayer
        self.wordTimingTracker = wordTimingTracker
        self.environment = environment
        self.synthesizer = synthesizer
        self.voiceRepository = voiceRepository
        self.textProvider = textProvider
        super.init()

        wordIndexObserver = wordTimingTracker.$currentWordIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] newIndex in
                self?.currentWordIndex = newIndex
            }

        KeyboardShortcuts.onKeyUp(for: .speakSelectedText) { [weak self] in
            Task { @MainActor in
                self?.speakSelectedText()
            }
        }
    }

    func speak() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isRunning = true
        wordTimings = []
        currentWordIndex = nil
        status = Strings.synthesizing

        Task.detached { [text = trimmed, voice = self.voice, language = self.language.rawValue, environment = self.environment, synthesizer = self.synthesizer] in
            do {
                await MainActor.run {
                    self.isSettingUp = true
                    self.setupLog = ""
                }
                try await environment.prepare { message, log in
                    await MainActor.run {
                        self.status = message
                        if !log.isEmpty {
                            self.setupLog = log
                        }
                    }
                }
                await MainActor.run {
                    self.isSettingUp = false
                    self.status = Strings.synthesizing
                }
                let result = try synthesizer.synthesize(text: text, voice: voice, language: language)
                await MainActor.run {
                    do {
                        self.wordTimings = try synthesizer.loadTimings(from: result.timingsURL)
                        FloatingOutputWindow.show()
                        try self.audioPlayer.play(url: result.audioURL)
                        self.audioPlayer.rate = Float(self.playbackSpeed)
                        self.wordTimingTracker.start(timings: self.wordTimings, audioPlayer: self.audioPlayer)
                        self.status = Strings.playingAudio
                    } catch {
                        self.status = "\(Strings.failedToPlayAudioPrefix)\(error.localizedDescription)"
                    }
                    self.isRunning = false
                }
            } catch {
                await MainActor.run {
                    self.status = "\(Strings.synthesisFailedPrefix)\(error.localizedDescription)"
                    self.isRunning = false
                    self.isSettingUp = false
                }
            }
        }
    }

    func loadVoices() async {
        do {
            let voiceList = try voiceRepository.listRemote()
            availableVoices = voiceList.available
            downloadedVoices = Set(voiceList.downloaded)
            if !voiceList.available.isEmpty, !voiceList.available.contains(voice) {
                voice = voiceList.downloaded.first ?? voiceList.available.first ?? voice
            }
        } catch {
            status = "\(Strings.failedToLoadVoicesPrefix)\(error.localizedDescription)"
        }
    }

    func downloadVoice(_ voiceName: String) {
        guard !isDownloadingVoice else { return }
        isDownloadingVoice = true
        downloadingVoiceName = voiceName

        Task.detached { [voiceRepository = self.voiceRepository] in
            do {
                try await voiceRepository.download(voiceName) { message, log in
                    await MainActor.run {
                        AppState.shared.status = message
                        if !log.isEmpty {
                            AppState.shared.setupLog = log
                        }
                    }
                }
                await MainActor.run {
                    AppState.shared.downloadedVoices.insert(voiceName)
                    AppState.shared.voice = voiceName
                    AppState.shared.isDownloadingVoice = false
                    AppState.shared.downloadingVoiceName = nil
                    AppState.shared.status = "Downloaded \(voiceName)"
                }
            } catch {
                await MainActor.run {
                    AppState.shared.status = "Failed to download \(voiceName): \(error.localizedDescription)"
                    AppState.shared.isDownloadingVoice = false
                    AppState.shared.downloadingVoiceName = nil
                }
            }
        }
    }

    func startBackgroundSetup() {
        Task.detached(priority: .background) { [environment = self.environment, voiceRepository = self.voiceRepository] in
            do {
                let cached = environment.isReady
                await MainActor.run {
                    AppState.shared.isSettingUp = true
                    AppState.shared.setupState = cached ? .loadingVoices : .creatingVenv
                    AppState.shared.status = cached ? Strings.setupLoadingVoices : Strings.setupCreatingVenv
                    AppState.shared.setupLog = ""
                }
                try await environment.prepare { message, log in
                    await MainActor.run {
                        AppState.shared.status = message
                        if message.lowercased().contains("install") {
                            AppState.shared.setupState = .installingDeps
                        } else if message.lowercased().contains("create") {
                            AppState.shared.setupState = .creatingVenv
                        }
                        if !log.isEmpty {
                            AppState.shared.setupLog = log
                        }
                    }
                }
                await MainActor.run {
                    AppState.shared.setupState = .loadingVoices
                    AppState.shared.status = Strings.setupLoadingVoices
                    AppState.shared.setupLog = ""
                }
                try await voiceRepository.prefetchRepo(message: Strings.setupDownloadingModel) { message, log in
                    await MainActor.run {
                        AppState.shared.status = message
                        if !log.isEmpty {
                            AppState.shared.setupLog = log
                        }
                    }
                }
                let voiceList = try voiceRepository.listRemote()
                await MainActor.run {
                    AppState.shared.setupState = .loadingVoices
                    AppState.shared.availableVoices = voiceList.available
                    AppState.shared.downloadedVoices = Set(voiceList.downloaded)
                    if !voiceList.downloaded.contains(AppState.shared.voice) {
                        AppState.shared.voice = voiceList.downloaded.first ?? "af_heart"
                    }
                    AppState.shared.setupState = .ready
                    AppState.shared.status = Strings.setupReady
                    AppState.shared.isSettingUp = false
                }
            } catch {
                await MainActor.run {
                    AppState.shared.setupState = .failed(error.localizedDescription)
                    AppState.shared.status = "\(Strings.setupFailedPrefix)\(error.localizedDescription)"
                    AppState.shared.isSettingUp = false
                }
            }
        }
    }

    func stop() {
        audioPlayer.stop()
        wordTimingTracker.stop()
        wordTimings = []
        currentWordIndex = nil
        status = "Stopped"
        isRunning = false
    }

    func openMainWindow() {
        AppDelegate.shared?.showWindow()
    }

    func speakSelectedText() {
        ensureAccessibilityPermission(prompt: true)
        if let selected = textProvider.getSelectedText() {
            text = selected
            HUDWindow.show(message: "Speaking...")
            speak()
        } else {
            HUDWindow.show(message: "No text selected")
            status = "No selected text found. Grant Accessibility permission and try again."
        }
    }

    private func ensureAccessibilityPermission(prompt: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        permissionStatus = trusted ? "Accessibility granted" : "Accessibility not granted"
    }
}
