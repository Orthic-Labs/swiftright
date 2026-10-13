#!/usr/bin/env python3
"""Bounded F10 input adapter for measured Rectangle Count20 exports.

Export row count is producer-owned. This source-only adapter accepts only
explicit artifact bindings joined to exact export rows; it never discovers,
copies, aliases, or qualifies evidence.
"""
from __future__ import annotations
import argparse, hashlib, json, re
from pathlib import Path
from typing import Any

MAX_JSON = 2 * 1024 * 1024
MAX_ROWS = 2048
MAX_ROW_BYTES = 256 * 1024 * 1024
SHA = re.compile(r"^[0-9a-f]{64}$")
RUN_COUNT = 20
RUN_RE = re.compile(r"(?:^|/)native/native-(\d{2})/")
ROLE_FILES = {
    "outcome": "capture-outcome.json",
    "finalStart": "final-start.json",
    "finalExit": "final-exit-certificate.json",
    "ownedProcess": "owned-process.json",
    "ownedClose": "owned-close.json",
    "terminalWorker": "terminal-worker.json",
    "measuredIdentity": "measured-capture-identity.json",
    "workerInventory": "owned-worker-inventory.json",
    "stdout": "host.stdout.txt",
    "stderr": "host.stderr.txt",
    "pixels": "native.pixels.json",
    "uia": "native.uia.json",
    "ordering": "capture-ordering.json",
}
GLOBAL_ROLES = {
    "plan": "native/plan.json",
    "compile": "native/observation.json",
    "runtimeReceipt": "native/runtime-source-receipt.json",
    "runtimeTree": "native/runtime-source-tree.json",
    "witness": "native/Sources/FactoryProbe/Witness.swift",
    "nativeObservation": "native/native-observation.json",
    "issuedMetadata": "native/issued-metadata.json",
}

class InputError(ValueError):
    pass

def bounded_json(path: Path) -> dict[str, Any]:
    st = path.lstat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_JSON:
        raise InputError(f"bounded JSON required: {path}")
    with path.open("rb") as stream:
        return json.load(stream)

def manifest_sha(path: Path) -> str:
    st = path.lstat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_JSON:
        raise InputError(f"bounded manifest required: {path}")
    h = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024): h.update(chunk)
    return "sha256:" + h.hexdigest()

def rows_of(document: dict[str, Any]) -> dict[str, dict[str, Any]]:
    rows = document.get("files")
    if not isinstance(rows, list) or not rows or len(rows) > MAX_ROWS:
        raise InputError("manifest files must contain 1..2048 rows")
    result: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("path"), str):
            raise InputError("manifest row path missing")
        path = row["path"]
        if path in result or path.startswith("/") or "\\" in path or ".." in Path(path).parts:
            raise InputError(f"unsafe or duplicate manifest path: {path}")
        size = row.get("bytes"); digest = str(row.get("sha256", "")).lower()
        if type(size) is not int or size < 0 or size > MAX_ROW_BYTES or not SHA.fullmatch(digest):
            raise InputError(f"manifest row hash/bytes invalid: {path}")
        result[path] = {"path": path, "bytes": size, "sha256": "sha256:" + digest}
    return result

def artifact_export_refs(path: Path) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    doc = bounded_json(path)
    if doc.get("kind") != "factory-rectangle-explicit-artifact-export-v1":
        raise InputError("artifact export kind mismatch")
    rows = rows_of(doc)
    if doc.get("count") != 3 or len(rows) != 3:
        raise InputError("artifact export must contain exactly three measured rows")
    if type(doc.get("totalBytes")) is not int or doc["totalBytes"] != sum(row["bytes"] for row in rows.values()):
        raise InputError("artifact export totalBytes mismatch")
    result: dict[str, dict[str, Any]] = {}
    seen: set[str] = set()
    for raw in doc.get("files", []):
        role = raw.get("role") if isinstance(raw, dict) else None
        path_value = raw.get("path") if isinstance(raw, dict) else None
        if role not in ("compiler", "exe", "renderer") or role in seen:
            raise InputError("artifact roles must be unique compiler/exe/renderer")
        if not isinstance(path_value, str) or path_value not in rows:
            raise InputError(f"artifact role path absent from export: {role}")
        row = rows[path_value]
        digest = str(raw.get("sha256", "")).lower()
        if digest.startswith("sha256:"): digest = digest[7:]
        if raw.get("bytes") != row["bytes"] or not SHA.fullmatch(digest) or "sha256:" + digest != row["sha256"]:
            raise InputError(f"{role} artifact hash/byte mismatch")
        result[role] = {**row, "role": role, "refKind": "explicit-artifact-export-row"}
        seen.add(role)
    if seen != {"compiler", "exe", "renderer"}:
        raise InputError("artifact export missing compiler/exe/renderer role")
    return doc, result

