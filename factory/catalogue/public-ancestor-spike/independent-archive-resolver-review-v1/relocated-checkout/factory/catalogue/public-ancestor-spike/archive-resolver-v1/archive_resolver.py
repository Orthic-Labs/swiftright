"""Strict resolver for pinned external SDK/tool bytes.

Manifest semantic paths remain exact absolute strings. Only archive paths are
repository-relative & path-checked.
"""
from __future__ import annotations

import gzip
import hashlib
import json
import copy
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
MANIFEST_PATH = ROOT / "factory/catalogue/public-ancestor-spike/archive-inputs-v1/archive-input-mapping.json"
PINNED_MANIFEST_SHA256 = "57d10fa4184cd2585917ca721f94ac9270421ecfd4e2fcd187e0043bf5f49b75"
V2_MANIFEST_PATH = ROOT / "factory/catalogue/public-ancestor-spike/archive-inputs-v2/archive-input-mapping.json"
V2_MANIFEST_SHA256 = "f1d53fde421d58b591c7e69eb35f3811db28785ca4cf15d244ba20b3cbd28dc8"
APPROVED_MANIFESTS = {MANIFEST_PATH: PINNED_MANIFEST_SHA256, V2_MANIFEST_PATH: V2_MANIFEST_SHA256}


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


def _sha_hex(value: Any, label: str) -> str:
    _require(type(value) is str and len(value) == 64 and all(c in "0123456789abcdef" for c in value), f"{label} must be lowercase SHA-256")
    return value


def _absolute_semantic(value: Any, label: str) -> str:
    _require(type(value) is str and value.startswith("/") and "\0" not in value, f"{label} must be exact absolute path string")
    parts = value.split("/")
    _require(len(parts) > 1 and parts[0] == "" and all(part not in ("", ".", "..") for part in parts[1:]), f"{label} contains path alias")
    return value


def _safe_archive_rel(value: Any, label: str) -> str:
    _require(type(value) is str and value, f"{label} must be non-empty string")
    _require("\\" not in value, f"{label} contains backslash")
    parts = value.split("/")
    _require(all(parts) and all(part not in (".", "..") for part in parts), f"{label} escapes repository")
    _require(not value.startswith("/"), f"{label} must be repository-relative")
    return value


def _archive_path(root: Path, relative: Any, label: str) -> Path:
    value = _safe_archive_rel(relative, label)
    candidate = root.joinpath(*value.split("/"))
    root_real = root.resolve()
    _require(candidate.resolve(strict=False).is_relative_to(root_real), f"{label} escapes repository")
    current = root
    for part in value.split("/"):
        current = current / part
        _require(not current.is_symlink(), f"{label} contains symlink")
    return candidate


