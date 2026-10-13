"""Offline common.schema verifier for fresh Mac r11 tuple bindings."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import warnings
from pathlib import Path

warnings.filterwarnings("ignore", category=DeprecationWarning)
from jsonschema import Draft202012Validator, RefResolver

CHUNK = 1024 * 1024
MAX_FILE = 64 * 1024 * 1024
MAX_JSON = 1024 * 1024
EXPECTED_SOURCE = "sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b"
EXPECTED_TUPLE = "sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011"
EXPECTED_CASE = "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9"
EXPECTED_CASE_HASH = "sha256:037c8e81cdc19fa488812bea6ed618aaa4ff8960a9b485fc60fc8c61dcc338de"
EXPECTED_MAC_HOST = "sha256:13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777"
EXPECTED_WINDOWS_HOST = "sha256:3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a"


def regular_stat(path: Path, bound: int) -> os.stat_result:
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
        raise ValueError(f"regular non-symlink file required: {path}")
    if info.st_size > bound:
        raise ValueError(f"file exceeds bounded size: {path}")
    return info


def digest(path: Path) -> tuple[str, int]:
    info = regular_stat(path, MAX_FILE)
    size = info.st_size
    if size > MAX_FILE:
        raise ValueError(f"file exceeds 64 MiB bound: {path}")
    h = hashlib.sha256()
    count = 0
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    with os.fdopen(fd, "rb") as stream:
        opened = os.fstat(stream.fileno())
        if (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns) != (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns):
            raise ValueError(f"file changed before reading: {path}")
        while True:
            block = stream.read(CHUNK)
            if not block:
                break
            count += len(block)
            h.update(block)
    after = os.stat(path)
    if count != size or (after.st_size, after.st_mtime_ns) != (info.st_size, info.st_mtime_ns):
        raise ValueError(f"file changed while reading: {path}")
    return "sha256:" + h.hexdigest(), count


def json_file(path: Path, label: str) -> object:
    info = regular_stat(path, MAX_JSON)
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    chunks: list[bytes] = []
    count = 0
    with os.fdopen(fd, "rb") as stream:
        opened = os.fstat(stream.fileno())
        if (opened.st_dev, opened.st_ino, opened.st_size, opened.st_mtime_ns) != (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns):
            raise ValueError(f"{label} changed before reading")
        while True:
            block = stream.read(CHUNK)
            if not block:
                break
            count += len(block)
            chunks.append(block)
    after = os.stat(path)
    if count != info.st_size or (after.st_size, after.st_mtime_ns) != (info.st_size, info.st_mtime_ns):
        raise ValueError(f"{label} changed while reading")
    return json.loads(b"".join(chunks).decode("utf-8"))


def ref(path: Path) -> dict[str, object]:
    sha, size = digest(path)
    return {"path": str(path), "sha256": sha, "bytes": size}


def require_ref(value: object, label: str, measured: dict[str, object]) -> None:
    if not isinstance(value, dict):
        raise ValueError(f"{label} ref missing")
    if value.get("sha256") != measured["sha256"] or value.get("bytes") != measured["bytes"]:
        raise ValueError(f"{label} bytes/hash mismatch")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--tuple", required=True)
    p.add_argument("--schema", required=True)
    p.add_argument("--root-nonce", required=True)
    p.add_argument("--source-hash", required=True)
    p.add_argument("--expected-tuple-id", required=True)
    p.add_argument("--source-binding-file", required=True)
    p.add_argument("--source-archive-file", required=True)
    return p.parse_args()


def verify(args: argparse.Namespace) -> dict[str, object]:
    if not re.fullmatch(r"[0-9a-fA-F]+", args.root_nonce):
        raise ValueError("root nonce must be non-empty hex")
    if args.source_hash != EXPECTED_SOURCE:
        raise ValueError("source hash is not admitted fresh r11 source")
    if args.expected_tuple_id != EXPECTED_TUPLE:
        raise ValueError("expected tuple ID is not measured fresh r11 ID")

    tuple_path = Path(args.tuple)
    schema_path = Path(args.schema)
    binding_path = Path(args.source_binding_file)
    archive_path = Path(args.source_archive_file)
    tuple_doc = json_file(tuple_path, "tuple")
    schema = json_file(schema_path, "schema")
    if not isinstance(tuple_doc, dict) or not isinstance(schema, dict):
        raise ValueError("tuple/schema JSON objects required")
    if schema.get("$id") != "https://swiftright.dev/factory/spec/v0.1/common.schema.json":
        raise ValueError("unexpected common.schema identity")
    def reject_external_refs(node: object) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "$ref" and (not isinstance(value, str) or not value.startswith("#")):
                    raise ValueError("external schema ref rejected")
                reject_external_refs(value)
        elif isinstance(node, list):
            for value in node:
                reject_external_refs(value)
    reject_external_refs(schema)
    if tuple_doc.get("kind") != "factory-source-bound-candidate-canonical-tuple-v1" or tuple_doc.get("version") != 1:
        raise ValueError("fresh tuple wrapper kind/version mismatch")
    if tuple_doc.get("candidateID") != args.expected_tuple_id:
        raise ValueError("fresh tuple candidate ID mismatch")
    if tuple_doc.get("frozenTupleBound") is not False:
        raise ValueError("fresh tuple must remain unfrozen")
    case = tuple_doc.get("case")
    if not isinstance(case, dict) or case.get("id") != EXPECTED_CASE or case.get("hash") != EXPECTED_CASE_HASH:
        raise ValueError("fresh case identity mismatch")
    tuple_value = tuple_doc.get("tuple")
    if not isinstance(tuple_value, dict):
        raise ValueError("fresh tuple payload missing")
    if tuple_value.get("id") != args.expected_tuple_id:
        raise ValueError("fresh tuple payload ID mismatch")
    if tuple_value.get("hostHashes", {}).get("macos") != EXPECTED_MAC_HOST:
        raise ValueError("fresh Mac host hash mismatch")
    if tuple_value.get("hostHashes", {}).get("windows") != EXPECTED_WINDOWS_HOST:
        raise ValueError("fresh Windows host hash mismatch")
    for key in ("sdk", "macosBuild", "runtimeCommit", "rendererHash", "factoryVersion", "acceptanceConfigHash"):
        if not isinstance(tuple_value.get(key), str) or not tuple_value[key]:
            raise ValueError(f"fresh tuple field missing: {key}")

    wrapper = {
        "$schema": schema.get("$schema"),
        "type": "object",
        "required": ["tuple"],
        "properties": {"tuple": {"$ref": schema["$id"] + "#/$defs/tuple"}},
    }
    Draft202012Validator(wrapper, resolver=RefResolver(schema["$id"], schema)).validate({"tuple": tuple_value})
    source_inputs = tuple_doc.get("sourceInputs")
    if not isinstance(source_inputs, dict):
        raise ValueError("fresh tuple source inputs missing")
    source_binding = source_inputs.get("sourceBinding")
    binding_ref = ref(binding_path)
    require_ref(source_binding, "sourceBinding", binding_ref)
    source_archive_ref = ref(archive_path)
    if source_archive_ref["sha256"] != binding_ref["sha256"] or source_archive_ref["bytes"] != binding_ref["bytes"]:
        raise ValueError("source archive/source binding mismatch")
    tuple_ref = ref(tuple_path)
    schema_ref = ref(schema_path)
    tool_ref = ref(Path(__file__).resolve())
    return {
        "kind": "factory-mac-common-schema-validation-receipt-v1",
        "version": "0.1",
        "status": "PASS_LOCAL_COMMON_SCHEMA",
        "exitCode": 0,
        "rootNonce": args.root_nonce,
        "sourceHash": args.source_hash,
        "tupleID": args.expected_tuple_id,
        "caseID": EXPECTED_CASE,
        "caseHash": EXPECTED_CASE_HASH,
        "macHostHash": EXPECTED_MAC_HOST,
        "windowsHostHash": EXPECTED_WINDOWS_HOST,
        "frozenTupleBound": False,
        "candidateTupleRef": tuple_ref,
        "schemaRef": schema_ref,
        "toolRef": tool_ref,
        "sourceRef": source_binding,
        "sourceArchiveRef": source_archive_ref,
        "nativeWindowActions": 0,
        "compilerActions": 0,
        "guiActions": 0,
        "remoteActions": 0,
        "lockActions": 0,
    }


def main() -> int:
    try:
        print(json.dumps(verify(parse_args()), sort_keys=True))
        return 0
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print(f"common schema verification rejected: {exc}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
