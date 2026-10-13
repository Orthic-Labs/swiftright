"""Bounded, symlink-safe JSON & archive byte helpers for adapter v9."""
from __future__ import annotations

import hashlib
import json
import os
import stat
from pathlib import Path, PurePosixPath
from typing import Any

CHUNK_SIZE = 1024 * 1024
JSON_LIMIT = 2 * 1024 * 1024
ARCHIVE_FILE_LIMIT = 64 * 1024 * 1024
ARCHIVE_TOTAL_LIMIT = 256 * 1024 * 1024


def _walk_existing(path: Path) -> None:
    """Reject symlink components before any lexical path normalization."""
    absolute = Path(os.path.abspath(os.fspath(path)))
    current = Path(absolute.anchor)
    for component in absolute.parts[1:]:
        current /= component
        try:
            info = os.lstat(current)
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode):
            raise ValueError(f"symlink path component rejected: {path}")


def regular_file(path: Path, *, max_bytes: int) -> os.stat_result:
    _walk_existing(path)
    try:
        info = os.lstat(path)
    except OSError as exc:
        raise ValueError(f"file unavailable: {path}") from exc
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise ValueError(f"regular non-symlink file required: {path}")
    if info.st_size > max_bytes:
        raise ValueError(f"file exceeds bounded limit: {path}")
    return info


def _json_pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def _reject_constant(value):
    raise ValueError(f"non-finite JSON value: {value}")


def bounded_json(path: Path, *, limit: int = JSON_LIMIT) -> Any:
    info = regular_file(path, max_bytes=limit)
    chunks = []
    total = 0
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(CHUNK_SIZE)
            if not chunk:
                break
            total += len(chunk)
            if total > limit:
                raise ValueError(f"JSON exceeds bounded limit: {path}")
            chunks.append(chunk)
    if total != info.st_size:
        raise ValueError(f"JSON changed during read: {path}")
    try:
        return json.loads(b"".join(chunks).decode("utf-8-sig"), object_pairs_hook=_json_pairs, parse_constant=_reject_constant)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"invalid JSON: {path}") from exc


def safe_relative(value: object) -> str:
    if not isinstance(value, str) or not value or "\\" in value or ":" in value or "\x00" in value:
        raise ValueError("unsafe archive-relative reference")
    parsed = PurePosixPath(value)
    if parsed.is_absolute() or ".." in parsed.parts or str(parsed) != value:
        raise ValueError("unsafe archive-relative reference")
    return value


def beneath(root: Path, relative: str) -> Path:
    safe_relative(relative)
    _walk_existing(root)
    root_abs = Path(os.path.abspath(os.fspath(root)))
    candidate = Path(os.path.abspath(os.fspath(root / relative)))
    try:
        candidate.relative_to(root_abs)
    except ValueError as exc:
        raise ValueError("archive path escapes root") from exc
    _walk_existing(candidate)
    return candidate


def stream_hash(path: Path, *, expected_bytes: int | None = None, max_bytes: int = ARCHIVE_FILE_LIMIT) -> tuple[str, int]:
    info = regular_file(path, max_bytes=max_bytes)
    if expected_bytes is not None and (type(expected_bytes) is not int or expected_bytes != info.st_size):
        raise ValueError(f"archive byte count mismatch: {path}")
    digest = hashlib.sha256()
    total = 0
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(CHUNK_SIZE)
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                raise ValueError(f"archive exceeds bounded limit: {path}")
            digest.update(chunk)
    if total != info.st_size or (expected_bytes is not None and total != expected_bytes):
        raise ValueError(f"archive changed during hash: {path}")
    return "sha256:" + digest.hexdigest(), total


def verify_ref(path: Path, reference: dict, *, max_bytes: int = ARCHIVE_FILE_LIMIT) -> tuple[str, int]:
    if not isinstance(reference, dict) or not isinstance(reference.get("sha256"), str) or type(reference.get("bytes")) is not int:
        raise ValueError("archive reference requires hash & byte count")
    if reference["bytes"] < 0 or not reference["sha256"].startswith("sha256:"):
        raise ValueError("archive reference shape invalid")
    actual, size = stream_hash(path, expected_bytes=reference["bytes"], max_bytes=max_bytes)
    if actual != reference["sha256"]:
        raise ValueError(f"archive hash mismatch: {path}")
    return actual, size


def stream_copy_verified(source: Path, destination: Path, *, expected_bytes: int, expected_sha256: str | None = None, max_bytes: int = ARCHIVE_FILE_LIMIT) -> int:
    if type(expected_bytes) is not int or expected_bytes < 0:
        raise ValueError("copy byte count invalid")
    regular_file(source, max_bytes=max_bytes)
    _walk_existing(destination.parent)
    destination.parent.mkdir(parents=True, exist_ok=True)
    _walk_existing(destination.parent)
    if destination.exists() or destination.is_symlink():
        raise ValueError(f"copy destination must be fresh: {destination}")
    digest = hashlib.sha256()
    total = 0
    with source.open("rb") as src, destination.open("xb") as dst:
        while True:
            chunk = src.read(CHUNK_SIZE)
            if not chunk:
                break
            total += len(chunk)
            if total > max_bytes:
                raise ValueError(f"copy exceeds bounded limit: {source}")
            digest.update(chunk)
            dst.write(chunk)
    if total != expected_bytes:
        raise ValueError(f"copy byte count drift: {source}")
    if expected_sha256 is not None and "sha256:" + digest.hexdigest() != expected_sha256:
        raise ValueError(f"copy hash drift: {source}")
    return total


def output_path(path: Path) -> None:
    if path.exists() or path.is_symlink():
        raise ValueError(f"output must be fresh: {path}")
    _walk_existing(path.parent)
