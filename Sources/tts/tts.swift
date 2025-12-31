import AVFoundation
import Carbon
@preconcurrency import ApplicationServices
import SwiftUI

struct TimedWord: Codable {
    let word: String
    let start: Double
    let end: Double
}

@main
struct TTSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra("Kokoro TTS", systemImage: "waveform") {
            MenuBarView()
                .environmentObject(state)
        }
        .commands {
            CommandMenu("View") {
                Toggle("Always on top", isOn: $state.alwaysOnTop)
            }
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

    @Published var text: String = Strings.defaultText
    @Published var voice: String = "af_heart"
    @Published var availableVoices: [String] = []
    @Published var language: String = "a"
    @Published var status: String = Strings.setupIdle
    @Published var isRunning: Bool = false
    @Published var isSettingUp: Bool = false
    @Published var setupState: SetupState = .idle
    @Published var setupLog: String = ""
    @Published var permissionStatus: String = Strings.accessibilityNotChecked
    @Published var wordTimings: [TimedWord] = []
    @Published var currentWordIndex: Int? = nil

    private var player: AVAudioPlayer?
    private var playbackTimer: Timer?
    var hotKeyManager: HotKeyManager?

    private override init() {
        super.init()
        hotKeyManager = HotKeyManager {
            Task { @MainActor in
                AppState.shared.speakSelectedText()
            }
        }
    }

    func speak() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isRunning = true
        status = Strings.synthesizing

        Task.detached { [text = trimmed, voice = self.voice, language = self.language] in
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
            let voices = try KokoroRunner.listVoices(voice: voice)
            availableVoices = voices
            if !voices.isEmpty, !voices.contains(voice) {
                voice = voices.first ?? voice
            }
        } catch {
            status = "\(Strings.failedToLoadVoicesPrefix)\(error.localizedDescription)"
        }
    }

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
                let selectedVoice = await MainActor.run { AppState.shared.voice }
                let voices = try KokoroRunner.listVoices(voice: selectedVoice)
                await MainActor.run {
                    AppState.shared.setupState = .loadingVoices
                    AppState.shared.availableVoices = voices
                    if let first = voices.first, !voices.contains(AppState.shared.voice) {
                        AppState.shared.voice = first
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
        player?.stop()
        playbackTimer?.invalidate()
        playbackTimer = nil
        currentWordIndex = nil
        status = "Stopped"
        isRunning = false
    }
    
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
    
    func openMainWindow() {
        AppDelegate.shared?.showWindow()
    }

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

    private func ensureAccessibilityPermission(prompt: Bool) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        permissionStatus = trusted ? "Accessibility granted" : "Accessibility not granted"
    }

    func reregisterHotKey() {
        hotKeyManager?.reregister()
    }
}

struct HighlightedTextView: View {
    let text: String
    let wordTimings: [TimedWord]
    let currentWordIndex: Int?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(wordTimings.enumerated()), id: \.offset) { index, timing in
                        Text(timing.word)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(index == currentWordIndex ? Color.yellow.opacity(0.6) : Color.gray.opacity(0.1))
                            .cornerRadius(4)
                            .font(.body)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Kokoro TTS")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("Uses a local Python Kokoro install to synthesize audio")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Text")
                    .font(.headline)
                if state.isRunning && !state.wordTimings.isEmpty {
                    HighlightedTextView(text: state.text, wordTimings: state.wordTimings, currentWordIndex: state.currentWordIndex)
                        .frame(minHeight: 140)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.2)))
                } else {
                    TextEditor(text: $state.text)
                        .frame(minHeight: 140)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.2)))
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Voice")
                        .font(.headline)
                    if state.availableVoices.isEmpty {
                        TextField("af_heart", text: $state.voice)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Voice", selection: $state.voice) {
                            ForEach(state.availableVoices, id: \.self) { voice in
                                Text(voice).tag(voice)
                            }
                        }
                        .frame(minWidth: 180)
                        .pickerStyle(.menu)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lang")
                        .font(.headline)
                    TextField("a", text: $state.language)
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                }
                Spacer()
            }

            HStack(spacing: 12) {
                Button("Speak") {
                    state.speak()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.isRunning || state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Stop") {
                    state.stop()
                }
                .disabled(state.isRunning == false && state.status != "Playing audio")

                Spacer()
            }

            if state.isSettingUp {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(state.setupState.label)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(state.status)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }

            if KokoroLogger.isEnabled, !state.setupLog.isEmpty {
                Text(state.setupLog)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }

            HStack(spacing: 4) {
                Text("Hotkey:")
                    .foregroundStyle(.secondary)
                Text("⌃⌘A")
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary)
                    .cornerRadius(4)
                Text("speaks selected text")
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)

            Text(state.permissionStatus)
                .foregroundStyle(.secondary)
                .font(.footnote)

            Spacer()
        }
        .padding(24)
    }

}

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Speak Selected Text") {
                state.speakSelectedText()
            }
            .keyboardShortcut("a", modifiers: [.command, .control])

            Toggle("Always on top (⌃⌘T)", isOn: $state.alwaysOnTop)
                .keyboardShortcut("t", modifiers: [.command, .control])

            #if DEBUG
            Toggle("Debug setup logs", isOn: $state.debugSetupLogs)
            #endif

            Divider()

            Button("Open Window") {
                state.openMainWindow()
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .task {
            state.openMainWindow()
        }
    }
}

