import Foundation

/// Manages the Kokoro TTS Python environment and synthesis operations.
/// Handles virtual environment setup, dependency installation, and running Python scripts.
enum KokoroRunner {

    // MARK: - Errors

    enum RunnerError: LocalizedError {
        case setupFailed(String)
        case missingScript
        case failedExit(code: Int32, stderr: String)
        case missingOutput

        var errorDescription: String? {
            switch self {
            case .setupFailed(let message):
                return "\(Strings.setupFailedPrefix)\(message)"
            case .missingScript:
                return Strings.missingScript
            case .failedExit(let code, let stderr):
                return "\(Strings.kokoroFailedExitPrefix)\(code)). \(stderr)"
            case .missingOutput:
                return Strings.missingOutput
            }
        }
    }

    // MARK: - Environment Setup

    /// Prepares the Python virtual environment, creating it and installing dependencies if needed.
    /// - Parameter update: Callback for progress updates (message, log).
    static func prepareEnvironment(_ update: @escaping @MainActor (String, String) async -> Void)
    async throws {
        // Allow override via environment variable
        if let pythonOverride = ProcessInfo.processInfo.environment["KOKORO_PY"],
           !pythonOverride.isEmpty {
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

        // Create virtual environment using uv
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

        // Install Python dependencies
        await update(Strings.setupInstallingDeps, "")
        print("[DEBUG] Installing deps with python: \(pythonURL.path)")
        let installDeps = runProcessStreaming(
            message: Strings.setupInstallingDeps,
            update: update,
            executable: "/usr/bin/env",
            arguments: [
                "uv", "pip", "install", "--python", pythonURL.path, "kokoro>=0.9.4",
                "huggingface_hub", "soundfile", "numpy"
            ]
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

    // MARK: - Synthesis

    /// Synthesizes speech from text using the Kokoro TTS model.
    /// - Parameters:
    ///   - text: The text to synthesize.
    ///   - voice: The voice ID to use (e.g., "af_heart").
    ///   - language: The language code (e.g., "a" for American English).
    /// - Returns: URLs to the generated audio file and word timings JSON.
    static func synthesize(text: String, voice: String, language: String) throws -> (
        audioURL: URL, timingsURL: URL
    ) {
        print(
            "[DEBUG] synthesize called - text: \(text.prefix(50))..., voice: \(voice), lang: \(language)"
        )
        guard let scriptURL = resourceBundle().url(forResource: "kokoro_say", withExtension: "py")
        else {
            print("[DEBUG] kokoro_say.py not found in bundle")
            throw RunnerError.missingScript
        }
        print("[DEBUG] Script URL: \(scriptURL.path)")

        // Create output directory
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "tts-swift", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outputURL = outputDir.appendingPathComponent("kokoro.wav")
        let timingsURL = outputDir.appendingPathComponent("kokoro_timings.json")

        // Configure the process
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

        // Select Python executable
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
            throw RunnerError.failedExit(
                code: result.exitCode,
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw RunnerError.missingOutput
        }

        return (outputURL, timingsURL)
    }

    /// Loads word timings from a JSON file.
    /// - Parameter url: URL to the timings JSON file.
    /// - Returns: Array of TimedWord objects.
    static func loadTimings(from url: URL) throws -> [TimedWord] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([TimedWord].self, from: data)
    }

    // MARK: - Voice Management

    struct VoiceList: Codable {
        let voices: [String]
        let downloaded: [String]
    }

    static func listRemoteVoices() throws -> VoiceList {
        guard let scriptURL = resourceBundle().url(forResource: "kokoro_list_remote", withExtension: "py") else {
            throw RunnerError.missingScript
        }

        let environment = ProcessInfo.processInfo.environment
        var arguments: [String] = [scriptURL.path]
        if let repo = environment["KOKORO_REPO"], !repo.isEmpty {
            arguments.append(contentsOf: ["--repo", repo])
        }
        if let revision = environment["KOKORO_REVISION"], !revision.isEmpty {
            arguments.append(contentsOf: ["--revision", revision])
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

        _ = KokoroLogger.log(title: "kokoro_list_remote.py", result: result)

        guard result.exitCode == 0 else {
            throw RunnerError.failedExit(code: result.exitCode, stderr: result.stderr)
        }

        let data = Data(result.stdout.utf8)
        return try JSONDecoder().decode(VoiceList.self, from: data)
    }

    static func downloadVoice(
        _ voice: String,
        update: @escaping @MainActor (String, String) async -> Void
    ) async throws {
        guard let scriptURL = resourceBundle().url(forResource: "kokoro_download_voice", withExtension: "py") else {
            throw RunnerError.missingScript
        }

        let environment = ProcessInfo.processInfo.environment
        var arguments: [String] = [scriptURL.path, "--voice", voice]
        if let repo = environment["KOKORO_REPO"], !repo.isEmpty {
            arguments.append(contentsOf: ["--repo", repo])
        }
        if let revision = environment["KOKORO_REVISION"], !revision.isEmpty {
            arguments.append(contentsOf: ["--revision", revision])
        }

        let pythonURL = venvPythonURL()
        let result: (exitCode: Int32, stdout: String, stderr: String)
        let message = "Downloading \(voice)..."
        if FileManager.default.fileExists(atPath: pythonURL.path) {
            result = runProcessStreamingPTY(message: message, update: update, executable: pythonURL.path, arguments: ["-u"] + arguments)
        } else if let pythonPath = environment["KOKORO_PY"], !pythonPath.isEmpty {
            result = runProcessStreamingPTY(message: message, update: update, executable: pythonPath, arguments: ["-u"] + arguments)
        } else {
            result = runProcessStreamingPTY(message: message, update: update, executable: "/usr/bin/env", arguments: ["python3", "-u"] + arguments)
        }

        _ = KokoroLogger.log(title: "kokoro_download_voice.py", result: result)

        guard result.exitCode == 0 else {
            throw RunnerError.failedExit(code: result.exitCode, stderr: result.stderr)
        }
    }

    static func listVoices(voice: String? = nil, listAll: Bool = false) throws -> [String] {
        guard
            let scriptURL = resourceBundle().url(forResource: "kokoro_voices", withExtension: "py")
        else {
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
            result = ProcessRunner.runPTY(
                executable: "/usr/bin/env", arguments: ["python3"] + arguments)
        }

        _ = KokoroLogger.log(title: "kokoro_voices.py", result: result)

        guard result.exitCode == 0 else {
            throw RunnerError.failedExit(code: result.exitCode, stderr: result.stderr)
        }

        let data = Data(result.stdout.utf8)
        let voices = try JSONDecoder().decode([String].self, from: data)
        return voices
    }

    /// Pre-downloads the model repository to avoid delays during first synthesis.
    /// - Parameters:
    ///   - message: Status message to display during download.
    ///   - update: Callback for progress updates.
    static func prefetchRepo(
        message: String,
        update: @escaping @MainActor (String, String) async -> Void
    ) async throws {
        guard
            let scriptURL = resourceBundle().url(
                forResource: "kokoro_prefetch", withExtension: "py")
        else {
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

    // MARK: - Path Utilities

    /// Returns the application support directory for this app.
    private static func appSupportDir() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        return base.appendingPathComponent(Strings.appSupportFolderName, isDirectory: true)
    }

    /// Returns the path to the Python executable in the virtual environment.
    private static func venvPythonURL() -> URL {
        appSupportDir()
            .appendingPathComponent("venv", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3")
    }

    /// Checks if the virtual environment has already been created.
    static func hasCachedVenv() -> Bool {
        FileManager.default.fileExists(atPath: venvPythonURL().path)
    }

    // MARK: - Process Execution Helpers

    private static func runProcess(executable: String, arguments: [String]) -> (
        exitCode: Int32, stdout: String, stderr: String
    ) {
        ProcessRunner.run(executable: executable, arguments: arguments)
    }

    /// Runs a process with streaming output updates.
    private static func runProcessStreaming(
        message: String,
        update: @escaping @MainActor (String, String) async -> Void,
        executable: String,
        arguments: [String]
    ) -> (exitCode: Int32, stdout: String, stderr: String) {
        // Thread-safe log accumulator
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

    /// Runs a process with PTY and streaming output updates.
    private static func runProcessStreamingPTY(
        message: String,
        update: @escaping @MainActor (String, String) async -> Void,
        executable: String,
        arguments: [String]
    ) -> (exitCode: Int32, stdout: String, stderr: String) {
        // Thread-safe log accumulator
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

    /// Returns the bundle containing Python script resources.
    private static func resourceBundle() -> Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    // MARK: - Test Helpers

    #if DEBUG
    static func appSupportDirForTests() -> URL { appSupportDir() }
    static func venvPythonURLForTests() -> URL { venvPythonURL() }
    static func runProcessForTests(executable: String, arguments: [String]) -> (
        exitCode: Int32, stdout: String, stderr: String
    ) {
        runProcess(executable: executable, arguments: arguments)
    }
    static func decodeVoicesForTests(_ input: String) throws -> [String] {
        let data = Data(input.utf8)
        return try JSONDecoder().decode([String].self, from: data)
    }
    #endif
}
