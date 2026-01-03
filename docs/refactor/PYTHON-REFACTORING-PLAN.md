# Python Refactoring Plan for tts-swift

This document outlines SOLID principles and unit testing opportunities for the Python scripts in `Sources/tts/Resources/`.

---

## Task List

### SOLID Refactoring
- [x] Extract voice file utilities into shared module
- [ ] Extract HuggingFace client wrapper for testability
- [x] Extract word timing extraction from `kokoro_say.py`
- [x] Create constants for voice file extensions

### Unit Tests (Non-Trivial Logic)
- [x] `test_punctuation_filtering` - token filtering in kokoro_say.py
- [x] `test_word_timing_accumulation` - time offset calculations
- [x] `test_find_downloaded_voices_in_cache` - cache path traversal
- [x] `test_allow_patterns_construction` - pattern building logic
- [x] `test_extension_fallback_chain` - .pt → .onnx → .bin ordering

---

## Current State Analysis

### Script Overview

| Script | Purpose | Lines | Issues |
|--------|---------|-------|--------|
| `kokoro_say.py` | TTS synthesis | 90 | Multiple responsibilities, untested logic |
| `kokoro_voices.py` | List voices | 63 | Duplicated extension check |
| `kokoro_list_remote.py` | List remote + downloaded | 80 | Good extraction, partially tested |
| `kokoro_download_voice.py` | Download single voice | 49 | Clean, minimal |
| `kokoro_prefetch.py` | Prefetch model | 76 | Clean, minimal |

---

## SOLID Analysis

### 1. Single Responsibility Principle (SRP)

#### `kokoro_say.py` - Multiple Responsibilities

Currently handles:
- Argument parsing
- Model downloading
- Pipeline execution
- Token/word timing extraction
- Punctuation filtering
- Audio chunk concatenation
- File I/O

**Suggested Refactoring:**

```python
# word_timing.py - Extract timing logic
def extract_word_timings(tokens, current_time: float) -> list[dict]:
    """Extract word timings from tokens, filtering punctuation."""
    timings = []
    for token in tokens:
        if is_punctuation_only(token):
            continue
        if token.start_ts is None or token.end_ts is None:
            continue
        timings.append({
            "word": token.text,
            "start": current_time + token.start_ts,
            "end": current_time + token.end_ts,
        })
    return timings


def is_punctuation_only(token) -> bool:
    """Check if token is punctuation that should be skipped."""
    punctuation_tags = {'.', ',', '!', '?', ':', ';', '-', '(', ')'}
    return token.tag in punctuation_tags and len(token.text.strip()) <= 1
```

### 2. Open/Closed Principle (OCP)

#### Voice File Extensions - Hardcoded in Multiple Places

**Current (repeated in 3 files):**
```python
# kokoro_list_remote.py:14-15
def is_voice_file(filename: str) -> bool:
    return filename.endswith(".pt") or filename.endswith(".onnx") or filename.endswith(".bin")

# kokoro_voices.py:34-38
allow_patterns = [
    f"voices/{voice}.pt",
    f"voices/{voice}.onnx",
    f"voices/{voice}.bin",
]

# kokoro_download_voice.py:20
extensions = [".pt", ".onnx", ".bin"]
```

**Suggested Refactoring:**

```python
# voice_utils.py - Shared constants and utilities
VOICE_EXTENSIONS = (".pt", ".onnx", ".bin")


def is_voice_file(filename: str) -> bool:
    """Check if filename is a voice file."""
    return filename.endswith(VOICE_EXTENSIONS)


def get_voice_name(path: str) -> str:
    """Extract voice name from file path."""
    import os
    return os.path.splitext(os.path.basename(path))[0]


def voice_patterns_for(voice: str) -> list[str]:
    """Generate allow_patterns for a specific voice."""
    return [f"voices/{voice}{ext}" for ext in VOICE_EXTENSIONS]
```

### 3. Dependency Inversion Principle (DIP)

#### Direct HuggingFace API Usage

**Current:**
```python
# Direct dependency on huggingface_hub
from huggingface_hub import snapshot_download
snapshot_download(repo_id=args.repo, ...)
```

**Suggested Refactoring (for testability):**

