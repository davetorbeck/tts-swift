#!/usr/bin/env python3
import argparse
import json
import os
import sys

# Disable HF progress bars to keep stdout clean for JSON parsing
os.environ["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"


def main() -> int:
    parser = argparse.ArgumentParser(description="List Kokoro voices from Hugging Face repo")
    parser.add_argument("--repo", default="hexgrad/Kokoro-82M", help="Hugging Face repo id")
    parser.add_argument("--revision", default="", help="Optional repo revision or commit hash")
    parser.add_argument("--voice", default="", help="Optional single voice to download")
    parser.add_argument("--all", action="store_true", help="Download and list all voices")
    args = parser.parse_args()

    try:
        from huggingface_hub import snapshot_download
    except Exception as exc:
        print("Failed to import dependencies. Install with: pip install huggingface_hub", file=sys.stderr)
        print(str(exc), file=sys.stderr)
        return 1

    try:
        voice = args.voice or os.environ.get("KOKORO_VOICE", "").strip()
        list_all = args.all or os.environ.get("KOKORO_ALL_VOICES", "").strip() == "1"

        allow_patterns = ["voices/*"]
        if not list_all:
            if not voice:
                voice = "af_heart"
            allow_patterns = [
                f"voices/{voice}.pt",
                f"voices/{voice}.onnx",
                f"voices/{voice}.bin",
            ]

        repo_path = snapshot_download(
            repo_id=args.repo,
            revision=args.revision or None,
            allow_patterns=allow_patterns,
        )
        voices_dir = os.path.join(repo_path, "voices")
        voices = []
        if os.path.isdir(voices_dir):
            for name in os.listdir(voices_dir):
                if name.endswith(".pt") or name.endswith(".onnx") or name.endswith(".bin"):
                    voices.append(os.path.splitext(name)[0])
        if not list_all and voice:
            voices = [voice]
        voices = sorted(set(voices))
        print(json.dumps(voices))
        return 0
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
