# SOLID Architecture Guide

A practical guide to applying SOLID principles in Swift and Python development.

---

## Overview

SOLID is an acronym for five design principles that make software more maintainable, testable, and extensible:

| Principle | Acronym | One-Liner |
|-----------|---------|-----------|
| Single Responsibility | SRP | One reason to change |
| Open/Closed | OCP | Open for extension, closed for modification |
| Liskov Substitution | LSP | Subtypes must be substitutable |
| Interface Segregation | ISP | Small, focused interfaces |
| Dependency Inversion | DIP | Depend on abstractions |

---

## 1. Single Responsibility Principle (SRP)

> A class should have one, and only one, reason to change.

### Smell: God Objects

A class that knows too much or does too much.

**Swift Example - Before:**
```swift
// Bad: AppState does everything
class AppState: ObservableObject {
    // State
    @Published var text: String
    @Published var voice: String
    
    // Audio playback
    private var player: AVAudioPlayer?
    func play(url: URL) { ... }
    func stop() { ... }
    
    // Word timing
    private var timer: Timer?
    func startTracking() { ... }
    
    // Environment setup
    func prepareEnvironment() async { ... }
    
    // Voice management
    func downloadVoice(_ name: String) { ... }
    
    // Permissions
    func checkAccessibility() { ... }
}
```

**Swift Example - After:**
```swift
// Good: Separate concerns
class TTSAudioPlayer: AudioPlayable { ... }
class WordTimingTracker: ObservableObject { ... }
class EnvironmentSetupCoordinator { ... }
class VoiceRepository: VoiceRepositoryProviding { ... }

class AppState: ObservableObject {
    private let player: AudioPlayable
    private let tracker: WordTimingTracker
    // Orchestrates, doesn't implement
}
```

**Python Example - Before:**
```python
# Bad: main() does everything
def main():
    args = parse_args()
    download_model()
    pipeline = create_pipeline()
    audio_chunks = []
    word_timings = []
    for result in pipeline(text):
        audio_chunks.append(process_audio(result))
        word_timings.extend(extract_timings(result))
    concatenate_and_save(audio_chunks)
    save_timings(word_timings)
```

**Python Example - After:**
```python
# Good: Separate functions
def extract_word_timings(tokens, offset: float) -> list[dict]: ...
def is_punctuation_only(token) -> bool: ...
def concatenate_audio(chunks: list) -> np.ndarray: ...

def main():
    args = parse_args()
    synthesizer = Synthesizer(args.repo)
    result = synthesizer.synthesize(args.text, args.voice)
    save_output(result)
```

### When to Split

Ask: "What could change independently?"
- UI requirements vs business logic
- Data storage vs data processing
- External API calls vs internal logic

---

## 2. Open/Closed Principle (OCP)

> Software entities should be open for extension, closed for modification.

### Smell: Switch Statements on Type

Adding a new type requires modifying existing code.

**Swift Example - Before:**
```swift
// Bad: Adding a language requires editing this switch
enum Language {
    case english, spanish, french
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        }
    }
}
```

**Swift Example - After:**
```swift
// Good: Data-driven, add without modifying
enum Language: String, CaseIterable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    
    private static let metadata: [Language: LanguageInfo] = [
        .english: LanguageInfo(display: "English", flag: "🇺🇸"),
        .spanish: LanguageInfo(display: "Spanish", flag: "🇪🇸"),
        .french: LanguageInfo(display: "French", flag: "🇫🇷"),
    ]
    
    var displayName: String { Self.metadata[self]!.display }
}
```

**Protocol-Based Extension:**
```swift
// Good: New payment methods don't modify PaymentProcessor
protocol PaymentMethod {
    func pay(amount: Decimal) async throws
}

struct CreditCard: PaymentMethod { ... }
struct ApplePay: PaymentMethod { ... }
struct Crypto: PaymentMethod { ... }  // New! No changes to existing code

class PaymentProcessor {
    func process(_ method: PaymentMethod, amount: Decimal) async throws {
        try await method.pay(amount: amount)
    }
}
```

**Python Example:**
```python
# Good: Add extensions without modifying core
VOICE_EXTENSIONS = (".pt", ".onnx", ".bin")  # Add new format here only

def is_voice_file(filename: str) -> bool:
    return filename.endswith(VOICE_EXTENSIONS)

def voice_patterns_for(voice: str) -> list[str]:
    return [f"voices/{voice}{ext}" for ext in VOICE_EXTENSIONS]
```

---

## 3. Liskov Substitution Principle (LSP)

> Subtypes must be substitutable for their base types.

### Smell: Override That Changes Behavior

Subclass breaks expectations of parent class.

**Swift Example - Before:**
```swift
// Bad: Penguin breaks Bird's contract
class Bird {
    func fly() { print("Flying") }
}

class Penguin: Bird {
    override func fly() {
        fatalError("Penguins can't fly!")  // Violates LSP
    }
}

func makeBirdFly(_ bird: Bird) {
    bird.fly()  // Crashes for Penguin!
}
```

**Swift Example - After:**
```swift
// Good: Separate capabilities
protocol Flyable {
    func fly()
}

class Bird { }

class Eagle: Bird, Flyable {
    func fly() { print("Soaring") }
}

class Penguin: Bird {
    func swim() { print("Swimming") }
}

func makeFly(_ flyer: Flyable) {
    flyer.fly()  // Only accepts things that can fly
}
```

### LSP in Practice

- Don't throw unexpected errors in overrides
- Don't return narrower types than expected
- Don't require stronger preconditions
- Don't weaken postconditions

---

## 4. Interface Segregation Principle (ISP)

> Clients should not be forced to depend on interfaces they don't use.

### Smell: Fat Protocols

