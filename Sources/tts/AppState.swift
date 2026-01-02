import AVFoundation
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

    // MARK: - Setup State

    /// Represents the current state of the Python environment setup.
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

    // MARK: - Persisted Settings

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

    // MARK: - Published State

    @Published var text: String = Strings.defaultText
    @Published var voice: String = "af_heart"
    @Published var availableVoices: [String] = []
    @Published var downloadedVoices: Set<String> = []
    @Published var isDownloadingVoice: Bool = false
    @Published var downloadingVoiceName: String? = nil
    @Published var language: KokoroLanguage = .americanEnglish
    @Published var status: String = Strings.setupIdle
    @Published var isRunning: Bool = false
    @Published var isSettingUp: Bool = false
    @Published var setupState: SetupState = .idle
    @Published var setupLog: String = ""
    @Published var permissionStatus: String = Strings.accessibilityNotChecked
    @Published var wordTimings: [TimedWord] = []
    @Published var currentWordIndex: Int? = nil

    // MARK: - Private Properties

    private var player: AVAudioPlayer?
    private var playbackTimer: Timer?
    var hotKeyManager: HotKeyManager?

    // MARK: - Initialization

    private override init() {
        super.init()
        hotKeyManager = HotKeyManager {
            Task { @MainActor in
                AppState.shared.speakSelectedText()
            }
        }
    }

    // MARK: - Synthesis

    /// Synthesizes and plays the current text.
    func speak() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isRunning = true
        wordTimings = []
        currentWordIndex = nil
        status = Strings.synthesizing

        Task.detached { [text = trimmed, voice = self.voice, language = self.language.rawValue] in
            do {
                await MainActor.run {
                    self.isSettingUp = true
                    self.setupLog = ""
                }
                try await KokoroRunner.prepareEnvironment { message, log in
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
                let (wavURL, timingsURL) = try KokoroRunner.synthesize(text: text, voice: voice, language: language)
                await MainActor.run {
                    do {
                        self.wordTimings = try KokoroRunner.loadTimings(from: timingsURL)
                        self.currentWordIndex = self.wordTimings.isEmpty ? nil : 0
                        FloatingOutputWindow.show()
                        self.player = try AVAudioPlayer(contentsOf: wavURL)
                        self.player?.prepareToPlay()
                        self.player?.play()
                        self.status = Strings.playingAudio
                        self.startPlaybackTracking()
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
            let voiceList = try KokoroRunner.listRemoteVoices()
            availableVoices = voiceList.voices
            downloadedVoices = Set(voiceList.downloaded)
            if !voiceList.voices.isEmpty, !voiceList.voices.contains(voice) {
                voice = voiceList.downloaded.first ?? voiceList.voices.first ?? voice
            }
        } catch {
            status = "\(Strings.failedToLoadVoicesPrefix)\(error.localizedDescription)"
        }
    }

    func downloadVoice(_ voiceName: String) {
        guard !isDownloadingVoice else { return }
        isDownloadingVoice = true
        downloadingVoiceName = voiceName

        Task.detached {
            do {
                try await KokoroRunner.downloadVoice(voiceName) { message, log in
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

    /// Starts background setup of the Python environment and voice loading.
    func startBackgroundSetup() {
        Task.detached(priority: .background) {
            do {
                let cached = KokoroRunner.hasCachedVenv()
                await MainActor.run {
                    AppState.shared.isSettingUp = true
                    AppState.shared.setupState = cached ? .loadingVoices : .creatingVenv
                    AppState.shared.status = cached ? Strings.setupLoadingVoices : Strings.setupCreatingVenv
                    AppState.shared.setupLog = ""
                }
                try await KokoroRunner.prepareEnvironment { message, log in
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
                try await KokoroRunner.prefetchRepo(message: Strings.setupDownloadingModel) { message, log in
                    await MainActor.run {
                        AppState.shared.status = message
                        if !log.isEmpty {
                            AppState.shared.setupLog = log
                        }
                    }
                }
                let voiceList = try KokoroRunner.listRemoteVoices()
                await MainActor.run {
                    AppState.shared.setupState = .loadingVoices
                    AppState.shared.availableVoices = voiceList.voices
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

    /// Stops the current playback.
    func stop() {
        player?.stop()
        playbackTimer?.invalidate()
        playbackTimer = nil
        wordTimings = []
        currentWordIndex = nil
        status = "Stopped"
        isRunning = false
    }

    /// Starts a timer to track playback position and update word highlighting.
    private func startPlaybackTracking() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                guard let player = self.player, let currentTime = player.currentTime as TimeInterval? else {
                    return
                }

                var newIndex: Int? = nil
                for (index, timing) in self.wordTimings.enumerated() {
                    if currentTime >= timing.start && currentTime < timing.end {
                        newIndex = index
                        break
                    }
                }

                if newIndex != self.currentWordIndex {
                    self.currentWordIndex = newIndex
                }
            }
        }
    }

    /// Opens the main application window.
    func openMainWindow() {
        AppDelegate.shared?.showWindow()
    }

    /// Speaks the currently selected text from any application.
    func speakSelectedText() {
        ensureAccessibilityPermission(prompt: true)
        if let selected = SelectedTextProvider.getSelectedText() {
            text = selected
            HUDWindow.show(message: "Speaking...")
            speak()
        } else {
            HUDWindow.show(message: "No text selected")
            status = "No selected text found. Grant Accessibility permission and try again."
        }
    }

    /// Checks and optionally prompts for accessibility permission.
    private func ensureAccessibilityPermission(prompt: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        permissionStatus = trusted ? "Accessibility granted" : "Accessibility not granted"
    }

    /// Re-registers the global hotkey (useful after permissions change).
    func reregisterHotKey() {
        hotKeyManager?.reregister()
    }
}
