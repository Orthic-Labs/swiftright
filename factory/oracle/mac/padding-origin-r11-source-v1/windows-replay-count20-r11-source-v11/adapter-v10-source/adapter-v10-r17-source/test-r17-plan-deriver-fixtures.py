#!/usr/bin/env python3
"""Bounded source-only r17 plan-deriver fixtures; no native evidence."""
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location("derive_r17", HERE / "derive-adapter-plan-r17.py")
if spec is None or spec.loader is None:
    raise SystemExit("HOLD: r17 deriver unavailable")
deriver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deriver)


def write_json(path: Path, value: dict) -> None:
    if path.exists() or path.is_symlink():
        raise ValueError("fixture output must be fresh: " + str(path))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True, type=Path)
    ap.add_argument("--control-root", required=True, type=Path)
    ap.add_argument("--base-plan", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    repo = args.repo.absolute()
    control_rel = deriver.rel_path(repo, args.control_root)
    base_rel = deriver.rel_path(repo, args.base_plan)
    output_rel = deriver.rel_path(repo, args.output)
    control_root = deriver.beneath(repo, control_rel)
    output_path = deriver.beneath(repo, output_rel)
    if control_root.exists() or control_root.is_symlink():
        raise SystemExit("HOLD: fixture control root must be fresh")
    control_root.mkdir(parents=True)
    base = deriver.bounded_json(deriver.beneath(repo, base_rel))
    tuple_doc = base.get("tuple")
    if not isinstance(tuple_doc, dict):
        raise SystemExit("HOLD: base tuple missing")
    captures = [
        {"run": index, "captureID": f"capture/{index:032x}", "imageID": f"image/{index:032x}", "provenance": {"sourceHash": tuple_doc["sourceHash"]}}
        for index in range(1, 21)
    ]
    seed = {
        "kind": "factory-prelaunch-capture-metadata-v2",
        "version": 2,
        "runID": "a" * 32,
        "expectedCount": 20,
        "frozenTupleBound": False,
        "sourceHash": tuple_doc["sourceHash"],
        "case": {"id": tuple_doc["caseID"], "hash": tuple_doc["caseHash"]},
        "captures": captures,
    }
    cases = [
        ("baseline", seed, True),
        ("alternate-run", {**seed, "runID": "b" * 32}, True),
        ("malformed-run", {**seed, "runID": "not-a-run"}, False),
        ("wrong-source", {**seed, "sourceHash": "sha256:" + "0" * 64}, False),
        ("wrong-case", {**seed, "case": {"id": tuple_doc["caseID"], "hash": "sha256:" + "0" * 64}}, False),
        ("duplicate-capture", {**seed, "captures": captures[:-1] + [{**captures[-1], "captureID": captures[0]["captureID"]}]}, False),
        ("wrong-count", {**seed, "captures": captures[:-1]}, False),
        ("frozen-tuple", {**seed, "frozenTupleBound": True}, False),
    ]
    results = []
    for name, metadata, accepted in cases:
        metadata_path = control_root / (name + "-issued.json")
        output = control_root / (name + "-plan.json")
        write_json(metadata_path, metadata)
        params = argparse.Namespace(
            base_plan=Path(base_rel),
            issued_metadata=metadata_path.relative_to(repo),
            repo=repo,
            output=output,
        )
        observed = True
        error = ""
        try:
            deriver.derive(params)
        except Exception as exc:
            observed = False
            error = str(exc)
        if observed != accepted:
            raise SystemExit("HOLD: deriver fixture expectation mismatch:" + name)
        results.append({"name": name, "accepted": observed, "expectedAccepted": accepted, "error": error, "nativeWindowActions": 0, "lockActions": 0})
    write_json(output_path, {"kind": "factory-r17-adapter-plan-deriver-fixture-controls", "status": "passed-source-only", "controls": results, "nativeEvidence": False, "qualification": "fixture-only-no-fresh-qualification", "nativeWindowActions": 0, "lockActions": 0})
    print(json.dumps({"status": "passed-source-only", "controls": len(results), "nativeEvidence": False, "nativeWindowActions": 0, "lockActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