Protocol with methods that some conformers don't need.

**Swift Example - Before:**
```swift
// Bad: Robot forced to implement eat()
protocol Worker {
    func work()
    func eat()
    func sleep()
}

struct Robot: Worker {
    func work() { print("Working") }
    func eat() { fatalError("Robots don't eat") }  // Forced stub
    func sleep() { fatalError("Robots don't sleep") }
}
```

**Swift Example - After:**
```swift
// Good: Focused protocols
protocol Workable {
    func work()
}

protocol Feedable {
    func eat()
}

protocol Restable {
    func sleep()
}

struct Human: Workable, Feedable, Restable {
    func work() { ... }
    func eat() { ... }
    func sleep() { ... }
}

struct Robot: Workable {
    func work() { ... }
    // No forced stubs
}
```

**Applied to Views:**
```swift
// Good: Views depend only on what they need
protocol SpeechControlling: ObservableObject {
    var text: String { get set }
    var isRunning: Bool { get }
    func speak()
    func stop()
}

protocol VoiceSelecting: ObservableObject {
    var voice: String { get set }
    var availableVoices: [String] { get }
}

// MainContentView only needs SpeechControlling
// VoicePickerView only needs VoiceSelecting
```

**Python Example:**
```python
# Good: Small, focused protocols (Python 3.8+)
from typing import Protocol

class Synthesizable(Protocol):
    def synthesize(self, text: str) -> bytes: ...

class VoiceListable(Protocol):
    def list_voices(self) -> list[str]: ...

# Implementations can choose which to support
class KokoroEngine:
    def synthesize(self, text: str) -> bytes: ...
    def list_voices(self) -> list[str]: ...

class SimpleEngine:
    def synthesize(self, text: str) -> bytes: ...
    # Doesn't need list_voices
```

---

## 5. Dependency Inversion Principle (DIP)

> High-level modules should not depend on low-level modules. Both should depend on abstractions.

### Smell: Direct Instantiation

Creating concrete dependencies inside a class.

**Swift Example - Before:**
```swift
// Bad: Tight coupling to concrete types
class OrderService {
    let database = CoreDataStore()  // Hard to test
    let api = NetworkClient()       // Hard to mock
    
    func saveOrder(_ order: Order) {
        database.save(order)
        api.sync(order)
    }
}
```

**Swift Example - After:**
```swift
// Good: Depend on abstractions
protocol OrderStorage {
    func save(_ order: Order)
}

protocol OrderSyncing {
    func sync(_ order: Order)
}

class OrderService {
    private let storage: OrderStorage
    private let syncer: OrderSyncing
    
    init(storage: OrderStorage, syncer: OrderSyncing) {
        self.storage = storage
        self.syncer = syncer
    }
    
    func saveOrder(_ order: Order) {
        storage.save(order)
        syncer.sync(order)
    }
}

// Production
let service = OrderService(
    storage: CoreDataStore(),
    syncer: NetworkClient()
)

// Testing
let testService = OrderService(
    storage: MockStorage(),
    syncer: MockSyncer()
)
```

**Python Example - Before:**
```python
# Bad: Direct dependency on huggingface_hub
def download_voice(voice: str):
    from huggingface_hub import hf_hub_download
    hf_hub_download(repo_id="hexgrad/Kokoro-82M", filename=f"voices/{voice}.pt")
```

**Python Example - After:**
```python
# Good: Abstraction allows mocking
from typing import Protocol

class ModelRepository(Protocol):
    def download_file(self, filename: str) -> str: ...

class HuggingFaceRepo:
    def __init__(self, repo_id: str):
        self.repo_id = repo_id
    
    def download_file(self, filename: str) -> str:
        from huggingface_hub import hf_hub_download
        return hf_hub_download(repo_id=self.repo_id, filename=filename)

class MockRepo:
    def __init__(self, files: dict[str, str]):
        self.files = files
    
    def download_file(self, filename: str) -> str:
        return self.files.get(filename, "")

def download_voice(voice: str, repo: ModelRepository):
    return repo.download_file(f"voices/{voice}.pt")
```

### Dependency Injection Patterns

**Constructor Injection (Preferred):**
```swift
class AppState {
    private let player: AudioPlayable
    
    init(player: AudioPlayable = TTSAudioPlayer()) {
        self.player = player
    }
}
```

**Property Injection:**
```swift
class ViewController {
    var dataSource: DataProviding!  // Set before use
}
```

**Method Injection:**
```swift
func process(using processor: DataProcessing) {
    processor.process(data)
}
```

---

## Quick Reference

### Code Smells → Principles

| Smell | Likely Violation |
|-------|-----------------|
| Class > 200 lines | SRP |
| Switch on type | OCP |
| Override throws error | LSP |
| Empty method stubs | ISP |
| `import` inside function | DIP |
| Singleton everywhere | DIP |
| Hard to write unit tests | DIP, SRP |

### Testing Heuristic

If you can't easily test a class in isolation:
1. **Can't create instance?** → DIP violation (inject dependencies)
2. **Too many mocks needed?** → SRP violation (split class)
3. **Test is fragile?** → OCP violation (use protocols)

---

## Related Documents

- [Swift Refactoring Plan](refactor/SOLID-REFACTORING-PLAN.md) - Specific refactoring tasks for Swift code
- [Python Refactoring Plan](refactor/PYTHON-REFACTORING-PLAN.md) - Specific refactoring tasks for Python scripts

---

## Further Reading

- [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html) - Robert C. Martin
- [Protocol-Oriented Programming in Swift](https://developer.apple.com/videos/play/wwdc2015/408/) - WWDC 2015
- [Dependency Injection in Swift](https://www.swiftbysundell.com/articles/dependency-injection-in-swift/) - Swift by Sundell
