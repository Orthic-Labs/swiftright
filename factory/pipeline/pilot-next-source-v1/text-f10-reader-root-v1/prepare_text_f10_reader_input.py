#!/usr/bin/env python3
"""Bounded F10 reader-input adapter for measured Text Windows20 exports.

This adapter admits explicit archive rows & measured Text compiler joins. It
does not discover files, rewrite captures, run native code, or grant parity.
Mac input remains an observational report with its terminal/dimension/paint
holds preserved verbatim.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import stat
from pathlib import Path
from typing import Any

MAX_JSON = 4 * 1024 * 1024
MAX_FILE = 256 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024
MAX_ROWS = 2048
SHA = "sha256:"
HEX = re.compile(r"^[0-9a-f]{64}$")
COUNT = 20
CASE_ID = "swiftui.text.layout.baseline.recipe.pilot-next.text-baseline-light.54310440be2e6418"
CASE_HASH = SHA + "29807aa918aa7c2c1c4a4705eb324b0020f29060be7359d4923694aeb5d437ad"
TUPLE_ID = "sr1-text-paint-v2-r11-paired20-20261012"
SOURCE_HASH = SHA + "4770ac41a8826891d972725f4af8e56f92c5b66ead5777eee677692cec71701e"
PLAN_HASH = SHA + "de8660b0c55a717d52171ec476b833881919696f434c3ceba077ba3b77fbc642"
COMPILE_HASH = SHA + "bef8851cef48e96889bb46f8e66d85cff7f9f0f8f19e34c65d3d09c38036010b"
EXE_HASH = SHA + "33248eaa0369e8d4b5e7dea9e1df7d6d86110ee3f31c8fdc9db61a500d057fe7"
RENDERER_HASH = SHA + "e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93"
SERIALIZER_HASH = SHA + "952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba"
RUNTIME_COMMIT = "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b"
RUN_RE = re.compile(r"^native/native-(\d{2})/")
ROLE_FILES = (
    "capture-outcome.json", "final-start.json", "final-exit-certificate.json",
    "owned-process.json", "owned-close.json", "terminal-worker.json",
    "measured-capture-identity.json", "owned-worker-inventory.json",
    "host.stdout.txt", "host.stderr.txt", "native.pixels.json", "native.uia.json",
    "native.printwindow.png", "native.screen.png",
)
GLOBAL_FILES = (
    "native/plan.json", "native/observation.json", "native/runtime-source-receipt.json",
    "native/runtime-source-tree.json", "native/native-observation.json",
    "native/candidate-binding.json", "native/candidate-tuple.json",
    "admission/source-inputs.json", "admission/recipe.json",
)


class Hold(ValueError):
    pass


def safe_rel(value: str) -> Path:
    p = Path(value)
    if not value or p.is_absolute() or "\\" in value or ".." in p.parts:
        raise Hold(f"unsafe archive path: {value}")
    return p


def bounded_bytes(path: Path, limit: int = MAX_JSON) -> bytes:
    st = path.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode) or st.st_size > limit:
        raise Hold(f"bounded regular file required: {path}")
    out = bytearray()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            out.extend(chunk)
            if len(out) > limit:
                raise Hold(f"file grew past bound: {path}")
    return bytes(out)


def bounded_json(path: Path) -> Any:
    try:
        return json.loads(bounded_bytes(path).decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise Hold(f"invalid JSON: {path}: {exc}") from exc


def streamed_digest(path: Path, limit: int = MAX_FILE) -> tuple[int, str]:
    st = path.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode) or st.st_size > limit:
        raise Hold(f"bounded regular file required: {path}")
    count = 0
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            count += len(chunk)
            if count > limit:
                raise Hold(f"file grew past bound: {path}")
            digest.update(chunk)
    return count, SHA + digest.hexdigest()


def sha_ref(value: Any) -> str:
    raw = str(value).lower()
    if raw.startswith(SHA):
        raw = raw[len(SHA):]
    if not HEX.fullmatch(raw):
        raise Hold(f"invalid sha256 reference: {value}")
    return SHA + raw


def hash_matches(value: Any, expected: str) -> bool:
    try:
        return sha_ref(value) == sha_ref(expected)
    except Hold:
        return False


def manifest_rows(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    rows = manifest.get("files")
    if not isinstance(rows, list) or not rows or len(rows) > MAX_ROWS:
        raise Hold("export manifest rows must be 1..2048")
    result: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("path"), str):
            raise Hold("export manifest row path missing")
        path = row["path"]
        safe_rel(path)
        if path in result:
            raise Hold(f"duplicate export row: {path}")
        size = row.get("bytes")
        if type(size) is not int or size < 0 or size > MAX_FILE:
            raise Hold(f"invalid export row bytes: {path}")
        result[path] = {"path": path, "bytes": size, "sha256": sha_ref(row.get("sha256"))}
    return result


def read_row(root: Path, rows: dict[str, dict[str, Any]], path: str, total: list[int]) -> dict[str, Any]:
    if path not in rows:
        raise Hold(f"archive row missing: {path}")
    rel = safe_rel(path)
    current = root
    for part in rel.parts:
        current = current / part
        if current.is_symlink():
            raise Hold(f"archive symlink component: {path}")
    size, digest = streamed_digest(current, MAX_FILE)
    expected = rows[path]
    if size != expected["bytes"] or digest != expected["sha256"]:
        raise Hold(f"archive row bytes/hash drift: {path}")
    total[0] += size
    if total[0] > MAX_TOTAL:
        raise Hold("archive exceeds 256MiB read bound")
    return expected


def require_identity(doc: dict[str, Any], label: str) -> None:
    case = doc.get("case")
    if isinstance(case, dict) and (case.get("id") != CASE_ID or case.get("hash") != CASE_HASH):
        raise Hold(f"{label} case identity mismatch")


def validate_mac_report(path: Path) -> dict[str, Any]:
    report = bounded_json(path)
    if not isinstance(report, dict) or report.get("status") != "observed-diagnostic":
        raise Hold("Mac report is not observed diagnostic")
    if report.get("semantic", {}).get("qualification") != "held":
        raise Hold("Mac report qualification must remain held")
    semantic = report.get("semantic")
    if not isinstance(semantic, dict) or "textBounds" not in semantic or "defaultPaint" not in semantic:
        raise Hold("Mac report lacks text bounds/default-paint observations")
    holds = report.get("holds")
    if not isinstance(holds, list) or not any("Mac original-process exit/cleanup evidence absent" in str(item) for item in holds):
        raise Hold("Mac report missing measured terminal hold")
    return {"status": report.get("status"), "qualification": semantic.get("qualification"),
            "holds": holds, "textBounds": semantic["textBounds"], "defaultPaint": semantic["defaultPaint"]}


def assess(archive_root: Path, mac_report: Path, output: Path) -> int:
    issues: list[str] = []
    total = [0]
    try:
        manifest_path = archive_root / "export-manifest.json"
        manifest = bounded_json(manifest_path)
        if manifest.get("kind") != "factory-native-observation-export-v1":
            raise Hold("Text export kind mismatch")
        if manifest.get("captureStatus") != "completed-source-bound-observation":
            raise Hold("Text export capture status mismatch")
        if manifest.get("qualified") is not False or manifest.get("lockReleased") is not True:
            raise Hold("Text export qualification/lock state mismatch")
        if manifest.get("tupleID") != TUPLE_ID:
            raise Hold("Text export tuple mismatch")
        rows = manifest_rows(manifest)
        if type(manifest.get("count")) is not int or manifest["count"] != len(rows):
            raise Hold("Text export declared count does not equal measured archive row count")
        run_paths = {int(match.group(1)) for path in rows if (match := RUN_RE.match(path))}
        if run_paths != set(range(1, COUNT + 1)):
            raise Hold("Text export native run directories are not exactly 01..20")
        for run in range(1, COUNT + 1):
            prefix = f"native/native-{run:02d}/"
            for name in ROLE_FILES:
                read_row(archive_root, rows, prefix + name, total)
        for path in GLOBAL_FILES:
            read_row(archive_root, rows, path, total)
        source_inputs = bounded_json(archive_root / "admission/source-inputs.json")
        plan = bounded_json(archive_root / "native/plan.json")
        compile_doc = bounded_json(archive_root / "native/observation.json")
        candidate = bounded_json(archive_root / "native/candidate-tuple.json")
        binding = bounded_json(archive_root / "native/candidate-binding.json")
        if source_inputs.get("caseID") != CASE_ID or source_inputs.get("caseHash") != CASE_HASH:
            raise Hold("Text source-input case mismatch")
        if source_inputs.get("tupleID") != TUPLE_ID or source_inputs.get("sourceHash") != SOURCE_HASH:
            raise Hold("Text source-input tuple/source mismatch")
        for key, expected in (("planHash", PLAN_HASH), ("compileReceiptHash", COMPILE_HASH),
                              ("exeHash", EXE_HASH), ("rendererSha256", RENDERER_HASH),
                              ("serializerControlSha256", SERIALIZER_HASH),
                              ("runtimeSourceCommit", RUNTIME_COMMIT)):
            if key == "runtimeSourceCommit":
                matched = source_inputs.get(key) == expected
            else:
                matched = hash_matches(source_inputs.get(key), expected)
            if not matched:
                raise Hold(f"Text source-input {key} mismatch")
        if plan.get("case", {}).get("id") != CASE_ID or plan.get("case", {}).get("hash") != CASE_HASH:
            raise Hold("Text plan case mismatch")
        if compile_doc.get("case", {}).get("id") != CASE_ID or compile_doc.get("case", {}).get("hash") != CASE_HASH:
            raise Hold("Text compiler receipt case mismatch")
        if compile_doc.get("kind") != "factory-text-owned-compile-v1" or compile_doc.get("phase") != "final":
            raise Hold("Text compiler receipt kind/phase mismatch")
        if not hash_matches(compile_doc.get("sourceHash"), SOURCE_HASH) or not hash_matches(compile_doc.get("exeSha256"), EXE_HASH):
            raise Hold("Text compiler source/exe join mismatch")
        if candidate.get("tuple", {}).get("id") != TUPLE_ID or binding.get("sourceHash") != SOURCE_HASH:
            raise Hold("Text candidate binding mismatch")
        mac = validate_mac_report(mac_report)
        result = {
            "kind": "factory-text-f10-production-reader-input-r1",
            "status": "ready-for-root-reader" if not issues else "held",
            "qualified": False, "nativeActions": 0,
            "windows": {"archiveRoot": str(archive_root), "manifest": str(manifest_path),
                         "manifestCount": manifest.get("count"), "rowCount": len(rows),
                         "readBytes": total[0], "tupleID": TUPLE_ID, "caseID": CASE_ID,
                         "requiredRuns": COUNT, "archiveRowsAdmitted": True,
                         "sourceInputs": {"path": "admission/source-inputs.json", "sourceHash": SOURCE_HASH,
                                          "planHash": PLAN_HASH, "compileReceiptHash": COMPILE_HASH,
                                          "exeHash": EXE_HASH, "rendererHash": RENDERER_HASH,
                                          "serializerHash": SERIALIZER_HASH, "runtimeCommit": RUNTIME_COMMIT}},
            "mac": {"reportPath": str(mac_report), "status": mac["status"],
                    "qualification": mac["qualification"], "holds": mac["holds"],
                    "semantic": {"textBounds": mac["textBounds"], "defaultPaint": mac["defaultPaint"]}},
            "productionReader": {"implementation": "factory.pipeline.archive_reader.ArchiveByteReader",
                                  "windowsArchives": {"text": str(archive_root)},
                                  "windowsExitProof": "factory.gate.windows_exit_admission",
                                  "semantic": "held-observation-only", "nativeParity": "held"},
            "missingOrBlocked": issues,
        }
    except (Hold, OSError, TypeError, ValueError, json.JSONDecodeError) as exc:
        result = {"kind": "factory-text-f10-production-reader-input-r1", "status": "held",
                  "qualified": False, "nativeActions": 0, "missingOrBlocked": [str(exc)],
                  "mac": {"reportPath": str(mac_report), "semantic": "unread"}}
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0 if result["status"] == "ready-for-root-reader" else 2


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--windows-archive", type=Path, required=True)
    parser.add_argument("--mac-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    return assess(args.windows_archive, args.mac_report, args.output)


if __name__ == "__main__":
    raise SystemExit(main())
