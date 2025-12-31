#!/usr/bin/env python3
import argparse
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description="Synthesize speech with Kokoro")
    parser.add_argument("--text", required=True, help="Text to synthesize")
    parser.add_argument("--voice", default="af_heart", help="Voice name")
    parser.add_argument("--lang", default="a", help="Language code (e.g., 'a' for American English)")
    parser.add_argument("--out", required=True, help="Output WAV path")
    parser.add_argument("--repo", default="hexgrad/Kokoro-82M", help="Hugging Face repo id")
    parser.add_argument("--revision", default="", help="Optional repo revision or commit hash")
    args = parser.parse_args()

    try:
        from kokoro import KPipeline
        from huggingface_hub import snapshot_download
        import numpy as np
        import soundfile as sf
    except Exception as exc:
        print("Failed to import dependencies. Install with: pip install kokoro huggingface_hub soundfile numpy", file=sys.stderr)
        print(str(exc), file=sys.stderr)
        return 1

    try:
        snapshot_download(
            repo_id=args.repo,
            revision=args.revision or None,
        )
        pipeline = KPipeline(lang_code=args.lang)
        audio_chunks = []
        for _, _, audio in pipeline(args.text, voice=args.voice):
            audio_chunks.append(audio)

        if not audio_chunks:
            print("No audio returned from Kokoro pipeline.", file=sys.stderr)
            return 2

        audio = np.concatenate(audio_chunks)
        sf.write(args.out, audio, 24000)
        return 0
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
