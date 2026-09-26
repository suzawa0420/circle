#!/usr/bin/env python3
"""Add immutable public assets without replacing files or Sprockets manifests."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import tempfile

DIGEST = re.compile(r'-[0-9a-f]{32,128}\.[A-Za-z0-9.]+$')


def sha(path):
    with path.open('rb') as stream:
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
        return digest.digest()


def sync(source, destination, apply=False):
    source, destination = Path(source), Path(destination)
    if source.is_symlink() or destination.is_symlink():
        raise ValueError('asset roots must not be symlinks')
    source, destination = source.resolve(strict=True), destination.resolve(strict=True)
    if source == destination or source in destination.parents or destination in source.parents:
        raise ValueError('asset roots must be separate directories')
    planned = []
    existing = 0
    for src in sorted(source.rglob('*')):
        rel = src.relative_to(source)
        if src.is_symlink():
            raise ValueError('symlinks are not allowed')
        if src.is_dir():
            continue
        if any(part.startswith('.') for part in rel.parts):
            continue  # Never transfer the Sprockets manifest or hidden files.
        if not src.is_file() or not DIGEST.search(src.name):
            raise ValueError('source contains a non-fingerprinted file')
        dst = destination / rel
        for parent in [dst, *dst.parents]:
            if parent == destination:
                break
            if parent.is_symlink():
                raise ValueError('destination symlinks are not allowed')
        if dst.exists():
            if not dst.is_file() or sha(src) != sha(dst):
                raise ValueError('existing asset differs; nothing has been written')
            existing += 1
        else:
            planned.append((src, dst))
    if apply:
        for src, dst in planned:
            dst.parent.mkdir(parents=True, exist_ok=True, mode=0o755)
            fd, temporary = tempfile.mkstemp(prefix='.asset-transfer-', dir=dst.parent)
            try:
                with os.fdopen(fd, 'wb') as out, src.open('rb') as inp:
                    for block in iter(lambda: inp.read(1024 * 1024), b''):
                        out.write(block)
                    out.flush()
                    os.fsync(out.fileno())
                os.chmod(temporary, 0o644)
                if sha(Path(temporary)) != sha(src):
                    raise ValueError('copied asset checksum failed')
                os.link(temporary, dst)  # Atomic publish; cannot overwrite a file.
            finally:
                os.unlink(temporary)
    return {'existing': existing, 'additions': len(planned), 'applied': apply}


if __name__ == '__main__':
    import json
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('destination')
    parser.add_argument('--apply', action='store_true', help='default is a read-only preview')
    args = parser.parse_args()
    try:
        print(json.dumps(sync(args.source, args.destination, args.apply)))
    except (OSError, ValueError):
        parser.exit(1, 'Asset sync refused or failed; inspect paths locally. No files were overwritten.\n')
