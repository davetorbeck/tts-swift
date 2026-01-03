# MVP Release

## Yet To Be Implemented

- [ ] Toggle floating HUD visibility
- [ ] Character limit for input text (~1000 chars, needs testing to find model threshold)
- [ ] Prompt user for accessibility permissions on startup
- [ ] Add descriptions to Kokoro voices

## Pre-Release Tasks

- [ ] Test app bundling for beta users
- [ ] Code signing and notarization
- [ ] Create DMG or installer
- [ ] Beta testing with external users

## Overview

Minimum viable product release for tts-swift - a macOS text-to-speech application using Kokoro with real-time word highlighting.

## Core Features

### Text-to-Speech Engine
- [x] Text-to-speech synthesis using Kokoro (Python-based)
- [x] Multi-language support (10 languages: US/UK English, Spanish, French, Hindi, Italian, Japanese, Korean, Portuguese, Chinese)
- [x] Voice selection from available voices
- [x] Voice downloading from Hugging Face on-demand
- [x] Word timing generation during synthesis

### User Interface
- [x] Menu bar app with dropdown menu
- [x] Main window with collapsible sidebar navigation
- [x] Voice picker view with download status indicators
- [x] Settings view with hotkey configuration
- [x] Text input editor
- [x] Highlighted text output view in main window
- [x] Floating HUD window for word display during playback
- [x] Real-time word highlighting synchronized with audio
- [x] Auto-scroll to current word in floating HUD
- [x] FlowLayout for natural word wrapping

### Audio Playback
- [x] Audio playback using AVAudioPlayer (24 kHz WAV)
- [x] Word timing tracker synchronized with audio playback
- [x] Play/Stop controls
- [x] Status display during synthesis and playback

### Hotkey & Accessibility
- [x] Global hotkey activation (⌃⌘A)
- [x] Configurable keyboard shortcuts via KeyboardShortcuts library
- [x] Read selected text from any application
- [x] Accessibility permission detection and prompting
- [x] HUD notification for "Speaking..." / "No text selected"

### Window Management
- [x] Always-on-top toggle for main window (⌃⌘T)
- [x] Floating HUD window stays on all spaces
- [x] Toggle sidebar visibility button
- [x] Transparent titlebar with movable window background

### Environment & Setup
- [x] Automatic Python virtual environment creation (~/.tts-swift/)
- [x] Automatic dependency installation (kokoro, huggingface_hub, etc.)
- [x] Background setup on app launch
- [x] Setup state progress UI (creating venv → installing deps → loading voices → ready)
- [x] Environment ready detection and caching for fast restarts
- [x] Model prefetching from Hugging Face

### Architecture
- [x] Protocol-based dependency injection (TTSProtocols)
- [x] Clean separation of concerns (Audio, Models, Runner, Views, Utilities)
- [x] Shared AppState singleton with Combine publishers
- [x] KokoroEnvironment for venv management
- [x] KokoroSynthesizer for audio generation
- [x] KokoroVoiceRepository for voice listing/downloading
- [x] ProcessRunner with PTY for subprocess handling
- [x] Centralized string constants (Strings.swift)
- [x] Debug logging via KokoroLogger

## Status

- **Current Status:** Feature Complete
- **All MVP features implemented**

## Notes

- Requires `espeak-ng` installed via Homebrew
- Uses bundled Python scripts in Resources/
- Environment variables available for customization (KOKORO_PY, KOKORO_REPO, KOKORO_REVISION)
