"""Strict resolver from immutable semantic paths to repository archive bytes."""
from __future__ import annotations

import gzip
import hashlib
import json
from pathlib import Path, PurePosixPath
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
ARCHIVE_ROOT = ROOT / "factory/catalogue/raw-symbolgraph-archive-v1"
MANIFEST_PATH = ARCHIVE_ROOT / "archive-manifest.json"
LINK_PATH = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
PINNED_MANIFEST_SHA256 = "6ddc54fe90bffd954f415963450cfa04d19d94070631b88619635826ce9139e3"
PINNED_LINK_SHA256 = "836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
CHUNK_SIZE = 64 * 1024 * 1024


class ArchiveResolverError(ValueError):
    """Pinned archive manifest, path, or byte integrity failure."""


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _require(ok: bool, message: str) -> None:
    if not ok:
        raise ArchiveResolverError(message)


def _strict_int(value: Any, label: str, *, minimum: int | None = None) -> int:
    _require(type(value) is int, f"{label} must be strict integer")
    if minimum is not None:
        _require(value >= minimum, f"{label} below minimum")
    return value


def _safe_rel(value: Any, label: str) -> PurePosixPath:
    _require(type(value) is str and value, f"{label} must be non-empty string")
    _require("\\" not in value, f"{label} contains backslash")
    _require(all(part for part in value.split("/")), f"{label} contains empty component")
    path = PurePosixPath(value)
    _require(not path.is_absolute() and all(part not in ("", ".", "..") for part in path.parts), f"{label} escapes repository")
    return path


def _sha_hex(value: Any, label: str) -> str:
    _require(type(value) is str and len(value) == 64 and all(c in "0123456789abcdef" for c in value), f"{label} must be lowercase SHA-256")
    return value


def _under(root: Path, path: Path, label: str) -> Path:
    root_real = root.resolve()
    candidate = root.joinpath(*_safe_rel(path.relative_to(root).as_posix(), label).parts) if path.is_relative_to(root) else path
    _require(not candidate.is_symlink(), f"{label} is symlink")
    for parent in [candidate, *candidate.parents]:
        if parent == root_real.parent:
            break
        if parent.exists():
            _require(not parent.is_symlink(), f"{label} contains symlink")
        if parent == root_real:
            break
    resolved = candidate.resolve(strict=False)
    _require(resolved.is_relative_to(root_real), f"{label} escapes repository")
    return candidate


def _repo_archive_path(root: Path, rel: Any, label: str) -> Path:
    safe = _safe_rel(rel, label)
    candidate = root.joinpath(*safe.parts)
    _require(not candidate.is_symlink(), f"{label} is symlink")
    current = root
    for part in safe.parts:
        current = current / part
        _require(not current.is_symlink(), f"{label} contains symlink")
    _require(candidate.resolve(strict=False).is_relative_to(root.resolve()), f"{label} escapes archive root")
    return candidate


