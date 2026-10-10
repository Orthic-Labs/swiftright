"""Lossless, descriptor-bound archive for the original SwiftUI SDK graphs."""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import tempfile
from typing import Any, Mapping


CHUNK_SIZE = 64 * 1024 * 1024
PINNED_LINK_SHA256 = "836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
LINK_PATH = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
ARCHIVE_PATH = HERE / "archive-manifest.json"


class ArchiveError(ValueError):
    """Archive pins, layout, or reconstructed graph bytes do not validate."""


def sha256(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _require(ok: bool, message: str) -> None:
    if not ok:
        raise ArchiveError(message)


def _safe_relative(value: Any) -> PurePosixPath:
    _require(isinstance(value, str) and value, "empty archive relative path")
    path = PurePosixPath(value)
    _require(not path.is_absolute() and all(part not in ("", ".", "..") for part in path.parts),
             "unsafe archive relative path")
    return path


def _write_gzip_chunk(raw: bytes, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("wb") as stream:
        with gzip.GzipFile(filename="", mode="wb", fileobj=stream, compresslevel=9, mtime=0) as zipped:
            zipped.write(raw)
        stream.flush()
        os.fsync(stream.fileno())


def capture_archive(*, link_path: Path = LINK_PATH, workspace_root: Path = ROOT,
                    output_dir: Path = HERE, chunk_size: int = CHUNK_SIZE) -> dict[str, Any]:
    """Capture exact raw files named by immutable 836, without JSON rewriting."""
    _require(chunk_size == CHUNK_SIZE, "archive chunk size is pinned at 64 MiB")
    link_bytes = link_path.read_bytes()
    _require(sha256(link_bytes) == PINNED_LINK_SHA256, "immutable 836 link artifact bytes changed")
    link = json.loads(link_bytes)
    descriptors = link.get("rawGraphInputs")
    _require(isinstance(descriptors, list) and len(descriptors) == 11,
             "immutable 836 descriptor count changed")

    output_dir.mkdir(parents=True, exist_ok=True)
    files: list[dict[str, Any]] = []
    for ordinal, descriptor in enumerate(descriptors):
        _require(isinstance(descriptor, dict) and isinstance(descriptor.get("path"), str),
                 "malformed immutable 836 raw input descriptor")
        relpath = _safe_relative(descriptor["path"])
        source = workspace_root.joinpath(*relpath.parts)
        source_size = source.stat().st_size
        whole = hashlib.sha256()
        chunks: list[dict[str, Any]] = []
        offset = 0
        with source.open("rb") as stream:
            while True:
                raw = stream.read(CHUNK_SIZE)
                if not raw:
                    break
                whole.update(raw)
                chunk_name = f"input-{ordinal:02d}/chunk-{len(chunks):04d}.json.gz"
                chunk_path = output_dir / chunk_name
                _write_gzip_chunk(raw, chunk_path)
                compressed = chunk_path.read_bytes()
                chunks.append({
                    "index": len(chunks),
                    "offset": offset,
                    "rawSize": len(raw),
                    "rawSha256": sha256(raw),
                    "archivePath": chunk_name,
                    "compressedSize": len(compressed),
                    "compressedSha256": sha256(compressed),
                    "gzipMtime": 0,
                })
                offset += len(raw)
        actual_hash = whole.hexdigest()
        _require(offset == source_size, f"input size changed while archiving: {descriptor['path']}")
        _require(descriptor.get("sha256") == "sha256:" + actual_hash,
                 f"raw graph bytes disagree with immutable 836: {descriptor['path']}")
        files.append({
            "ordinal": ordinal,
            "originalPath": descriptor["path"],
            "originalSize": source_size,
            "originalSha256": actual_hash,
            "chunks": chunks,
        })

    manifest = {
        "kind": "raw-symbolgraph-lossless-archive",
        "version": 1,
        "chunkSize": CHUNK_SIZE,
        "compression": "gzip-level-9-mtime-0",
        "linkEvidencePath": link_path.relative_to(workspace_root).as_posix(),
        "linkEvidenceSha256": PINNED_LINK_SHA256,
        "rawGraphInputs": descriptors,
        "files": files,
    }
    manifest_path = output_dir / "archive-manifest.json"
    _atomic_json(manifest_path, manifest)
    return manifest


def _atomic_json(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = (json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def load_archive(manifest_path: str | Path, *, expected_manifest_sha256: str,
                 link_path: str | Path, workspace_root: str | Path,
                 scratch_root: str | Path) -> dict[str, Path]:
    """Verify every pin, reconstruct all exact files, then expose cache paths.

    Returned paths are under a content-addressed scratch directory. Nothing is
    returned until ordered chunk hashes, source descriptor equality, and each
    whole original-file hash have passed.
    """
    manifest_path = Path(manifest_path)
    link_path = Path(link_path)
    workspace_root = Path(workspace_root)
    scratch_root = Path(scratch_root)
    manifest_raw = manifest_path.read_bytes()
    _require(sha256(manifest_raw) == expected_manifest_sha256,
             "archive manifest bytes do not match trusted manifest pin")
    manifest = json.loads(manifest_raw)
    _require(manifest.get("kind") == "raw-symbolgraph-lossless-archive" and manifest.get("version") == 1,
             "unsupported archive manifest")
    _require(manifest.get("chunkSize") == CHUNK_SIZE and manifest.get("compression") == "gzip-level-9-mtime-0",
             "archive format parameters changed")
    link_raw = link_path.read_bytes()
    live_link_hash = sha256(link_raw)
    _require(manifest.get("linkEvidenceSha256") == PINNED_LINK_SHA256
             and live_link_hash == manifest.get("linkEvidenceSha256"),
             "link evidence bytes do not match immutable 836 pin")
    link = json.loads(link_raw)
    descriptors = link.get("rawGraphInputs")
    _require(isinstance(descriptors, list) and descriptors == manifest.get("rawGraphInputs"),
             "archive inputs differ from exact ordered link descriptors")
    files = manifest.get("files")
    _require(isinstance(files, list) and len(files) == len(descriptors),
             "archive file denominator differs from immutable link descriptors")

    scratch_root.mkdir(parents=True, exist_ok=True)
    final_dir = scratch_root / f"raw-symbolgraph-{expected_manifest_sha256}"
    _require(not final_dir.exists(), "content-addressed archive cache already exists")
    staging = Path(tempfile.mkdtemp(prefix=".raw-symbolgraph-stage-", dir=scratch_root))
    staged: dict[str, Path] = {}
    try:
        for ordinal, (descriptor, record) in enumerate(zip(descriptors, files, strict=True)):
            _require(isinstance(record, dict) and record.get("ordinal") == ordinal,
                     "archive input order or ordinal changed")
            original_path = _safe_relative(descriptor.get("path"))
            _require(record.get("originalPath") == descriptor.get("path"), "archive source path changed")
            _require(descriptor.get("sha256") == "sha256:" + str(record.get("originalSha256")),
                     "whole original hash differs from immutable source descriptor")
            original_size = record.get("originalSize")
            _require(type(original_size) is int and original_size >= 0, "invalid original source size")
            chunks = record.get("chunks")
            _require(isinstance(chunks, list) and bool(chunks), "archive input has no chunks")
            destination = staging.joinpath(*original_path.parts)
            destination.parent.mkdir(parents=True, exist_ok=True)
            digest = hashlib.sha256()
            offset = 0
            with destination.open("wb") as stream:
                for index, chunk in enumerate(chunks):
                    _require(isinstance(chunk, dict) and chunk.get("index") == index,
                             "archive chunk order/index changed")
                    _require(chunk.get("offset") == offset, "archive chunk offset has a gap or overlap")
                    _require(type(chunk.get("gzipMtime")) is int and chunk["gzipMtime"] == 0,
                             "gzip timestamp is not deterministic")
                    archive_rel = _safe_relative(chunk.get("archivePath"))
                    archive_path = manifest_path.parent.joinpath(*archive_rel.parts)
                    _require(archive_path.resolve().is_relative_to(manifest_path.parent.resolve()),
                             "archive chunk resolves outside archive folder")
                    compressed = archive_path.read_bytes()
                    _require(len(compressed) == chunk.get("compressedSize"), "compressed chunk size changed")
                    _require(sha256(compressed) == chunk.get("compressedSha256"), "compressed chunk hash changed")
                    _require(len(compressed) >= 10 and compressed[4:8] == b"\0\0\0\0",
                             "gzip header does not carry deterministic zero mtime")
                    try:
                        raw = gzip.decompress(compressed)
                    except (OSError, EOFError) as exc:
                        raise ArchiveError("compressed chunk cannot be decompressed") from exc
                    _require(len(raw) == chunk.get("rawSize"), "raw chunk size changed")
                    _require(sha256(raw) == chunk.get("rawSha256"), "raw chunk hash changed")
                    if index < len(chunks) - 1:
                        _require(len(raw) == CHUNK_SIZE, "non-final raw chunk is not exactly 64 MiB")
                    stream.write(raw)
                    digest.update(raw)
                    offset += len(raw)
                stream.flush()
                os.fsync(stream.fileno())
            _require(offset == original_size, "reconstructed source size differs from original")
            _require(digest.hexdigest() == record.get("originalSha256"),
                     "reconstructed whole-file SHA-256 differs from immutable descriptor")
            staged[descriptor["path"]] = destination
        os.replace(staging, final_dir)
        return {key: final_dir / Path(*_safe_relative(key).parts) for key in staged}
    except BaseException:
        if staging.exists():
            shutil.rmtree(staging)
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    capture = sub.add_parser("capture")
    capture.add_argument("--link", type=Path, default=LINK_PATH)
    capture.add_argument("--workspace-root", type=Path, default=ROOT)
    capture.add_argument("--output-dir", type=Path, default=HERE)
    args = parser.parse_args(argv)
    if args.command == "capture":
        manifest = capture_archive(link_path=args.link, workspace_root=args.workspace_root,
                                   output_dir=args.output_dir)
        print(json.dumps({"files": len(manifest["files"]),
                          "rawBytes": sum(file["originalSize"] for file in manifest["files"]),
                          "chunks": sum(len(file["chunks"]) for file in manifest["files"]),
                          "manifestSha256": sha256((args.output_dir / "archive-manifest.json").read_bytes())},
                         sort_keys=True))
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
