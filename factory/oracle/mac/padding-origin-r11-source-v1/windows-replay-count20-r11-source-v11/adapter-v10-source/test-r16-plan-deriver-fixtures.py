#!/usr/bin/env python3
"""Source-only deriver fixtures; synthetic plans never qualify native evidence."""
from __future__ import annotations
import argparse, importlib.util, json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
spec = importlib.util.spec_from_file_location("derive_r16", HERE / "derive-adapter-plan-r16.py")
if spec is None or spec.loader is None:
    raise SystemExit("HOLD: deriver unavailable")
deriver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deriver)


def write_json(path: Path, value: dict) -> None:
    with path.open("x", encoding="utf-8") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--control-root", required=True, type=Path)
    ap.add_argument("--base-plan", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    args.control_root.mkdir(parents=True, exist_ok=True)
    base = json.loads(args.base_plan.read_text(encoding="utf-8"))
    tuple_doc = base["tuple"]
    captures = [{"run": index, "captureID": f"capture/{index:032x}", "imageID": f"image/{index:032x}", "provenance": {"sourceHash": tuple_doc["sourceHash"]}} for index in range(1, 21)]
    seed = {"kind": "factory-prelaunch-capture-metadata-v2", "version": 2, "runID": "a" * 32, "expectedCount": 20, "frozenTupleBound": False, "sourceHash": tuple_doc["sourceHash"], "case": {"id": tuple_doc["caseID"], "hash": tuple_doc["caseHash"]}, "captures": captures}
    cases = [("baseline", seed, True), ("alternate-run", {**seed, "runID": "b" * 32}, True), ("malformed-run", {**seed, "runID": "not-a-run"}, False), ("wrong-source", {**seed, "sourceHash": "sha256:" + "0" * 64}, False), ("wrong-case", {**seed, "case": {"id": tuple_doc["caseID"], "hash": "sha256:" + "0" * 64}}, False), ("duplicate-capture", {**seed, "captures": captures[:-1] + [{**captures[-1], "captureID": captures[0]["captureID"]}]}, False)]
    results = []
    for name, metadata, accepted in cases:
        metadata_path = args.control_root / (name + "-issued.json")
        output_path = args.control_root / (name + "-plan.json")
        write_json(metadata_path, metadata)
        params = argparse.Namespace(base_plan=args.base_plan, issued_metadata=metadata_path.relative_to(args.control_root.parent), repo=args.control_root.parent, output=output_path)
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
    result = {"kind": "factory-r16-adapter-plan-deriver-fixture-controls", "status": "passed-source-only", "controls": results, "nativeEvidence": False, "qualification": "fixture-only-no-fresh-qualification", "nativeWindowActions": 0, "lockActions": 0}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(json.dumps({"status": result["status"], "controls": len(results), "nativeEvidence": False, "nativeWindowActions": 0, "lockActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
