#!/usr/bin/env python3
"""Fresh Count20 input admission with explicit plan & measured archive joins."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, re
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent
V7 = HERE.parent / "adapter-v7-source" / "produce-inputs-v7.py"
spec = importlib.util.spec_from_file_location("adapter_inputs_v7", V7)
if spec is None or spec.loader is None:
    raise SystemExit("HOLD: frozen v7 producer unavailable")
v7 = importlib.util.module_from_spec(spec); spec.loader.exec_module(v7)

def bounded_json(path: Path) -> dict:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > 8 * 1024 * 1024:
        raise ValueError("bounded JSON input required")
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict): raise ValueError("JSON object required")
    return value

def safe_path(value: str) -> Path:
    p = PurePosixPath(value)
    if not isinstance(value, str) or not value or p.is_absolute() or str(p) != value or ".." in p.parts or "\\" in value or ":" in value:
        raise ValueError("unsafe archive ref path")
    return Path(*p.parts)

def verify_ref(ref: dict, root: Path) -> None:
    if not isinstance(ref, dict) or not isinstance(ref.get("path"), str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", str(ref.get("sha256"))):
        raise ValueError("archive ref requires path & 64-hex SHA256")
    path = (root.resolve() / safe_path(ref["path"])).resolve(); path.relative_to(root.resolve())
    st = path.stat()
    if not path.is_file() or path.is_symlink(): raise ValueError("archive ref must be regular file:" + ref["path"])
    digest = hashlib.sha256(); size = 0
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024): digest.update(chunk); size += len(chunk)
    if "sha256:" + digest.hexdigest() != ref["sha256"] or size != ref.get("bytes"):
        raise ValueError("archive ref byte/hash mismatch:" + ref["path"])

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

def ref_json(ref: dict, root: Path) -> dict:
    path = (root.resolve() / safe_path(ref["path"])).resolve(); path.relative_to(root.resolve())
    return json.loads(path.read_text(encoding="utf-8-sig"))

def validate(document: dict, root: Path, plan: dict) -> int:
    if plan.get("kind") != "factory-fresh-r11-count20-adapter-plan-v1" or plan.get("count") != 20:
        raise ValueError("fresh Count20 plan identity missing")
    expected = plan["tuple"]; roles = document.get("roles")
    if not isinstance(roles, dict): raise ValueError("roles required")
    required = {"issuedMetadata", "tuple", "candidateBinding", "plan", "compile", "exe", "renderer", "manifest", "coordinator"}
    if not required.issubset(roles): raise ValueError("measured producer roles incomplete")
    issued = ref_json(roles["issuedMetadata"], root)
    if issued.get("expectedCount") != 20 or issued.get("frozenTupleBound") is not False or issued.get("sourceHash") != expected["sourceHash"]:
        raise ValueError("fresh issued metadata identity mismatch")
    captures = issued.get("captures")
    if not isinstance(captures, list) or len(captures) != 20: raise ValueError("fresh capture cardinality mismatch")
    cr = re.compile(plan["captureIdentity"]["capturePattern"]); ir = re.compile(plan["captureIdentity"]["imagePattern"]); ids = set(); images = set()
    for row in captures:
        cid, iid = row.get("captureID"), row.get("imageID")
        if not isinstance(cid, str) or not cr.fullmatch(cid) or cid in ids: raise ValueError("capture provenance ID mismatch")
        if not isinstance(iid, str) or not ir.fullmatch(iid) or iid in images: raise ValueError("image provenance ID mismatch")
        ids.add(cid); images.add(iid)
    tuple_doc = ref_json(roles["tuple"], root); value = tuple_doc.get("tuple", {}); hosts = value.get("hostHashes", {})
    if tuple_doc.get("candidateID") != expected["id"] or tuple_doc.get("case", {}).get("id") != expected["caseID"] or tuple_doc.get("case", {}).get("hash") != expected["caseHash"]:
        raise ValueError("fresh tuple/case identity mismatch")
    if value.get("id") != expected["id"] or hosts.get("macos") != expected["macHostHash"] or hosts.get("windows") != expected["windowsHostHash"]:
        raise ValueError("fresh measured host join mismatch")
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", str(value.get("rendererHash"))): raise ValueError("renderer hash join missing")
    runs = document.get("runs")
    if not isinstance(runs, list) or len(runs) != 20 or {x.get("run") for x in runs} != set(range(1, 21)):
        raise ValueError("measured Count20 run rows missing")
    if any(not isinstance(x.get("outcome"), dict) or not isinstance(x.get("measurement"), dict) for x in runs):
        raise ValueError("provider outcome/measurement joins missing")
    for row in captures:
        provenance = row.get("provenance") or {}
        if provenance.get("sourceHash") != expected["sourceHash"] or not provenance.get("producer"):
            raise ValueError("provider source provenance missing")
    return verify_all(document, root)

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--input-map", required=True, type=Path); ap.add_argument("--plan", required=True, type=Path); ap.add_argument("--archive-root", required=True, type=Path); ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists(): raise SystemExit("HOLD: refusing to overwrite output")
    try:
        document = bounded_json(args.input_map); plan = bounded_json(args.plan); refs = validate(document, args.archive_root, plan)
        if refs < 20: raise ValueError("measured archive closure incomplete")
        output = v7.mod.produce(args.input_map, args.archive_root)
        output["kind"] = "settled-capture-adapter-inputs-v8-fresh-r11"; output["version"] = 8
        output["freshSourceProfile"] = {"tupleID": plan["tuple"]["id"], "caseID": plan["tuple"]["caseID"], "sourceHash": plan["tuple"]["sourceHash"], "expectedCount": 20, "validatedArchiveRefs": refs, "nativeActions": 0, "qualification": "source-admitted-observation-only"}
    except Exception as exc: raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle: json.dump(output, handle, indent=2, sort_keys=True); handle.write("\n")
    print(json.dumps({"status": "produced-fresh-r11-v8", "count": 20, "validatedArchiveRefs": refs, "nativeActions": 0, "lockActions": 0}, sort_keys=True)); return 0

if __name__ == "__main__": raise SystemExit(main())
