#!/usr/bin/env python3
"""Pack only explicit SR0 stage inputs into bounded, hash-recorded ZIP."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import zipfile

MAX_MANIFEST_BYTES = 1 * 1024 * 1024
MAX_FILES = 256
MAX_FILE_BYTES = 8 * 1024 * 1024
MAX_TOTAL_BYTES = 32 * 1024 * 1024
CHUNK = 64 * 1024
TOOL_SOURCES = (
    ("sourceMirrorPacker", "pack-source-mirror-r10.py"),
    ("sourceMirrorAdmission", "admit-source-mirror-r10.ps1"),
)


def fail(message: str) -> None:
    raise SystemExit(f"source mirror rejected: {message}")


def safe_rel(value: object) -> str:
    if not isinstance(value, str) or not value or "\\" in value:
        fail("entry path must be nonempty POSIX relative path")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        fail(f"unsafe entry path: {value}")
    return path.as_posix()


def regular_file(path: Path) -> Path:
    if path.is_symlink() or not path.is_file():
        fail(f"source must be regular non-reparse file: {path}")
    return path


def digest(path: Path) -> tuple[int, str]:
    size = 0
    h = hashlib.sha256()
    with path.open("rb") as stream:
        while True:
            block = stream.read(CHUNK)
            if not block:
                break
            size += len(block)
            if size > MAX_FILE_BYTES:
                fail(f"file exceeds 8MiB: {path}")
            h.update(block)
    return size, h.hexdigest()


def read_manifest(path: Path) -> dict:
    item = regular_file(path)
    if item.stat().st_size > MAX_MANIFEST_BYTES:
        fail("manifest exceeds 1MiB")
    try:
        value = json.loads(item.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"manifest unreadable: {exc}")
    if value.get("schema") != "sr0-display-selfjob-v4-source-mirror-r10":
        fail("manifest schema mismatch")
    entries = value.get("entries")
    if not isinstance(entries, list) or not 0 < len(entries) <= MAX_FILES - 4:
        fail("manifest entry count outside bound")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--output-zip", required=True)
    args = parser.parse_args()
    repo = Path(args.repository_root).resolve()
    manifest_path = Path(args.manifest).resolve()
    output = Path(args.output_zip).resolve()
    if not repo.is_dir() or repo.is_symlink():
        fail("repository root must be regular directory")
    if output.parent.is_symlink():
        fail("output parent must not be reparse/symlink")
    if output.exists():
        fail(f"output ZIP must be fresh: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    spec = read_manifest(manifest_path)
    seen: set[str] = set()
    measured: list[dict] = []
    total = 0
    for raw in spec["entries"]:
        if not isinstance(raw, dict):
            fail("entry must be object")
        role = raw.get("role")
        if not isinstance(role, str) or not role or role in {x["role"] for x in measured}:
            fail("entry role must be unique nonempty string")
        rel = safe_rel(raw.get("path"))
        if rel in seen:
            fail(f"duplicate entry path: {rel}")
        seen.add(rel)
        source = regular_file(repo / Path(*PurePosixPath(rel).parts))
        size, sha = digest(source)
        total += size
        if total > MAX_TOTAL_BYTES:
            fail("source aggregate exceeds 32MiB")
        measured.append({"role": role, "path": rel, "bytes": size, "sha256": sha})
    manifest_spec_bytes = manifest_path.read_bytes()
    tool_sources: list[dict] = []
    tool_total = 0
    for role, name in TOOL_SOURCES:
        tool_path = regular_file(manifest_path.parent / name)
        size, sha = digest(tool_path)
        tool_total += size
        tool_sources.append({"role": role, "path": name, "bytes": size, "sha256": sha})
    manifest = {
        "schema": spec["schema"],
        "manifestSpecSha256": hashlib.sha256(manifest_spec_bytes).hexdigest(),
        "maxFiles": MAX_FILES,
        "maxFileBytes": MAX_FILE_BYTES,
        "maxTotalBytes": MAX_TOTAL_BYTES,
        "repositoryRelative": True,
        "entries": measured,
        "toolSources": tool_sources,
        "executables": spec.get("executables", []),
    }
    manifest_bytes = (json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")
    if len(manifest_bytes) > MAX_MANIFEST_BYTES or total + tool_total + len(manifest_bytes) + len(manifest_spec_bytes) > MAX_TOTAL_BYTES:
        fail("manifest pushes source aggregate over 32MiB")
    temp = output.with_name(output.name + f".{os.getpid()}.tmp")
    if temp.exists():
        fail(f"temporary ZIP must be fresh: {temp}")
    try:
        with zipfile.ZipFile(temp, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            info = zipfile.ZipInfo("source-mirror-manifest.json")
            info.date_time = (1980, 1, 1, 0, 0, 0)
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, manifest_bytes)
            info = zipfile.ZipInfo("source-mirror-spec-r10.json")
            info.date_time = (1980, 1, 1, 0, 0, 0)
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, manifest_spec_bytes)
            for tool in tool_sources:
                info = zipfile.ZipInfo(tool["path"])
                info.date_time = (1980, 1, 1, 0, 0, 0)
                info.compress_type = zipfile.ZIP_DEFLATED
                with (manifest_path.parent / tool["path"]).open("rb") as stream:
                    with archive.open(info, "w") as target:
                        while True:
                            block = stream.read(CHUNK)
                            if not block:
                                break
                            target.write(block)
            for entry in measured:
                info = zipfile.ZipInfo(entry["path"])
                info.date_time = (1980, 1, 1, 0, 0, 0)
                info.compress_type = zipfile.ZIP_DEFLATED
                with (repo / Path(*PurePosixPath(entry["path"]).parts)).open("rb") as stream:
                    with archive.open(info, "w") as target:
                        while True:
                            block = stream.read(CHUNK)
                            if not block:
                                break
                            target.write(block)
        os.replace(temp, output)
    except BaseException:
        if temp.exists():
            fail(f"ZIP creation failed; temporary output remains: {temp}")
        raise
    print(json.dumps({"status": "packed", "outputZip": str(output), "fileCount": len(measured) + len(tool_sources) + 2, "sourceBytes": total, "toolBytes": tool_total, "manifestBytes": len(manifest_bytes) + len(manifest_spec_bytes)}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
