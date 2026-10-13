#!/usr/bin/env python3
"""Fresh Count20 normalization & proof composition over frozen v6 logic."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, re
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent
V6 = Path("factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/adapter-v6-source/run-adapter-v6.py")
spec = importlib.util.spec_from_file_location("run_adapter_v6", V6)
if spec is None or spec.loader is None: raise SystemExit("HOLD: frozen adapter-v6 runtime unavailable")
mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)

def bounded_json(path: Path) -> dict:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > 16 * 1024 * 1024: raise ValueError("bounded JSON input required")
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict): raise ValueError("JSON object required")
    return value

def safe_path(value: str) -> Path:
    p = PurePosixPath(value)
    if not isinstance(value, str) or not value or p.is_absolute() or str(p) != value or ".." in p.parts or "\\" in value or ":" in value: raise ValueError("unsafe archive ref path")
    return Path(*p.parts)

def verify_ref(ref: dict, root: Path) -> None:
    if not isinstance(ref, dict) or not isinstance(ref.get("path"), str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", str(ref.get("sha256"))): raise ValueError("archive ref requires path & SHA256")
    path = (root.resolve() / safe_path(ref["path"])).resolve(); path.relative_to(root.resolve()); st = path.stat()
    if not path.is_file() or path.is_symlink(): raise ValueError("archive ref must be regular file:" + ref["path"])
    digest = hashlib.sha256(); size = 0
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024): digest.update(chunk); size += len(chunk)
    if "sha256:" + digest.hexdigest() != ref["sha256"] or size != ref.get("bytes"): raise ValueError("archive ref byte/hash mismatch:" + ref["path"])

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
    expected = plan["tuple"]; captures = value.get("captures")
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
    if args.output.exists(): raise SystemExit("HOLD: refusing to overwrite output")
    try:
        inputs = bounded_json(args.inputs); plan = bounded_json(args.plan); refs = verify_all(inputs, args.archive_root)
        if refs < 20: raise ValueError("measured archive closure incomplete")
        normalized = mod.normalize(args.inputs, args.archive_root)
        if normalized.get("typedStatus") not in ("normalized-observational", "normalized-observational-derived"): raise ValueError("normalized adapter held:" + ";".join(normalized.get("issues", [])))
        if args.proof_bundle:
            bundle = bounded_json(args.proof_bundle); derived = mod.derive_mod.derive(normalized["captures"], bundle)
            out = {"kind": "settled-typed-capture-normalization-v8-composed", "version": 8, "typedStatus": "normalized-observational-derived", "qualified": False, "nativeParity": "hold", "normalizedStage": {"kind": normalized.get("kind"), "typedStatus": normalized.get("typedStatus"), "captureCount": len(normalized.get("captures", [])), "issues": normalized.get("issues", [])}, "proofStage": {"schema": bundle.get("schema"), "status": bundle.get("status")}, "captures": derived, "issues": list(normalized.get("issues", [])) + ["provider/native parity remains held"]}
        else:
            out = dict(normalized); out["kind"] = "settled-typed-capture-normalization-v8"; out["version"] = 8; out["successorStage"] = {"status": "normalized-before-proof-r2", "nativeActions": 0}
        validate_output(out, plan); out["freshSourceProfile"] = {"tupleID": plan["tuple"]["id"], "caseID": plan["tuple"]["caseID"], "sourceHash": plan["tuple"]["sourceHash"], "expectedCount": 20, "validatedArchiveRefs": refs, "nativeActions": 0, "qualification": "source-admitted-observation-only"}
    except Exception as exc: raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle: json.dump(out, handle, indent=2, sort_keys=True); handle.write("\n")
    print(json.dumps({"status": out.get("typedStatus"), "count": len(out.get("captures", [])), "proofAttached": bool(args.proof_bundle), "validatedArchiveRefs": refs, "nativeActions": 0, "lockActions": 0}, sort_keys=True)); return 0

if __name__ == "__main__": raise SystemExit(main())
