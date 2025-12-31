#!/usr/bin/env python3
import argparse
import os
import sys
import time

# Disable HF progress bars to keep stdout clean
os.environ["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"


def main() -> int:
    parser = argparse.ArgumentParser(description="Prefetch Kokoro model repo from Hugging Face")
    parser.add_argument("--repo", default="hexgrad/Kokoro-82M", help="Hugging Face repo id")
    parser.add_argument("--revision", default="", help="Optional repo revision or commit hash")
    args = parser.parse_args()

    def log(message: str) -> None:
        timestamp = time.strftime("%H:%M:%S")
        print(f"[{timestamp}] {message}", flush=True)

    try:
        from huggingface_hub import snapshot_download
        from huggingface_hub.utils import logging as hf_logging
    except Exception as exc:
        print("Failed to import dependencies. Install with: pip install huggingface_hub", file=sys.stderr)
        print(str(exc), file=sys.stderr)
        return 1

    try:
        hf_logging.set_verbosity_debug()
        log(f"Python: {sys.version.split()[0]}")
        log(f"Repo: {args.repo} Revision: {args.revision or 'latest'}")
        log(f"HF_HOME={os.environ.get('HF_HOME', '')}")
        log(f"HF_HUB_CACHE={os.environ.get('HF_HUB_CACHE', '')}")
        log("Starting snapshot_download...")
        # Download only essential files, not all 72 voices
        # This avoids rate limiting on unauthenticated requests
        snapshot_download(
            repo_id=args.repo,
            revision=args.revision or None,
            allow_patterns=[
                "*.json",
                "*.txt", 
                "*.py",
                "*.model",
                "kokoro-v*.onnx",
                "voices/af_heart.pt",  # Default voice only
            ],
            ignore_patterns=["voices/*.pt", "voices/*.onnx", "voices/*.bin"],
        )
        log("snapshot_download finished.")
        
        # Pre-download spacy model required by kokoro
        try:
            import spacy
            try:
                spacy.load("en_core_web_sm")
                log("spacy model already installed.")
            except OSError:
                log("Downloading spacy en_core_web_sm model...")
                from spacy.cli import download
                download("en_core_web_sm")
                log("spacy model installed.")
        except ImportError:
            log("spacy not installed, skipping model download.")
        
        print("Kokoro repo cached.")
        return 0
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
