# First-Launch Voice Download UX

## Context

Today the app:

- Prepares the Python environment on launch.
- Prefetches the Hugging Face model repo to reduce first-synthesis latency.
- Loads the available voice list and which voices are already downloaded.
- Downloads individual voice files only when the user selects a voice that is not downloaded.

This works, but the "first-run" experience can feel confusing because a new user may not understand:

- Why speaking might be slow or fail the first time.
- That voices are separate downloads.
- What they should do to "get to a working voice" as quickly as possible.

## Problem Statement

On a fresh install with an empty Hugging Face cache, a user should be able to:

1. Understand what's happening during initial setup.
2. Download a voice with clear progress and retry semantics.
3. Start speaking as soon as a single voice is ready.

## Goals

- Fast path to first successful speech (one click, minimal waiting).
- No mystery failures: if a voice is missing, the UI guides the user to fix it.
- Clear progress and status while downloading.
- Safe defaults that don't surprise users with large downloads.

## Non-Goals

- Bulk downloading all voices.
- Fancy discovery/recommendation systems (ratings, previews, etc.).
- Replacing the existing model prefetch step.

---

## UX Research: Best Practices

Sources: Nielsen Norman Group, Google Material Design (Offline), Apple On-Demand Resources, Android Play Feature Delivery.

### Progress Indicator Timing (NN/g)

| Duration | Indicator Type | Notes |
|----------|----------------|-------|
| < 1 second | None | Animation is distracting |
| 1-2 seconds | Immediate feedback | Button state change, subtle animation |
| 2-10 seconds | Looped animation (spinner) | Add text explaining what's happening |
| > 10 seconds | Percent-done bar | Show time estimate or steps remaining |

**Key insight**: Users wait 3x longer when shown a progress indicator vs. no feedback at all.

### What to Show During Download

1. **Immediate feedback** - the moment user taps, change button state or show spinner.
2. **Text label** - e.g. "Downloading voice..." (never just a spinner alone).
3. **File size** - helps users on metered connections decide whether to proceed (Google Offline Design).
4. **Time or steps remaining** - for downloads > 10 seconds, show "~30 seconds" or "Step 2 of 3".
5. **Cancel / Pause option** - give users an escape hatch for long downloads.
6. **Completion confirmation** - "Voice downloaded - Ready to speak."

### Error & Retry Patterns

- **Explain why** - "Download failed: no internet connection" beats generic "Error".
- **Offer clear action** - Retry button, or option to choose a different voice.
- **Don't block the app** - let users continue browsing while retry is pending.

### Anticipating User Needs (Android)

- **Predict intent** - if user is about to need a resource, start downloading before they ask.
- **Background install** - download while user does other things, notify when ready.
- **Deferred install** - for non-urgent content, queue download for later (e.g. when on Wi-Fi).

For our app: consider starting voice download as soon as user opens Voice Picker (before they tap a specific voice), if we can predict which voice they'll pick (e.g. their last-used voice, or the recommended default).

### Download Patterns (Apple ODR)

| Pattern | Example | Design Approach |
|---------|---------|-----------------|
| Random access | Browsing app | Many small tags, progressive loading |
| Limited prediction | Open-world game | Load subset based on current state |
| Linear progression | Level-based game | Download in advance, free old resources |

For our app: **Limited prediction** - we can predict the user's next likely voice (default or last-used) and prefetch it.

### First-Run Download UX (Android)

- **Explain value before large downloads** - "Download this voice to start speaking" is better than a silent download.
- **Small downloads (< 10 MB)**: spinner + brief message.
- **Larger downloads**: progress bar + estimated time.
- **Don't hijack context** - when download completes, notify and let user decide when to switch.

### Anti-Patterns to Avoid

| Don't | Why |
|-------|-----|
| Static "Loading..." text with no animation | Users can't tell if app is frozen |
| "Don't click again" warnings | Users don't read them; provide feedback instead |
| Silent failures | User has no idea what went wrong or what to do |
| Forced wait with no escape | Always offer Cancel for long operations |
| Spinner for > 10 seconds | Users lose faith; use percent-done instead |

---

## Proposed UX

### UX Principle: "Download one voice, then you're unblocked"

Treat "having at least one downloaded voice" as the key milestone for first-run success.

### Revised First-Launch Flow

