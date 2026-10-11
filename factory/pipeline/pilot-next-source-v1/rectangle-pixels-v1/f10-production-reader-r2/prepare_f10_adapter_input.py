#!/usr/bin/env python3
"""Assess explicit Rectangle F10 export rows for reader input materialization.

This source-only preparer never discovers or copies archive files. It emits a
held input map until parent exit certification, compiler, executable, renderer,
all proof roles, & exact source joins are present.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

MAX_JSON = 2 * 1024 * 1024
SHA = re.compile(r"^[0-9a-f]{64}$")
COUNT = 20
EXPECTED_TUPLE = "sr1-rectangle-r11-source-paired20-20261011"
EXPECTED_CASE = "swiftui.shapes.fill-stroke.recipe.pilot-next.rectangle-fill-light.025c6e76f4061037"
ROLES = ("outcome", "observation", "owned", "close", "plan", "compile", "witness", "exe", "renderer", "runtimeReceipt", "runtimeTree", "stdout", "stderr")


class InputError(ValueError):
    pass


def bounded_json(path: Path) -> dict:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_JSON:
        raise InputError(f"bounded export manifest required: {path}")
    with path.open("rb") as stream:
        return json.load(stream)


def manifest_sha(path: Path) -> str:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_JSON:
        raise InputError(f"bounded export manifest required: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def row_index(document: dict) -> dict[str, dict]:
    rows = document.get("files")
    if not isinstance(rows, list) or not rows:
        raise InputError("export manifest files array required")
    result = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("path"), str):
            raise InputError("export row path required")
        if row["path"] in result:
            raise InputError(f"duplicate export row: {row['path']}")
        if type(row.get("bytes")) is not int or row["bytes"] < 0 or not SHA.fullmatch(str(row.get("sha256", ""))):
            raise InputError(f"export row hash/bytes invalid: {row['path']}")
        result[row["path"]] = {"path": row["path"], "bytes": row["bytes"], "sha256": "sha256:" + row["sha256"]}
    return result


def required_paths(run: int) -> dict[str, str]:
    prefix = f"native/native-{run:02d}"
    return {
        "outcome": f"{prefix}/capture-outcome.json",
        "observation": "native/native-observation.json",
        "owned": f"{prefix}/owned-process.json",
        "close": f"{prefix}/owned-close.json",
        "plan": "native/plan.json",
        "compile": "native/observation.json",
        "witness": "native/Sources/FactoryProbe/Witness.swift",
        "runtimeReceipt": "native/runtime-source-receipt.json",
        "runtimeTree": "native/runtime-source-tree.json",
        "stdout": f"{prefix}/host.stdout.txt",
        "stderr": f"{prefix}/host.stderr.txt",
    }


def _sha_ref(value: object) -> str:
    text = str(value)
    return text if text.startswith("sha256:") else "sha256:" + text


def external_bindings(document: dict, rows: dict[str, dict], issues: list[str]) -> dict[str, dict]:
    """Resolve explicit compiler/exe/renderer byte refs when producer exports them.

    Suffix discovery remains diagnostic fallback for old exports; future admitted
    exports must carry explicit path/bytes/hash refs, which are joined to rows.
    """
    explicit = document.get("externalByteBindings")
    if explicit is not None:
        if not isinstance(explicit, dict):
            issues.append("externalByteBindings must be an object")
            return {}
        result: dict[str, dict] = {}
        for role in ("compiler", "exe", "renderer"):
            ref = explicit.get(role)
            if not isinstance(ref, dict) or not isinstance(ref.get("path"), str):
                issues.append(f"explicit {role} byte binding missing")
                continue
            path = ref["path"]
            row = rows.get(path)
            if row is None:
                issues.append(f"explicit {role} byte binding row missing: {path}")
                continue
            if type(ref.get("bytes")) is not int or ref["bytes"] < 0:
                issues.append(f"explicit {role} byte count invalid: {path}")
                continue
            expected_bytes = ref["bytes"]
            expected_sha = _sha_ref(ref.get("sha256", ""))
            if expected_bytes != row["bytes"] or expected_sha != row["sha256"]:
                issues.append(f"explicit {role} byte binding drift: {path}")
                continue
            result[role] = {"path": path, "bytes": row["bytes"], "sha256": row["sha256"], "refKind": "explicit-export-row"}
        return result

    result = {}
    suffixes = {
        "compiler": lambda path: path.lower().endswith("swift.exe"),
        "exe": lambda path: path.lower().endswith(".exe") and not path.lower().endswith("swift.exe"),
        "renderer": lambda path: "renderer" in path.lower(),
    }
    for role, predicate in suffixes.items():
        matches = sorted(path for path in rows if predicate(path))
        if len(matches) != 1:
            issues.append(f"{role} byte binding requires exactly one explicit export row; found {len(matches)}")
        elif matches:
            result[role] = {**rows[matches[0]], "refKind": "legacy-export-row-diagnostic"}
    return result


def assess_export(document: dict, manifest_path: Path, expected_tuple: str = EXPECTED_TUPLE, expected_case: str = EXPECTED_CASE) -> dict:
    rows = row_index(document)
    issues: list[str] = []
    if document.get("count") != 760:
        issues.append("export count must equal 760")
    if document.get("tupleID") != expected_tuple:
        issues.append("export tupleID mismatch")
    if document.get("originalParentKernelExitCertificate") is not True:
        issues.append("parent kernel exit certificate is not admitted")

    proof_rows = []
    for run in range(1, COUNT + 1):
        role_paths = required_paths(run)
        missing = [role for role, path in role_paths.items() if path not in rows]
        if missing:
            issues.append(f"run {run:02d} missing proof rows: {','.join(missing)}")
        proof_rows.append({"run": run, "roles": {role: rows[path] for role, path in role_paths.items() if path in rows}, "missing": missing})

    external = external_bindings(document, rows, issues)

    source = {
        "manifestPath": str(manifest_path),
        "manifestSha256": manifest_sha(manifest_path),
        "tupleID": expected_tuple,
        "caseID": expected_case,
        "requiredCount": COUNT,
    }
    return {
        "kind": "factory-rectangle-f10-adapter-input-v1",
        "version": 1,
        "status": "ready-for-root-materialization" if not issues else "held",
        "qualified": False,
        "source": source,
        "export": {"declaredCount": document.get("count"), "manifestSha256": source["manifestSha256"], "originalParentKernelExitCertificate": document.get("originalParentKernelExitCertificate")},
        "proofRows": proof_rows,
        "externalByteBindings": external,
        "missingOrBlocked": issues,
        "windowsExitProof": {"roles": list(ROLES), "nativeParityGranted": False},
        "nativeActions": 0,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--export-manifest", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expected-tuple", default=EXPECTED_TUPLE)
    parser.add_argument("--expected-case", default=EXPECTED_CASE)
    args = parser.parse_args()
    try:
        document = bounded_json(args.export_manifest)
        result = assess_export(document, args.export_manifest, args.expected_tuple, args.expected_case)
        code = 0 if result["status"] == "ready-for-root-materialization" else 2
    except (InputError, OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
        result = {"kind": "factory-rectangle-f10-adapter-input-v1", "version": 1, "status": "rejected", "qualified": False, "missingOrBlocked": [str(exc)], "nativeActions": 0}
        code = 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