enum KokoroRunner {
    enum RunnerError: LocalizedError {
        case setupFailed(String)
        case missingScript
        case failedExit(code: Int32, stderr: String)
        case missingOutput

        var errorDescription: String? {
            switch self {
            case let .setupFailed(message):
                return "\(Strings.setupFailedPrefix)\(message)"
            case .missingScript:
                return Strings.missingScript
            case let .failedExit(code, stderr):
                return "\(Strings.kokoroFailedExitPrefix)\(code)). \(stderr)"
            case .missingOutput:
                return Strings.missingOutput
            }
        }
    }

    static func prepareEnvironment(_ update: @escaping @MainActor (String, String) async -> Void) async throws {
        if let pythonOverride = ProcessInfo.processInfo.environment["KOKORO_PY"], !pythonOverride.isEmpty {
            return
        }

        let pythonURL = venvPythonURL()
        if FileManager.default.fileExists(atPath: pythonURL.path) {
            await update("Using cached environment…", "")
            return
        }

        await update(Strings.setupStarting, "")
        let supportDir = appSupportDir()
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

        let venvDir = supportDir.appendingPathComponent("venv", isDirectory: true)
        let createVenv = runProcessStreaming(
            message: Strings.setupCreatingVenv,
            update: update,
            executable: "/usr/bin/env",
            arguments: ["uv", "venv", "--seed", venvDir.path]
        )
        print("[DEBUG] uv venv exit code: \(createVenv.exitCode)")
        print("[DEBUG] uv venv stdout: \(createVenv.stdout)")
        print("[DEBUG] uv venv stderr: \(createVenv.stderr)")
        guard createVenv.exitCode == 0 else {
            throw RunnerError.setupFailed("\(Strings.uvVenvFailedPrefix)\(createVenv.stderr)")
        }
        let createLog = KokoroLogger.log(title: "uv venv", result: createVenv)
        await update(Strings.setupCreatedVenv, createLog)

        await update(Strings.setupInstallingDeps, "")
        print("[DEBUG] Installing deps with python: \(pythonURL.path)")
        let installDeps = runProcessStreaming(
            message: Strings.setupInstallingDeps,
            update: update,
            executable: "/usr/bin/env",
            arguments: ["uv", "pip", "install", "--python", pythonURL.path, "kokoro>=0.9.4", "huggingface_hub", "soundfile", "numpy"]
        )
        print("[DEBUG] uv pip install exit code: \(installDeps.exitCode)")
        print("[DEBUG] uv pip install stdout: \(installDeps.stdout)")
        print("[DEBUG] uv pip install stderr: \(installDeps.stderr)")
        guard installDeps.exitCode == 0 else {
            throw RunnerError.setupFailed("\(Strings.uvPipFailedPrefix)\(installDeps.stderr)")
        }
        let installLog = KokoroLogger.log(title: "uv pip install", result: installDeps)
        await update(Strings.setupInstalledDeps, installLog)
        print("[DEBUG] prepareEnvironment completed successfully")
    }