```
+------------------------------------------------------------------+
| App Launch                                                       |
+------------------------------------------------------------------+
| 1. Create venv       [spinner + "Creating Python environment..."]|
| 2. Install deps      [spinner + "Installing dependencies..."]   |
| 3. Prefetch model    [progress bar + "Downloading model..."]    |
| 4. Load voice list   [spinner + "Loading voices..."]            |
| 5. Prefetch default voice (background, optional)                |
|    - If enabled: "Downloading recommended voice..."             |
|    - On complete: status bar shows "Ready"                      |
+------------------------------------------------------------------+
| If no voice downloaded after step 4:                            |
|   Show callout: "Download a voice to get started"               |
|   [Download Recommended] [Choose Voice...]                       |
+------------------------------------------------------------------+
```

### First Launch (no voices downloaded)

When `downloadedVoices` is empty after setup completes:

- Show a prominent callout at the top of the Voices screen:
  - Title: "Download a voice to get started"
  - Primary CTA: "Download Recommended Voice"
  - Secondary CTA: "Choose a different voice..."
  - Optional tertiary: "Skip for now" (keeps UI usable but makes it clear speaking requires a voice)

Recommended voice:

- Default to the current default voice (e.g. `af_heart`) unless a better "starter voice" is chosen.
- If voice descriptions are added later, display a human-friendly name (e.g. "Heart (US English)") while preserving the internal id.

### Voice Download States (per-voice)

| State | UI |
|-------|-----|
| Not downloaded | Cloud-download icon |
| Downloading | Spinner + "Downloading..." + Cancel button |
| Downloaded | Green checkmark |
| Failed | Red exclamation + "Retry" |

### Voice Picker Behavior

In the voice picker menu:

- Keep showing downloaded vs not-downloaded indicators.
- When a not-downloaded voice is selected:
  - Start download immediately.
  - Keep the UI responsive.
  - Show a clear "downloading" state (spinner + text) for that specific voice.
  - Do not silently switch voices until download succeeds.

### Speak Button States

| Condition | Button Label | Behavior |
|-----------|--------------|----------|
| Voice downloaded, ready | "Speak" | Synthesize immediately |
| Voice not downloaded | "Speak" | Auto-download, then synthesize |
| Downloading in progress | "Downloading..." (disabled) | Wait for download |
| Download failed | "Retry Download" | Retry, then synthesize |

If the user tries to speak and the selected voice is not downloaded:

- Do not fail with a generic "synthesis failed".
- Instead:
  - Trigger the voice download.
  - Show status: "Downloading voice <voice>..."
  - Disable Speak (or change it to "Downloading...").
  - Automatically start synthesis after download completes.

This makes "press Speak" a valid first-run path even if the user never visits the Voices screen.

### Download Progress and Copy

Progress should be visible in at least one place (preferably two):

- Global status area: high-level status ("Downloading voice...", "Downloaded", "Retry").
- Voice row / picker: voice-specific state (so the user sees which voice is being downloaded).

Suggested copy:

- "Downloading recommended voice..."
- "Downloading <voice>..."
- "Download failed - Check your connection and retry."
- "Voice downloaded - Ready to speak."

### Retry and Error Handling

Common failure cases:

- Offline / captive portal
- Hugging Face rate limit
- Partial/corrupted cache

UX requirements:

- Surface a clear error message and a Retry action.
- Allow the user to switch to a different voice after a failure.
- If the model repo prefetch fails but voice download could still work (or vice versa), present the most useful next action instead of a single "setup failed" state.

---

## Recommended Implementation Changes

1. **Show file size next to voice name** (optional, if available from HF API).
2. **Use spinner + text for voice downloads < 10 seconds** - "Downloading af_heart..."
3. **Add Cancel button** for voice downloads.
4. **On completion, show confirmation** - "Voice ready" with checkmark.
5. **On failure, show Retry + explanation** - "Download failed. Check your connection."
6. **Prefetch default voice** in background after model prefetch completes (anticipate need).
7. **Notify, don't hijack** - when prefetch completes, update status bar; don't force user into a modal.

---

## Implementation Notes

### Where the logic lives

- Voice list and download orchestration currently lives in `AppState` + `VoiceRepositoryProviding`.
- Voice downloads already stream progress messages.

### Minimal incremental steps

1. Detect first-run "no voices downloaded" state.
2. Add a callout UI in the Voices screen.
3. Add a voice-specific "downloading" state presentation.
4. Make Speak auto-trigger download if needed, then continue.

---

## Acceptance Criteria

