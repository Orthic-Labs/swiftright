#!/usr/bin/env python3
"""Join one r13 strict report with genuine same-host build/incremental proofs.

This adapter emits provenance only. It never rewrites raw inputs, reruns the
analyzer, or turns held display evidence into qualification.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import sys
import tempfile
from pathlib import Path

MAX_FILE = 16 * 1024 * 1024
MAX_TOTAL = 32 * 1024 * 1024
BUF = 64 * 1024
EXE_SHA = "7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c"
DLL_SHA = "7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2"
SOURCE_MANIFEST_SHA = "26705e8f1fdd0164a9963c9cb0f730fda2e313e5c07348097c8fe8ab3ef7e468"
SOURCE_FILE_SHA = "6e0f6ffb9d5afebb249412e92cbc76583a17c1a24f6602016d86dfdfa94b5429"
INCREMENTAL_SHA = "e41bd6479dfb1dbac0867a85b43ba700b933b6c4e3bf14d9c38dbf0eb6c4126c"


class Hold(RuntimeError):
    pass


def reject(message: str) -> None:
    raise Hold(message)


def leaf(path: Path, limit: int = MAX_FILE) -> os.stat_result:
    path = path.absolute()
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        try:
            st = os.lstat(current)
        except FileNotFoundError:
            reject(f"missing input: {path}")
        if stat.S_ISLNK(st.st_mode):
            reject(f"symlink input rejected: {path}")
    st = os.lstat(path)
    if not stat.S_ISREG(st.st_mode) or st.st_size > limit:
        reject(f"bounded regular input required: {path}")
    return st


def digest(path: Path, limit: int = MAX_FILE) -> tuple[int, str]:
    st = leaf(path, limit)
    size = 0
    h = hashlib.sha256()
    with path.open("rb") as source:
        while block := source.read(BUF):
            size += len(block)
            if size > limit:
                reject(f"input grew beyond bound: {path}")
            h.update(block)
    if size != st.st_size:
        reject(f"input changed during read: {path}")
    return size, h.hexdigest()


def load(path: Path) -> tuple[object, dict]:
    size, sha = digest(path)
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        reject(f"invalid JSON {path}: {exc}")
    return value, {"path": str(path.absolute()), "bytes": size, "sha256": sha}


def write_fresh(path: Path, value: object) -> None:
    if path.exists() or path.is_symlink():
        reject(f"fresh output required: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".r13-prov-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            json.dump(value, out, indent=2, sort_keys=True)
            out.write("\n")
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp, path)
    finally:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass


def args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--strict-report", required=True, type=Path)
    p.add_argument("--materializer-receipt", required=True, type=Path)
    p.add_argument("--incremental", required=True, type=Path)
    p.add_argument("--release-build-metadata", required=True, type=Path)
    p.add_argument("--compiled-source-manifest", required=True, type=Path)
    p.add_argument("--out", required=True, type=Path)
    return p.parse_args()


def main() -> int:
    ns = args()
    paths = [ns.strict_report, ns.materializer_receipt, ns.incremental,
             ns.release_build_metadata, ns.compiled_source_manifest]
    total = 0
    loaded: dict[Path, tuple[object, dict]] = {}
    for path in paths:
        value, ref = load(path.absolute())
        total += ref["bytes"]
        if total > MAX_TOTAL:
            reject("provenance inputs exceed aggregate bound")
        loaded[path] = (value, ref)
    report, report_ref = loaded[ns.strict_report]
    receipt, receipt_ref = loaded[ns.materializer_receipt]
    incremental, incremental_ref = loaded[ns.incremental]
    build_meta, build_meta_ref = loaded[ns.release_build_metadata]
    source_manifest, source_manifest_ref = loaded[ns.compiled_source_manifest]
    if not isinstance(report, dict) or report.get("platform") != "windows":
        reject("strict report platform mismatch")
    if report.get("overall") != "INCOMPLETE":
        reject("expected held strict report")
    if not isinstance(receipt, dict) or receipt.get("qualificationHeld") is not True:
        reject("materializer receipt is not held")
    if not isinstance(incremental, dict) or incremental.get("kind") != "sr0-tuple12-ui-only-incremental-v9":
        reject("incremental receipt kind mismatch")
    if incremental.get("platform") != "windows" or incremental.get("source_manifest_sha256") != SOURCE_MANIFEST_SHA:
        reject("incremental source identity mismatch")
    if incremental.get("source_file_sha256") != SOURCE_FILE_SHA:
        reject("incremental source file identity mismatch")
    if not isinstance(build_meta, dict) or build_meta.get("configuration") != "release":
        reject("release build metadata mismatch")
    if build_meta.get("sourceManifestSha256") != SOURCE_MANIFEST_SHA or build_meta.get("exe_sha256") != EXE_SHA or build_meta.get("dll_sha256") != DLL_SHA:
        reject("release artifact/source join mismatch")
    if not isinstance(source_manifest, dict):
        reject("compiled source manifest must be object")
    report_build = report.get("build") or {}
    if report_build.get("exe_sha256") != EXE_SHA or report_build.get("sourceManifestSha256") != SOURCE_MANIFEST_SHA:
        reject("strict report build join mismatch")
    if not isinstance(report.get("runs"), dict) or "r1" not in report["runs"]:
        reject("strict report r1 missing")
    summary = report["runs"]["r1"].get("summary") or {}
    timing = {
        "presentsInWindow": summary.get("presents_in_window"),
        "displayedInWindow": summary.get("displayed_in_window"),
        "replacedInWindow": (summary.get("presents_in_window") - summary.get("displayed_in_window")) if isinstance(summary.get("presents_in_window"), int) and isinstance(summary.get("displayed_in_window"), int) else None,
        "presentedIntervalMs": summary.get("presented_interval_ms"),
        "visibleMs": summary.get("visible_ms"),
    }
    if timing["presentsInWindow"] != 3601 or timing["displayedInWindow"] != 47 or timing["replacedInWindow"] != 3554:
        reject("unexpected r13 strict timing facts")
    result = {
        "kind": "sr0-r13-offline-provenance-adapter-v3",
        "status": "diagnostic-held",
        "platform": "windows",
        "qualificationClaim": False,
        "parityClaim": False,
        "nativeActions": 0,
        "rawInputsUnchanged": True,
        "strictReport": {"ref": report_ref, "overall": report["overall"], "refusalReasons": report.get("refusal_reasons", [])},
        "timing": timing,
        "sameHostSourceJoin": {
            "incremental": incremental_ref,
            "releaseBuildMetadata": build_meta_ref,
            "compiledSourceManifest": source_manifest_ref,
            "sourceManifestSha256": SOURCE_MANIFEST_SHA,
            "sourceFileSha256": SOURCE_FILE_SHA,
            "workloadExeSha256": EXE_SHA,
            "rendererDllSha256": DLL_SHA,
        },
        "materializer": receipt_ref,
        "holds": [
            "incremental proof now joins same source/build/artifact lineage; no qualification promotion",
            "47 displayed of 3601 presents; 3554 replaced, with p95 presentation interval 3999.415 ms & input-to-visible p95 3044.3844 ms",
            "strict refusal reports minimized, occluded, or throttled; isolated interactive full-visible run is required to distinguish cause",
            "incremental proof is artifact_restoration_only; it does not claim final-noop identity",
        ],
    }
    write_fresh(ns.out.absolute(), result)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Hold as exc:
        print(f"HOLD: {exc}", file=sys.stderr)
        raise SystemExit(2)