    static func synthesize(text: String, voice: String, language: String) throws -> (audioURL: URL, timingsURL: URL) {
        print("[DEBUG] synthesize called - text: \(text.prefix(50))..., voice: \(voice), lang: \(language)")
        guard let scriptURL = resourceBundle().url(forResource: "kokoro_say", withExtension: "py") else {
            print("[DEBUG] kokoro_say.py not found in bundle")
            throw RunnerError.missingScript
        }
        print("[DEBUG] Script URL: \(scriptURL.path)")

        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("tts-swift", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outputURL = outputDir.appendingPathComponent("kokoro.wav")
        let timingsURL = outputDir.appendingPathComponent("kokoro_timings.json")

        let process = Process()
        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = stdoutPipe

        let environment = ProcessInfo.processInfo.environment
        let repoOverride = environment["KOKORO_REPO"]
        let revisionOverride = environment["KOKORO_REVISION"]

        var arguments: [String] = [
            scriptURL.path,
            "--text", text,
            "--voice", voice,
            "--lang", language,
            "--out", outputURL.path,
            "--timings", timingsURL.path
        ]

        if let repo = repoOverride, !repo.isEmpty {
            arguments.append(contentsOf: ["--repo", repo])
        }
        if let revision = revisionOverride, !revision.isEmpty {
            arguments.append(contentsOf: ["--revision", revision])
        }

        if let pythonPath = environment["KOKORO_PY"], !pythonPath.isEmpty {
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = ["-u"] + arguments
        } else {
            let pythonURL = venvPythonURL()
            if FileManager.default.fileExists(atPath: pythonURL.path) {
                process.executableURL = pythonURL
                process.arguments = ["-u"] + arguments
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["python3", "-u"] + arguments
            }
        }

        let result = ProcessRunner.runPTY(process: process)

        _ = KokoroLogger.log(title: "kokoro_say.py", result: result)

        if result.exitCode != 0 {
            throw RunnerError.failedExit(code: result.exitCode, stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw RunnerError.missingOutput
        }

        return (outputURL, timingsURL)
    }
    
    static func loadTimings(from url: URL) throws -> [TimedWord] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([TimedWord].self, from: data)
    }

    static func listVoices(voice: String? = nil, listAll: Bool = false) throws -> [String] {
        guard let scriptURL = resourceBundle().url(forResource: "kokoro_voices", withExtension: "py") else {
            throw RunnerError.missingScript
        }

        let environment = ProcessInfo.processInfo.environment
        let repoOverride = environment["KOKORO_REPO"]
        let revisionOverride = environment["KOKORO_REVISION"]

        var arguments: [String] = [scriptURL.path]
        if let repo = repoOverride, !repo.isEmpty {
            arguments.append(contentsOf: ["--repo", repo])
        }
        if let revision = revisionOverride, !revision.isEmpty {
            arguments.append(contentsOf: ["--revision", revision])
        }
        if listAll {
            arguments.append("--all")
        } else if let voice, !voice.isEmpty {
            arguments.append(contentsOf: ["--voice", voice])
        }

        let pythonURL = venvPythonURL()
        let result: (exitCode: Int32, stdout: String, stderr: String)
        if FileManager.default.fileExists(atPath: pythonURL.path) {
            result = ProcessRunner.runPTY(executable: pythonURL.path, arguments: arguments)
        } else if let pythonPath = environment["KOKORO_PY"], !pythonPath.isEmpty {
            result = ProcessRunner.runPTY(executable: pythonPath, arguments: arguments)
        } else {
            result = ProcessRunner.runPTY(executable: "/usr/bin/env", arguments: ["python3"] + arguments)
        }

        _ = KokoroLogger.log(title: "kokoro_voices.py", result: result)

        guard result.exitCode == 0 else {
            throw RunnerError.failedExit(code: result.exitCode, stderr: result.stderr)
        }

        let data = Data(result.stdout.utf8)
        let voices = try JSONDecoder().decode([String].self, from: data)
        return voices
    }

    static func prefetchRepo(
        message: String,
        update: @escaping @MainActor (String, String) async -> Void
    ) async throws {
        guard let scriptURL = resourceBundle().url(forResource: "kokoro_prefetch", withExtension: "py") else {
            throw RunnerError.missingScript
        }

        let environment = ProcessInfo.processInfo.environment
        let repoOverride = environment["KOKORO_REPO"]
        let revisionOverride = environment["KOKORO_REVISION"]

        var arguments: [String] = [scriptURL.path]
        if let repo = repoOverride, !repo.isEmpty {
            arguments.append(contentsOf: ["--repo", repo])
        }
        if let revision = revisionOverride, !revision.isEmpty {
            arguments.append(contentsOf: ["--revision", revision])
        }

        let pythonURL = venvPythonURL()
        let result: (exitCode: Int32, stdout: String, stderr: String)
        if FileManager.default.fileExists(atPath: pythonURL.path) {
            result = runProcessStreamingPTY(
                message: message,
                update: update,
                executable: pythonURL.path,
                arguments: ["-u"] + arguments
            )
        } else if let pythonPath = environment["KOKORO_PY"], !pythonPath.isEmpty {
            result = runProcessStreamingPTY(
                message: message,
                update: update,
                executable: pythonPath,
                arguments: ["-u"] + arguments
            )
        } else {
            result = runProcessStreamingPTY(
                message: message,
                update: update,
                executable: "/usr/bin/env",
                arguments: ["python3", "-u"] + arguments
            )
        }

        _ = KokoroLogger.log(title: "kokoro_prefetch.py", result: result)

        guard result.exitCode == 0 else {
            throw RunnerError.failedExit(code: result.exitCode, stderr: result.stderr)
        }
    }

    private static func appSupportDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(Strings.appSupportFolderName, isDirectory: true)
    }

