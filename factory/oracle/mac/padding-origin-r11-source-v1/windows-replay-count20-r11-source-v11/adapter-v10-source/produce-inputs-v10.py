#!/usr/bin/env python3
"""Compose v10 normalized inputs only after strict issued/task joins."""
from __future__ import annotations
import argparse, importlib.util, json, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
V9 = HERE.parent / "adapter-v9-source" / "produce-inputs-v9.py"
sys.path.insert(0, str(V9.parent))
spec = importlib.util.spec_from_file_location("adapter_inputs_v9", V9)
if spec is None or spec.loader is None:
    raise SystemExit("HOLD: frozen v9 input producer unavailable")
v9 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v9)
from bounded_io_v9 import bounded_json as bounded_json_file, output_path  # noqa: E402
from lineage_v10 import validate_document_lineage  # noqa: E402


def bounded_json(path: Path) -> dict:
    value = bounded_json_file(path)
    if not isinstance(value, dict):
        raise ValueError("JSON object required")
    return value


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input-map", required=True, type=Path)
    ap.add_argument("--plan", required=True, type=Path)
    ap.add_argument("--archive-root", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    output_path(args.output)
    try:
        document = bounded_json(args.input_map)
        plan = bounded_json(args.plan)
        lineage = validate_document_lineage(document, args.archive_root, plan)
        refs = v9.validate(document, args.archive_root, plan)
        if refs < 20:
            raise ValueError("measured archive closure incomplete")
        normalized = v9.v7.mod.produce(args.input_map, args.archive_root)
        normalized["kind"] = "settled-capture-adapter-inputs-v10-fresh-r11"
        normalized["version"] = 10
        normalized["issuedLineage"] = {"runID": lineage["runID"], "issuedMetadataSha256": lineage["issuedMetadataHash"]}
        normalized["memoryReceipt"] = lineage["memoryReceipt"]
        normalized["freshSourceProfile"] = {"tupleID": plan["tuple"]["id"], "caseID": plan["tuple"]["caseID"], "sourceHash": plan["tuple"]["sourceHash"], "expectedCount": 20, "validatedArchiveRefs": refs, "nativeActions": 0, "qualification": "source-admitted-observation-only"}
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(normalized, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(json.dumps({"status": "produced-fresh-r11-v10", "count": 20, "validatedArchiveRefs": refs, "runID": lineage["runID"], "nativeActions": 0, "lockActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
