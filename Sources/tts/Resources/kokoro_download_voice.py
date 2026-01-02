#!/usr/bin/env python3
import argparse
import sys


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default="hexgrad/Kokoro-82M")
    parser.add_argument("--revision", default="")
    parser.add_argument("--voice", required=True)
    args = parser.parse_args()

    try:
        from huggingface_hub import hf_hub_download
    except Exception as exc:
        print(f"Failed to import huggingface_hub: {exc}", file=sys.stderr)
        return 1

    try:
        extensions = [".pt", ".onnx", ".bin"]
        downloaded = False
        
        for ext in extensions:
            filename = f"voices/{args.voice}{ext}"
            try:
                hf_hub_download(
                    repo_id=args.repo,
                    filename=filename,
                    revision=args.revision or None,
                )
                downloaded = True
                print(f"Downloaded {args.voice}", flush=True)
                break
            except Exception:
                continue
        
        if not downloaded:
            print(f"Voice {args.voice} not found in repo", file=sys.stderr)
            return 1
        
        return 0
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