    private static func venvPythonURL() -> URL {
        appSupportDir()
            .appendingPathComponent("venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3")
    }

    static func hasCachedVenv() -> Bool {
        FileManager.default.fileExists(atPath: venvPythonURL().path)
    }

    private static func runProcess(executable: String, arguments: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
        ProcessRunner.run(executable: executable, arguments: arguments)
    }

    private static func runProcessStreaming(
        message: String,
        update: @escaping @MainActor (String, String) async -> Void,
        executable: String,
        arguments: [String]
    ) -> (exitCode: Int32, stdout: String, stderr: String) {
        final class LiveLog: @unchecked Sendable {
            private let lock = NSLock()
            private var value = ""

            func append(_ text: String) -> String {
                lock.lock()
                value.append(text)
                let snapshot = value
                lock.unlock()
                return snapshot
            }
        }

        let liveLog = LiveLog()
        let result = ProcessRunner.run(executable: executable, arguments: arguments) { chunk, _ in
            let normalized = chunk.replacingOccurrences(of: "\r", with: "\n")
            let snapshot = liveLog.append(normalized)
            Task { @MainActor in
                await update(message, snapshot)
            }
        }
        return result
    }

    private static func runProcessStreamingPTY(
        message: String,
        update: @escaping @MainActor (String, String) async -> Void,
        executable: String,
        arguments: [String]
    ) -> (exitCode: Int32, stdout: String, stderr: String) {
        final class LiveLog: @unchecked Sendable {
            private let lock = NSLock()
            private var value = ""

            func append(_ text: String) -> String {
                lock.lock()
                value.append(text)
                let snapshot = value
                lock.unlock()
                return snapshot
            }
        }

        let liveLog = LiveLog()
        let result = ProcessRunner.runPTY(executable: executable, arguments: arguments) { chunk, _ in
            let normalized = chunk.replacingOccurrences(of: "\r", with: "\n")
            let snapshot = liveLog.append(normalized)
            Task { @MainActor in
                await update(message, snapshot)
            }
        }
        return result
    }

    private static func resourceBundle() -> Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    #if DEBUG
    static func appSupportDirForTests() -> URL { appSupportDir() }
    static func venvPythonURLForTests() -> URL { venvPythonURL() }
    static func runProcessForTests(executable: String, arguments: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
        runProcess(executable: executable, arguments: arguments)
    }
    static func decodeVoicesForTests(_ input: String) throws -> [String] {
        let data = Data(input.utf8)
        return try JSONDecoder().decode([String].self, from: data)
    }
    #endif
}