class ArchiveResolver:
    """Resolve exact original semantic paths through pinned repository archive bytes."""

    def __init__(self, *, manifest_path: Path = MANIFEST_PATH,
                 expected_manifest_sha256: str = PINNED_MANIFEST_SHA256,
                 archive_root: Path = ARCHIVE_ROOT,
                 workspace_root: Path = ROOT,
                 allow_fixture: bool = False) -> None:
        self.manifest_path = Path(manifest_path)
        self.archive_root = Path(archive_root)
        self.workspace_root = Path(workspace_root)
        self.allow_fixture = allow_fixture
        _require(not self.archive_root.is_symlink() and not self.workspace_root.is_symlink(), "resolver roots must not be symlinks")
        if not allow_fixture:
            _require(self.manifest_path.resolve() == MANIFEST_PATH.resolve(), "manifest alias is not pinned")
            _require(self.archive_root.resolve() == ARCHIVE_ROOT.resolve(), "archive root alias is not pinned")
            _require(expected_manifest_sha256 == PINNED_MANIFEST_SHA256, "manifest hash is not pinned")
        self.expected_manifest_sha256 = expected_manifest_sha256
        _require(self.manifest_path.is_file() and not self.manifest_path.is_symlink(), "manifest is missing or symlink")
        parent = self.manifest_path.parent
        while parent != parent.parent:
            _require(not parent.is_symlink(), "manifest parent is symlink")
            if parent == self.archive_root:
                break
            parent = parent.parent
        try:
            manifest_raw = self.manifest_path.read_bytes()
        except OSError as exc:
            raise ArchiveResolverError("manifest bytes cannot be read") from exc
        _require(_sha(manifest_raw) == expected_manifest_sha256, "manifest bytes do not match trusted pin")
        self.manifest = self._validate_manifest(json.loads(manifest_raw))
        self._records = {record["originalPath"]: record for record in self.manifest["files"]}
        if not allow_fixture:
            self._validate_link_evidence()

    def _validate_manifest(self, manifest: Any) -> dict[str, Any]:
        _require(type(manifest) is dict, "manifest must be object")
        expected = {"captureSources", "chunkSize", "compression", "files", "kind", "linkEvidencePath", "linkEvidenceSha256", "rawGraphInputs", "version"}
        _require(set(manifest) == expected, "manifest fields differ from pinned schema")
        _require(manifest["kind"] == "raw-symbolgraph-lossless-archive", "manifest kind changed")
        _require(_strict_int(manifest["version"], "manifest version") == 1, "manifest version changed")
        _require(_strict_int(manifest["chunkSize"], "chunkSize") == CHUNK_SIZE, "chunk size changed")
        _require(manifest["compression"] == "gzip-level-9-mtime-0", "compression changed")
        _sha_hex(manifest["linkEvidenceSha256"], "linkEvidenceSha256")
        _safe_rel(manifest["linkEvidencePath"], "linkEvidencePath")
        sources = manifest["captureSources"]
        _require(type(sources) is dict, "captureSources must be object")
        for name, digest in sources.items():
            _safe_rel(name, "capture source path")
            _sha_hex(digest, f"capture source hash {name}")
        descriptors = manifest["rawGraphInputs"]
        files = manifest["files"]
        _require(type(descriptors) is list and type(files) is list and len(descriptors) == len(files), "descriptor/file counts differ")
        seen: set[str] = set()
        for ordinal, (descriptor, record) in enumerate(zip(descriptors, files, strict=True)):
            _require(type(descriptor) is dict and set(descriptor) == {"path", "sha256"}, "descriptor schema changed")
            original = _safe_rel(descriptor["path"], "original path")
            original_text = original.as_posix()
            _require(original_text not in seen, "duplicate original mapping")
            seen.add(original_text)
            _require(type(descriptor["sha256"]) is str and descriptor["sha256"].startswith("sha256:"), "descriptor SHA prefix missing")
            descriptor_hash = _sha_hex(descriptor["sha256"][7:], "descriptor SHA")
            _require(type(record) is dict, "file record must be object")
            _require(_strict_int(record.get("ordinal"), "file ordinal") == ordinal, "file ordinal changed")
            _require(record.get("originalPath") == original_text, "original semantic path changed")
            _require(_strict_int(record.get("originalSize"), "original size", minimum=0) >= 0, "original size changed")
            _require(record.get("originalSha256") == descriptor_hash, "original whole hash differs from descriptor")
            self._validate_storage(record, ordinal)
        return manifest

    def _validate_storage(self, record: dict[str, Any], ordinal: int) -> None:
        modes = [key for key in ("chunks", "plainPath", "gzipPath") if key in record]
        _require(len(modes) == 1, f"file {ordinal} must have one archive storage mode")
        mode = modes[0]
        base_fields = {"ordinal", "originalPath", "originalSize", "originalSha256"}
        _require(set(record) == base_fields | {mode}, f"file {ordinal} schema changed")
        if mode == "chunks":
            chunks = record[mode]
            _require(type(chunks) is list and bool(chunks), f"file {ordinal} has no chunks")
            offset = 0
            for index, chunk in enumerate(chunks):
                _require(type(chunk) is dict and set(chunk) == {"archivePath", "compressedSha256", "compressedSize", "gzipMtime", "index", "offset", "rawSha256", "rawSize"}, "chunk schema changed")
                _require(_strict_int(chunk.get("index"), "chunk index") == index, "chunk index changed")
                _require(_strict_int(chunk.get("offset"), "chunk offset", minimum=0) == offset, "chunk offsets have gap or overlap")
                _require(_strict_int(chunk.get("rawSize"), "raw chunk size", minimum=0) >= 0, "raw chunk size changed")
                _require(_strict_int(chunk.get("compressedSize"), "compressed chunk size", minimum=0) >= 0, "compressed chunk size changed")
                _require(_strict_int(chunk.get("gzipMtime"), "gzip mtime") == 0, "gzip mtime changed")
                _sha_hex(chunk.get("rawSha256"), "raw chunk SHA")
                _sha_hex(chunk.get("compressedSha256"), "compressed chunk SHA")
                _safe_rel(chunk.get("archivePath"), "archive chunk path")
                offset += chunk["rawSize"]
            _require(offset == record["originalSize"], "chunk sizes differ from original size")
        elif mode == "plainPath":
            _safe_rel(record[mode], "plain archive path")
        else:
            _safe_rel(record[mode], "gzip archive path")

    def _validate_link_evidence(self) -> None:
        _require(self.manifest["linkEvidenceSha256"] == PINNED_LINK_SHA256, "link hash is not immutable836")
        link_path = _repo_archive_path(self.workspace_root, self.manifest["linkEvidencePath"], "link evidence path")
        _require(link_path == LINK_PATH, "link evidence path changed")
        try:
            link_raw = link_path.read_bytes()
        except OSError as exc:
            raise ArchiveResolverError("link evidence bytes cannot be read") from exc
        _require(_sha(link_raw) == PINNED_LINK_SHA256, "link evidence bytes changed")
        link = json.loads(link_raw)
        _require(link.get("rawGraphInputs") == self.manifest["rawGraphInputs"], "manifest descriptors differ from immutable link")

    def verify(self, original_path: str, *, expected_sha256: str | None = None) -> dict[str, Any]:
        safe = _safe_rel(original_path, "original path")
        key = safe.as_posix()
        record = self._records.get(key)
        _require(record is not None, "original semantic path is not archived")
        if expected_sha256 is not None:
            _require(type(expected_sha256) is str and expected_sha256.startswith("sha256:"), "expected hash must use sha256 prefix")
            _require(expected_sha256 == "sha256:" + record["originalSha256"], "expected original hash differs from archive")
        return record

    def read_bytes(self, original_path: str, *, expected_sha256: str | None = None, force_archive: bool = False) -> bytes:
        record = self.verify(original_path, expected_sha256=expected_sha256)
        if not force_archive:
            source = _repo_archive_path(self.workspace_root, original_path, "original source path")
            if source.exists():
                _require(source.is_file(), "original source path is not a file")
                raw = source.read_bytes()
                _require(_sha(raw) == record["originalSha256"] and len(raw) == record["originalSize"], "original source bytes are corrupt")
                return raw
        return self._read_archived(record)

    def resolve_path(self, original_path: str, *, force_archive: bool = False) -> Path:
        """Return verified live path; chunked archive callers must use read_bytes."""
        record = self.verify(original_path)
        if force_archive:
            _require("chunks" not in record, "chunked archive has no single path; use read_bytes(force_archive=True)")
            key = record.get("plainPath") or record.get("gzipPath")
            return _repo_archive_path(self.archive_root, key, "archive path")
        source = _repo_archive_path(self.workspace_root, original_path, "original source path")
        _require(source.is_file() and _sha(source.read_bytes()) == record["originalSha256"], "original source path is missing or corrupt")
        return source

    def _read_archived(self, record: dict[str, Any]) -> bytes:
        if "chunks" in record:
            result = bytearray()
            for chunk in record["chunks"]:
                path = _repo_archive_path(self.archive_root, chunk["archivePath"], "archive chunk path")
                try:
                    compressed = path.read_bytes()
                except OSError as exc:
                    raise ArchiveResolverError("compressed archive bytes cannot be read") from exc
                _require(len(compressed) == chunk["compressedSize"], "compressed archive bytes changed")
                _require(_sha(compressed) == chunk["compressedSha256"], "compressed archive SHA changed")
                _require(len(compressed) >= 8 and compressed[4:8] == b"\0\0\0\0", "gzip mtime bytes changed")
                try:
                    raw = gzip.decompress(compressed)
                except (OSError, EOFError) as exc:
                    raise ArchiveResolverError("compressed archive bytes cannot be decompressed") from exc
                _require(len(raw) == chunk["rawSize"] and _sha(raw) == chunk["rawSha256"], "raw archive chunk changed")
                result.extend(raw)
            raw = bytes(result)
        else:
            key = record.get("plainPath") or record.get("gzipPath")
            path = _repo_archive_path(self.archive_root, key, "archive path")
            try:
                encoded = path.read_bytes()
            except OSError as exc:
                raise ArchiveResolverError("archive bytes cannot be read") from exc
            if "gzipPath" in record:
                try:
                    raw = gzip.decompress(encoded)
                except (OSError, EOFError) as exc:
                    raise ArchiveResolverError("gzip archive bytes cannot be decompressed") from exc
            else:
                raw = encoded
        _require(len(raw) == record["originalSize"] and _sha(raw) == record["originalSha256"], "reconstructed archive bytes changed")
        return raw


def pinned_resolver() -> ArchiveResolver:
    """Return resolver bound to immutable repository archive; no aliases accepted."""
    return ArchiveResolver()
