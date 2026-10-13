"""Offline, data-only rehydration plan for archived Mac compiler bytes.

This module consumes only compiler-tool-archive-v1 bytes. It never resolves,
opens, executes, or falls back to installed compiler paths.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import stat
import sys
from pathlib import Path, PurePosixPath
from typing import Any


REPO = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(REPO))
ARCHIVE_ROOT = REPO / "factory/oracle/mac/compiler-tool-archive-v1"
ARCHIVE_MANIFEST = ARCHIVE_ROOT / "archive-manifest.json"
ARCHIVE_MANIFEST_SHA256 = "sha256:66cb21fad8d62d556e1954aeb9da232f5c05709f172242f050a227068629a8b7"
ARCHIVE_HELPER = ARCHIVE_ROOT / "archive_tool_bytes.py"
ARCHIVE_HELPER_SHA256 = "sha256:d9853b3c78c647da7b6c5834e48d7b57460c6aa262b3697ddee27f462d5a0f5f"
XCRUN_SHA256 = "sha256:bbe7671518a3905f9d3fce54312fbc77c2876b0d62aca74a0688fa869d31a8a9"
FRONTEND_SHA256 = "sha256:84b410d8143298f90ab0b721d488dab90e2fdbf23577ae6186162832a1155cb7"
FRONTEND_RAW_NAME = FRONTEND_SHA256.removeprefix("sha256:") + ".raw"
ARCHIVE_MANIFEST_VERSION = "1"
INTERNAL_CACHE_ROOT = Path("/Users/adrdsouza/Library/Caches/SwiftRightFactory")
DEFAULT_OUTPUT = INTERNAL_CACHE_ROOT / "padding-origin-fresh-v1" / "rehydrated-tool-cache-v1"


def digest(raw: bytes) -> str:
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def _regular(path: Path, label: str) -> None:
    if path.is_symlink() or not path.is_file() or not stat.S_ISREG(path.stat().st_mode):
        raise ValueError(f"{label} must be a regular non-symlink file: {path}")


def _archive_relative(value: Any) -> str:
    if not isinstance(value, str) or not value or "\\" in value or "\x00" in value:
        raise ValueError("archive member path must be relative")
    parsed = PurePosixPath(value)
    if parsed.is_absolute() or ".." in parsed.parts or str(parsed) != value:
        raise ValueError("archive member path escapes archive root")
    return value


def _read_archive_member(entry: dict[str, Any], archive_root: Path = ARCHIVE_ROOT) -> bytes:
    member = _archive_relative(entry.get("archivePath"))
    path = archive_root / member
    _regular(path, "archive member")
    compressed = path.read_bytes()
    if type(entry.get("archiveBytes")) is not int or len(compressed) != entry["archiveBytes"]:
        raise ValueError(f"compressed size mismatch: {member}")
    if digest(compressed) != entry.get("archiveSha256"):
        raise ValueError(f"compressed hash mismatch: {member}")
    compression = entry.get("compression")
    if compression == "gzip":
        raw = gzip.decompress(compressed)
    elif compression == "none":
        raw = compressed
    else:
        raise ValueError(f"unsupported compression: {member}")
    if type(entry.get("bytes")) is not int or len(raw) != entry["bytes"]:
        raise ValueError(f"raw size mismatch: {member}")
    if digest(raw) != entry.get("sha256"):
        raise ValueError(f"raw hash mismatch: {member}")
    return raw


def load_manifest(path: Path = ARCHIVE_MANIFEST) -> dict[str, Any]:
    _regular(path, "archive manifest")
    raw = path.read_bytes()
    if digest(raw) != ARCHIVE_MANIFEST_SHA256:
        raise ValueError("archive manifest hash differs from frozen pin")
    value = json.loads(raw.decode("utf-8"))
    _validate_manifest_identity(value)
    entries = value.get("entries")
    if not isinstance(entries, list) or len(entries) != 2:
        raise ValueError("archive manifest entry set differs")
    by_sha = {entry.get("sha256"): entry for entry in entries if isinstance(entry, dict)}
    if set(by_sha) != {XCRUN_SHA256, FRONTEND_SHA256}:
        raise ValueError("archive tool hash set differs")
    for entry in entries:
        _archive_relative(entry.get("archivePath"))
    return value


def _validate_manifest_identity(value: Any) -> None:
    if (not isinstance(value, dict) or value.get("kind") != "mac-compiler-tool-archive-v1"
            or type(value.get("version")) is not str or value.get("version") != ARCHIVE_MANIFEST_VERSION):
        raise ValueError("archive manifest identity differs")


def write_data_only(path: Path, raw: bytes) -> str:
    """Write exact bytes as regular 0644 data; reject mode or byte fallback."""
    path = Path(path)
    if path.exists() or path.is_symlink():
        _regular(path, "rehydrated output")
        if stat.S_IMODE(path.stat().st_mode) != 0o644:
            raise ValueError(f"existing output mode is not 0644: {path}")
        if path.read_bytes() != raw:
            raise ValueError(f"existing output bytes differ: {path}")
        return "REUSED_EXACT"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(raw)
    path.chmod(0o644)
    _regular(path, "rehydrated output")
    if stat.S_IMODE(path.stat().st_mode) != 0o644 or stat.S_IMODE(path.stat().st_mode) & 0o111:
        raise ValueError(f"rehydrated output mode is not data-only 0644: {path}")
    return "WRITTEN"


def reader_config() -> dict[str, Any]:
    """Return consumer mapping using stable cache filenames, never live paths."""
    return {
        "version": 1,
        "macRoots": ["."],
        "windowsArchives": {},
        "macPathMap": {
            "/usr/bin/xcrun": "xcrun",
            "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc": FRONTEND_RAW_NAME,
            "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend": FRONTEND_RAW_NAME,
        },
    }


def _internal_output(path: Path) -> Path:
    path = path.expanduser()
    if path.is_symlink():
        raise ValueError("rehydration output cannot be a symlink")
    path = path.resolve()
    root = INTERNAL_CACHE_ROOT.resolve()
    if path == root or not path.is_relative_to(root):
        raise ValueError("rehydration output must be an internal SwiftRightFactory cache child")
    return path


def verify_production_mapping(output_dir: Path, config_path: Path, extracted: list[dict[str, Any]]) -> dict[str, Any]:
    """Read every mapped tool through production ArchiveByteReader."""
    from factory.pipeline.reader_config import load_origin_reader_config
    from factory.pipeline.archive_reader import ArchiveByteReader

    reader = load_origin_reader_config(config_path)
    if not isinstance(reader, ArchiveByteReader):
        raise ValueError("production reader config did not yield ArchiveByteReader")
    by_path = {item["path"]: item for item in extracted}
    logical = {
        "/usr/bin/xcrun": "xcrun",
        "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc": FRONTEND_RAW_NAME,
        "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend": FRONTEND_RAW_NAME,
    }
    seen = []
    capture = {"platform": "macos"}
    for logical_path, filename in logical.items():
        item = by_path[filename]
        raw = reader(capture=capture, reference={"path": logical_path, "sha256": item["sha256"], "bytes": item["bytes"]})
        if not isinstance(raw, bytes) or digest(raw) != item["sha256"]:
            raise ValueError(f"production mapping hash mismatch: {logical_path}")
        seen.append({"logicalPath": logical_path, "target": filename, "sha256": item["sha256"], "bytes": len(raw)})
    return {"status": "PASS", "reader": "factory.pipeline.archive_reader.ArchiveByteReader", "references": seen}


def rehydrate(output_dir: Path = DEFAULT_OUTPUT, *, manifest_path: Path = ARCHIVE_MANIFEST) -> dict[str, Any]:
    """Verify archive, write 0644 raw data & relative consumer config."""
    output_dir = _internal_output(output_dir)
    manifest = load_manifest(manifest_path)
    entries = {entry["sha256"]: entry for entry in manifest["entries"]}
    extracted = []
    for expected, name in ((XCRUN_SHA256, "xcrun"), (FRONTEND_SHA256, FRONTEND_RAW_NAME)):
        raw = _read_archive_member(entries[expected], manifest_path.parent)
        destination = output_dir / name
        action = write_data_only(destination, raw)
        extracted.append({"path": name, "bytes": len(raw), "sha256": digest(raw), "mode": "0644", "action": action,
                          "archivePath": entries[expected]["archivePath"], "archiveSha256": entries[expected]["archiveSha256"]})
    config_raw = (json.dumps(reader_config(), indent=2, sort_keys=True) + "\n").encode()
    config_path = output_dir / "reader_config.json"
    config_action = write_data_only(config_path, config_raw)
    production_mapping = verify_production_mapping(output_dir, config_path, extracted)
    receipt = {"version": 1, "status": "PASS", "candidateOnly": True,
               "currentToolReadsDuringReplay": 0, "nativeExecutions": 0, "compilerExecutions": 0,
               "extracted": extracted, "readerConfig": {"path": "reader_config.json", "sha256": digest(config_raw), "action": config_action},
               "archiveManifest": {"path": str(manifest_path), "sha256": digest(manifest_path.read_bytes())},
               "productionMapping": production_mapping, "noExecutableFallback": True, "modePolicy": "0644-exact",
               "archiveManifestVersion": ARCHIVE_MANIFEST_VERSION}
    receipt_raw = (json.dumps(receipt, indent=2, sort_keys=True) + "\n").encode()
    write_data_only(output_dir / "verification-receipt.json", receipt_raw)
    return receipt


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    options = parser.parse_args(argv)
    print(json.dumps(rehydrate(options.output_dir), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
