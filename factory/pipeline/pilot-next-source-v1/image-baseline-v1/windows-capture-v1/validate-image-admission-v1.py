#!/usr/bin/env python3
"""Validate measured Image plan/case/receipt joins; never launches capture."""
from __future__ import annotations
import argparse, hashlib, json, re
from pathlib import Path

MAX_JSON=2*1024*1024; MAX_FILE=64*1024*1024; RUNTIME="37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b"; RENDERER="e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93"
HASH=re.compile(r"sha256:[0-9a-f]{64}\Z")
RAW_HASH=re.compile(r"[0-9a-f]{64}\Z")
def regular(p:Path,limit:int)->None:
    s=p.stat()
    if not p.is_file() or p.is_symlink() or s.st_size>limit: raise ValueError(f"bounded regular file required: {p}")
def digest(p:Path,limit:int=MAX_FILE)->str:
    regular(p,limit); h=hashlib.sha256()
    with p.open("rb") as f:
        while b:=f.read(1024*1024): h.update(b)
    return "sha256:"+h.hexdigest()
def load(p:Path): regular(p,MAX_JSON); return json.loads(p.read_text(encoding="utf-8-sig"))
def canonical(value): return "sha256:"+hashlib.sha256(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(",",":"),allow_nan=False).encode()).hexdigest()
def ref(value,name):
    if not isinstance(value,dict) or not isinstance(value.get("path"),str) or not isinstance(value.get("sha256"),str) or not isinstance(value.get("bytes"),int): raise ValueError(f"{name} ref malformed")
    p=Path(value["path"]); actual=digest(p,MAX_JSON); expected=value["sha256"]
    if actual!=expected or p.stat().st_size!=value["bytes"]: raise ValueError(f"{name} ref drift")
    return load(p),p
def main()->int:
    ap=argparse.ArgumentParser(); ap.add_argument("--inputs",type=Path,required=True); ap.add_argument("--output",type=Path,required=True); args=ap.parse_args()
    if args.output.exists(): raise SystemExit("output must be fresh")
    source=load(args.inputs)
    if source.get("kind") not in ("factory-image-source-inputs-v1","factory-image-source-inputs-v2") or source.get("count") not in (1,20): raise SystemExit("Image source input kind/count mismatch")
    required=("caseID","caseHash","tupleID","tupleHash","sourceHash","recipeHash","planHash","compileReceiptHash","runtimeSourceCommit","rendererSha256","tupleRef","caseRef","planRef","compileRef","sourceRef")
    if any(not isinstance(source.get(k),str) or not source[k] for k in required): raise SystemExit("Image source input field missing")
    case,case_path=ref(source["caseRef"],"case"); tuple_doc,tuple_path=ref(source["tupleRef"],"tuple"); plan,plan_path=ref(source["planRef"],"plan"); receipt,receipt_path=ref(source["compileRef"],"compile receipt"); source_doc,source_path=ref(source["sourceRef"],"source")
    case=case.get("case",case); tuple_value=tuple_doc.get("tuple",tuple_doc)
    if not HASH.fullmatch(source["recipeHash"]) or not RAW_HASH.fullmatch(source["planHash"]) or not RAW_HASH.fullmatch(source["compileReceiptHash"]) or not RAW_HASH.fullmatch(source["rendererSha256"]): raise SystemExit("Image hash format malformed")
    if case.get("id")!=source["caseID"] or canonical(case)!=source["caseHash"] or case.get("recipe",{}).get("hash")!=source["recipeHash"] or tuple_value.get("id")!=source["tupleID"] or canonical(tuple_value)!=source["tupleHash"] or source_doc.get("sourceHash")!=source["sourceHash"]: raise SystemExit("Image case/tuple/source join mismatch")
    if digest(plan_path)!= "sha256:"+source["planHash"] or plan.get("kind")!="factory-image-compiler-plan-v1" or plan.get("case",{}).get("id")!=source["caseID"] or plan.get("sourceHash")!=source["sourceHash"] or plan.get("runtimeSourceCommit")!=RUNTIME or plan.get("rendererSha256")!="sha256:"+source["rendererSha256"]: raise SystemExit("Image plan join mismatch")
    if digest(receipt_path)!= "sha256:"+source["compileReceiptHash"] or receipt.get("kind")!="factory-image-owned-compile-v1" or receipt.get("exitCode")!=0 or receipt.get("streamsSealed") is not True or receipt.get("streamDrainComplete") is not True or receipt.get("originalHandleRetained") is not True or receipt.get("ownedExited") is not True or receipt.get("jobActiveCount")!=0 or receipt.get("sourceHash")!=source["sourceHash"] or receipt.get("planSha256")!=source["planHash"] or receipt.get("runtimeSourceCommit")!=RUNTIME or receipt.get("rendererSha256")!="sha256:"+source["rendererSha256"]: raise SystemExit("Image compile receipt join mismatch")
    image=plan.get("image",{})
    if image != {"symbol":"star.fill","resizable":True,"fit":"contain","foreground":"yellow","frame":{"width":32,"height":32}}: raise SystemExit("Image contract mismatch")
    result={"kind":"factory-image-admission-v1","status":"passed-source-only","count":source["count"],"caseID":source["caseID"],"tupleID":source["tupleID"],"sourceHash":source["sourceHash"],"recipeHash":source["recipeHash"],"planHash":source["planHash"],"compileReceiptHash":source["compileReceiptHash"],"runtimeSourceCommit":RUNTIME,"rendererSha256":source["rendererSha256"],"nativeActions":0,"compilerActions":0,"guiActions":0,"remoteActions":0,"lockActions":0}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open("x",encoding="utf-8",newline="\n") as f: json.dump(result,f,sort_keys=True,indent=2); f.write("\n")
    return 0
if __name__=="__main__": raise SystemExit(main())
