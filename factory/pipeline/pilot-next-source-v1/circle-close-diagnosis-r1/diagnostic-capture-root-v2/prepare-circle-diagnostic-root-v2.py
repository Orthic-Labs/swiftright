#!/usr/bin/env python3
"""Bounded source-only Circle incremental diagnostic Count1 packer.

This command stages explicit donor rows, measured final incremental evidence, & a
fresh diagnostic overlay. It never compiles, launches, acquires locks, or edits
an existing destination.
"""
from __future__ import annotations
import argparse, hashlib, json, os, re, stat
from pathlib import Path

MAX_FILES=256
MAX_FILE=64*1024*1024
MAX_JSON=4*1024*1024
MAX_TOTAL=256*1024*1024
BUF=1024*1024
PLAN_SHA="a47edfddc082d183dff2f6af9888725896bf859c5c2e60b1e12a8fb0d392f6f"
RECEIPT_SHA="fcbcdfafd2358b34b2d9483d229ccc019a5bba7c6320569436b39702edbe2428"
EXE_SHA="84ad41579a21bdf8456d5b1c63f862c7fb227001f970ef1a09ec3557e8b4b490"
TUPLE_SHA="44413e65c5ae87e479129531458f5910a9477dc6cf3b8961db9e449755dec65f"
RENDERER_SHA="e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93"
RUNTIME="37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b"
CLEANUP_SHA="cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13"
OLD_CLEANUP_SHA="a9386ddd954490a0da9565211248944ebeb5a27492465512f0e9a55f9dbf2bd7"

# Explicit donor rows; no recursive discovery is used.
DONOR_STAGE="stage-manifest.json"
OVERLAY_FILES=(
    "diagnostic-profile-root-v2.ps1"
    "integration-fresh-circle-diagnostic-v1.ps1"
    "final-plan-eligibility-diagnostic-v1.ps1"
    "capture-circle-diagnostic-single-v1.ps1"
    "dispatch-circle-diagnostic-single-v1.ps1"
    "coordinator-count1-diagnostic-v1.ps1"
    "capture-build-preflight-diagnostic-v1.ps1"
    "issue-circle-diagnostic-metadata-v1.ps1"
    "test-circle-diagnostic-controls-v1.ps1"
)

def regular(path: Path, limit: int=MAX_FILE):
    st=path.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode):
        raise RuntimeError(f"unsafe non-regular source: {path}")
    if st.st_size>limit: raise RuntimeError(f"source exceeds bound: {path}")
    return st

def digest(path: Path, limit: int=MAX_FILE):
    st=regular(path,limit); h=hashlib.sha256(); size=0
    with path.open("rb") as stream:
        while True:
            block=stream.read(BUF)
            if not block: break
            size += len(block)
            if size>limit: raise RuntimeError(f"source grew beyond bound: {path}")
            h.update(block)
    if path.lstat().st_size!=size: raise RuntimeError(f"source changed during read: {path}")
    return h.hexdigest(),size

def load_json(path: Path, limit: int=MAX_JSON):
    digest(path,limit)
    return json.loads(path.read_text(encoding="utf-8-sig"))

def copy_bounded(src: Path, dst: Path, limit: int=MAX_FILE):
    expected,size=digest(src,limit)
    dst.parent.mkdir(parents=True,exist_ok=True)
    if dst.exists(): raise RuntimeError(f"fresh destination collision: {dst}")
    written=0
    with src.open("rb") as reader, dst.open("xb") as writer:
        while True:
            block=reader.read(BUF)
            if not block: break
            written += len(block)
            if written>limit: raise RuntimeError(f"copy exceeded bound: {src}")
            writer.write(block)
    actual,actual_size=digest(dst,limit)
    if (actual,actual_size)!=(expected,size): raise RuntimeError(f"copy verification failed: {src}")
    return expected,size

