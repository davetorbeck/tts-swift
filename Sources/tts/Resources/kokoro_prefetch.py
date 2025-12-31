#!/usr/bin/env python3
import argparse
import os
import sys
import time


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
        snapshot_download(
            repo_id=args.repo,
            revision=args.revision or None,
        )
        log("snapshot_download finished.")
        print("Kokoro repo cached.")
        return 0
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
