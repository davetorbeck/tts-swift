# SOLID Refactoring Plan for tts-swift

This document outlines a phased approach to applying SOLID principles to the tts-swift codebase.

---

## Task List

### Phase 1: Extract Audio Playback (SRP) - High Priority
- [ ] Create `Sources/tts/Audio/` directory
- [ ] Create `AudioPlayable` protocol
- [ ] Create `TTSAudioPlayer` implementation
- [ ] Inject into `AppState`
- [ ] Update `speak()`, `stop()`, `startPlaybackTracking()`
- [ ] Create `MockAudioPlayer` for testing

### Phase 2: Extract Word Timing Tracker (SRP) - High Priority
- [ ] Create `WordTimingTracker` class
- [ ] Inject into `AppState`
- [ ] Remove `playbackTimer` and `startPlaybackTracking()` from `AppState`
- [ ] Update views to observe `WordTimingTracker` if needed

### Phase 3: Create Protocols for KokoroRunner (DIP) - High Priority
- [ ] Create `Sources/tts/Protocols/` directory
- [ ] Define `TTSEnvironmentProviding` protocol
- [ ] Define `TTSSynthesizing` protocol
- [ ] Define `VoiceRepositoryProviding` protocol
- [ ] Create `KokoroEnvironment` wrapper
- [ ] Create `KokoroSynthesizer` wrapper
- [ ] Create `KokoroVoiceRepository` wrapper
- [ ] Update `AppState` to accept protocol dependencies
- [ ] Create mock implementations for testing

### Phase 4: Extract Output Window Controller (DIP) - Medium Priority
- [ ] Create `OutputWindowControlling` protocol
- [ ] Make `FloatingOutputWindow` conform
- [ ] Inject into `AppState`
- [ ] Create `MockOutputWindowController` for testing

### Phase 5: Extract Text Provider (DIP) - Medium Priority
- [ ] Create `TextProviding` protocol
- [ ] Make `SelectedTextProvider` conform
- [ ] Inject into `AppState`

### Phase 6: Interface Segregation for Views (ISP) - Low Priority
- [ ] Define focused protocols (`SpeechControlling`, `PlaybackObserving`, etc.)
- [ ] Make `AppState` conform to each
- [ ] Update views to use protocol types
- [ ] Evaluate if complexity is worth it

### Phase 7: Setup Coordinator Extraction (SRP) - Low Priority
- [ ] Create `EnvironmentSetupCoordinator`
- [ ] Move `startBackgroundSetup()` logic
- [ ] Inject coordinator into `AppState`
- [ ] Update views that observe setup state

### Unit Tests (Non-Trivial Logic)
- [ ] `WordTimingTrackerTests` - time range matching, index updates, edge cases
- [ ] `FlowLayoutTests` - line wrapping calculations, sizing edge cases
- [ ] `KokoroLoggerTests` - format output with various inputs
- [ ] `TimedWordDecodingTests` - JSON parsing edge cases
- [ ] `PythonExecutableSelectionTests` - env var / venv / system fallback chain
- [ ] `SetupStateTransitionTests` - state machine transitions

### Success Criteria
- [ ] `AppState` under 150 lines
- [ ] All external dependencies injected via protocols
- [ ] Unit tests for word timing tracker
- [ ] Unit tests for synthesis orchestration
- [ ] No direct `KokoroRunner` calls from `AppState`
- [ ] No singleton access except at composition root

---

## Current State Analysis

### Key Files and Responsibilities

| File | Current Responsibilities | Lines |
|------|-------------------------|-------|
| `AppState.swift` | State, playback, shortcuts, permissions, setup, synthesis | 334 |
| `KokoroRunner.swift` | Environment, synthesis, voices, paths, process helpers | 488 |
| `AppDelegate.swift` | Window management, lifecycle, permissions | 63 |
| `FloatingOutputWindow.swift` | Window creation, content management | 98 |
| `ProcessRunner.swift` | Process execution (well-focused) | 227 |

---

## Phase 1: Extract Audio Playback (SRP)

**Goal:** Remove audio playback responsibility from `AppState`.