def assess(document: dict[str, Any], manifest: Path, artifacts: Path, expected_tuple: str, expected_case: str) -> dict[str, Any]:
    rows = rows_of(document); issues: list[str] = []
    if document.get("kind") != "factory-native-observation-export-v1":
        issues.append("Windows export kind mismatch")
    if document.get("captureStatus") != "completed-source-bound-observation":
        issues.append("Windows export captureStatus is not completed-source-bound-observation")
    if document.get("lockReleased") is not True:
        issues.append("Windows export lockReleased certificate missing")
    if document.get("qualified") is not False:
        issues.append("Windows export qualified flag must remain false")
    declared = document.get("count")
    if type(declared) is not int or declared != len(rows):
        issues.append(f"producer count must equal manifest row count ({declared!r} vs {len(rows)})")
    if document.get("tupleID") != expected_tuple: issues.append("tupleID mismatch")
    if document.get("caseID") != expected_case: issues.append("caseID mismatch")
    if document.get("originalParentAtLaunchCertificate") is not True or document.get("originalParentKernelExitCertificate") is not True:
        issues.append("original parent kernel certificates not admitted")
    run_rows: dict[int, dict[str, dict[str, Any]]] = {}
    for path, row in rows.items():
        match = RUN_RE.search(path)
        if match: run_rows.setdefault(int(match.group(1)), {})[path.rsplit("/", 1)[-1]] = row
    if sorted(run_rows) != list(range(1, RUN_COUNT + 1)):
        issues.append(f"expected exactly native-01..native-{RUN_COUNT:02d} proof directories")
    proof = []
    for run in range(1, RUN_COUNT + 1):
        current = run_rows.get(run, {})
        missing = [role for role, name in ROLE_FILES.items() if name not in current]
        if missing: issues.append(f"run {run:02d} missing proof roles: {','.join(missing)}")
        proof.append({"run": run, "roles": {role: current[name] for role, name in ROLE_FILES.items() if name in current}, "missing": missing})
    globals_out = {}
    for role, path in GLOBAL_ROLES.items():
        if path not in rows: issues.append(f"global proof role missing: {role}")
        else: globals_out[role] = rows[path]
    try: artifact_doc, artifacts_out = artifact_export_refs(artifacts)
    except (InputError, OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
        artifact_doc = {}; artifacts_out = {}; issues.append(str(exc))
    merged_rows = [*rows.values(), *artifacts_out.values()]
    status = "ready-for-root-materialization" if not issues else "held"
    return {
        "kind": "factory-rectangle-f10-adapter-input-v3", "version": 3,
        "status": status, "qualified": False,
        "source": {"manifestPath": str(manifest), "manifestSha256": manifest_sha(manifest), "artifactBindingsPath": str(artifacts), "tupleID": expected_tuple, "caseID": expected_case, "requiredCount": RUN_COUNT},
        "export": {"declaredCount": declared, "manifestRowCount": len(rows), "tupleID": document.get("tupleID"), "caseID": document.get("caseID"), "originalParentAtLaunchCertificate": document.get("originalParentAtLaunchCertificate"), "originalParentKernelExitCertificate": document.get("originalParentKernelExitCertificate")},
        "globalRoles": globals_out, "proofRows": proof, "externalByteBindings": artifacts_out,
        "mergedManifest": {"windowsRowCount": len(rows), "artifactRowCount": len(artifacts_out), "rowCount": len(merged_rows), "files": merged_rows, "windowsExportSha256": manifest_sha(manifest), "artifactExportSha256": manifest_sha(artifacts) if artifact_doc else None},
        "missingOrBlocked": issues, "windowsExitProof": {"roles": [*ROLE_FILES, *GLOBAL_ROLES, "compiler", "exe", "renderer"], "nativeParityGranted": False}, "nativeActions": 0,
    }

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--export-manifest", type=Path, required=True); ap.add_argument("--artifact-export-manifest", type=Path, required=True); ap.add_argument("--output", type=Path, required=True); ap.add_argument("--expected-tuple", required=True); ap.add_argument("--expected-case", required=True); args = ap.parse_args()
    try:
        result = assess(bounded_json(args.export_manifest), args.export_manifest, args.artifact_export_manifest, args.expected_tuple, args.expected_case); code = 0 if result["status"] == "ready-for-root-materialization" else 2
    except (InputError, OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
        result = {"kind": "factory-rectangle-f10-adapter-input-v3", "version": 3, "status": "rejected", "qualified": False, "missingOrBlocked": [str(exc)], "nativeActions": 0}; code = 2
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"); return code

if __name__ == "__main__": raise SystemExit(main())
