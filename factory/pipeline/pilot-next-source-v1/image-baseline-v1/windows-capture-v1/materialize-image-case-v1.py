#!/usr/bin/env python3
"""Materialize fresh Image case from measured tuple; never invents host values."""
from __future__ import annotations
import argparse, hashlib, json, re
from datetime import datetime, timezone
from pathlib import Path

MAX_JSON = 2 * 1024 * 1024
RUNTIME = "37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b"
RENDERER = "sha256:e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93"
INPUTS = {"symbol":"star.fill","resizable":True,"fit":"contain","foreground":"yellow","frame":{"width":32,"height":32}}
HASH = re.compile(r"sha256:[0-9a-f]{64}\Z")

def regular(path: Path, limit: int = MAX_JSON) -> None:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > limit: raise ValueError(f"bounded regular file required: {path}")

def load(path: Path) -> object:
    regular(path); return json.loads(path.read_text(encoding="utf-8-sig"))

def sha(path: Path) -> str:
    regular(path); h=hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024): h.update(chunk)
    return "sha256:" + h.hexdigest()

def canonical(value: object) -> str:
    data=json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(",",":"),allow_nan=False).encode()
    return "sha256:"+hashlib.sha256(data).hexdigest()

def main() -> int:
    ap=argparse.ArgumentParser(); ap.add_argument("--tuple",type=Path,required=True); ap.add_argument("--plan",type=Path,required=True); ap.add_argument("--output",type=Path,required=True); args=ap.parse_args()
    if args.output.exists() and (not args.output.is_dir() or any(args.output.iterdir())): raise SystemExit("output must be a fresh directory")
    tuple_value=load(args.tuple); plan=load(args.plan); packet=Path(__file__).resolve().parents[1]; recipe=load(packet/"recipe.json")
    required={"id","sdk","macosBuild","toolchains","runtimeCommit","rendererHash","hostHashes","factoryVersion","acceptanceConfigHash"}
    if not isinstance(tuple_value,dict) or set(tuple_value) != required: raise SystemExit("tuple keys must match common schema")
    if tuple_value["runtimeCommit"] != RUNTIME or tuple_value["rendererHash"] != RENDERER: raise SystemExit("tuple runtime/renderer drift")
    if not all(isinstance(tuple_value[k], str) and tuple_value[k].strip() for k in ("id", "sdk", "macosBuild", "factoryVersion")) or not HASH.fullmatch(str(tuple_value["acceptanceConfigHash"])): raise SystemExit("tuple identity/config malformed")
    hosts=tuple_value["hostHashes"]
    if set(hosts) != {"macos","windows"} or any(not isinstance(v,str) or not v.startswith("sha256:") or len(v)!=71 for v in hosts.values()): raise SystemExit("both measured host hashes required")
    witness_hash=sha(packet/"witness.swift")
    recipe_hash=canonical(recipe)
    if plan.get("kind") != "factory-image-compiler-plan-v1" or plan.get("candidate") != "swiftui.image.baseline.pilot-next" or plan.get("recipe",{}).get("id") != "swiftui.image.baseline.recipe" or plan.get("recipe",{}).get("hash") != recipe_hash or plan.get("sourceHash") != witness_hash or plan.get("image") != INPUTS: raise SystemExit("Image plan/source mismatch")
    tuple_hash=canonical(tuple_value); suffix=tuple_hash.split(":",1)[1][:16]; case_id=f"swiftui.image.baseline.recipe.pilot-next.image-baseline-light.{suffix}"
    case={"kind":"case","version":"0.1","id":case_id,"block":"swiftui.image","inputs":INPUTS,"coverage":"declared","expectedCaseSetHash":canonical([{"id":case_id,"inputs":INPUTS,"coverage":"declared"}]),"provenance":{"sourceHash":recipe_hash,"createdAt":datetime.now(timezone.utc).isoformat().replace("+00:00","Z"),"producer":"factory/pipeline/pilot-next-source-v1/image-baseline-v1/windows-capture-v1"},"recipe":{"id":"swiftui.image.baseline.recipe","hash":recipe_hash},"tuple":tuple_value,"witness":{"path":"factory/pipeline/pilot-next-source-v1/image-baseline-v1/witness.swift","sourceHash":witness_hash}}
    case_hash=canonical(case); output=args.output.resolve(); output.mkdir(parents=True,exist_ok=True)
    target=output/"case.json"
    with target.open("x",encoding="utf-8",newline="\n") as stream: json.dump(case,stream,ensure_ascii=False,sort_keys=True,indent=2); stream.write("\n")
    print(json.dumps({"caseId":case_id,"caseHash":case_hash,"tupleHash":tuple_hash,"recipeHash":recipe_hash},sort_keys=True)); return 0

if __name__ == "__main__": raise SystemExit(main())