**Priority:** High  
**Effort:** Low  
**Impact:** Enables testing, cleaner separation

### New File: `Sources/tts/Audio/AudioPlayer.swift`

```swift
import AVFoundation

protocol AudioPlayable {
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
```

### Changes to `AppState.swift`

```swift
// Before
private var player: AVAudioPlayer?

// After
private let audioPlayer: AudioPlayable

init(audioPlayer: AudioPlayable = TTSAudioPlayer()) {
    self.audioPlayer = audioPlayer
}
```

### Tasks

- [ ] Create `Sources/tts/Audio/` directory
- [ ] Create `AudioPlayable` protocol
- [ ] Create `TTSAudioPlayer` implementation
- [ ] Inject into `AppState`
- [ ] Update `speak()`, `stop()`, `startPlaybackTracking()`
- [ ] Create `MockAudioPlayer` for testing

---

## Phase 2: Extract Word Timing Tracker (SRP)

**Goal:** Separate playback tracking from `AppState`.

**Priority:** High  
**Effort:** Low  
**Impact:** Testable timing logic

### New File: `Sources/tts/Audio/WordTimingTracker.swift`

```swift
import Foundation
import Combine

@MainActor
final class WordTimingTracker: ObservableObject {
    @Published private(set) var currentWordIndex: Int?
    
    private var timings: [TimedWord] = []
    private var timer: Timer?
    private weak var audioPlayer: AudioPlayable?
    
    func start(timings: [TimedWord], audioPlayer: AudioPlayable) {
        self.timings = timings
        self.audioPlayer = audioPlayer
        self.currentWordIndex = timings.isEmpty ? nil : 0
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateCurrentWord()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        timings = []
        currentWordIndex = nil
    }
    
    private func updateCurrentWord() {
        guard let player = audioPlayer else { return }
        let currentTime = player.currentTime
        
        for (index, timing) in timings.enumerated() {
            if currentTime >= timing.start && currentTime < timing.end {
                if currentWordIndex != index {
                    currentWordIndex = index
                }
                return
            }
        }
    }
}
```

### Tasks

- [ ] Create `WordTimingTracker` class
- [ ] Inject into `AppState`
- [ ] Remove `playbackTimer` and `startPlaybackTracking()` from `AppState`
- [ ] Update views to observe `WordTimingTracker` if needed

---

## Phase 3: Create Protocols for KokoroRunner (DIP)

**Goal:** Abstract `KokoroRunner` behind protocols for testability.

**Priority:** High  
**Effort:** Medium  
**Impact:** Enables mocking, future TTS engines

### New File: `Sources/tts/Protocols/TTSProtocols.swift`

```swift
import Foundation

// MARK: - Environment

protocol TTSEnvironmentProviding {
    func prepare(onProgress: @escaping @MainActor (String, String) async -> Void) async throws
    var isReady: Bool { get }
}

// MARK: - Synthesis

struct SynthesisResult {
    let audioURL: URL
    let timingsURL: URL
}

protocol TTSSynthesizing {
    func synthesize(text: String, voice: String, language: String) throws -> SynthesisResult
    func loadTimings(from url: URL) throws -> [TimedWord]
}

// MARK: - Voice Management

struct VoiceList {
    let available: [String]
    let downloaded: [String]
}

protocol VoiceRepositoryProviding {
    func listRemote() throws -> VoiceList
    func download(_ voice: String, onProgress: @escaping @MainActor (String, String) async -> Void) async throws
}
```

### New File: `Sources/tts/Runner/KokoroEnvironment.swift`

```swift
import Foundation

struct KokoroEnvironment: TTSEnvironmentProviding {
    var isReady: Bool {
        KokoroRunner.hasCachedVenv()
    }
    
    func prepare(onProgress: @escaping @MainActor (String, String) async -> Void) async throws {
        try await KokoroRunner.prepareEnvironment(onProgress)
    }
}
```

### New File: `Sources/tts/Runner/KokoroSynthesizer.swift`

