#!/usr/bin/env python3
import argparse
import json
import os
import sys

# Disable HF progress bars to keep stdout clean
os.environ["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"


def main() -> int:
    parser = argparse.ArgumentParser(description="Synthesize speech with Kokoro")
    parser.add_argument("--text", required=True, help="Text to synthesize")
    parser.add_argument("--voice", default="af_heart", help="Voice name")
    parser.add_argument("--lang", default="a", help="Language code (e.g., 'a' for American English)")
    parser.add_argument("--out", required=True, help="Output WAV path")
    parser.add_argument("--timings", default="", help="Optional output path for word timing JSON")
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
        # Only download the voice file we need, not the entire repo
        snapshot_download(
            repo_id=args.repo,
            revision=args.revision or None,
            allow_patterns=[
                "*.json",
                "*.txt",
                "kokoro-v*.pth",
                f"voices/{args.voice}.pt",
            ],
        )
        pipeline = KPipeline(lang_code=args.lang, repo_id=args.repo)
        audio_chunks = []
        word_timings = []
        current_time = 0.0

        for result in pipeline(args.text, voice=args.voice):
            audio_chunks.append(result.output.audio.numpy() if hasattr(result.output.audio, 'numpy') else result.output.audio)
            
            for token in result.tokens:
                is_punctuation_only = token.tag in ['.', ',', '!', '?', ':', ';', '-', '(', ')'] and len(token.text.strip()) <= 1
                if is_punctuation_only:
                    continue
                
                # Skip tokens with missing timestamps
                if token.start_ts is None or token.end_ts is None:
                    continue
                
                word_timings.append({
                    "word": token.text,
                    "start": current_time + token.start_ts,
                    "end": current_time + token.end_ts,
                })
            
            chunk_audio = result.output.audio.numpy() if hasattr(result.output.audio, 'numpy') else result.output.audio
            chunk_duration = (chunk_audio.shape[0] if hasattr(chunk_audio, 'shape') else len(chunk_audio)) / 24000.0
            current_time += chunk_duration

        if not audio_chunks:
            print("No audio returned from Kokoro pipeline.", file=sys.stderr)
            return 2

        audio = np.concatenate(audio_chunks)
        sf.write(args.out, audio, 24000)
        
        if args.timings:
            with open(args.timings, 'w') as f:
                json.dump(word_timings, f)
        
        return 0
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
