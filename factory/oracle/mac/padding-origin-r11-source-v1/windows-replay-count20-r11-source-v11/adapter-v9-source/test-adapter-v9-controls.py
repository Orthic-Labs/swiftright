#!/usr/bin/env python3
"""Source-only controls over v9 production validators & explicit fault fixtures."""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path

from bounded_io_v9 import ARCHIVE_FILE_LIMIT, ARCHIVE_TOTAL_LIMIT, bounded_json, beneath, output_path, safe_relative, verify_ref


HERE = Path(__file__).resolve().parent


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"validator unavailable: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def case(label: str, callback, expected: bool) -> dict:
    try:
        callback()
        accepted, error = True, ""
    except Exception as exc:
        accepted, error = False, str(exc)
    if accepted != expected:
        raise RuntimeError(f"control expectation failed: {label}: {error}")
    return {"name": label, "accepted": accepted, "expected": expected, "error": error}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input-map", required=True, type=Path)
    ap.add_argument("--plan", required=True, type=Path)
    ap.add_argument("--archive-root", required=True, type=Path)
    ap.add_argument("--proof-bundle", required=True, type=Path)
    ap.add_argument("--control-root", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    output_path(args.output)
    if args.control_root.exists() or args.control_root.is_symlink():
        raise RuntimeError("control root must be fresh")
    args.control_root.mkdir(parents=True)
    if ARCHIVE_TOTAL_LIMIT != 256 * 1024 * 1024 or ARCHIVE_FILE_LIMIT != 64 * 1024 * 1024:
        raise RuntimeError("adapter archive bounds drift")
    plan = bounded_json(args.plan)
    document = bounded_json(args.input_map)
    bundle = bounded_json(args.proof_bundle)
    producer = load("adapter_v9_producer", HERE / "produce-inputs-v9.py")
    reader = load("adapter_v9_reader", HERE / "run-trusted-reader-v9.py")
    results = []
    results.append(case("producer-baseline", lambda: producer.validate(document, args.archive_root, plan), True))
    bad_map = copy.deepcopy(document)
    bad_map["roles"]["tuple"]["sha256"] = "sha256:" + "0" * 64
    results.append(case("producer-tuple-reference-hash", lambda: producer.validate(bad_map, args.archive_root, plan), False))
    bad_plan = copy.deepcopy(plan)
    bad_plan["tuple"]["sourceHash"] = "sha256:" + "f" * 64
    results.append(case("producer-source-profile", lambda: producer.validate(document, args.archive_root, bad_plan), False))
    bad_bytes = copy.deepcopy(document)
    bad_bytes["roles"]["tuple"]["bytes"] = int(bad_bytes["roles"]["tuple"]["bytes"]) + 1
    results.append(case("producer-tuple-reference-bytes", lambda: producer.validate(bad_bytes, args.archive_root, plan), False))
    tuple_ref = document["roles"]["tuple"]
    tuple_target = beneath(args.archive_root, tuple_ref["path"])
    bad_bound = copy.deepcopy(tuple_ref)
    bad_bound["bytes"] = ARCHIVE_FILE_LIMIT + 1
    results.append(case("archive-file-bound", lambda: verify_ref(tuple_target, bad_bound), False))
    results.append(case("archive-relative-escape", lambda: beneath(args.archive_root, "../escape"), False))
    results.append(case("archive-absolute-path", lambda: safe_relative("/absolute/path"), False))
    tuple_link = args.control_root / "tuple-link.json"
    try:
        os.symlink(tuple_target, tuple_link)
    except OSError as exc:
        raise RuntimeError("symlink fixture unavailable") from exc
    results.append(case("archive-symlink-component", lambda: verify_ref(tuple_link, tuple_ref), False))
    results.append(case("reader-baseline", lambda: reader.validate_plan(bundle, plan), True))
    bad_case = copy.deepcopy(bundle)
    bad_case["captures"][0]["case"]["id"] = "wrong-case"
    results.append(case("reader-case-join", lambda: reader.validate_plan(bad_case, plan), False))
    bad_ids = copy.deepcopy(bundle)
    bad_ids["captures"][1]["id"] = bad_ids["captures"][0]["id"]
    results.append(case("reader-duplicate-capture-id", lambda: reader.validate_plan(bad_ids, plan), False))
    bad_roles = copy.deepcopy(bundle)
    del bad_roles["captures"][0]["meta"]["conditions"]["windowsExitProof"]["files"][next(iter(bad_roles["captures"][0]["meta"]["conditions"]["windowsExitProof"]["files"]))]
    results.append(case("reader-missing-proof-role", lambda: reader.validate_plan(bad_roles, plan), False))
    out = {"schema": "factory-fresh-r11-adapter-v9-controls-v2", "status": "passed-source-only", "controls": results, "nativeWindowActions": 0, "compilerActions": 0, "remoteActions": 0, "lockActions": 0, "sourceMutations": 0, "archiveOperationBytes": ARCHIVE_TOTAL_LIMIT, "archiveFileBytes": ARCHIVE_FILE_LIMIT}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(out, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(json.dumps({"status": out["status"], "controls": len(results), "nativeActions": 0, "lockActions": 0}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