```swift
import Foundation

struct KokoroSynthesizer: TTSSynthesizing {
    func synthesize(text: String, voice: String, language: String) throws -> SynthesisResult {
        let (audioURL, timingsURL) = try KokoroRunner.synthesize(
            text: text,
            voice: voice,
            language: language
        )
        return SynthesisResult(audioURL: audioURL, timingsURL: timingsURL)
    }
    
    func loadTimings(from url: URL) throws -> [TimedWord] {
        try KokoroRunner.loadTimings(from: url)
    }
}
```

### New File: `Sources/tts/Runner/KokoroVoiceRepository.swift`

```swift
import Foundation

struct KokoroVoiceRepository: VoiceRepositoryProviding {
    func listRemote() throws -> VoiceList {
        let result = try KokoroRunner.listRemoteVoices()
        return VoiceList(available: result.voices, downloaded: result.downloaded)
    }
    
    func download(_ voice: String, onProgress: @escaping @MainActor (String, String) async -> Void) async throws {
        try await KokoroRunner.downloadVoice(voice, update: onProgress)
    }
}
```

### Updated `AppState` Constructor

```swift
@MainActor
final class AppState: NSObject, ObservableObject {
    // Dependencies
    private let audioPlayer: AudioPlayable
    private let environment: TTSEnvironmentProviding
    private let synthesizer: TTSSynthesizing
    private let voiceRepository: VoiceRepositoryProviding
    
    init(
        audioPlayer: AudioPlayable = TTSAudioPlayer(),
        environment: TTSEnvironmentProviding = KokoroEnvironment(),
        synthesizer: TTSSynthesizing = KokoroSynthesizer(),
        voiceRepository: VoiceRepositoryProviding = KokoroVoiceRepository()
    ) {
        self.audioPlayer = audioPlayer
        self.environment = environment
        self.synthesizer = synthesizer
        self.voiceRepository = voiceRepository
        super.init()
        // ... keyboard shortcut setup
    }
}
```

### Tasks

- [ ] Create `Sources/tts/Protocols/` directory
- [ ] Define `TTSEnvironmentProviding` protocol
- [ ] Define `TTSSynthesizing` protocol
- [ ] Define `VoiceRepositoryProviding` protocol
- [ ] Create `KokoroEnvironment` wrapper
- [ ] Create `KokoroSynthesizer` wrapper
- [ ] Create `KokoroVoiceRepository` wrapper
- [ ] Update `AppState` to accept protocol dependencies
- [ ] Create mock implementations for testing

---

## Phase 4: Extract Output Window Controller (DIP)

**Goal:** Abstract `FloatingOutputWindow` behind a protocol.

**Priority:** Medium  
**Effort:** Low  
**Impact:** Testable, decoupled

### Protocol Definition

```swift
@MainActor
protocol OutputWindowControlling {
    func show()
    func hide()
    var isVisible: Bool { get }
}

extension FloatingOutputWindow: OutputWindowControlling {
    // Already has show(), hide(), isVisible
}
```

### Tasks

- [ ] Create `OutputWindowControlling` protocol
- [ ] Make `FloatingOutputWindow` conform
- [ ] Inject into `AppState`
- [ ] Create `MockOutputWindowController` for testing

---

## Phase 5: Extract Text Provider (DIP)

**Goal:** Abstract `SelectedTextProvider` for testability.

**Priority:** Medium  
**Effort:** Low  
**Impact:** Testable hotkey behavior

### Protocol Definition

```swift
protocol TextProviding {
    func getSelectedText() -> String?
}

extension SelectedTextProvider: TextProviding {
    // Already has getSelectedText()
}

// For testing
struct MockTextProvider: TextProviding {
    var textToReturn: String?
    
    func getSelectedText() -> String? {
        textToReturn
    }
}
```

### Tasks

