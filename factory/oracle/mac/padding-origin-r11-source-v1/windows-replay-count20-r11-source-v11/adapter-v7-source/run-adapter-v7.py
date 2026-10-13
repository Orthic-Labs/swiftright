#!/usr/bin/env python3
"""Fresh r11 Count20 normalization over frozen adapter-v6 runtime/proof stages."""
from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
V6 = Path("factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/adapter-v6-source/run-adapter-v6.py")
spec = importlib.util.spec_from_file_location("run_adapter_v6", V6)
if spec is None or spec.loader is None:
    raise SystemExit("HOLD: frozen adapter-v6 runtime unavailable")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

TUPLE_ID = "sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011"
CASE_ID = "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9"
SOURCE_HASH = "sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b"


def validate_output(document: dict) -> None:
    if document.get("typedStatus") not in ("normalized-observational", "normalized-observational-derived"):
        raise ValueError("fresh normalization held: " + ";".join(document.get("issues", [])))
    captures = document.get("captures")
    if not isinstance(captures, list) or len(captures) != 20:
        raise ValueError("fresh normalized Count20 cardinality mismatch")
    if any(c.get("id", "")[:8] != "capture/" or len(c.get("id", "")) != 40 for c in captures):
        raise ValueError("fresh normalized capture provenance mismatch")
    if any(not isinstance(c.get("images"), list) or not c["images"] or c["images"][0].get("id", "")[:6] != "image/" for c in captures):
        raise ValueError("fresh normalized image provenance mismatch")
    for capture in captures:
        meta = capture.get("meta", {})
        if meta.get("sourceBoundCandidateTupleHash") is None or meta.get("issuedMetadataHash") is None:
            raise ValueError("fresh normalized raw source joins missing")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--inputs", required=True, type=Path)
    ap.add_argument("--archive-root", required=True, type=Path)
    ap.add_argument("--proof-bundle", type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists():
        raise SystemExit("HOLD: refusing to overwrite output")
    try:
        output = mod.normalize(args.inputs, args.archive_root)
        validate_output(output)
        output["kind"] = "settled-typed-capture-normalization-v7-fresh-r11"
        output["version"] = 7
        output["freshSourceProfile"] = {"tupleID": TUPLE_ID, "caseID": CASE_ID, "sourceHash": SOURCE_HASH, "expectedCount": 20, "nativeActions": 0, "qualification": "source-admitted-observation-only"}
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(output, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(json.dumps({"status": output.get("typedStatus"), "count": 20, "nativeActions": 0, "lockActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
