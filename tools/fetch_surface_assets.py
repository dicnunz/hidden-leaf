#!/usr/bin/env python3
"""Restore the small, hash-pinned CC0 surface set used by village materials."""
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def main():
    manifest = json.loads((ROOT / "tools/surface-assets.lock.json").read_text())
    for entry in manifest["files"]:
        path = ROOT / entry["path"]
        if path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"]:
            continue
        request = urllib.request.Request(entry["url"], headers={"User-Agent": "Shinobi-Villages-AssetBuilder/1.0"})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
        if len(data) != entry["bytes"] or hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise RuntimeError(f"Surface integrity check failed: {entry['path']}")
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".partial")
        temporary.write_bytes(data)
        temporary.replace(path)
        print(entry["path"])
    print(f"Verified {len(manifest['files'])} CC0 surface files")


if __name__ == "__main__":
    main()