class ArchiveResolver:
    """Resolve exact external semantic paths through pinned archive bytes."""

    def __init__(self, *, manifest_path: Path = MANIFEST_PATH,
                 expected_manifest_sha256: str = PINNED_MANIFEST_SHA256,
                 archive_root: Path = ROOT,
                 allow_fixture: bool = False) -> None:
        _require(type(allow_fixture) is bool, "allow_fixture must be bool")
        self.manifest_path = Path(manifest_path)
        self.archive_root = Path(archive_root)
        self.allow_fixture = allow_fixture
        self._validate_root(self.archive_root, "archive root")
        self._validate_manifest_path()
        if not allow_fixture:
            _require(self.archive_root.resolve() == ROOT.resolve(), "archive root alias is not pinned")
            approved = APPROVED_MANIFESTS.get(self.manifest_path)
            _require(approved is not None and expected_manifest_sha256 == approved, "manifest path or hash is not approved")
        _sha_hex(expected_manifest_sha256, "manifest hash")
        _require(self.manifest_path.is_file(), "manifest is missing")
        raw = self.manifest_path.read_bytes()
        _require(_sha(raw) == expected_manifest_sha256, "manifest bytes do not match trusted pin")
        try:
            manifest = json.loads(raw)
        except (TypeError, ValueError) as exc:
            raise ArchiveResolverError("manifest is not valid JSON") from exc
        validated = self._validate_manifest(manifest)
        self._records = {}
        for entry in validated["entries"]:
            frozen = copy.deepcopy(entry)
            self._records[entry["semanticPath"]] = frozen
            for alias in entry.get("aliases", []):
                self._records[alias] = copy.deepcopy(frozen)
        self.manifest = copy.deepcopy(validated)

    def _validate_root(self, root: Path, label: str) -> None:
        _require(root.is_absolute() and not root.is_symlink(), f"{label} must be absolute non-symlink")
        current = root
        while True:
            _require(not current.is_symlink(), f"{label} parent is symlink")
            if current.parent == current:
                break
            current = current.parent

    def _validate_manifest_path(self) -> None:
        _require(self.manifest_path.is_absolute() and not self.manifest_path.is_symlink(), "manifest path must be absolute non-symlink")
        if not self.allow_fixture:
            _require(self.manifest_path.resolve(strict=False).is_relative_to(ROOT.resolve()), "manifest path escapes repository")
        current = self.manifest_path.parent
        while True:
            _require(not current.is_symlink(), "manifest parent is symlink")
            if current.parent == current:
                break
            current = current.parent

    def _validate_manifest(self, manifest: Any) -> dict[str, Any]:
        _require(type(manifest) is dict, "manifest must be object")
        _require("schema" in manifest and "status" in manifest, "manifest schema fields missing")
        schema = manifest["schema"]
        _require(schema == "factory.public-ancestor.archive-input-mapping.v1", "manifest schema changed")
        _require(manifest["status"] in ("frozen-inputs-only", "frozen-additive-inputs-only"), "manifest status changed")
        is_v2 = manifest.get("kind") == "additive-force-archive-inputs-v2"
        if is_v2:
            _require(set(manifest) == {"baseMapping", "entries", "kind", "policy", "schema", "sourceScope", "status"}, "v2 manifest fields changed")
            _require(manifest["baseMapping"] == {"path": "factory/catalogue/public-ancestor-spike/archive-inputs-v1/archive-input-mapping.json", "sha256": PINNED_MANIFEST_SHA256}, "v2 base mapping changed")
            _safe_archive_rel(manifest["baseMapping"]["path"], "v2 base mapping path")
        else:
            _require(set(manifest) == {"directoryPrerequisites", "entries", "policy", "schema", "sourceScope", "status"}, "v1 manifest fields changed")
            _require(manifest["status"] == "frozen-inputs-only", "v1 manifest status changed")
            _require(schema == "factory.public-ancestor.archive-input-mapping.v1", "v1 manifest schema changed")
        _require(type(manifest["policy"]) is dict, "policy must be object")
        if "maxArchiveBytes" in manifest["policy"]:
            _strict_int(manifest["policy"]["maxArchiveBytes"], "policy maxArchiveBytes", minimum=0)
        _require(type(manifest["sourceScope"]) is dict, "sourceScope must be object")
        for key, value in manifest["sourceScope"].items():
            _require(type(key) is str and type(value) is str, "sourceScope fields must be strings")
            if key.endswith("Sha256"):
                _sha_hex(value, f"sourceScope {key}")
        if not is_v2:
            self._validate_directories(manifest["directoryPrerequisites"])
        entries = manifest["entries"]
        _require(type(entries) is list and entries, "entries must be non-empty list")
        seen: set[str] = set()
        for index, entry in enumerate(entries):
            self._validate_entry(entry, index, seen)
        return manifest

    def _validate_directories(self, directories: Any) -> None:
        _require(type(directories) is list, "directoryPrerequisites must be list")
        for index, item in enumerate(directories):
            _require(type(item) is dict, f"directory prerequisite {index} must be object")
            expected = {"bytes", "kind", "provenance", "roles", "semanticPath", "sha256"}
            _require(set(item) == expected, f"directory prerequisite {index} schema changed")
            _require(item["kind"] == "directory" and item["bytes"] is None and item["sha256"] is None, f"directory prerequisite {index} changed")
            _absolute_semantic(item["semanticPath"], f"directory prerequisite {index} path")
            _require(type(item["roles"]) is list and type(item["provenance"]) is list, f"directory prerequisite {index} metadata changed")

    def _validate_entry(self, entry: Any, index: int, seen: set[str]) -> None:
        _require(type(entry) is dict, f"entry {index} must be object")
        expected = {"archive", "bytes", "provenance", "roles", "semanticPath", "sha256"}
        has_kind = "kind" in entry
        has_aliases = "aliases" in entry
        allowed = expected | ({"kind", "observedLive"} if has_kind else set()) | ({"aliases"} if has_aliases else set())
        _require(set(entry) <= allowed and expected <= set(entry), f"entry {index} schema changed")
        if has_kind:
            _require(entry["kind"] == "file", f"entry {index} is not file")
        semantic = _absolute_semantic(entry["semanticPath"], f"entry {index} semanticPath")
        _require(semantic not in seen, "duplicate original mapping")
        seen.add(semantic)
        if has_aliases:
            aliases = entry["aliases"]
            _require(type(aliases) is list and aliases, f"entry {index} aliases changed")
            for alias in aliases:
                alias_path = _absolute_semantic(alias, f"entry {index} alias")
                _require(alias_path == semantic, f"entry {index} alias differs from semantic path")
        size = _strict_int(entry["bytes"], f"entry {index} bytes", minimum=0)
        digest = _sha_hex(entry["sha256"], f"entry {index} sha256")
        _require(type(entry["roles"]) is list and type(entry["provenance"]) is list, f"entry {index} metadata changed")
        if "observedLive" in entry:
            observed = entry["observedLive"]
            _require(type(observed) is dict and set(observed) == {"bytes", "sha256"}, f"entry {index} observedLive schema changed")
            _require(_strict_int(observed["bytes"], f"entry {index} observedLive bytes", minimum=0) == size, f"entry {index} observedLive size differs")
            _require(_sha_hex(observed["sha256"], f"entry {index} observedLive sha256") == digest, f"entry {index} observedLive hash differs")
        archive = entry["archive"]
        _require(type(archive) is dict, f"entry {index} archive must be object")
        plain = {"bytes", "compression", "path", "sha256"}
        zipped = plain | {"decompressedBytes", "decompressedSha256"}
        _require(set(archive) in (plain, zipped), f"entry {index} archive schema changed")
        archive_size = _strict_int(archive["bytes"], f"entry {index} archive bytes", minimum=0)
        _sha_hex(archive["sha256"], f"entry {index} archive sha256")
        _safe_archive_rel(archive["path"], f"entry {index} archive path")
        compression = archive["compression"]
        _require(compression in ("none", "gzip"), f"entry {index} archive compression changed")
        if compression == "none":
            _require(set(archive) == plain and archive_size == size and archive["sha256"] == digest, f"entry {index} plain archive descriptor differs")
        else:
            _require(set(archive) == zipped, f"entry {index} gzip archive schema changed")
            _require(_strict_int(archive["decompressedBytes"], f"entry {index} decompressed bytes", minimum=0) == size and archive["decompressedSha256"] == digest, f"entry {index} gzip descriptor differs")
            _sha_hex(archive["decompressedSha256"], f"entry {index} decompressed sha256")

    def verify(self, original_path: str, *, expected_sha256: str | None = None, expected_size: int | None = None) -> dict[str, Any]:
        _require(type(original_path) is str, "original path must be exact string")
        record = self._records.get(original_path)
        _require(record is not None, "original semantic path is not archived")
        if expected_sha256 is not None:
            _require(type(expected_sha256) is str and expected_sha256 == "sha256:" + record["sha256"], "expected hash differs from archive")
        if expected_size is not None:
            _require(type(expected_size) is int and not isinstance(expected_size, bool) and expected_size == record["bytes"], "expected size differs from archive")
        return copy.deepcopy(record)

    def read_bytes(self, original_path: str, *, expected_sha256: str | None = None,
                   expected_size: int | None = None, force_archive: bool = False) -> bytes:
        _require(type(force_archive) is bool, "force_archive must be bool")
        record = self.verify(original_path, expected_sha256=expected_sha256, expected_size=expected_size)
        if not force_archive:
            source = Path(original_path)
            if source.exists():
                _require(source.is_file(), "original source path is not a file")
                raw = source.read_bytes()
                _require(len(raw) == record["bytes"] and _sha(raw) == record["sha256"], "original source bytes are corrupt")
                return raw
        return self._read_archived(record)

    def resolve_path(self, original_path: str, *, force_archive: bool = False) -> Path:
        _require(type(force_archive) is bool, "force_archive must be bool")
        record = self.verify(original_path)
        if not force_archive:
            source = Path(original_path)
            _require(source.is_file(), "original source path is missing")
            _require(_sha(source.read_bytes()) == record["sha256"], "original source bytes are corrupt")
            return source
        archive = record["archive"]
        _require(archive["compression"] == "none", "compressed archive has no raw path; use read_bytes(force_archive=True)")
        path = _archive_path(self.archive_root, archive["path"], "archive path")
        raw = path.read_bytes()
        _require(len(raw) == record["bytes"] and _sha(raw) == record["sha256"], "archive bytes are corrupt")
        return path

    def _read_archived(self, record: dict[str, Any]) -> bytes:
        archive = record["archive"]
        path = _archive_path(self.archive_root, archive["path"], "archive path")
        try:
            encoded = path.read_bytes()
        except OSError as exc:
            raise ArchiveResolverError("archive bytes cannot be read") from exc
        _require(len(encoded) == archive["bytes"] and _sha(encoded) == archive["sha256"], "archive bytes are corrupt")
        if archive["compression"] == "gzip":
            try:
                raw = gzip.decompress(encoded)
            except (OSError, EOFError) as exc:
                raise ArchiveResolverError("gzip archive bytes cannot be decompressed") from exc
        else:
            raw = encoded
        _require(len(raw) == record["bytes"] and _sha(raw) == record["sha256"], "reconstructed archive bytes are corrupt")
        return raw


def pinned_resolver() -> ArchiveResolver:
    return ArchiveResolver()
