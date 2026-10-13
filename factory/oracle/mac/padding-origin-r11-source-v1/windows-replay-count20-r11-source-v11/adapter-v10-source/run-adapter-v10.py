#!/usr/bin/env python3
"""Fresh Count20 normalization & proof composition over frozen v6 logic."""
from __future__ import annotations
import argparse, importlib.util, json, re, sys
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "adapter-v9-source"))
from bounded_io_v9 import ARCHIVE_FILE_LIMIT, bounded_json as bounded_json_file, beneath, output_path, safe_relative, verify_ref as verify_archive_ref
from lineage_v10 import validate_document_lineage
REPO = next((parent for parent in HERE.parents if (parent / "factory").is_dir()), None)
if REPO is None:
    raise SystemExit("HOLD: repository root unavailable")
V6 = REPO / "factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/adapter-v6-source/run-adapter-v6.py"
FRESH_TUPLE_ID = "sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011"
FRESH_CASE_ID = "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9"
FRESH_SOURCE_HASH = "sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b"
spec = importlib.util.spec_from_file_location("run_adapter_v6", V6)
if spec is None or spec.loader is None: raise SystemExit("HOLD: frozen adapter-v6 runtime unavailable")
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)

def bounded_json(path: Path) -> dict:
    value = bounded_json_file(path)
    if not isinstance(value, dict): raise ValueError("JSON object required")
    return value

def safe_path(value: str) -> Path:
    return Path(*PurePosixPath(safe_relative(value)).parts)

def verify_ref(ref: dict, root: Path) -> None:
    if not isinstance(ref, dict) or not isinstance(ref.get("path"), str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", str(ref.get("sha256"))): raise ValueError("archive ref requires path & SHA256")
    path = beneath(root, ref["path"])
    verify_archive_ref(path, ref, max_bytes=ARCHIVE_FILE_LIMIT)

def verify_all(value, root: Path, seen=None) -> int:
    seen = set() if seen is None else seen
    if isinstance(value, dict):
        if {"path", "sha256", "bytes"}.issubset(value):
            marker = (value.get("path"), value.get("sha256"), value.get("bytes"))
            if marker not in seen: seen.add(marker); verify_ref(value, root)
        for child in value.values(): verify_all(child, root, seen)
    elif isinstance(value, list):
        for child in value: verify_all(child, root, seen)
    return len(seen)

def validate_output(value: dict, plan: dict) -> None:
    if value.get("typedStatus") not in ("normalized-observational", "normalized-observational-derived"): raise ValueError("fresh normalization held:" + ";".join(value.get("issues", [])))
    expected = plan["tuple"]
    if expected.get("id") != FRESH_TUPLE_ID or expected.get("caseID") != FRESH_CASE_ID or expected.get("sourceHash") != FRESH_SOURCE_HASH:
        raise ValueError("fresh tuple/source profile mismatch")
    captures = value.get("captures")
    if not isinstance(captures, list) or len(captures) != 20: raise ValueError("fresh normalized Count20 cardinality mismatch")
    cr = re.compile(plan["captureIdentity"]["capturePattern"]); ir = re.compile(plan["captureIdentity"]["imagePattern"]); ids = set(); images = set()
    for capture in captures:
        cid = capture.get("id"); imgs = capture.get("images") or []; iid = imgs[0].get("id") if imgs else None
        if not isinstance(cid, str) or not cr.fullmatch(cid) or cid in ids: raise ValueError("normalized capture provenance mismatch")
        if not isinstance(iid, str) or not ir.fullmatch(iid) or iid in images: raise ValueError("normalized image provenance mismatch")
        ids.add(cid); images.add(iid); meta = capture.get("meta", {}); provenance = capture.get("provenance", {})
        if meta.get("sourceBoundCandidateTupleHash") is None or meta.get("issuedMetadataHash") is None: raise ValueError("normalized raw source joins missing")
        if provenance.get("sourceHash") != expected["sourceHash"]: raise ValueError("normalized source provenance mismatch")

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--inputs", required=True, type=Path); ap.add_argument("--plan", required=True, type=Path); ap.add_argument("--archive-root", required=True, type=Path); ap.add_argument("--proof-bundle", type=Path); ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    output_path(args.output)
    try:
        inputs = bounded_json(args.inputs); plan = bounded_json(args.plan)
        lineage = validate_document_lineage(inputs, args.archive_root, plan)
        refs = verify_all(inputs, args.archive_root)
        if refs < 20: raise ValueError("measured archive closure incomplete")
        normalized = mod.normalize(args.inputs, args.archive_root)
        if normalized.get("typedStatus") not in ("normalized-observational", "normalized-observational-derived"): raise ValueError("normalized adapter held:" + ";".join(normalized.get("issues", [])))
        if args.proof_bundle:
            bundle = bounded_json(args.proof_bundle); derived = mod.derive_mod.derive(normalized["captures"], bundle)
            out = {"kind": "settled-typed-capture-normalization-v10-composed", "version": 10, "typedStatus": "normalized-observational-derived", "qualified": False, "nativeParity": "hold", "normalizedStage": {"kind": normalized.get("kind"), "typedStatus": normalized.get("typedStatus"), "captureCount": len(normalized.get("captures", [])), "issues": normalized.get("issues", [])}, "proofStage": {"schema": bundle.get("schema"), "status": bundle.get("status")}, "captures": derived, "issues": list(normalized.get("issues", [])) + ["provider/native parity remains held"]}
        else:
            out = dict(normalized); out["kind"] = "settled-typed-capture-normalization-v10"; out["version"] = 10; out["successorStage"] = {"status": "normalized-before-proof-r2", "nativeActions": 0}
        validate_output(out, plan)
        out["issuedLineage"] = {"runID": lineage["runID"], "issuedMetadataSha256": lineage["issuedMetadataHash"]}
        out["memoryReceipt"] = lineage["memoryReceipt"]
        out["freshSourceProfile"] = {"tupleID": plan["tuple"]["id"], "caseID": plan["tuple"]["caseID"], "sourceHash": plan["tuple"]["sourceHash"], "expectedCount": 20, "validatedArchiveRefs": refs, "nativeActions": 0, "qualification": "source-admitted-observation-only"}
    except Exception as exc: raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle: json.dump(out, handle, indent=2, sort_keys=True); handle.write("\n")
    print(json.dumps({"status": out.get("typedStatus"), "count": len(out.get("captures", [])), "proofAttached": bool(args.proof_bundle), "validatedArchiveRefs": refs, "runID": lineage["runID"], "nativeActions": 0, "lockActions": 0}, sort_keys=True)); return 0

if __name__ == "__main__": raise SystemExit(main())