enum Strings {
    static let defaultText = "Hello from Kokoro."
    static let setupIdle = "Idle"
    static let setupStarting = "Setting up Python environment…"
    static let setupCreatingVenv = "Creating Python environment…"
    static let setupCreatedVenv = "Created Python environment"
    static let setupInstallingDeps = "Installing Python dependencies…"
    static let setupInstalledDeps = "Dependencies installed"
    static let setupLoadingVoices = "Loading voices…"
    static let setupDownloadingModel = "Downloading model files…"
    static let setupReady = "Ready"
    static let setupFailedPrefix = "Setup failed: "
    static let synthesizing = "Synthesizing…"
    static let playingAudio = "Playing audio"
    static let failedToPlayAudioPrefix = "Failed to play audio: "
    static let synthesisFailedPrefix = "Synthesis failed: "
    static let failedToLoadVoicesPrefix = "Failed to load voices: "
    static let accessibilityNotChecked = "Accessibility not checked"
    static let missingScript = "Missing bundled kokoro_say.py script."
    static let kokoroFailedExitPrefix = "Kokoro process failed (exit "
    static let missingOutput = "Kokoro did not produce output audio."
    static let uvVenvFailedPrefix = "uv venv failed. Install uv with: brew install uv\n"
    static let uvPipFailedPrefix = "uv pip install failed.\n"
    static let appSupportFolderName = "tts-swift"
}

@MainActor
final class HUDWindow {
    private static var window: NSWindow?
    private static var hideTask: Task<Void, Never>?

    static func show(message: String, duration: TimeInterval = 1.5) {
        hideTask?.cancel()

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()

        let padding: CGFloat = 24
        let width = max(label.frame.width + padding * 2, 160)
        let height: CGFloat = 56

        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12

        label.frame = NSRect(x: padding, y: (height - label.frame.height) / 2, width: label.frame.width, height: label.frame.height)
        visualEffect.addSubview(label)

        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .stationary]
            w.ignoresMouseEvents = true
            window = w
        }

        window?.setContentSize(NSSize(width: width, height: height))
        window?.contentView = visualEffect

        if let screen = NSScreen.main {
            let x = (screen.frame.width - width) / 2
            let y = screen.frame.height * 0.75
            window?.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window?.alphaValue = 1
        window?.orderFrontRegardless()

        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    window?.animator().alphaValue = 0
                } completionHandler: {
                    Task { @MainActor in
                        window?.orderOut(nil)
                    }
                }
            }
        }
    }
}

final class HotKeyManager: @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let handler: @Sendable () -> Void

    init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        register()
    }

    deinit {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef = handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }

    func reregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef = handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        register()
    }

    private func register() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B4F4B4F), id: 1) // 'KOKO'

        let modifiers = UInt32(cmdKey | controlKey)
        let keyCodeA: UInt32 = 0x00

        let status = RegisterEventHotKey(keyCodeA, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else { return }

        var installedHandler: EventHandlerRef?
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            let handler = manager.handler
            DispatchQueue.main.async {
                handler()
            }
            return noErr
        }, 1, &eventSpec, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()), &installedHandler)

        if handlerStatus == noErr {
            handlerRef = installedHandler
        }
    }
}

enum SelectedTextProvider {
    static func getSelectedText() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedElement: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard focusedError == .success, let element = focusedElement else { return nil }

        var selectedText: CFTypeRef?
        let selectedError = AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText)
        guard selectedError == .success else { return nil }

        return selectedText as? String
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState.shared)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    private var window: NSWindow?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        showWindow()
        AppState.shared.startBackgroundSetup()
        promptAccessibilityPermission()
    }

    private func promptAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        AppState.shared.permissionStatus = trusted ? "Accessibility granted" : "Accessibility not granted"
        AppState.shared.reregisterHotKey()
    }

    func showWindow() {
        if window == nil {
            let contentView = ContentView()
                .environmentObject(AppState.shared)
                .frame(minWidth: 560, minHeight: 420)

            let hostingView = NSHostingView(rootView: contentView)
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "Kokoro TTS"
            newWindow.center()
            newWindow.contentView = hostingView
            newWindow.isReleasedWhenClosed = false
            window = newWindow
        }

        setAlwaysOnTop(AppState.shared.alwaysOnTop)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setAlwaysOnTop(_ enabled: Bool) {
        window?.level = enabled ? .floating : .normal
    }
}
