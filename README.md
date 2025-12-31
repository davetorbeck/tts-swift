# tts-swift

A minimal macOS SwiftUI app that calls Kokoro locally via Python and plays the generated WAV.

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

## How it works

- SwiftUI calls a bundled script at `Sources/tts/Resources/kokoro_say.py` to synthesize a WAV.
- The Python script uses `KPipeline` from the official Kokoro package, ensures the Hugging Face repo is downloaded, writes audio at 24 kHz, and the app plays it with `AVAudioPlayer`.
- Voice and language code are passed through as plain strings (e.g., voice `af_heart`, lang `a`).

## Notes

- If you see errors about missing `espeak-ng`, install it per your platform.
- Long text may be segmented into multiple chunks; the script concatenates them with NumPy.