- [ ] Create `TextProviding` protocol
- [ ] Make `SelectedTextProvider` conform (it's already an enum with static method, may need adjustment)
- [ ] Inject into `AppState`

---

## Phase 6: Interface Segregation for Views (ISP)

**Goal:** Views depend only on what they need.

**Priority:** Low  
**Effort:** Medium  
**Impact:** Type safety, clearer contracts

### Protocol Definitions

```swift
// For MainContentView
protocol SpeechControlling: ObservableObject {
    var text: String { get set }
    var isRunning: Bool { get }
    var status: String { get }
    func speak()
    func stop()
}

// For FloatingOutputContent
protocol PlaybackObserving: ObservableObject {
    var wordTimings: [TimedWord] { get }
    var currentWordIndex: Int? { get }
}

// For VoicePickerView
protocol VoiceSelecting: ObservableObject {
    var voice: String { get set }
    var availableVoices: [String] { get }
    var downloadedVoices: Set<String> { get }
    var isDownloadingVoice: Bool { get }
    func downloadVoice(_ name: String)
}

// For SettingsDetailView
protocol SettingsProviding: ObservableObject {
    var alwaysOnTop: Bool { get set }
    var language: KokoroLanguage { get set }
    var setupState: SetupState { get }
    var permissionStatus: String { get }
}
```

### Tasks

- [ ] Define focused protocols
- [ ] Make `AppState` conform to each
- [ ] Update views to use protocol types (requires existential `any` or generics)
- [ ] Consider if complexity is worth it for this codebase size

---

## Phase 7: Setup Coordinator Extraction (SRP)

**Goal:** Move setup orchestration out of `AppState`.

**Priority:** Low  
**Effort:** Medium  
**Impact:** Cleaner `AppState`, reusable setup logic

### New File: `Sources/tts/Setup/EnvironmentSetupCoordinator.swift`

```swift
@MainActor
final class EnvironmentSetupCoordinator: ObservableObject {
    @Published private(set) var state: SetupState = .idle
    @Published private(set) var log: String = ""
    @Published private(set) var isSettingUp: Bool = false
    
    private let environment: TTSEnvironmentProviding
    private let voiceRepository: VoiceRepositoryProviding
    
    init(
        environment: TTSEnvironmentProviding = KokoroEnvironment(),
        voiceRepository: VoiceRepositoryProviding = KokoroVoiceRepository()
    ) {
        self.environment = environment
        self.voiceRepository = voiceRepository
    }
    
    func startBackgroundSetup() async -> Result<VoiceList, Error> {
        // Move logic from AppState.startBackgroundSetup()
    }
}
```

### Tasks

- [ ] Create `EnvironmentSetupCoordinator`
- [ ] Move `startBackgroundSetup()` logic
- [ ] Inject coordinator into `AppState` or use as separate observable
- [ ] Update views that observe setup state

---

## Implementation Order

```
Phase 1 ──► Phase 2 ──► Phase 3 ──► Phase 4
   │                       │           │
   │                       │           │
   ▼                       ▼           ▼
Testing              Testing      Testing
Audio                Synthesis    Window
Playback             Logic        Display

Phase 5 ──► Phase 6 ──► Phase 7
   │           │           │
   ▼           ▼           ▼
Testing    Optional    Optional
Hotkey     (evaluate   (evaluate
Behavior   need)       need)
```

---

## File Structure After Refactoring

```
Sources/tts/
├── App/
│   ├── app.swift
│   ├── AppDelegate.swift
│   └── AppState.swift (slimmed down)
├── Audio/
│   ├── AudioPlayer.swift
│   └── WordTimingTracker.swift
├── Models/
│   └── TimedWord.swift
├── Protocols/
│   └── TTSProtocols.swift
├── Runner/
│   ├── KokoroRunner.swift (internal implementation)
│   ├── KokoroEnvironment.swift
│   ├── KokoroSynthesizer.swift
│   └── KokoroVoiceRepository.swift
├── Setup/
│   └── EnvironmentSetupCoordinator.swift
├── Utilities/
│   ├── HUDWindow.swift
│   ├── KeyboardShortcutNames.swift
│   ├── SelectedTextProvider.swift
│   └── Strings.swift
├── Views/
│   ├── ContentView.swift
│   ├── FlowLayout.swift
│   ├── HighlightedTextView.swift
│   ├── MainContentView.swift
│   ├── MenuBarView.swift
│   ├── SettingsDetailView.swift
│   ├── SidebarView.swift
│   └── VoicePickerView.swift
├── Windows/
│   └── FloatingOutputWindow.swift
├── KokoroLogger.swift
└── ProcessRunner.swift
```

---

## Testing Strategy

After each phase, create corresponding test files:

```
Tests/ttsTests/
├── Audio/
│   ├── TTSAudioPlayerTests.swift
│   └── WordTimingTrackerTests.swift
├── Mocks/
│   ├── MockAudioPlayer.swift
│   ├── MockSynthesizer.swift
│   ├── MockVoiceRepository.swift
│   └── MockTextProvider.swift
├── Runner/
│   └── KokoroSynthesizerTests.swift
└── AppStateTests.swift
```

---

## Success Criteria

- [ ] `AppState` under 150 lines
- [ ] All external dependencies injected via protocols
- [ ] Unit tests for audio playback logic
- [ ] Unit tests for word timing tracker
- [ ] Unit tests for synthesis orchestration
- [ ] No direct `KokoroRunner` calls from `AppState`
- [ ] No singleton access except at composition root (`app.swift`)

---

## Notes

- Phases 1-5 provide the most value for testability
- Phases 6-7 are optional and may add unnecessary complexity for a small app
- Keep `KokoroRunner` as internal implementation detail behind protocols
- Use Swift's default parameter values for easy migration (existing code keeps working)

---

## Unit Testing Analysis

### Worth Testing (Non-Trivial Logic)

| Component | Location | Why Test | Test Cases |
|-----------|----------|----------|------------|
| **Word Timing Tracker** | `AppState.swift:284-306` | Time-based index lookup with edge cases | Time before first word, between words, after last word, exact boundaries, empty timings |
| **FlowLayout sizing** | `FlowLayout.swift:10-31` | Layout math with wrapping logic | Single item, exact fit, wrap needed, empty subviews, very wide item |
| **FlowLayout placement** | `FlowLayout.swift:33-54` | Coordinate calculations | Verify x/y positions after wraps, spacing applied correctly |
| **KokoroLogger.format** | `KokoroLogger.swift:18-32` | String assembly with conditionals | Empty stdout, empty stderr, both empty, both present, various exit codes |
| **TimedWord decoding** | `KokoroRunner.swift:182-185` | JSON parsing | Valid JSON, missing fields, extra fields, empty array, malformed JSON |
| **VoiceList decoding** | `KokoroRunner.swift:224-226` | JSON parsing | Valid response, empty lists, missing keys |
| **Python executable selection** | `KokoroRunner.swift:148-161` | Priority chain logic | KOKORO_PY set, venv exists, fallback to system |
| **SetupState transitions** | `AppState.swift:214-269` | State machine correctness | Happy path, failure at each stage, cached venv skip |

### NOT Worth Testing (Trivial/Obvious)

| Component | Location | Why Skip |
|-----------|----------|----------|
| `Strings` constants | `Strings.swift` | Just string literals, no logic |
| `TimedWord` struct | `TimedWord.swift` | Pure data container, Codable is tested by decoding tests |
| `KokoroLanguage.displayName` | `AppState.swift:20-33` | Simple switch, obvious mapping |
| Property getters/setters | Various | No transformation logic |
| `appSupportDir()` path | `KokoroRunner.swift:371-375` | Already tested, just path construction |
| Keyboard shortcut names | `TTSTests.swift:15-52` | Already tested, borderline trivial |
| View body composition | `*View.swift` | Test via UI/snapshot tests if needed |
| `hasCachedVenv()` | `KokoroRunner.swift:386-388` | Just `FileManager.fileExists` wrapper |

### Recommended Test Structure

```
Tests/ttsTests/
├── Audio/
│   └── WordTimingTrackerTests.swift
├── Layout/
│   └── FlowLayoutTests.swift
├── Runner/
│   ├── TimedWordDecodingTests.swift
│   ├── VoiceListDecodingTests.swift
│   └── PythonExecutableSelectionTests.swift
├── Logging/
│   └── KokoroLoggerTests.swift
├── Mocks/
│   ├── MockAudioPlayer.swift
│   ├── MockSynthesizer.swift
│   └── MockVoiceRepository.swift
└── TTSTests.swift (existing)
```

### Example Test Cases

#### WordTimingTrackerTests

```swift
final class WordTimingTrackerTests: XCTestCase {
    
    func testReturnsNilForEmptyTimings() {
        let tracker = WordTimingTracker()
        let result = tracker.indexForTime(0.5, in: [])
        XCTAssertNil(result)
    }
    
    func testReturnsFirstWordWhenTimeInRange() {
        let timings = [
            TimedWord(word: "Hello", start: 0.0, end: 0.5),
            TimedWord(word: "world", start: 0.5, end: 1.0)
        ]
        let result = tracker.indexForTime(0.25, in: timings)
        XCTAssertEqual(result, 0)
    }
    
    func testReturnsNilWhenTimeBetweenWords() {
        // If there's a gap between words
        let timings = [
            TimedWord(word: "Hello", start: 0.0, end: 0.4),
            TimedWord(word: "world", start: 0.6, end: 1.0)
        ]
        let result = tracker.indexForTime(0.5, in: timings)
        XCTAssertNil(result) // or handle gap differently
    }
    
    func testExactBoundaryBelongsToCurrentWord() {
        let timings = [
            TimedWord(word: "Hello", start: 0.0, end: 0.5),
            TimedWord(word: "world", start: 0.5, end: 1.0)
        ]
        // start is inclusive, end is exclusive
        XCTAssertEqual(tracker.indexForTime(0.5, in: timings), 1)
    }
}
```

#### FlowLayoutTests

```swift
final class FlowLayoutTests: XCTestCase {
    
    func testSingleItemFitsWithinWidth() {
        // Item width 50, container width 100
        // Should not wrap, height = item height
    }
    
    func testItemWrapsWhenExceedingWidth() {
        // Two items of width 60 each, container width 100
        // Second item should wrap to next line
    }
    
    func testSpacingAppliedBetweenItems() {
        // Verify spacing is added horizontally and vertically
    }
    
    func testEmptySubviewsReturnsZeroHeight() {
        // No subviews = zero height
    }
}
```

#### KokoroLoggerTests

```swift
final class KokoroLoggerTests: XCTestCase {
    
    func testFormatWithBothOutputs() {
        let result = KokoroLogger.format(
            title: "test",
            result: (exitCode: 0, stdout: "out", stderr: "err")
        )
        XCTAssertTrue(result.contains("test (exit 0)"))
        XCTAssertTrue(result.contains("stdout:"))
        XCTAssertTrue(result.contains("stderr:"))
    }
    
    func testFormatOmitsEmptyStdout() {
        let result = KokoroLogger.format(
            title: "test",
            result: (exitCode: 1, stdout: "", stderr: "error")
        )
        XCTAssertFalse(result.contains("stdout:"))
        XCTAssertTrue(result.contains("stderr:"))
    }
    
    func testFormatOmitsEmptyStderr() {
        let result = KokoroLogger.format(
            title: "test",
            result: (exitCode: 0, stdout: "output", stderr: "")
        )
        XCTAssertTrue(result.contains("stdout:"))
        XCTAssertFalse(result.contains("stderr:"))
    }
    
    func testFormatWithWhitespaceOnlyIsTreatedAsEmpty() {
        let result = KokoroLogger.format(
            title: "test",
            result: (exitCode: 0, stdout: "  \n  ", stderr: "\t\n")
        )
        // Whitespace-only should be treated as empty
        XCTAssertFalse(result.contains("stdout:"))
        XCTAssertFalse(result.contains("stderr:"))
    }
}
```

### Testing Priority

1. **High**: `WordTimingTracker` - Core user-facing feature, timing bugs are noticeable
2. **High**: `FlowLayout` - Layout bugs cause visual issues, math-heavy
3. **Medium**: JSON decoding - Data integrity, catches API changes
4. **Medium**: `KokoroLogger.format` - Easy to test, documents expected format
5. **Low**: Python executable selection - Requires mocking FileManager, less value