def replace_declared(src: Path, dst: Path, old_hash: str, limit: int=MAX_FILE):
    """Replace only fresh staged donor role after verifying its measured old bytes."""
    old,size= digest(dst,limit)
    if old!=old_hash: raise RuntimeError(f"declared replacement predecessor drift: {dst}")
    expected,new_size=digest(src,limit)
    tmp=dst.with_name(dst.name+".root-v2-replacement")
    if tmp.exists(): raise RuntimeError(f"replacement collision: {tmp}")
    written=0
    with src.open("rb") as reader, tmp.open("xb") as writer:
        while True:
            block=reader.read(BUF)
            if not block: break
            written+=len(block)
            if written>limit: raise RuntimeError(f"replacement exceeded bound: {src}")
            writer.write(block)
    actual,actual_size=digest(tmp,limit)
    if (actual,actual_size)!=(expected,new_size): raise RuntimeError(f"replacement verification failed: {src}")
    os.replace(tmp,dst)
    return expected,new_size

def patch_cleanup_call(path: Path, needle: str, replacement: str):
    """Patch one known worker call in fresh output, retaining donor bytes in graph."""
    before,size=digest(path,8*1024*1024)
    text=path.read_text(encoding="utf-8")
    if text.count(needle)!=1:
        raise RuntimeError(f"expected one cleanup call: {path}")
    path.write_text(text.replace(needle,replacement),encoding="utf-8",newline="")
    after,after_size=digest(path,8*1024*1024)
    return before,size,after,after_size

def norm_sha(value):
    text=str(value)
    return text[7:].lower() if text.lower().startswith("sha256:") else text.lower()

def assert_sha(path: Path, expected: str, label: str):
    got,size=digest(path)
    if got!=norm_sha(expected): raise RuntimeError(f"{label} hash mismatch: {got} != {expected}")
    return got,size

