#!/usr/bin/env python3
"""Download and verify the pinned runtime assets using Python 3.11+."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import stat
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    lock = json.loads((ROOT / 'assets.lock.json').read_text())
    expected = lock['sha256']
    if len(expected) != 64 or any(c not in '0123456789abcdef' for c in expected):
        raise ValueError('Invalid SHA-256 in assets.lock.json')
    destination = ROOT / 'assets'
    if destination.exists() or destination.is_symlink():
        raise SystemExit('assets/ already exists. Move it aside before fetching a fresh copy.')
    build = ROOT / '.build'
    build.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='assets-', dir=build) as temporary:
        stage = Path(temporary)
        archive = stage / 'assets.zip'
        request = urllib.request.Request(lock['url'], headers={'User-Agent': 'hidden-leaf-assets'})
        print('Downloading', lock['url'], flush=True)
        with urllib.request.urlopen(request, timeout=120) as source, archive.open('wb') as target:
            shutil.copyfileobj(source, target)
        with archive.open('rb') as source:
            actual = hashlib.file_digest(source, 'sha256').hexdigest()
        if actual != expected:
            raise ValueError(f'Archive SHA-256 mismatch: {actual}')
        unpack = stage / 'unpack'
        with zipfile.ZipFile(archive) as bundle:
            seen = set()
            for member in bundle.infolist():
                path = PurePosixPath(member.filename)
                mode = member.external_attr >> 16
                if (path.is_absolute() or '..' in path.parts or not path.parts
                        or path.parts[0] != 'assets' or '\\' in member.filename
                        or ':' in member.filename or stat.S_ISLNK(mode)
                        or member.filename in seen):
                    raise ValueError(f'Unsafe archive member: {member.filename}')
                seen.add(member.filename)
            bundle.extractall(unpack)
        for name in ('village_v3.glb', 'village_v3.json'):
            if not (unpack / 'assets' / name).is_file():
                raise ValueError(f'Archive missing {name}')
        (unpack / 'assets').rename(destination)
    print('Verified assets installed at', destination)


if __name__ == '__main__':
    main()
