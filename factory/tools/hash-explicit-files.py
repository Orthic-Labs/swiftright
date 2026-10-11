#!/usr/bin/env python3
"""Hash an explicit, bounded set of regular files without whole-file reads."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import time

CHUNK_BYTES = 1024 * 1024
MAX_FILE_BYTES = 64 * 1024 * 1024
MAX_TOTAL_BYTES = 256 * 1024 * 1024
MAX_FILES = 256
MAX_SECONDS = 60


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+")
    args = parser.parse_args()
    if len(args.files) > MAX_FILES:
        parser.error(f"maximum {MAX_FILES} explicit files")
    deadline = time.monotonic() + MAX_SECONDS
    remaining = MAX_TOTAL_BYTES
    for name in args.files:
        if time.monotonic() >= deadline:
            raise ValueError("hashing deadline exceeded")
        path = Path(name)
        before = path.lstat()
        if not stat.S_ISREG(before.st_mode):
            raise ValueError(f"regular file required: {path}")
        if before.st_size > MAX_FILE_BYTES or before.st_size > remaining:
            raise ValueError(f"file exceeds byte budget: {path} ({before.st_size})")
        digest = hashlib.sha256()
        consumed = 0
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0))
        with os.fdopen(fd, "rb") as stream:
            opened = os.fstat(stream.fileno())
            if (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns) != (
                before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns
            ):
                raise ValueError(f"file changed before read: {path}")
            while True:
                if time.monotonic() >= deadline:
                    raise ValueError("hashing deadline exceeded")
                data = stream.read(min(CHUNK_BYTES, before.st_size - consumed + 1))
                if not data:
                    break
                consumed += len(data)
                if consumed > before.st_size:
                    raise ValueError(f"file grew during read: {path}")
                digest.update(data)
            after = os.fstat(stream.fileno())
        if consumed != before.st_size or (after.st_size, after.st_mtime_ns) != (
            before.st_size, before.st_mtime_ns
        ):
            raise ValueError(f"file changed during read: {path}")
        remaining -= consumed
        print(json.dumps({"path": str(path), "bytes": consumed, "sha256": digest.hexdigest()}), flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"hashing refused: {error}", file=sys.stderr)
        sys.exit(2)