```python
# hf_client.py - Wrapper for testing
from typing import Protocol


class ModelRepository(Protocol):
    def download_snapshot(self, repo_id: str, patterns: list[str]) -> str:
        """Download repo snapshot, return local path."""
        ...
    
    def download_file(self, repo_id: str, filename: str) -> str:
        """Download single file, return local path."""
        ...
    
    def list_files(self, repo_id: str) -> list[str]:
        """List all files in repo."""
        ...


class HuggingFaceRepository:
    """Production implementation using huggingface_hub."""
    
    def __init__(self, revision: str | None = None):
        self.revision = revision
    
    def download_snapshot(self, repo_id: str, patterns: list[str]) -> str:
        from huggingface_hub import snapshot_download
        return snapshot_download(
            repo_id=repo_id,
            revision=self.revision,
            allow_patterns=patterns,
        )
    
    def download_file(self, repo_id: str, filename: str) -> str:
        from huggingface_hub import hf_hub_download
        return hf_hub_download(
            repo_id=repo_id,
            filename=filename,
            revision=self.revision,
        )
    
    def list_files(self, repo_id: str) -> list[str]:
        from huggingface_hub import HfApi
        api = HfApi()
        return api.list_repo_files(repo_id=repo_id, revision=self.revision)


class MockRepository:
    """Test implementation."""
    
    def __init__(self, files: list[str], local_path: str):
        self.files = files
        self.local_path = local_path
    
    def download_snapshot(self, repo_id: str, patterns: list[str]) -> str:
        return self.local_path
    
    def list_files(self, repo_id: str) -> list[str]:
        return self.files
```

---

## Unit Testing Analysis

### Worth Testing (Non-Trivial Logic)

| Function | Location | Why Test | Test Cases |
|----------|----------|----------|------------|
| **Punctuation filtering** | `kokoro_say.py:53-55` | Edge cases in token handling | Single char punctuation, multi-char, mixed |
| **Word timing accumulation** | `kokoro_say.py:61-65` | Time offset math across chunks | Single chunk, multiple chunks, gaps |
| **`find_downloaded_voices_in_cache`** | `kokoro_list_remote.py:18-41` | Complex path traversal | No cache, empty snapshots, multiple snapshots |
| **Allow patterns construction** | `kokoro_voices.py:30-38` | Conditional logic | Single voice, all voices, env var override |
| **Extension fallback** | `kokoro_download_voice.py:23-35` | First-match logic | .pt exists, .onnx exists, .bin exists, none exist |
| **`is_voice_file`** | `kokoro_list_remote.py:14-15` | Already tested | Edge cases covered |
| **`get_voice_name_from_path`** | `kokoro_list_remote.py:10-11` | Already tested | Edge cases covered |

### NOT Worth Testing (Trivial)

| Component | Location | Why Skip |
|-----------|----------|----------|
| Argument parsing | All scripts | argparse handles validation |
| Import error handling | All scripts | Simple try/except, obvious |
| `os.environ` settings | Top of files | Just setting values |
| `json.dumps` output | Various | Standard library, tested upstream |
| File write operations | `kokoro_say.py:79-80` | I/O, integration test territory |
| HF API calls | Various | External service, mock or integration test |

---

## Recommended Test Additions

### `test_kokoro.py` - New Test Cases

