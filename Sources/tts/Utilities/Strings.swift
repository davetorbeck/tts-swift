import Foundation

/// Centralized string constants for the TTS application.
/// Keeps user-facing messages and status strings in one place for easy maintenance.
enum Strings {
    // MARK: - Default Values
    static let defaultText = "Hello from Kokoro."

    // MARK: - Setup States
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

    // MARK: - Synthesis States
    static let synthesizing = "Synthesizing…"
    static let playingAudio = "Playing audio"

    // MARK: - Error Messages
    static let failedToPlayAudioPrefix = "Failed to play audio: "
    static let synthesisFailedPrefix = "Synthesis failed: "
    static let failedToLoadVoicesPrefix = "Failed to load voices: "
    static let missingScript = "Missing bundled kokoro_say.py script."
    static let kokoroFailedExitPrefix = "Kokoro process failed (exit "
    static let missingOutput = "Kokoro did not produce output audio."
    static let uvVenvFailedPrefix = "uv venv failed. Install uv with: brew install uv\n"
    static let uvPipFailedPrefix = "uv pip install failed.\n"

    // MARK: - Accessibility
    static let accessibilityNotChecked = "Accessibility not checked"

    // MARK: - App Configuration
    static let appSupportFolderName = "tts-swift"
}