- Fresh install: user can get to first speech with a single obvious action.
- Selecting an undownloaded voice shows a visible downloading state until completion.
- Pressing Speak with an undownloaded voice triggers download and then speaks.
- Failures show a Retry path without requiring app restart.

---

## Open Questions

- Should we auto-download the recommended voice as part of background setup, or always require an explicit click?
- What is the best "starter voice" in terms of size/quality across languages?
- Should we add an opt-in setting: "Auto-download recommended voice on first launch"? (default off)
- Which 5 English voices should be in the starter pack? Criteria: quality, variety (US/UK, male/female), size.

---

## Decision: Starter Voice Pack

**Only offer 5 English voices on first launch.**

### Rationale

- Reduces decision paralysis for new users (paradox of choice).
- Faster time-to-first-speech.
- English covers the majority of initial users.
- Users who want other languages can browse the full catalog later.

### Proposed Starter Voices (Based on Kokoro Quality Grades)

| Voice ID | Display Name | Grade | Why |
|----------|--------------|-------|-----|
| `af_heart` | Heart - American Female | **A** | Best overall, current default |
| `af_bella` | Bella - American Female | A- | Second best, variety |
| `bf_emma` | Emma - British Female | B- | Best British female |
| `am_fenrir` | Fenrir - American Male | C+ | Best American male |
| `bm_george` | George - British Male | C | Best British male |

*Selection based on Overall Grade from Kokoro's VOICES.md. Users only see display names, never voice IDs.*

### Voice Descriptions (Important)

**Never show voice codes (e.g. `af_heart`) to users.** Only display human-readable information:

- **Name** - e.g. "Heart", "Emma", "Adam"
- **Nationality/Accent** - e.g. "American", "British"
- **Gender** - e.g. "Female", "Male"

| Internal Code | User Sees |
|---------------|-----------|
| `af_heart` | Heart - American Female |
| `af_sky` | Sky - American Female |
| `am_adam` | Adam - American Male |
| `bf_emma` | Emma - British Female |
| `bm_george` | George - British Male |

Voice codes are internal identifiers only - they should never appear in the UI.

### Data Source: Kokoro VOICES.md

Kokoro publishes voice metadata at: `https://huggingface.co/hexgrad/Kokoro-82M/raw/main/VOICES.md`

Available data per voice:
- **Name** (e.g., `af_heart`, `bf_emma`)
- **Traits** (emoji: 🚺 Female, 🚹 Male, special: ❤️🔥🎧)
- **Overall Grade** (A, A-, B-, C+, C, D, F+, etc.)

Example from VOICES.md:
| Name | Traits | Overall Grade |
|------|--------|---------------|
| af_heart | 🚺❤️ | **A** |
| af_bella | 🚺🔥 | A- |
| bf_emma | 🚺 | B- |
| am_fenrir | 🚹 | C+ |

**Recommendation**: Parse VOICES.md at build time or fetch on first launch to populate voice descriptions. Fallback to ID parsing if unavailable.

### UX for Starter Pack

- First launch shows only the 5 English starter voices in the picker.
- "Show all voices" link/button reveals the full catalog (all languages).
- After first voice is downloaded, user is unblocked; remaining 4 stay available but not auto-downloaded.

---

## Code Examples

### Starter Voices & Descriptions

