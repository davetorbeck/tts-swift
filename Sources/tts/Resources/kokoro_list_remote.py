#!/usr/bin/env python3
import argparse
import json
import os
import sys

os.environ["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"


def get_voice_name_from_path(path: str) -> str:
    return os.path.splitext(os.path.basename(path))[0]


def is_voice_file(filename: str) -> bool:
    return filename.endswith(".pt") or filename.endswith(".onnx") or filename.endswith(".bin")


def find_downloaded_voices_in_cache(repo: str) -> list[str]:
    downloaded = []
    cache_dir = os.environ.get("HF_HUB_CACHE") or os.environ.get("HF_HOME")
    if not cache_dir:
        cache_dir = os.path.expanduser("~/.cache/huggingface/hub")
    
    repo_folder = repo.replace("/", "--")
    models_path = os.path.join(cache_dir, f"models--{repo_folder}")
    
    if not os.path.isdir(models_path):
        return downloaded
    
    snapshots_path = os.path.join(models_path, "snapshots")
    if not os.path.isdir(snapshots_path):
        return downloaded
    
    for snapshot in os.listdir(snapshots_path):
        voices_dir = os.path.join(snapshots_path, snapshot, "voices")
        if os.path.isdir(voices_dir):
            for name in os.listdir(voices_dir):
                if is_voice_file(name):
                    downloaded.append(get_voice_name_from_path(name))
    
    return downloaded


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default="hexgrad/Kokoro-82M")
    parser.add_argument("--revision", default="")
    args = parser.parse_args()

    try:
        from huggingface_hub import HfApi
    except Exception as exc:
        print(f"Failed to import huggingface_hub: {exc}", file=sys.stderr)
        return 1

    try:
        api = HfApi()
        files = api.list_repo_files(repo_id=args.repo, revision=args.revision or None)
        
        voices = set()
        for f in files:
            if f.startswith("voices/") and is_voice_file(f):
                voices.add(get_voice_name_from_path(f))
        
        downloaded = find_downloaded_voices_in_cache(args.repo)
        
        result = {
            "voices": sorted(voices),
            "downloaded": sorted(set(downloaded))
        }
        print(json.dumps(result))
        return 0
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