```python
class TestPunctuationFiltering(unittest.TestCase):
    """Tests for kokoro_say.py punctuation logic."""
    
    def test_single_char_punctuation_is_skipped(self):
        """Tokens with single punctuation chars should be filtered."""
        # Mock token with tag='.' and text='.'
        token = MagicMock(tag='.', text='.', start_ts=0.0, end_ts=0.1)
        self.assertTrue(is_punctuation_only(token))
    
    def test_word_with_punctuation_tag_kept(self):
        """Words that happen to have punctuation tag but >1 char kept."""
        token = MagicMock(tag='.', text='Mr.', start_ts=0.0, end_ts=0.2)
        self.assertFalse(is_punctuation_only(token))
    
    def test_regular_word_not_filtered(self):
        """Regular words should not be filtered."""
        token = MagicMock(tag='WORD', text='hello', start_ts=0.0, end_ts=0.3)
        self.assertFalse(is_punctuation_only(token))
    
    def test_missing_timestamps_skipped(self):
        """Tokens with None timestamps should be skipped."""
        token = MagicMock(tag='WORD', text='hello', start_ts=None, end_ts=0.3)
        # This is handled in extract_word_timings, not is_punctuation_only


class TestWordTimingAccumulation(unittest.TestCase):
    """Tests for time offset calculations across chunks."""
    
    def test_first_chunk_uses_zero_offset(self):
        """First chunk timings should start from 0."""
        tokens = [
            MagicMock(tag='WORD', text='hello', start_ts=0.0, end_ts=0.3),
            MagicMock(tag='WORD', text='world', start_ts=0.3, end_ts=0.6),
        ]
        timings = extract_word_timings(tokens, current_time=0.0)
        self.assertEqual(timings[0]['start'], 0.0)
        self.assertEqual(timings[1]['start'], 0.3)
    
    def test_second_chunk_adds_offset(self):
        """Second chunk timings should add previous chunk duration."""
        tokens = [
            MagicMock(tag='WORD', text='next', start_ts=0.0, end_ts=0.3),
        ]
        # First chunk was 1.0 seconds
        timings = extract_word_timings(tokens, current_time=1.0)
        self.assertEqual(timings[0]['start'], 1.0)
        self.assertEqual(timings[0]['end'], 1.3)


class TestFindDownloadedVoices(unittest.TestCase):
    """Tests for cache directory traversal."""
    
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.original_env = os.environ.copy()
    
    def tearDown(self):
        import shutil
        shutil.rmtree(self.temp_dir, ignore_errors=True)
        os.environ.clear()
        os.environ.update(self.original_env)
    
    def test_returns_empty_when_no_cache(self):
        """Should return empty list when cache dir doesn't exist."""
        os.environ['HF_HUB_CACHE'] = '/nonexistent/path'
        result = find_downloaded_voices_in_cache('hexgrad/Kokoro-82M')
        self.assertEqual(result, [])
    
    def test_finds_voices_in_snapshots(self):
        """Should find voice files in snapshot directories."""
        # Create mock cache structure
        os.environ['HF_HUB_CACHE'] = self.temp_dir
        snapshot_voices = os.path.join(
            self.temp_dir, 
            'models--hexgrad--Kokoro-82M',
            'snapshots',
            'abc123',
            'voices'
        )
        os.makedirs(snapshot_voices)
        open(os.path.join(snapshot_voices, 'af_heart.pt'), 'w').close()
        open(os.path.join(snapshot_voices, 'bf_emma.pt'), 'w').close()
        
        result = find_downloaded_voices_in_cache('hexgrad/Kokoro-82M')
        self.assertEqual(sorted(result), ['af_heart', 'bf_emma'])
    
    def test_ignores_non_voice_files(self):
        """Should not include non-voice files."""
        os.environ['HF_HUB_CACHE'] = self.temp_dir
        snapshot_voices = os.path.join(
            self.temp_dir,
            'models--hexgrad--Kokoro-82M',
            'snapshots',
            'abc123',
            'voices'
        )
        os.makedirs(snapshot_voices)
        open(os.path.join(snapshot_voices, 'af_heart.pt'), 'w').close()
        open(os.path.join(snapshot_voices, 'config.json'), 'w').close()
        
        result = find_downloaded_voices_in_cache('hexgrad/Kokoro-82M')
        self.assertEqual(result, ['af_heart'])


class TestExtensionFallback(unittest.TestCase):
    """Tests for voice download extension fallback."""
    
    def test_tries_pt_first(self):
        """Should attempt .pt extension first."""
        # Would need to mock hf_hub_download and verify call order
        pass
    
    def test_falls_back_to_onnx(self):
        """Should try .onnx if .pt fails."""
        pass
    
    def test_falls_back_to_bin(self):
        """Should try .bin if .pt and .onnx fail."""
        pass
    
    def test_returns_error_if_all_fail(self):
        """Should return error code if no extension found."""
        pass
```

---

## Implemented File Structure

```
Sources/tts/Resources/
├── kokoro_say.py           # Simplified, uses lib/word_timing
├── kokoro_voices.py        # Simplified, uses lib/voice_utils
├── kokoro_list_remote.py   # Uses lib/voice_utils
├── kokoro_download_voice.py # Uses lib/voice_utils
├── kokoro_prefetch.py      # Already clean
├── lib/
│   ├── __init__.py         # Exports all shared utilities
│   ├── voice_utils.py      # VOICE_EXTENSIONS, is_voice_file, get_voice_name, voice_patterns_for
│   └── word_timing.py      # PUNCTUATION_TAGS, is_punctuation_only, extract_word_timings
├── test_kokoro.py          # 28 tests covering all shared utilities
└── pyrightconfig.json
```

Note: `hf_client.py` wrapper deferred - only implement if mocking HuggingFace becomes painful.

---

## Implementation Status

| Priority | Task | Effort | Impact | Status |
|----------|------|--------|--------|--------|
| **High** | Add punctuation filtering tests | Low | Documents edge cases | Done |
| **High** | Add word timing accumulation tests | Low | Core feature correctness | Done |
| **High** | Add cache traversal tests | Medium | Prevents regressions | Done |
| **Medium** | Extract `voice_utils.py` | Low | DRY, single source of truth | Done |
| **Medium** | Extract `word_timing.py` | Low | Enables unit testing | Done |
| **Low** | Create `hf_client.py` wrapper | Medium | Only if mocking HF becomes painful | Deferred |

---

## Notes

- Python scripts are CLI tools, so integration tests via subprocess are also valid
- Avoid over-abstracting - these are simple scripts, not a library
- Focus testing on logic that has caused bugs or is error-prone
- Use `uv run python -m unittest test_kokoro.py -v` to run tests