```swift
// VoiceMetadata.swift
struct VoiceInfo: Codable {
    let id: String
    let name: String
    let nationality: String
    let gender: Gender
    let grade: String?  // From Kokoro VOICES.md (A, B-, C+, etc.)
    
    enum Gender: String, Codable {
        case female, male
    }
    
    var displayName: String {
        name.capitalized
    }
    
    var description: String {
        "\(nationality) \(gender == .female ? "Female" : "Male")"
    }
}

enum VoiceMetadata {
    // Best English voices based on Kokoro's quality grades
    static let starterVoices: [VoiceInfo] = [
        VoiceInfo(id: "af_heart", name: "Heart", nationality: "American", gender: .female, grade: "A"),
        VoiceInfo(id: "af_bella", name: "Bella", nationality: "American", gender: .female, grade: "A-"),
        VoiceInfo(id: "bf_emma", name: "Emma", nationality: "British", gender: .female, grade: "B-"),
        VoiceInfo(id: "am_fenrir", name: "Fenrir", nationality: "American", gender: .male, grade: "C+"),
        VoiceInfo(id: "bm_george", name: "George", nationality: "British", gender: .male, grade: "C"),
    ]
    
    static let recommended = "af_heart"
    
    // Full list - could be loaded from bundled JSON or fetched from HF
    static var allVoices: [String: VoiceInfo] = {
        var dict = [String: VoiceInfo]()
        for voice in starterVoices {
            dict[voice.id] = voice
        }
        return dict
    }()
    
    static func displayName(for voiceId: String) -> String {
        if let info = allVoices[voiceId] {
            return info.displayName
        }
        // Fallback: extract name from ID (af_heart -> Heart)
        return String(voiceId.dropFirst(3)).capitalized
    }
    
    static func description(for voiceId: String) -> String {
        if let info = allVoices[voiceId] {
            return info.description
        }
        return parseDescriptionFromId(voiceId)
    }
    
    private static func parseDescriptionFromId(_ id: String) -> String {
        guard id.count >= 3 else { return id }
        let prefix = String(id.prefix(2))
        let name = String(id.dropFirst(3)).capitalized
        
        let nationality: String
        switch prefix.first {
        case "a": nationality = "American"
        case "b": nationality = "British"
        case "e": nationality = "Spanish"
        case "f": nationality = "French"
        case "h": nationality = "Hindi"
        case "i": nationality = "Italian"
        case "j": nationality = "Japanese"
        case "p": nationality = "Brazilian"
        case "z": nationality = "Chinese"
        default: nationality = ""
        }
        
        let gender = prefix.last == "f" ? "Female" : "Male"
        
        return "\(name) - \(nationality) \(gender)"
    }
}
```

### Voice Download State

```swift
// New enum for per-voice download state
enum VoiceDownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double?) // nil = indeterminate
    case downloaded
    case failed(Error)
    
    static func == (lhs: VoiceDownloadState, rhs: VoiceDownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.notDownloaded, .notDownloaded): return true
        case (.downloading, .downloading): return true
        case (.downloaded, .downloaded): return true
        case (.failed, .failed): return true
        default: return false
        }
    }
}

// AppState additions
@Published var voiceDownloadStates: [String: VoiceDownloadState] = [:]
@Published var showAllVoices: Bool = false

var visibleVoices: [String] {
    showAllVoices ? availableVoices : availableVoices.filter { StarterVoices.all.contains($0) }
}

var needsFirstVoiceDownload: Bool {
    downloadedVoices.isEmpty
}
```

### First-Run Callout View

```swift
struct FirstRunCalloutView: View {
    @EnvironmentObject private var state: AppState
    
    var body: some View {
        if state.needsFirstVoiceDownload {
            VStack(spacing: 12) {
                Label("Download a voice to get started", systemImage: "speaker.wave.2")
                    .font(.headline)
                
                HStack(spacing: 12) {
                    Button("Download Recommended Voice") {
                        state.downloadVoice(StarterVoices.recommended)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Choose a different voice...") {
                        // Focus voice picker
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(.regularMaterial)
            .cornerRadius(12)
        }
    }
}
```

### Updated Voice Picker with States & Descriptions

```swift
struct VoicePickerView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedVoice: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Voice", selection: $selectedVoice) {
                ForEach(state.visibleVoices, id: \.self) { voiceId in
                    HStack {
                        // Show human-readable info only - NO voice codes!
                        VStack(alignment: .leading, spacing: 2) {
                            Text(VoiceMetadata.displayName(for: voiceId))
                                .fontWeight(.medium)
                            Text(VoiceMetadata.description(for: voiceId))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        voiceStateIcon(for: voiceId)
                    }
                    .tag(voiceId)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(state.isDownloadingVoice)
            .onAppear { selectedVoice = state.voice }
            .onChange(of: selectedVoice) { _, newVoice in
                handleVoiceSelection(newVoice)
            }
            
            if !state.showAllVoices {
                Button("Show all voices...") {
                    state.showAllVoices = true
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func voiceStateIcon(for voiceId: String) -> some View {
        let downloadState = state.voiceDownloadStates[voiceId] ?? 
            (state.downloadedVoices.contains(voiceId) ? .downloaded : .notDownloaded)
        
        switch downloadState {
        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .downloading:
            ProgressView()
                .controlSize(.small)
        case .downloaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func handleVoiceSelection(_ voiceId: String) {
        if state.downloadedVoices.contains(voiceId) {
            state.voice = voiceId
        } else {
            state.downloadVoice(voiceId)
        }
    }
}
```

### Speak Button with Auto-Download

