"""Constrained byte reader for F10's Mac & Windows origin guards.

This object supplies bytes only. The platform guards remain responsible for
checking invocation, ownership, source, case & process joins.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import stat
from pathlib import Path, PurePosixPath
from typing import Mapping, Sequence

from factory.core.artifacts import canonical_hash
from factory.gate.windows_exit_admission import ROLES


_HASH = re.compile(r"sha256:[0-9a-f]{64}\Z")
_BARE_HASH = re.compile(r"[0-9a-f]{64}\Z")


class ArchiveReadError(ValueError):
    """Raised when reference cannot be resolved within admitted archive roots."""


def _digest(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def _safe_relative(value: object) -> str:
    if (not isinstance(value, str) or not value or "\\" in value or ":" in value or "\x00" in value
            or value in (".", "..")):
        raise ArchiveReadError("unsafe archive-relative reference")
    parsed = PurePosixPath(value)
    if parsed.is_absolute() or ".." in parsed.parts or str(parsed) != value:
        raise ArchiveReadError("unsafe archive-relative reference")
    return value


def _json_bytes(data: bytes, label: str):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ArchiveReadError(f"duplicate JSON key in {label}")
            result[key] = value
        return result

    def bad_constant(_):
        raise ArchiveReadError(f"non-finite JSON constant in {label}")

    try:
        return json.loads(data.decode("utf-8-sig"), object_pairs_hook=pairs,
                          parse_constant=bad_constant)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ArchiveReadError(f"invalid JSON in {label}") from exc


def _read_beneath(root: Path, relative: str, max_bytes: int) -> bytes:
    """Open components with O_NOFOLLOW, so a symlink cannot escape root."""
    relative = _safe_relative(relative)
    components = PurePosixPath(relative).parts
    if not components:
        raise ArchiveReadError("empty archive path")
    directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0) | getattr(os, "O_NOFOLLOW", 0)
    file_flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
    directory_fd = os.open(root, directory_flags)
    opened_dirs = [directory_fd]
    file_fd = None
    try:
        for component in components[:-1]:
            directory_fd = os.open(component, directory_flags, dir_fd=directory_fd)
            opened_dirs.append(directory_fd)
        file_fd = os.open(components[-1], file_flags, dir_fd=directory_fd)
        info = os.fstat(file_fd)
        if not stat.S_ISREG(info.st_mode):
            raise ArchiveReadError("archive reference is not a regular file")
        if info.st_size > max_bytes:
            raise ArchiveReadError("archive reference exceeds configured byte limit")
        chunks = []
        remaining = max_bytes + 1
        while remaining:
            chunk = os.read(file_fd, min(1024 * 1024, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
        data = b"".join(chunks)
        if len(data) > max_bytes:
            raise ArchiveReadError("archive reference exceeds configured byte limit")
        return data
    except OSError as exc:
        raise ArchiveReadError(f"archive path unavailable or symlinked: {relative}") from exc
    finally:
        if file_fd is not None:
            os.close(file_fd)
        for fd in reversed(opened_dirs):
            os.close(fd)


class ArchiveByteReader:
    """Callable ``origin_reader`` bound to admitted filesystem roots.

    ``windows_archives`` maps the bare hex portion of ``canonical_hash(capture)`` to one extracted
    capture directory. Mac references are absolute receipt paths and must fall
    under ``mac_roots``; optional ``mac_path_map`` permits explicit logical to
    archived-file mappings such as a fixture's ``/usr/bin/xcrun`` receipt.
    """

    def __init__(self, *, mac_roots: Sequence[str | Path] = (),
                 windows_archives: Mapping[str, str | Path] | None = None,
                 mac_path_map: Mapping[str, str | Path] | None = None,
                 max_bytes: int = 1024 * 1024 * 1024):
        if type(max_bytes) is not int or max_bytes <= 0:
            raise ValueError("max_bytes must be positive exact integer")
        roots = [Path(item).expanduser().resolve(strict=True) for item in mac_roots]
        if any(not root.is_dir() for root in roots) or len(set(roots)) != len(roots):
            raise ValueError("Mac roots must be distinct existing directories")
        self.mac_roots = tuple(sorted(roots, key=lambda item: len(item.parts), reverse=True))
        self.windows_archives = {}
        for capture_hash, root in (windows_archives or {}).items():
            if not isinstance(capture_hash, str) or not re.fullmatch(r"[0-9a-f]{64}", capture_hash):
                raise ValueError("Windows archive key must be canonical capture hash")
            resolved = Path(root).expanduser().resolve(strict=True)
            if not resolved.is_dir():
                raise ValueError("Windows archive root must be an existing directory")
            self.windows_archives[capture_hash] = resolved
        self.mac_path_map = {}
        for logical, physical in (mac_path_map or {}).items():
            if not isinstance(logical, str) or not logical.startswith("/"):
                raise ValueError("Mac path-map keys must be absolute references")
            target = Path(physical).expanduser().resolve(strict=True)
            if not target.is_file():
                raise ValueError("Mac path-map target must be an existing file")
            self.mac_path_map[logical] = target
        self.max_bytes = max_bytes

    def __call__(self, *, capture: dict, reference):
        if not isinstance(capture, dict):
            raise ArchiveReadError("capture object required")
        platform = capture.get("platform")
        if platform == "macos":
            return self._read_mac(reference)
        if platform == "windows":
            return self._read_windows(capture, reference)
        raise ArchiveReadError("unsupported native capture platform")

    def _read_mac(self, reference) -> bytes:
        if not isinstance(reference, dict) or set(reference) not in ({"path", "sha256"}, {"path", "sha256", "bytes"}):
            raise ArchiveReadError("Mac reference descriptor shape invalid")
        logical = reference["path"]
        expected = reference["sha256"]
        if not isinstance(logical, str) or not logical.startswith("/") or "\x00" in logical or ".." in PurePosixPath(logical).parts:
            raise ArchiveReadError("Mac reference path must be absolute & normalized")
        if str(PurePosixPath(logical)) != logical:
            raise ArchiveReadError("Mac reference path must be normalized")
        if not isinstance(expected, str) or not _HASH.fullmatch(expected):
            raise ArchiveReadError("Mac reference hash invalid")
        if "bytes" in reference and (type(reference["bytes"]) is not int or reference["bytes"] < 0):
            raise ArchiveReadError("Mac reference byte count invalid")

        target = self.mac_path_map.get(logical, Path(logical))
        selected_root = None
        for root in self.mac_roots:
            try:
                relative = target.relative_to(root)
                selected_root = root
                break
            except ValueError:
                continue
        if selected_root is None:
            raise ArchiveReadError("Mac reference is outside admitted roots")
        raw = _read_beneath(selected_root, relative.as_posix(), self.max_bytes)
        if _digest(raw) != expected:
            raise ArchiveReadError("Mac reference bytes differ from pinned hash")
        if "bytes" in reference and len(raw) != reference["bytes"]:
            raise ArchiveReadError("Mac reference byte count differs")
        return raw

    def _read_windows(self, capture: dict, reference) -> bytes:
        if not isinstance(reference, str):
            raise ArchiveReadError("Windows reference must be relative path string")
        relative = _safe_relative(reference)
        capture_hash = canonical_hash(capture).removeprefix("sha256:")
        root = self.windows_archives.get(capture_hash)
        if root is None:
            raise ArchiveReadError("Windows capture has no explicitly admitted archive root")

        conditions = capture.get("meta", {}).get("conditions", {})
        proof = conditions.get("windowsExitProof") if isinstance(conditions, dict) else None
        if not isinstance(proof, dict) or type(proof.get("version")) is not int or proof.get("version") != 1:
            raise ArchiveReadError("Windows exit proof missing or invalid")
        files = proof.get("files")
        if not isinstance(files, dict) or set(files) != set(ROLES):
            raise ArchiveReadError("Windows exit proof role set invalid")
        allowed: dict[str, str] = {}

        def admit(path, digest):
            path = _safe_relative(path)
            if not isinstance(digest, str) or not _HASH.fullmatch(digest):
                raise ArchiveReadError("Windows bound hash invalid")
            prior = allowed.get(path)
            if prior is not None and prior != digest:
                raise ArchiveReadError("Windows archive path has conflicting bindings")
            allowed[path] = digest

        def read_bound(path, expected):
            admit(path, expected)
            raw = _read_beneath(root, path, self.max_bytes)
            if _digest(raw) != expected:
                raise ArchiveReadError(f"Windows bound bytes differ: {path}")
            return raw

        for role, descriptor in files.items():
            if not isinstance(descriptor, dict) or set(descriptor) != {"path", "hash"}:
                raise ArchiveReadError("Windows role descriptor shape invalid")
            admit(descriptor["path"], descriptor["hash"])

        # Nested names are admitted only from already hash-verified proof inputs.
        decoded = {}
        for role in ("compile", "plan", "runtimeTree", "observation"):
            descriptor = files[role]
            raw = read_bound(descriptor["path"], descriptor["hash"])
            decoded[role] = _json_bytes(raw, role)

        if not isinstance(decoded["compile"], dict) or not isinstance(decoded["plan"], dict):
            raise ArchiveReadError("Windows compile/plan proof objects must be JSON objects")
        if not isinstance(decoded["runtimeTree"], list):
            raise ArchiveReadError("Windows runtime tree must be a JSON array")

        compiler_hash = decoded["compile"].get("compilerHash")
        if not isinstance(compiler_hash, str) or not _BARE_HASH.fullmatch(compiler_hash):
            raise ArchiveReadError("Windows compiler hash missing")
        admit("tool/compiler.bin", "sha256:" + compiler_hash)

        source_bindings = decoded["plan"].get("sourceBindings")
        if not isinstance(source_bindings, list) or not source_bindings:
            raise ArchiveReadError("Windows plan source bindings missing")
        for binding in source_bindings:
            if not isinstance(binding, dict):
                raise ArchiveReadError("Windows source binding malformed")
            digest = binding.get("sha256")
            if not isinstance(digest, str) or not _HASH.fullmatch(digest):
                raise ArchiveReadError("Windows source binding hash invalid")
            admit("host/" + _safe_relative(binding.get("path")), digest)

        runtime_bindings = decoded["runtimeTree"]
        if not isinstance(runtime_bindings, list) or not runtime_bindings:
            raise ArchiveReadError("Windows runtime tree missing")
        for binding in runtime_bindings:
            if not isinstance(binding, dict):
                raise ArchiveReadError("Windows runtime binding malformed")
            digest = binding.get("sha256")
            if not isinstance(digest, str) or not _HASH.fullmatch(digest):
                raise ArchiveReadError("Windows runtime binding hash invalid")
            admit("runtime/" + _safe_relative(binding.get("path")), digest)

        observations = decoded["observation"]
        rows = observations if isinstance(observations, list) else [observations]
        run = capture.get("meta", {}).get("run")
        matching = [row for row in rows if isinstance(row, dict) and type(row.get("index")) is int and row.get("index") == run]
        if len(matching) != 1:
            raise ArchiveReadError("Windows raw observation row missing or duplicated")
        observed_files = matching[0].get("files")
        if not isinstance(observed_files, list) or not observed_files:
            raise ArchiveReadError("Windows observation file bindings missing")
        for binding in observed_files:
            if not isinstance(binding, dict):
                raise ArchiveReadError("Windows observation file binding malformed")
            digest = binding.get("sha256")
            if not isinstance(digest, str) or not _BARE_HASH.fullmatch(digest):
                raise ArchiveReadError("Windows observation file hash invalid")
            admit(binding.get("path"), "sha256:" + digest)

        expected = allowed.get(relative)
        if expected is None:
            raise ArchiveReadError("Windows reference is not bound by capture proof")
        return read_bound(relative, expected)

