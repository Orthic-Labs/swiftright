#!/usr/bin/env python3
"""Emit one hash-bound Circle diagnostic source-input document.

Inputs are explicit measured files supplied by the caller. This helper performs
bounded reads only; it never discovers files, compiles, launches, or mutates a
source tree. Paths in output preserve caller spelling for transport manifests.
"""
from __future__ import annotations
import argparse, hashlib, json, os, stat
from pathlib import Path

BUF=1024*1024
MAX_JSON=4*1024*1024
MAX_FILE=64*1024*1024
CIRCLE_COMPILED_PACKAGE=r"D:\Claude\swiftright\.factory-work\hosts\circle\package"

def regular(p: Path, limit: int=MAX_FILE):
    s=p.lstat()
    if not stat.S_ISREG(s.st_mode) or stat.S_ISLNK(s.st_mode) or s.st_size>limit:
        raise RuntimeError(f"unsafe or oversized reference: {p}")
    return s

def digest(p: Path, limit: int=MAX_FILE):
    s=regular(p,limit); h=hashlib.sha256(); n=0
    with p.open("rb") as f:
        while True:
            b=f.read(BUF)
            if not b: break
            n+=len(b)
            if n>limit: raise RuntimeError(f"reference grew beyond bound: {p}")
            h.update(b)
    if p.lstat().st_size!=n: raise RuntimeError(f"reference changed during read: {p}")
    return h.hexdigest(),n

def obj(p: Path):
    digest(p,MAX_JSON)
    return json.loads(p.read_text(encoding="utf-8-sig"))

def ref(p: Path, limit: int=MAX_FILE):
    h,n=digest(p,limit)
    return {"path":str(p),"sha256":"sha256:"+h,"bytes":n}

def sha(value):
    s=str(value)
    return s[7:].lower() if s.lower().startswith("sha256:") else s.lower()

def canonical(value):
    value=sha(value)
    if not __import__('re').fullmatch(r'[0-9a-f]{64}',value):
        raise RuntimeError('canonical hash is not 64 hex')
    return 'sha256:'+value

def require_circle_package(value):
    value=str(value).replace('/','\\').rstrip('\\')
    if value.lower()!=CIRCLE_COMPILED_PACKAGE.lower():
        raise RuntimeError('compiled host package must use canonical Circle package path')
    return CIRCLE_COMPILED_PACKAGE

