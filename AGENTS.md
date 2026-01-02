# tts-swift Development Guidelines

## Project Structure

- `Sources/tts/` - Main Swift source files
  - `tts.swift` - Main app, AppState, views, and Kokoro runner
  - `FloatingOutputWindow.swift` - Always-on-top HUD for word highlighting
  - `ProcessRunner.swift` - Process execution utilities
  - `KokoroLogger.swift` - Debug logging
  - `Resources/` - Bundled Python scripts

## Building & Running

```bash
swift build
swift run
```

## Key Components

- **AppState** - Shared state for TTS synthesis, playback, and word timing
- **FloatingOutputWindow** - Floating HUD that shows highlighted words during playback
- **FlowLayout** - Custom SwiftUI Layout for horizontal word wrapping
- **KokoroRunner** - Manages Python environment and synthesis calls
- **HotKeyManager** - Global hotkey registration (⌃⌘A)

## Word Highlighting

The app tracks word timing during playback:
1. Python script outputs word timestamps to JSON
2. Swift loads timings and updates `currentWordIndex` via timer
3. FlowLayout displays words with highlight on current word
4. Auto-scrolls to keep current word visible

## Environment Variables

- `KOKORO_PY` - Custom Python path
- `KOKORO_REPO` - Override Hugging Face repo
- `KOKORO_REVISION` - Pin specific revision

## Python Scripts

See `Sources/tts/Resources/AGENTS.md` for Python-specific guidelines.