```swift
struct SpeakButton: View {
    @EnvironmentObject private var state: AppState
    
    var body: some View {
        Button(action: handleSpeak) {
            HStack(spacing: 6) {
                if state.isDownloadingVoice {
                    ProgressView()
                        .controlSize(.small)
                    Text("Downloading...")
                } else {
                    Image(systemName: "play.fill")
                    Text("Speak")
                }
            }
        }
        .disabled(state.isRunning || state.isDownloadingVoice)
    }
    
    private func handleSpeak() {
        // Auto-download if voice not available
        if !state.downloadedVoices.contains(state.voice) {
            state.downloadVoiceAndSpeak(state.voice)
        } else {
            state.speak()
        }
    }
}

// AppState addition
func downloadVoiceAndSpeak(_ voiceName: String) {
    guard !isDownloadingVoice else { return }
    isDownloadingVoice = true
    downloadingVoiceName = voiceName
    voiceDownloadStates[voiceName] = .downloading(progress: nil)
    status = "Downloading \(voiceName)..."

    Task.detached { [voiceRepository = self.voiceRepository] in
        do {
            try await voiceRepository.download(voiceName) { message, log in
                await MainActor.run {
                    AppState.shared.status = message
                }
            }
            await MainActor.run {
                AppState.shared.downloadedVoices.insert(voiceName)
                AppState.shared.voice = voiceName
                AppState.shared.voiceDownloadStates[voiceName] = .downloaded
                AppState.shared.isDownloadingVoice = false
                AppState.shared.downloadingVoiceName = nil
                // Auto-speak after download
                AppState.shared.speak()
            }
        } catch {
            await MainActor.run {
                AppState.shared.voiceDownloadStates[voiceName] = .failed(error)
                AppState.shared.status = "Download failed: \(error.localizedDescription)"
                AppState.shared.isDownloadingVoice = false
                AppState.shared.downloadingVoiceName = nil
            }
        }
    }
}
```

### Download Failed State with Retry

```swift
struct VoiceDownloadErrorView: View {
    let voiceName: String
    let error: Error
    @EnvironmentObject private var state: AppState
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Download failed")
                    .font(.caption.bold())
                Text(error.localizedDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button("Retry") {
                state.downloadVoice(voiceName)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .background(.red.opacity(0.1))
        .cornerRadius(8)
    }
}
```

### Cancel Download Support

```swift
// AppState additions
private var downloadTask: Task<Void, Never>?

func downloadVoice(_ voiceName: String) {
    guard !isDownloadingVoice else { return }
    isDownloadingVoice = true
    downloadingVoiceName = voiceName
    voiceDownloadStates[voiceName] = .downloading(progress: nil)

    downloadTask = Task.detached { [voiceRepository = self.voiceRepository] in
        do {
            try Task.checkCancellation()
            try await voiceRepository.download(voiceName) { message, log in
                try? Task.checkCancellation()
                await MainActor.run {
                    AppState.shared.status = message
                }
            }
            try Task.checkCancellation()
            await MainActor.run {
                AppState.shared.downloadedVoices.insert(voiceName)
                AppState.shared.voice = voiceName
                AppState.shared.voiceDownloadStates[voiceName] = .downloaded
                AppState.shared.isDownloadingVoice = false
                AppState.shared.downloadingVoiceName = nil
                AppState.shared.status = "Downloaded \(voiceName)"
            }
        } catch is CancellationError {
            await MainActor.run {
                AppState.shared.voiceDownloadStates[voiceName] = .notDownloaded
                AppState.shared.status = "Download cancelled"
                AppState.shared.isDownloadingVoice = false
                AppState.shared.downloadingVoiceName = nil
            }
        } catch {
            await MainActor.run {
                AppState.shared.voiceDownloadStates[voiceName] = .failed(error)
                AppState.shared.status = "Download failed: \(error.localizedDescription)"
                AppState.shared.isDownloadingVoice = false
                AppState.shared.downloadingVoiceName = nil
            }
        }
    }
}

func cancelDownload() {
    downloadTask?.cancel()
    downloadTask = nil
}
```

### Cancel Button in UI

```swift
// Add to VoicePickerView or status area
if state.isDownloadingVoice, let voiceName = state.downloadingVoiceName {
    HStack(spacing: 8) {
        ProgressView()
            .controlSize(.small)
        Text("Downloading \(voiceName)...")
            .font(.caption)
        Button("Cancel") {
            state.cancelDownload()
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.red)
    }
}
