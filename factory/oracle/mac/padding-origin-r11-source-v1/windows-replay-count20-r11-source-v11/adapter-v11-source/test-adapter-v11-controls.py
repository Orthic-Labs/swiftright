#!/usr/bin/env python3
"""Source-only r17 export controls; mutations stay in memory."""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("produce_input_map_v11", HERE / "produce-input-map-v11.py")
if SPEC is None or SPEC.loader is None:
    raise SystemExit("HOLD: producer source unavailable")
producer = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = producer
SPEC.loader.exec_module(producer)
from produce_input_map_v11 import Hold, bounded_json, validate_manifest, validate_manifest_document


def expect_reject(label: str, fn) -> dict:
    try:
        fn()
    except (Hold, ValueError) as exc:
        return {"name": label, "status": "rejected", "reason": str(exc)}
    raise SystemExit(f"control unexpectedly accepted: {label}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True, type=Path)
    ap.add_argument("--archive-root", required=True, type=Path)
    ap.add_argument("--export-manifest", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("HOLD: output must be fresh")
    repo = args.repo.absolute()
    archive_rel = args.archive_root.absolute().relative_to(repo).as_posix()
    manifest_rel = args.export_manifest.absolute().relative_to(repo).as_posix()
    baseline, _ = validate_manifest(repo, archive_rel, manifest_rel)
    manifest = bounded_json(args.export_manifest)
    if not isinstance(manifest, dict):
        raise SystemExit("HOLD: manifest object required")
    cases = []
    wrong_kind = copy.deepcopy(manifest)
    wrong_kind["kind"] = "root-factory-native-v16-export-v1"
    cases.append(expect_reject("wrong-kind", lambda: validate_manifest_document(repo, archive_rel, wrong_kind)))
    wrong_hash = copy.deepcopy(manifest)
    wrong_hash["files"][0]["sha256"] = "0" * 64
    cases.append(expect_reject("wrong-bytes-hash", lambda: validate_manifest_document(repo, archive_rel, wrong_hash)))
    wrong_bytes = copy.deepcopy(manifest)
    wrong_bytes["files"][0]["bytes"] = int(wrong_bytes["files"][0]["bytes"]) + 1
    cases.append(expect_reject("wrong-byte-count", lambda: validate_manifest_document(repo, archive_rel, wrong_bytes)))
    missing_layout = copy.deepcopy(manifest)
    missing_layout["files"] = [row for row in missing_layout["files"] if not row["path"].startswith("overlay/")]
    cases.append(expect_reject("missing-overlay-layout", lambda: validate_manifest_document(repo, archive_rel, missing_layout)))
    output = {
        "schema": "factory-native-count20-r17-adapter-controls-v11",
        "status": "baseline-admitted-faults-rejected",
        "baseline": baseline,
        "faultControls": cases,
        "nativeActions": 0,
        "lockActions": 0,
        "qualification": "source-control-only",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(output, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(json.dumps({"status": output["status"], "faults": len(cases), "nativeActions": 0, "lockActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
