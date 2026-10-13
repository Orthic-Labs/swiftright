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
CLEANUP_SHA="cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13"
OLD_CLEANUP_SHA="a9386ddd954490a0da9565211248944ebeb5a27492465512f0e9a55f9dbf2bd7"

# Explicit donor rows; no recursive discovery is used.
DONOR_STAGE="stage-manifest.json"
OVERLAY_FILES=(
    "diagnostic-profile.ps1"
    "diagnostic-profile-root-v4.ps1"
    "integration-fresh-circle-diagnostic-v4.ps1"
    "final-plan-eligibility-diagnostic-v4.ps1"
    "capture-circle-diagnostic-single-v4.ps1"
    "dispatch-circle-diagnostic-single-v4.ps1"
    "coordinator-count1-diagnostic-v4.ps1"
    "capture-build-preflight-diagnostic-v4.ps1"
    "issue-circle-diagnostic-metadata-v4.ps1"
    "test-circle-diagnostic-controls-v4.ps1"
    "test-circle-diagnostic-controls-root-v4.ps1"
    "interactive-task-circle-single-v4.ps1"
    "Sr0OwnedJobProcess-v15.cs"
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
    tmp=dst.with_name(dst.name+".root-v4-replacement")
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

def canonical(value):
    h=norm_sha(value)
    if not re.fullmatch(r"[0-9a-f]{64}",h): raise RuntimeError("canonical hash must be 64 hex")
    return "sha256:"+h

def json_paths(value, path_map):
    if isinstance(value,dict):
        return {k:(path_map.get(str(v),v) if k=="path" and isinstance(v,str) else json_paths(v,path_map)) for k,v in value.items()}
    if isinstance(value,list): return [json_paths(v,path_map) for v in value]
    return value

def json_refs(value, local_targets):
    if isinstance(value,dict):
        out={k:json_refs(v,local_targets) for k,v in value.items()}
        p=out.get("path")
        if isinstance(p,str) and p in local_targets:
            h,n=local_targets[p];out["sha256"]="sha256:"+h;out["bytes"]=n
        return out
    if isinstance(value,list): return [json_refs(v,local_targets) for v in value]
    return value

def write_json(path,obj):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(obj,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")

def copy_or_verify(src,dst,limit=MAX_FILE):
    h,n=digest(src,limit)
    if dst.exists():
        got,size=digest(dst,limit)
        if (got,size)!=(h,n): raise RuntimeError("explicit staged role collision: "+str(dst))
    else: copy_bounded(src,dst,limit)
    return h,n

def win_join(root,rel):
    return str(root).rstrip('\\/')+'\\'+str(rel).replace('/','\\')

def ref_for(path, target):
    h,n=digest(path,MAX_FILE)
    return {"path":target,"sha256":"sha256:"+h,"bytes":n}

def replace_hash_refs(value, targets):
    """Refresh exact staged refs after path rewrites; external refs stay measured."""
    if isinstance(value,dict):
        out={k:replace_hash_refs(v,targets) for k,v in value.items()}
        p=out.get('path')
        if isinstance(p,str) and p in targets:
            h,n=targets[p];out['sha256']='sha256:'+h;out['bytes']=n
        return out
    if isinstance(value,list): return [replace_hash_refs(v,targets) for v in value]
    return value

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
    ap.add_argument("--binding",required=True)
    ap.add_argument("--context",required=True)
    ap.add_argument("--capture-plan",required=True)
    ap.add_argument("--serializer",required=True)
    ap.add_argument("--integration-bindings",required=True)
    ap.add_argument("--build-preflight",required=True)
    ap.add_argument("--uia-worker",required=True)
    ap.add_argument("--renderer",required=True)
    ap.add_argument("--exe",required=True)
    ap.add_argument("--cleanup-v2",required=True)
    ap.add_argument("--renderer-cleanup-v2",required=True)
    ap.add_argument("--installed-root",required=True)
    ap.add_argument("--external-plan-target",required=True)
    ap.add_argument("--external-receipt-target",required=True)
    ap.add_argument("--external-exe-target",required=True)
    ap.add_argument("--external-renderer-target",required=True)
    ap.add_argument("--zip-path",required=True)
    ap.add_argument("--installer-path",required=True)
    ap.add_argument("--stage-manifest-path",required=True)
    ap.add_argument("--build-script",required=True)
    ap.add_argument("--build-script-sha256",required=True)
    ap.add_argument("--job-helper",required=True)
    ap.add_argument("--job-helper-sha256",required=True)
    args=ap.parse_args()
    donor=Path(args.donor_root); overlay=Path(args.overlay_root); out=Path(args.output_root)
    source_inputs=Path(args.source_inputs); plan_path=Path(args.final_plan); receipt_path=Path(args.final_receipt)
    tuple_path=Path(args.tuple); case_path=Path(args.case); manifest_path=Path(args.manifest); recipe_path=Path(args.recipe)
    cleanup=Path(args.cleanup_v2); renderer_cleanup=Path(args.renderer_cleanup_v2)
    if out.exists(): raise RuntimeError(f"fresh output required: {out}")
    if not donor.is_dir() or not overlay.is_dir(): raise RuntimeError("donor/overlay root missing")
    for p in (source_inputs,plan_path,receipt_path,tuple_path,case_path,manifest_path,recipe_path,Path(args.binding),Path(args.context),Path(args.capture_plan),Path(args.serializer),Path(args.integration_bindings),Path(args.build_preflight),Path(args.uia_worker),Path(args.renderer),Path(args.exe),cleanup,renderer_cleanup,Path(args.build_script),Path(args.job_helper)): regular(p)
    si=load_json(source_inputs)
    plan=load_json(plan_path); receipt=load_json(receipt_path); tup=load_json(tuple_path)
    actual_manifest=load_json(manifest_path); case=load_json(case_path); recipe=load_json(recipe_path)
    PLAN_SHA,_=digest(plan_path); RECEIPT_SHA,_=digest(receipt_path); TUPLE_SHA,_=digest(tuple_path)
    EXE_SHA=norm_sha(str(plan.get("expectedHostHash"))); RENDERER_SHA=norm_sha(str(plan.get("rendererSha256"))); RUNTIME=str(plan.get("runtimeSourceCommit"))
    if plan.get("kind")!="factory-circle-incremental-compile-plan-v1" or plan.get("phase")!="final": raise RuntimeError("incremental plan kind/phase required")
    if not str(plan.get("candidate","")).startswith("swiftui.circle.fixed.pilot-next."): raise RuntimeError("diagnostic candidate mismatch")
    if plan.get("qualification")!="diagnostic-native-only-not-qualified" or plan.get("executionEligible") is not True: raise RuntimeError("diagnostic eligibility mismatch")
    if receipt.get("kind")!="factory-circle-incremental-owned-compile-v1" or receipt.get("phase")!="final": raise RuntimeError("incremental receipt kind/phase required")
    if norm_sha(assert_sha(plan_path,PLAN_SHA,"plan")[0])!=PLAN_SHA: raise RuntimeError("plan seal mismatch")
    if norm_sha(assert_sha(receipt_path,RECEIPT_SHA,"receipt")[0])!=RECEIPT_SHA: raise RuntimeError("receipt seal mismatch")
    if norm_sha(str(plan.get("expectedHostHash")))!=EXE_SHA or norm_sha(str(receipt.get("exeSha256")))!=EXE_SHA: raise RuntimeError("exe seal mismatch")
    if tup.get("id")!=plan.get("tuple",{}).get("id") or tup.get("hostHashes")!=plan.get("tuple",{}).get("hostHashes"): raise RuntimeError("tuple host closure mismatch")
    if norm_sha(str(tup.get("hostHashes",{}).get("windows")))!=EXE_SHA: raise RuntimeError("tuple/exe join mismatch")
    if plan.get("runtimeSourceCommit")!=RUNTIME or receipt.get("runtimeSourceCommit")!=RUNTIME: raise RuntimeError("runtime join mismatch")
    if str(si.get("kind"))!="factory-circle-source-inputs-diagnostic-v1" or int(si.get("count",0))!=1: raise RuntimeError("source-inputs kind/count mismatch")
    for key,expected in (("planHash",PLAN_SHA),("compileReceiptHash",RECEIPT_SHA),("exeHash",EXE_SHA),("tupleHash",TUPLE_SHA),("rendererSha256",RENDERER_SHA)):
        if norm_sha(str(si.get(key)))!=expected: raise RuntimeError(f"source-input {key} mismatch")
    if str(si.get("candidate"))!=str(plan.get("candidate")) or str(si.get("tupleID"))!=str(tup.get("id")) or str(si.get("caseID"))!=str(actual_manifest.get("case",{}).get("id")): raise RuntimeError("source-input identity mismatch")
    if canonical(actual_manifest.get("case",{}).get("hash"))!=canonical(plan.get("case",{}).get("hash")): raise RuntimeError("case canonical hash mismatch")
    if canonical(actual_manifest.get("recipe",{}).get("hash"))!=canonical(recipe.get("hash",actual_manifest.get("recipe",{}).get("hash"))): raise RuntimeError("recipe canonical hash mismatch")
    if norm_sha(str(si.get("caseHash")))!=norm_sha(str(actual_manifest.get("case",{}).get("hash"))): raise RuntimeError("source-input case hash mismatch")
    if norm_sha(str(si.get("sourceHash")))!=norm_sha(str(actual_manifest.get("sourceHash"))): raise RuntimeError("source-input source hash mismatch")
    if norm_sha(str(si.get("recipeHash")))!=norm_sha(str(actual_manifest.get("recipe",{}).get("hash"))): raise RuntimeError("source-input recipe hash mismatch")
    manifest_raw_hash,_=digest(manifest_path,MAX_JSON)
    if plan.get("manifestHash") and norm_sha(str(plan.get("manifestHash")))!=manifest_raw_hash: raise RuntimeError("manifest byte hash mismatch")
    if si.get("manifestHash") and norm_sha(str(si.get("manifestHash")))!=manifest_raw_hash: raise RuntimeError("source-input manifest byte hash mismatch")
    cleanup_hash,cleanup_bytes=digest(cleanup); renderer_hash,renderer_bytes=digest(renderer_cleanup)
    if cleanup_hash!=CLEANUP_SHA or renderer_hash!=CLEANUP_SHA: raise RuntimeError("cleanup-v2 seal mismatch")
    build_source=Path(args.build_script);helper_source=Path(args.job_helper)
    build_hash,build_bytes=digest(build_source);helper_hash,helper_bytes=digest(helper_source)
    if build_hash!=norm_sha(args.build_script_sha256) or helper_hash!=norm_sha(args.job_helper_sha256): raise RuntimeError("build/helper source seal mismatch")
    donor_manifest=load_json(donor/DONOR_STAGE)
    rows=donor_manifest.get("files")
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
        actual,size=copy_bounded(src,out/"package"/"overlay"/"root-v4"/name)
        total+=size; staged.append({"path":str(Path("package/overlay/root-v4")/name).replace(os.sep,"/"),"bytes":size,"sha256":actual})
    for src,rel in ((cleanup,"package/overlay/root-v4/producer/support/cleanup-v2.ps1"),(renderer_cleanup,"package/overlay/root-v4/producer/dependencies/uia-worker/support/cleanup-v2.ps1")):
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
        transforms.append({"path":rel,"beforeSha256":old_hash,"beforeBytes":old_bytes,"afterSha256":new_hash,"afterBytes":new_bytes,"change":"pass measured worker exe hash to root-v4 cleanup"})
        for row in staged:
            if row["path"]==rel: row.update({"bytes":new_bytes,"sha256":new_hash})
    # Copy measured candidate documents into one explicit installed namespace.
    role_specs=(
      ("tuple",tuple_path,"package/overlay/root-v4/admission/candidate-tuple-final.json"),
      ("case",case_path,"package/overlay/root-v4/admission/case-final.json"),
      ("manifest",manifest_path,"package/overlay/root-v4/admission/manifest-final.json"),
      ("recipe",recipe_path,"package/overlay/root-v4/admission/recipe-final.json"),
      ("binding",Path(args.binding),"package/overlay/root-v4/admission/candidate-binding-final.json"),
      ("context",Path(args.context),"package/overlay/root-v4/admission/context-final.json"),
      ("capturePlan",Path(args.capture_plan),"package/producer/capture-plan.json"),
      ("serializer",Path(args.serializer),"package/producer/serializer-control.json"),
      ("integrationBindings",Path(args.integration_bindings),"package/producer/integration-bindings.json"),
      ("buildPreflight",Path(args.build_preflight),"package/overlay/root-v4/capture-build-preflight-v4.ps1"),
      ("uiaWorker",Path(args.uia_worker),"package/producer/dependencies/uia-worker/invoke-worker-mta.ps1"),
    )
    role_local={};role_targets={};path_map={}
    for name,src,rel in role_specs:
        regular(src,MAX_JSON if src.suffix.lower()=='.json' else MAX_FILE)
        dst=out/rel
        lim=MAX_JSON if src.suffix.lower()=='.json' else MAX_FILE
        if dst.exists() and name in ("capturePlan","integrationBindings","uiaWorker"):
            source_hash,source_size=digest(src,lim);actual,size=digest(dst,lim)
            if (actual,size)!=(source_hash,source_size):
                raise RuntimeError(f"staged role differs from measured source: {name}")
        else: actual,size=copy_or_verify(src,dst,lim)
        role_local[name]=dst;role_targets[name]=win_join(args.installed_root,rel)
        path_map[str(src)]=role_targets[name];path_map[str(src.resolve())]=role_targets[name]
        staged.append({"path":rel,"bytes":size,"sha256":actual});total+=size
    path_map.update({str(plan_path):args.external_plan_target,str(plan_path.resolve()):args.external_plan_target,
                     str(receipt_path):args.external_receipt_target,str(receipt_path.resolve()):args.external_receipt_target,
                     str(Path(args.exe)):args.external_exe_target,str(Path(args.exe).resolve()):args.external_exe_target,
                     str(Path(args.renderer)):args.external_renderer_target,str(Path(args.renderer).resolve()):args.external_renderer_target})
    # Candidate documents carry historical Windows paths. Rebind only their
    # typed fields; never apply basename-wide replacement to arbitrary rows.
    binding_doc=load_json(role_local["binding"]); tuple_doc=load_json(role_local["tuple"])
    old_tuple=binding_doc.get("canonicalTupleRef",{}).get("path")
    if isinstance(old_tuple,str): path_map[old_tuple]=role_targets["tuple"]
    compiled_plan=tuple_doc.get("sourceInputs",{}).get("compiledPlan",{}).get("path")
    if isinstance(compiled_plan,str): path_map[compiled_plan]=args.external_plan_target
    context_ref=tuple_doc.get("sourceInputs",{}).get("context",{}).get("path")
    if isinstance(context_ref,str): path_map[context_ref]=role_targets["context"]
    # Preserve local JSON semantics while replacing only exact source paths.
    # Manifest bytes are sealed by plan.manifestHash; preserve them exactly.
    # Case & recipe canonical hashes are content identities; preserve bytes.
    for name in ("tuple","binding","context"):
        doc=load_json(role_local[name]);write_json(role_local[name],json_paths(doc,path_map))
    # Fixed-point reseal updates candidate tuple/binding/context refs after path rewrites.
    for _ in range(3):
        local_targets={}
        for name,p in role_local.items():
            h,n=digest(p,MAX_JSON if p.suffix.lower()=='.json' else MAX_FILE);local_targets[role_targets[name]]=(h,n)
        for name in ("tuple","binding","context"):
            write_json(role_local[name],replace_hash_refs(load_json(role_local[name]),local_targets))
    # Fixed-point rewrites changed role bytes; stage rows must describe final
    # bytes consumed by installer, never pre-rewrite donor bytes.
    for name,p in role_local.items():
        rel=p.relative_to(out).as_posix(); h,n=digest(p,MAX_JSON if p.suffix.lower()=='.json' else MAX_FILE)
        for row in staged:
            if row.get("path")==rel: row.update({"sha256":h,"bytes":n})
    # Installed graph receives external measured plan/receipt/binary refs; binary bytes stay external.
    si_final=dict(si);si_final.update({
      "kind":"factory-circle-source-inputs-diagnostic-v4","caseHash":canonical(actual_manifest.get("case",{}).get("hash")),
      "recipeHash":canonical(actual_manifest.get("recipe",{}).get("hash")),"tupleID":tup["id"],"candidate":plan["candidate"],
      "planHash":PLAN_SHA,"compileReceiptHash":RECEIPT_SHA,"tupleHash":digest(role_local["tuple"],MAX_JSON)[0],
      "bindingHash":digest(role_local["binding"],MAX_JSON)[0],"contextHash":digest(role_local["context"],MAX_JSON)[0],
      "exeHash":EXE_SHA,"rendererSha256":RENDERER_SHA,"caseID":actual_manifest.get("case",{}).get("id"),
      "sourceHash":plan.get("sourceHash",si.get("sourceHash")),"runtimeSourceCommit":RUNTIME,
      "planRef":{"path":args.external_plan_target,"sha256":"sha256:"+PLAN_SHA,"bytes":digest(plan_path,MAX_JSON)[1]},
      "compileRef":{"path":args.external_receipt_target,"sha256":"sha256:"+RECEIPT_SHA,"bytes":digest(receipt_path,MAX_JSON)[1]},
      "receiptRef":{"path":args.external_receipt_target,"sha256":"sha256:"+RECEIPT_SHA,"bytes":digest(receipt_path,MAX_JSON)[1]},
      "exeRef":ref_for(exe_path:=Path(args.exe),args.external_exe_target),"rendererRef":ref_for(Path(args.renderer),args.external_renderer_target),
      "rendererPath":args.external_renderer_target,"compiledHostPackagePath":args.external_plan_target.rsplit('\\',1)[0],"compileReceiptPath":args.external_receipt_target,
      "tupleRef":ref_for(role_local["tuple"],role_targets["tuple"]),"bindingRef":ref_for(role_local["binding"],role_targets["binding"]),
      "contextRef":ref_for(role_local["context"],role_targets["context"]),"caseRef":ref_for(role_local["case"],role_targets["case"]),
      "manifestRef":ref_for(role_local["manifest"],role_targets["manifest"]),"recipeRef":ref_for(role_local["recipe"],role_targets["recipe"]),
      "capturePlanRef":ref_for(role_local["capturePlan"],role_targets["capturePlan"]),"capturePlanPath":role_targets["capturePlan"],
      "serializerRef":ref_for(role_local["serializer"],role_targets["serializer"]),"serializerPath":role_targets["serializer"],
      "integrationBindingsRef":ref_for(role_local["integrationBindings"],role_targets["integrationBindings"]),
      "buildPreflightRef":ref_for(role_local["buildPreflight"],role_targets["buildPreflight"]),"buildPreflightPath":role_targets["buildPreflight"],
      "uiaWorkerPath":role_targets["uiaWorker"],"uiaWorkerHash":digest(role_local["uiaWorker"],MAX_FILE)[0],
      "integrationBindingsHash":digest(role_local["integrationBindings"],MAX_JSON)[0],"serializerControlSha256":digest(role_local["serializer"],MAX_FILE)[0],
      "buildPreflightHash":digest(role_local["buildPreflight"],MAX_FILE)[0],"capturePlanHash":digest(role_local["capturePlan"],MAX_JSON)[0],
    })
    si_target=out/"package/overlay/root-v4/admission/source-inputs.json";write_json(si_target,si_final)
    si_h,si_n=digest(si_target,MAX_JSON);staged.append({"path":"package/overlay/root-v4/admission/source-inputs.json","bytes":si_n,"sha256":si_h});total+=si_n
    if total>MAX_TOTAL: raise RuntimeError("staged total bound")
    unique={row["path"]:row for row in staged};staged=list(unique.values())
    graph={"kind":"factory-circle-incremental-diagnostic-source-graph-v4","candidate":plan["candidate"],"plan":{"path":"external:"+args.external_plan_target,"sha256":"sha256:"+PLAN_SHA,"bytes":digest(plan_path,MAX_JSON)[1]},"receipt":{"path":"external:"+args.external_receipt_target,"sha256":"sha256:"+RECEIPT_SHA,"bytes":digest(receipt_path,MAX_JSON)[1]},"tuple":{"path":role_targets["tuple"],"sha256":"sha256:"+digest(role_local["tuple"],MAX_JSON)[0]},"exeSha256":EXE_SHA,"rendererSha256":RENDERER_SHA,"runtimeSourceCommit":RUNTIME,"diagnosticQualification":"diagnostic-native-only-not-qualified","count":1,"nativeActions":0,"compilerActions":0,"lockActions":0,"buildSource":{"path":str(build_source),"sha256":build_hash,"bytes":build_bytes},"jobHelperSource":{"path":str(helper_source),"sha256":helper_hash,"bytes":helper_bytes},"cleanup":{"renderer":{"path":win_join(args.installed_root,"package/producer/support/cleanup.ps1"),"sha256":"sha256:"+CLEANUP_SHA,"bytes":renderer_bytes},"uia":{"path":win_join(args.installed_root,"package/producer/dependencies/uia-worker/support/cleanup-v2.ps1"),"sha256":"sha256:"+CLEANUP_SHA,"bytes":cleanup_bytes}},"externalMeasuredRefs":True,"sourceTransforms":transforms,"files":staged}
    write_json(out/"source-graph-v4.json",graph)
    graph_h,graph_n=digest(out/"source-graph-v4.json",MAX_JSON)
    stage_doc={"kind":"factory-circle-incremental-diagnostic-stage-v4","status":"SOURCE_ONLY","stageRoot":args.installed_root,"candidate":plan["candidate"],"incrementalPlanKind":plan["kind"],"incrementalReceiptKind":receipt["kind"],"plan":graph["plan"],"receipt":graph["receipt"],"files":staged,"sourceGraph":{"path":"source-graph-v4.json","sha256":"sha256:"+graph_h,"bytes":graph_n},"limits":{"maxFiles":MAX_FILES,"maxFileBytes":MAX_FILE,"maxTotalBytes":MAX_TOTAL},"nativeActions":0,"compilerActions":0,"lockActions":0}
    stage_manifest=Path(args.stage_manifest_path)
    if stage_manifest.exists(): raise RuntimeError("fresh stage manifest required: "+str(stage_manifest))
    write_json(stage_manifest,stage_doc);stage_h,stage_n=digest(stage_manifest,MAX_JSON)
    payload=[(out/row["path"],row["path"]) for row in staged]+[(out/"source-graph-v4.json","source-graph-v4.json"),(stage_manifest,"stage-manifest-v4.json")]
    payload_bytes=sum(digest(p,MAX_FILE)[1] for p,_ in payload)
    if len(payload)+1>MAX_FILES or payload_bytes>MAX_TOTAL: raise RuntimeError("archive bounds exceeded")
    inventory={"kind":"factory-circle-incremental-diagnostic-zip-inventory-v4","files":[{"path":rel,"bytes":digest(p,MAX_FILE)[1],"sha256":digest(p,MAX_FILE)[0]} for p,rel in payload],"fileCount":len(payload),"payloadBytes":payload_bytes,"nativeActions":0,"compilerActions":0,"lockActions":0}
    inv_path=out/"zip-inventory-v4.json";write_json(inv_path,inventory);payload.append((inv_path,"zip-inventory-v4.json"))
    zip_path=Path(args.zip_path)
    if zip_path.exists(): raise RuntimeError("fresh ZIP required: "+str(zip_path))
    zip_path.parent.mkdir(parents=True,exist_ok=True)
    import zipfile
    with zipfile.ZipFile(zip_path,'x',compression=zipfile.ZIP_DEFLATED) as z:
        for p,rel in payload: z.write(p,rel)
    zip_h,zip_n=digest(zip_path,MAX_TOTAL)
    template=overlay/"install-circle-diagnostic-root-v4.ps1";template_data=template.read_text(encoding='utf-8')
    template_data=template_data.replace("build-circle-diagnostic-root-v4.ps1","build-circle-diagnostic-root-v4.ps1").replace("circle-close-r11-r4",str(args.installed_root).replace('/','\\'))
    installer=Path(args.installer_path)
    if installer.exists(): raise RuntimeError("fresh installer required: "+str(installer))
    installer.parent.mkdir(parents=True,exist_ok=True);installer.write_text(template_data,encoding='utf-8')
    installer_h,installer_n=digest(installer,MAX_FILE)
    print(json.dumps({"status":"SOURCE_ONLY_STAGED","kind":graph["kind"],"files":len(staged),"bytes":total,"planSha256":PLAN_SHA,"receiptSha256":RECEIPT_SHA,"exeSha256":EXE_SHA,"cleanupV2Sha256":CLEANUP_SHA,"graphSha256":graph_h,"stageManifestSha256":stage_h,"zipSha256":zip_h,"zipBytes":zip_n,"installerSha256":installer_h,"installerBytes":installer_n,"nativeActions":0,"compilerActions":0,"lockActions":0},sort_keys=True))

if __name__=="__main__": main()