def safe_rel(value: str):
    p=Path(value.replace("\\","/"))
    if p.is_absolute() or not p.parts or re.match(r"^[A-Za-z]:$",p.parts[0]) or any(part in ("",".","..") for part in p.parts):
        raise RuntimeError(f"unsafe source row: {value}")
    return Path(*p.parts)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--donor-root",required=True)
    ap.add_argument("--overlay-root",required=True)
    ap.add_argument("--output-root",required=True)
    ap.add_argument("--source-inputs",required=True)
    ap.add_argument("--final-plan",required=True)
    ap.add_argument("--final-receipt",required=True)
    ap.add_argument("--tuple",required=True)
    ap.add_argument("--case",required=True)
    ap.add_argument("--manifest",required=True)
    ap.add_argument("--recipe",required=True)
    ap.add_argument("--cleanup-v2",required=True)
    ap.add_argument("--renderer-cleanup-v2",required=True)
    args=ap.parse_args()
    donor=Path(args.donor_root); overlay=Path(args.overlay_root); out=Path(args.output_root)
    source_inputs=Path(args.source_inputs); plan_path=Path(args.final_plan); receipt_path=Path(args.final_receipt)
    tuple_path=Path(args.tuple); case_path=Path(args.case); manifest_path=Path(args.manifest); recipe_path=Path(args.recipe)
    cleanup=Path(args.cleanup_v2); renderer_cleanup=Path(args.renderer_cleanup_v2)
    if out.exists(): raise RuntimeError(f"fresh output required: {out}")
    if not donor.is_dir() or not overlay.is_dir(): raise RuntimeError("donor/overlay root missing")
    for p in (source_inputs,plan_path,receipt_path,tuple_path,case_path,manifest_path,recipe_path,cleanup,renderer_cleanup): regular(p)
    si=load_json(source_inputs)
    plan=load_json(plan_path); receipt=load_json(receipt_path); tup=load_json(tuple_path)
    if plan.get("kind")!="factory-circle-incremental-compile-plan-v1" or plan.get("phase")!="final": raise RuntimeError("incremental plan kind/phase required")
    if plan.get("candidate")!="swiftui.circle.fixed.pilot-next.close-diagnostic-r1": raise RuntimeError("diagnostic candidate mismatch")
    if plan.get("qualification")!="diagnostic-native-only-not-qualified" or plan.get("executionEligible") is not True: raise RuntimeError("diagnostic eligibility mismatch")
    if receipt.get("kind")!="factory-circle-incremental-owned-compile-v1" or receipt.get("phase")!="final": raise RuntimeError("incremental receipt kind/phase required")
    if norm_sha(assert_sha(plan_path,PLAN_SHA,"plan")[0])!=PLAN_SHA: raise RuntimeError("plan seal mismatch")
    if norm_sha(assert_sha(receipt_path,RECEIPT_SHA,"receipt")[0])!=RECEIPT_SHA: raise RuntimeError("receipt seal mismatch")
    if norm_sha(str(plan.get("expectedHostHash")))!=EXE_SHA or norm_sha(str(receipt.get("exeSha256")))!=EXE_SHA: raise RuntimeError("exe seal mismatch")
    if tup.get("id")!=plan.get("tuple",{}).get("id") or norm_sha(str(tup.get("hostHashes",{}).get("windows")))!=EXE_SHA: raise RuntimeError("tuple/exe join mismatch")
    if plan.get("runtimeSourceCommit")!=RUNTIME or receipt.get("runtimeSourceCommit")!=RUNTIME: raise RuntimeError("runtime join mismatch")
    if str(si.get("kind"))!="factory-circle-source-inputs-diagnostic-v1" or int(si.get("count",0))!=1: raise RuntimeError("source-inputs kind/count mismatch")
    for key,expected in (("planHash",PLAN_SHA),("compileReceiptHash",RECEIPT_SHA),("exeHash",EXE_SHA),("tupleHash",TUPLE_SHA),("rendererSha256",RENDERER_SHA)):
        if norm_sha(str(si.get(key)))!=expected: raise RuntimeError(f"source-input {key} mismatch")
    cleanup_hash,cleanup_bytes=digest(cleanup); renderer_hash,renderer_bytes=digest(renderer_cleanup)
    if cleanup_hash!=CLEANUP_SHA or renderer_hash!=CLEANUP_SHA: raise RuntimeError("cleanup-v2 seal mismatch")
    manifest=load_json(donor/DONOR_STAGE)
    rows=manifest.get("files")
    if not isinstance(rows,list) or len(rows)>MAX_FILES: raise RuntimeError("donor manifest rows invalid")
    total=0; staged=[]
    for row in rows:
        rel=safe_rel(str(row.get("path",""))); src=donor/rel
        if not src.is_file(): raise RuntimeError(f"donor manifest source absent: {rel}")
        expected=norm_sha(str(row.get("sha256",""))); actual,size=digest(src)
        if actual!=expected or size!=int(row.get("bytes",-1)): raise RuntimeError(f"donor row drift: {rel}")
        copy_bounded(src,out/"package"/rel); total+=size; staged.append({"path":str(Path("package")/rel).replace(os.sep,"/"),"bytes":size,"sha256":actual})
        if total>MAX_TOTAL: raise RuntimeError("donor total bound")
    for name in OVERLAY_FILES:
        src=overlay/name
        if not src.is_file(): raise RuntimeError(f"overlay source absent: {name}")
        actual,size=copy_bounded(src,out/"package"/"overlay"/"root-v2"/name)
        total+=size; staged.append({"path":str(Path("package/overlay/root-v2")/name).replace(os.sep,"/"),"bytes":size,"sha256":actual})
    for src,rel in ((cleanup,"package/overlay/root-v2/producer/support/cleanup-v2.ps1"),(renderer_cleanup,"package/overlay/root-v2/producer/dependencies/uia-worker/support/cleanup-v2.ps1")):
        actual,size=copy_bounded(src,out/rel);total+=size;staged.append({"path":rel,"bytes":size,"sha256":actual})
    # Fresh package explicitly replaces both donor cleanup roles; donor itself is untouched.
    for src,rel in ((cleanup,Path("package/producer/support/cleanup.ps1")),(renderer_cleanup,Path("package/producer/dependencies/uia-worker/support/cleanup.ps1"))):
        actual,size=replace_declared(src,out/rel,OLD_CLEANUP_SHA);total+=size
        for row in staged:
            if row["path"]==str(rel).replace(os.sep,"/"): row.update({"bytes":size,"sha256":actual})
    # Root-v3 cleanup requires an executable hash. Patch only known worker
    # callsites in fresh output; donor source remains immutable.
    transforms=[]
    for rel in ("package/overlay/uia-worker-invoke-v2.ps1",
                "package/producer/dependencies/uia-worker/invoke-worker-mta.ps1",
                "package/producer/dependencies/uia-worker/invoke-worker.ps1"):
        path=out/rel
        if not path.is_file(): raise RuntimeError(f"required cleanup callsite missing: {rel}")
        old_hash,old_bytes,new_hash,new_bytes=patch_cleanup_call(
            path,
            "Invoke-FactoryOwnedCleanup $p $exe $startedAt -KnownStartedIdentity",
            "Invoke-FactoryOwnedCleanup $p $exe $startedAt -ExpectedExeHash $exeHash -KnownStartedIdentity")
        transforms.append({"path":rel,"beforeSha256":old_hash,"beforeBytes":old_bytes,"afterSha256":new_hash,"afterBytes":new_bytes,"change":"pass measured worker exe hash to root-v3 cleanup"})
        for row in staged:
            if row["path"]==rel: row.update({"bytes":new_bytes,"sha256":new_hash})
    for src,rel in ((source_inputs,"package/overlay/root-v2/admission/source-inputs.json"),(plan_path,"package/plan-final.json"),(receipt_path,"package/compile-receipt-final.json"),(tuple_path,"package/overlay/root-v2/admission/candidate-tuple-final.json"),(case_path,"package/overlay/root-v2/admission/case-final.json"),(manifest_path,"package/overlay/root-v2/admission/manifest-final.json"),(recipe_path,"package/overlay/root-v2/admission/recipe-final.json")):
        actual,size=copy_bounded(src,out/rel,MAX_JSON if src in (source_inputs,plan_path,receipt_path,tuple_path,case_path,manifest_path,recipe_path) else MAX_FILE);total+=size;staged.append({"path":rel,"bytes":size,"sha256":actual})
    if total>MAX_TOTAL: raise RuntimeError("staged total bound")
    graph={"kind":"factory-circle-incremental-diagnostic-source-graph-v2","candidate":plan["candidate"],"plan":{"path":"package/plan-final.json","sha256":PLAN_SHA},"receipt":{"path":"package/compile-receipt-final.json","sha256":RECEIPT_SHA},"tuple":{"path":"package/overlay/root-v2/admission/candidate-tuple-final.json","sha256":TUPLE_SHA},"exeSha256":EXE_SHA,"rendererSha256":RENDERER_SHA,"runtimeSourceCommit":RUNTIME,"diagnosticQualification":"diagnostic-native-only-not-qualified","count":1,"nativeActions":0,"compilerActions":0,"cleanup":{"renderer":{"path":"package/overlay/root-v2/producer/support/cleanup-v2.ps1","sha256":CLEANUP_SHA,"bytes":renderer_bytes},"uia":{"path":"package/overlay/root-v2/producer/dependencies/uia-worker/support/cleanup-v2.ps1","sha256":CLEANUP_SHA,"bytes":cleanup_bytes}},"sourceTransforms":transforms,"files":staged}
    out.joinpath("source-graph-v2.json").write_text(json.dumps(graph,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"status":"SOURCE_ONLY_STAGED","kind":graph["kind"],"files":len(staged),"bytes":total,"planSha256":PLAN_SHA,"receiptSha256":RECEIPT_SHA,"exeSha256":EXE_SHA,"cleanupV2Sha256":CLEANUP_SHA,"nativeActions":0,"compilerActions":0,"lockActions":0},sort_keys=True))

if __name__=="__main__": main()