def main():
    ap=argparse.ArgumentParser()
    for n in ("plan","receipt","tuple","case","manifest","recipe","binding","context","capture-plan","serializer","integration-bindings","build-preflight","uia-worker","renderer","exe","out"):
        ap.add_argument("--"+n,required=True)
    ap.add_argument("--compiled-host-package",required=True)
    ap.add_argument("--source-hash",default="")
    a=ap.parse_args()
    compiled_package=require_circle_package(a.compiled_host_package)
    paths={k.replace("-","_"):Path(v) for k,v in vars(a).items() if k not in ("out","compiled_host_package","source_hash")}
    plan=obj(paths["plan"]); receipt=obj(paths["receipt"]); tup=obj(paths["tuple"]); manifest=obj(paths["manifest"])
    case=obj(paths["case"]); recipe=obj(paths["recipe"])
    candidate=str(plan.get("candidate","")); tuple_id=str(tup.get("id",plan.get("tuple",{}).get("id","")))
    case_id=str(manifest.get("case",{}).get("id",case.get("id","")))
    case_hash=canonical(manifest.get("case",{}).get("hash",case.get("hash","")))
    recipe_hash=canonical(manifest.get("recipe",{}).get("hash",recipe.get("hash","")))
    source_hash=str(a.source_hash or plan.get("sourceHash",receipt.get("sourceHash","")))
    if not candidate or not tuple_id or not case_id or not case_hash or not recipe_hash or not source_hash:
        raise RuntimeError("plan/case/tuple/source identity is incomplete")
    if manifest.get("case",{}).get("id") not in (None,case_id) or canonical(manifest.get("case",{}).get("hash","")) != case_hash:
        raise RuntimeError("manifest case identity differs from generated case")
    if plan.get("sourceHash") and str(plan.get("sourceHash"))!=source_hash:
        raise RuntimeError("plan source hash differs from requested source hash")
    if plan.get("manifestHash") and sha(plan.get("manifestHash"))!=digest(paths["manifest"],MAX_JSON)[0]:
        raise RuntimeError("plan manifest byte hash differs from generated manifest")
    if manifest.get("sourceHash") and str(manifest.get("sourceHash"))!=source_hash:
        raise RuntimeError("manifest source hash differs from requested source hash")
    plan_h,_=digest(paths["plan"],MAX_JSON); receipt_h,_=digest(paths["receipt"],MAX_JSON); tuple_h,_=digest(paths["tuple"],MAX_JSON)
    binding_h,_=digest(paths["binding"],MAX_JSON); context_h,_=digest(paths["context"],MAX_JSON)
    recipe_raw_h,_=digest(paths["recipe"],MAX_JSON); manifest_h,_=digest(paths["manifest"],MAX_JSON)
    capture_h,_=digest(paths["capture_plan"],MAX_JSON); serializer_h,_=digest(paths["serializer"])
    integration_h,_=digest(paths["integration_bindings"],MAX_JSON); preflight_h,_=digest(paths["build_preflight"],MAX_FILE)
    renderer_h,renderer_n=digest(paths["renderer"]); exe_h,exe_n=digest(paths["exe"]); uia_h,uia_n=digest(paths["uia_worker"])
    expected_exe=sha(plan.get("expectedHostHash",receipt.get("exeSha256",exe_h)))
    if expected_exe!=exe_h: raise RuntimeError("measured executable differs from plan/receipt")
    renderer_pin=sha(plan.get("rendererSha256",receipt.get("rendererSha256",renderer_h)))
    if renderer_pin!=renderer_h: raise RuntimeError("measured renderer differs from plan/receipt")
    runtime=str(plan.get("runtimeSourceCommit",receipt.get("runtimeSourceCommit","")))
    if not runtime: raise RuntimeError("runtime source commit missing")
    si={
      "kind":"factory-circle-source-inputs-diagnostic-v1","count":1,"candidate":candidate,
      "caseID":case_id,"caseHash":case_hash,"sourceHash":source_hash,"tupleID":tuple_id,
      "planHash":plan_h,"compileReceiptHash":receipt_h,"tupleHash":tuple_h,"bindingHash":binding_h,
      "recipeHash":recipe_hash,"exeHash":exe_h,"rendererSha256":renderer_h,
      "rendererPath":str(paths["renderer"]),"compiledHostPackagePath":compiled_package,
      "compileReceiptPath":str(paths["receipt"]),"capturePlanPath":str(paths["capture_plan"]),
      "capturePlanHash":capture_h,"capturePlanRef":ref(paths["capture_plan"],MAX_JSON),"buildPreflightPath":str(paths["build_preflight"]),
      "buildPreflightHash":preflight_h,"runtimeSourceCommit":runtime,
      "serializerControlSha256":serializer_h,"serializerPath":str(paths["serializer"]),
      "contextRef":ref(paths["context"],MAX_JSON),"planRef":ref(paths["plan"],MAX_JSON),
      "compileRef":ref(paths["receipt"],MAX_JSON),"tupleRef":ref(paths["tuple"],MAX_JSON),
      "bindingRef":ref(paths["binding"],MAX_JSON),"caseRef":ref(paths["case"],MAX_JSON),"recipeRef":ref(paths["recipe"],MAX_JSON),
      "manifestRef":ref(paths["manifest"],MAX_JSON),"receiptRef":ref(paths["receipt"],MAX_JSON),
      "rendererRef":ref(paths["renderer"]),"exeRef":ref(paths["exe"]),
      "serializerRef":ref(paths["serializer"]),"integrationBindingsRef":ref(paths["integration_bindings"],MAX_JSON),
      "buildPreflightRef":ref(paths["build_preflight"]),"uiaWorkerPath":str(paths["uia_worker"]),
      "uiaWorkerHash":uia_h,"manifestHash":"sha256:"+manifest_h,
      "rawRecipeHash":recipe_raw_h,"serializerBytes":digest(paths["serializer"])[1],
      "exeBytes":exe_n,"rendererBytes":renderer_n,"uiaWorkerBytes":uia_n,"integrationBindingsHash":integration_h
    }
    out=Path(a.out)
    if out.exists(): raise RuntimeError(f"fresh output required: {out}")
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(si,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    h,n=digest(out,MAX_JSON)
    print(json.dumps({"status":"SOURCE_ONLY_INPUTS_MATERIALIZED","path":str(out),"bytes":n,"sha256":h,"nativeActions":0,"compilerActions":0,"lockActions":0},sort_keys=True))

if __name__=="__main__": main()
