# tts-swift

A minimal macOS SwiftUI app that calls Kokoro locally via Python and plays the generated WAV. Features real-time word highlighting during playback with a floating HUD display.

## Prerequisites

1) Install `espeak-ng` (required by Kokoro):

```
brew install espeak-ng
```

2) Create a Python environment and install dependencies:

```
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install "kokoro>=0.9.4" huggingface_hub soundfile numpy
```

## Run

```
swift run
```

Global hotkey: Control + Option + Command + T triggers "Speak Selected Text".

macOS will prompt for Accessibility access the first time you try to read selected text. Grant access in System Settings → Privacy & Security → Accessibility.

By default the app uses `python3` from your PATH. If you want to point at a specific Python, set:

```
export KOKORO_PY=/path/to/python
```

To override the Hugging Face repo or pin a specific revision:

```
export KOKORO_REPO=hexgrad/Kokoro-82M
export KOKORO_REVISION=main
```

## Architecture

```
                           tts-swift
    ┌─────────────────────────────────────────────────────┐
    │                                                     │
    │   INPUT                                             │
    │   ├─ UI TextEditor (MainContentView)               │
    │   └─ Global Hotkey ⌃⌥⌘T (HotKeyManager)            │
    │          │                                          │
    │          ▼                                          │
    │   ┌─────────────────────────────────────────┐      │
    │   │           AppState (Singleton)          │      │
    │   │  • text, voice, language                │      │
    │   │  • wordTimings, currentWordIndex        │      │
    │   │  • AVAudioPlayer + playback timer       │      │
    │   └─────────────────┬───────────────────────┘      │
    │                     │                               │
    │                     ▼                               │
    │   ┌─────────────────────────────────────────┐      │
    │   │           KokoroRunner (Swift)          │      │
    │   │  • Manages Python venv (~/.tts-swift/)  │      │
    │   │  • Runs ProcessRunner with PTY          │      │
    │   └─────────────────┬───────────────────────┘      │
    │                     │                               │
    │                     ▼                               │
    │   ┌─────────────────────────────────────────┐      │
    │   │         kokoro_say.py (Python)          │      │
    │   │  • KPipeline + Hugging Face model       │      │
    │   │  • espeak-ng for phonemes               │      │
    │   │  • Outputs: kokoro.wav + timings.json   │      │
    │   └─────────────────┬───────────────────────┘      │
    │                     │                               │
    │                     ▼                               │
    │   OUTPUT                                            │
    │   ├─ AVAudioPlayer (24 kHz WAV playback)           │
    │   ├─ 50ms timer updates currentWordIndex           │
    │   ├─ FloatingOutputWindow (HUD with highlights)    │
    │   └─ HighlightedTextView (main window)             │
    │                                                     │
    └─────────────────────────────────────────────────────┘
```

### UI Layout

```
┌─ Menu Bar ──────────────────────────────────────────────────────┐
│  [♪] ▼                                                          │
│      ├─ Speak Selected Text (⌃⌘A)                               │
│      ├─ Always on top (⌃⌘T)                                     │
│      ├─ Open Window                                             │
│      └─ Quit                                                    │
└─────────────────────────────────────────────────────────────────┘

┌─ Main Window ───────────────────────────────────────────────────┐
│ ┌─ Sidebar ─┐ ┌─ Detail View ─────────────────────────────────┐ │
│ │           │ │                                               │ │
│ │ ♪ Voices  │ │  Input                    Output              │ │
│ │ ⚙ Settings│ │  ┌─────────────────┐     ┌─────────────────┐  │ │
│ │           │ │  │                 │     │ Hello [world]   │  │ │
│ │           │ │  │ Hello world     │     │ ← highlighted   │  │ │
│ │           │ │  │                 │     │                 │  │ │
│ │           │ │  └─────────────────┘     └─────────────────┘  │ │
│ │           │ │                                               │ │
│ │           │ │  [▶ Speak]  [■ Stop]                          │ │
│ │           │ │                                               │ │
│ └───────────┘ └───────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘

┌─ Floating HUD (during playback) ────────────────────────────────┐
│  Now Speaking                                             ─ □ x │
│ ┌───────────────────────────────────────────────────────────┐   │
│ │  Hello [world] this is a test of the text to speech       │   │
│ │  system with word highlighting and auto-scroll            │   │
│ └───────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## How it works

- SwiftUI calls a bundled script at `Sources/tts/Resources/kokoro_say.py` to synthesize a WAV.
- The Python script uses `KPipeline` from the official Kokoro package, ensures the Hugging Face repo is downloaded, writes audio at 24 kHz, and the app plays it with `AVAudioPlayer`.
- Voice and language code are passed through as plain strings (e.g., voice `af_heart`, lang `a`).

## Notes

- If you see errors about missing `espeak-ng`, install it per your platform.
- Long text may be segmented into multiple chunks; the script concatenates them with NumPy.
