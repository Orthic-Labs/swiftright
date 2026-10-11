"""Canonical artifact bytes, measured source hashes & provenance."""

from __future__ import annotations

from datetime import datetime, timezone
import hashlib
from pathlib import Path
import re
from typing import Any

from factory.tools.canonical_json import dump_bytes, load, sha256

_HASH = re.compile(r"sha256:[0-9a-f]{64}\Z")


def canonical_hash(value: Any) -> str:
    return sha256(value)


def file_hash(path: str | Path) -> str:
    return "sha256:" + hashlib.sha256(Path(path).read_bytes()).hexdigest()


def provenance(source: Any, inputs: list[dict[str, str]] | None = None, *,
               producer: str = "sr1-factory", created_at: str | None = None) -> dict[str, Any]:
    """Path hashes raw source bytes; a hash is retained; other values hash canonical JSON."""
    if isinstance(source, Path):
        source_hash = file_hash(source)
    elif isinstance(source, str) and _HASH.fullmatch(source):
        source_hash = source
    else:
        source_hash = canonical_hash(source)
    result: dict[str, Any] = {
        "sourceHash": source_hash,
        "createdAt": created_at or datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "producer": producer,
    }
    if inputs:
        result["inputs"] = inputs
    return result


def artifact_ref(value: dict[str, Any]) -> dict[str, str]:
    return {"id": value["id"], "hash": canonical_hash(value)}


def write_artifact(path: str | Path, value: Any) -> str:
    """Write canonical bytes without a newline; return their actual content hash."""
    destination = Path(path)
    payload = dump_bytes(value)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(payload)
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def load_artifact(path: str | Path) -> Any:
    return load(path)


def validate_artifact(value: Any) -> None:
    from factory.tools.schema_validate import load_registry, validate_artifact as check
    registry, schemas = load_registry(Path(__file__).resolve().parents[1] / "spec/schema")
    errors = check(value, registry, schemas)
    if errors:
        raise ValueError("; ".join(errors))
