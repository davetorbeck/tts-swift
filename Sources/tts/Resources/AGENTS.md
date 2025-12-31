# Python Development Guidelines

## IMPORTANT: Always Use uv

**Never use `python`, `pip`, or `venv` directly.** Always use `uv` for all Python operations:

```bash
# Run a script with dependencies
uv run --with huggingface_hub script.py

# Run with multiple dependencies
uv run --with "kokoro huggingface_hub soundfile numpy" script.py

# Run tests
uv run python -m unittest test_kokoro.py -v
```

## Scripts

- `kokoro_prefetch.py` - Prefetch Kokoro model from Hugging Face
- `kokoro_say.py` - Synthesize speech with Kokoro TTS
- `kokoro_voices.py` - List available Kokoro voices
- `test_kokoro.py` - Unit tests for all scripts
