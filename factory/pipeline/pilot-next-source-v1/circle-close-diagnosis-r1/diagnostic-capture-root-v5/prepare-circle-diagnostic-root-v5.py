#!/usr/bin/env python3
"""Prepare one fresh Circle diagnostic source packet.

This is source-only: it reads explicit measured inputs, copies bounded named
rows, remaps typed refs into one Windows namespace, reseals every ref, & emits
SI, graph, manifest, ZIP & installer. It never discovers, compiles, launches,
locks, deletes, or edits donor files.
"""
from __future__ import annotations
import argparse, hashlib, json, os, re, stat, zipfile
from pathlib import Path

BUF=1024*1024; MAX_JSON=4*1024*1024; MAX_FILE=64*1024*1024
MAX_TOTAL=256*1024*1024; MAX_FILES=256
CLEANUP_SHA="cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13"
OVERLAY_NAMES=(
  "diagnostic-profile.ps1","diagnostic-profile-root-v4.ps1",
  "integration-fresh-circle-diagnostic-v4.ps1",
  "final-plan-eligibility-diagnostic-v4.ps1",
  "capture-circle-diagnostic-single-v4.ps1",
  "dispatch-circle-diagnostic-single-v4.ps1",
  "coordinator-count1-diagnostic-v4.ps1",
  "capture-build-preflight-diagnostic-v4.ps1",
  "issue-circle-diagnostic-metadata-v4.ps1",
  "test-circle-diagnostic-controls-v4.ps1",
  "test-circle-diagnostic-controls-root-v4.ps1",
  "interactive-task-circle-single-v4.ps1","Sr0OwnedJobProcess-v15.cs",
)

def regular(p:Path, limit=MAX_FILE):
    s=p.lstat()
    if not stat.S_ISREG(s.st_mode) or stat.S_ISLNK(s.st_mode): raise RuntimeError(f"unsafe source: {p}")
    if s.st_size>limit: raise RuntimeError(f"source exceeds bound: {p}")
    return s

def digest(p:Path, limit=MAX_FILE):
    s=regular(p,limit); h=hashlib.sha256(); n=0
    with p.open("rb") as f:
        while True:
            b=f.read(BUF)
            if not b: break
            n+=len(b)
            if n>limit: raise RuntimeError(f"stream bound exceeded: {p}")
            h.update(b)
    if p.lstat().st_size!=n: raise RuntimeError(f"source changed while reading: {p}")
    return h.hexdigest(),n

def load(p:Path, limit=MAX_JSON):
    digest(p,limit)
    return json.loads(p.read_text(encoding="utf-8-sig"))

def write_json(p:Path, value):
    p.parent.mkdir(parents=True,exist_ok=True)
    if p.exists(): raise RuntimeError(f"fresh destination collision: {p}")
    p.write_text(json.dumps(value,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    return digest(p,MAX_JSON)

def copy_file(src:Path,dst:Path,limit=MAX_FILE):
    h,n=digest(src,limit); dst.parent.mkdir(parents=True,exist_ok=True)
    if dst.exists(): raise RuntimeError(f"fresh destination collision: {dst}")
    with src.open("rb") as r:
        with dst.open("xb") as dstf:
            while True:
                b=r.read(BUF)
                if not b: break
                dstf.write(b)
    if digest(dst,limit)!=(h,n): raise RuntimeError(f"copy seal mismatch: {src}")
    return h,n

def hs(v):
    s=str(v)
    return s[7:].lower() if s.lower().startswith("sha256:") else s.lower()

def pref(v):
    h=hs(v)
    if not re.fullmatch(r"[0-9a-f]{64}",h): raise RuntimeError(f"invalid SHA-256: {v}")
    return "sha256:"+h

def win(root, rel): return str(root).rstrip("\\/")+"\\"+str(rel).replace("/","\\")
def safe_rel(v):
    s=str(v).replace("\\","/")
    p=Path(s)
    if not s or p.is_absolute() or re.match(r"^[A-Za-z]:",s) or any(x in ("",".","..") for x in p.parts):
        raise RuntimeError(f"unsafe relative row: {v}")
    return Path(*p.parts)

def ref(path,target,limit=MAX_FILE):
    h,n=digest(path,limit)
    return {"path":target,"sha256":"sha256:"+h,"bytes":n}

def collect_path_values(v,out):
    if isinstance(v,dict):
        if isinstance(v.get("path"),str): out.add(v["path"])
        for x in v.values(): collect_path_values(x,out)
    elif isinstance(v,list):
        for x in v: collect_path_values(x,out)

def rewrite_paths(v, mapping):
    if isinstance(v,dict):
        out={k:rewrite_paths(x,mapping) for k,x in v.items()}
        if isinstance(out.get("path"),str) and out["path"] in mapping: out["path"]=mapping[out["path"]]
        return out
    if isinstance(v,list): return [rewrite_paths(x,mapping) for x in v]
    return v

def refresh_refs(v, local_by_target, external_by_target):
    if isinstance(v,dict):
        out={k:refresh_refs(x,local_by_target,external_by_target) for k,x in v.items()}
        p=out.get("path")
        if isinstance(p,str):
            if p in local_by_target: h,n=local_by_target[p]; out["sha256"]="sha256:"+h;out["bytes"]=n
            elif p in external_by_target: h,n=external_by_target[p]; out["sha256"]="sha256:"+h;out["bytes"]=n
        return out
    if isinstance(v,list): return [refresh_refs(x,local_by_target,external_by_target) for x in v]
    return v

def expected(v,*keys):
    for k in keys:
        if isinstance(v,dict) and v.get(k) not in (None,""): return hs(v[k])
    return ""

def main():
    ap=argparse.ArgumentParser()
    for n in ("donor-root","overlay-root","output-root","installed-root","final-plan","final-receipt","tuple","case","manifest","recipe","binding","context","capture-plan","serializer","integration-bindings","build-preflight","uia-worker","renderer","exe","cleanup-v3","job-helper"):
        ap.add_argument("--"+n,required=True)
    ap.add_argument("--external-plan-target",required=True); ap.add_argument("--external-receipt-target",required=True)
    ap.add_argument("--external-exe-target",required=True); ap.add_argument("--external-renderer-target",required=True)
    ap.add_argument("--source-inputs-target",required=True); ap.add_argument("--zip-path",required=True)
    ap.add_argument("--installer-path",required=True); ap.add_argument("--stage-manifest-path",required=True)
    args=ap.parse_args(); A={k.replace("-","_"):Path(v) for k,v in vars(args).items() if isinstance(v,str)}
    out=A["output_root"]; donor=A["donor_root"]; overlay=A["overlay_root"]
    if out.exists(): raise RuntimeError(f"fresh output required: {out}")
    if not donor.is_dir() or not overlay.is_dir(): raise RuntimeError("donor/overlay root missing")
    final_plan=load(A["final_plan"]); final_receipt=load(A["final_receipt"]); tup=load(A["tuple"])
    case=load(A["case"]); manifest=load(A["manifest"]); recipe=load(A["recipe"])
    plan_h,plan_n=digest(A["final_plan"],MAX_JSON); receipt_h,receipt_n=digest(A["final_receipt"],MAX_JSON)
    tuple_h,tuple_n=digest(A["tuple"],MAX_JSON); case_h,case_n=digest(A["case"],MAX_JSON)
    manifest_h,manifest_n=digest(A["manifest"],MAX_JSON); recipe_raw_h,recipe_n=digest(A["recipe"],MAX_JSON)
    exe_h,exe_n=digest(A["exe"]); renderer_h,renderer_n=digest(A["renderer"])
    if final_plan.get("kind")!="factory-circle-incremental-compile-plan-v1" or final_plan.get("phase")!="final": raise RuntimeError("measured final plan kind/phase mismatch")
    if final_receipt.get("kind")!="factory-circle-incremental-owned-compile-v1" or final_receipt.get("phase")!="final": raise RuntimeError("measured final receipt kind/phase mismatch")
    if not str(final_plan.get("candidate","")).startswith("swiftui.circle.fixed.pilot-next."): raise RuntimeError("candidate is not Circle diagnostic")
    if final_plan.get("executionEligible") is not True or final_plan.get("qualification")!="diagnostic-native-only-not-qualified": raise RuntimeError("diagnostic eligibility drift")
    plan_exe=expected(final_plan,"expectedHostHash","exeSha256"); receipt_exe=expected(final_receipt,"exeSha256","expectedHostHash")
    if plan_exe!=exe_h or receipt_exe!=exe_h: raise RuntimeError("measured EXE join mismatch")
    plan_renderer=expected(final_plan,"rendererSha256","rendererHash"); receipt_renderer=expected(final_receipt,"rendererSha256","rendererHash")
    if plan_renderer and plan_renderer!=renderer_h: raise RuntimeError("plan renderer join mismatch")
    if receipt_renderer and receipt_renderer!=renderer_h: raise RuntimeError("receipt renderer join mismatch")
    candidate=str(final_plan["candidate"]); tuple_id=str(tup.get("id")); case_id=str(manifest.get("case",{}).get("id",case.get("id","")))
    if not tuple_id or not case_id: raise RuntimeError("fresh tuple/case identity absent")
    if tup.get("hostHashes",{}).get("windows") and hs(tup["hostHashes"]["windows"])!=exe_h: raise RuntimeError("tuple Windows host mismatch")
    if tup.get("rendererHash") and hs(tup["rendererHash"])!=renderer_h: raise RuntimeError("tuple renderer mismatch")
    if tup.get("case",{}).get("id") and str(tup["case"]["id"])!=case_id: raise RuntimeError("tuple case ID mismatch")
    if tup.get("case",{}).get("hash") and hs(tup["case"]["hash"])!=hs(manifest.get("case",{}).get("hash",case.get("hash"))): raise RuntimeError("tuple case hash mismatch")
    if manifest.get("case",{}).get("id") and str(manifest["case"]["id"])!=case_id: raise RuntimeError("manifest case ID mismatch")
    if manifest.get("sourceHash") and hs(manifest["sourceHash"])!=hs(final_plan.get("sourceHash")): raise RuntimeError("manifest source join mismatch")
    runtime=str(final_plan.get("runtimeSourceCommit") or final_receipt.get("runtimeSourceCommit") or "")
    if final_plan.get("manifestHash") and hs(final_plan["manifestHash"])!=manifest_h: raise RuntimeError("measured manifest byte join mismatch")
    if final_receipt.get("runtimeSourceCommit") and str(final_receipt["runtimeSourceCommit"])!=runtime: raise RuntimeError("receipt runtime join mismatch")
    if tup.get("runtimeCommit") and str(tup["runtimeCommit"])!=runtime: raise RuntimeError("tuple runtime join mismatch")
    if not runtime: raise RuntimeError("runtime commit absent")
    # Stage only donor manifest rows plus explicit overlay rows. Existing donor docs
    # are preserved as history; fresh admission docs replace same logical roles.
    package=out/"package"; package.mkdir(parents=True)
    donor_manifest=load(donor/"stage-manifest.json"); rows=donor_manifest.get("files")
    if not isinstance(rows,list) or len(rows)>MAX_FILES: raise RuntimeError("donor stage manifest invalid")
    skip={"admission/candidate-binding.json","admission/candidate-tuple.json","admission/context.json","admission/recipe.json","admission/source-inputs.json","producer/capture-plan.json","producer/integration-bindings.json"}
    staged={}; total=0
    for row in rows:
        rel=safe_rel(row.get("path")); rels=rel.as_posix()
        if rels in skip: continue
        src=donor/rel; h,n=digest(src)
        if h!=hs(row.get("sha256")) or n!=int(row.get("bytes",-1)): raise RuntimeError(f"donor row drift: {rels}")
        copy_file(src,package/rel); staged["package/"+rels]={"sha256":h,"bytes":n}; total+=n
    # Explicit v5 overlay files must exist; no fallback/aliasing if helper absent.
    for name in OVERLAY_NAMES:
        src=overlay/name
        if not src.is_file(): raise RuntimeError(f"required diagnostic overlay missing: {name}")
        h,n=copy_file(src,package/"overlay"/"root-v5"/name); staged["package/overlay/root-v5/"+name]={"sha256":h,"bytes":n}; total+=n
    role_specs=[
      ("binding",A["binding"],"package/admission/candidate-binding.json",MAX_JSON),
      ("tuple",A["tuple"],"package/admission/candidate-tuple.json",MAX_JSON),
      ("context",A["context"],"package/admission/context.json",MAX_JSON),
      ("case",A["case"],"package/admission/case.json",MAX_JSON),
      ("manifest",A["manifest"],"package/admission/manifest.json",MAX_JSON),
      ("recipe",A["recipe"],"package/admission/recipe.json",MAX_JSON),
      ("capturePlan",A["capture_plan"],"package/producer/capture-plan.json",MAX_JSON),
      ("serializer",A["serializer"],"package/producer/serializer-control.json",MAX_JSON),
      ("integrationBindings",A["integration_bindings"],"package/producer/integration-bindings.json",MAX_JSON),
      ("buildPreflight",A["build_preflight"],"package/overlay/root-v5/capture-build-preflight.ps1",MAX_FILE),
      ("uiaWorker",A["uia_worker"],"package/producer/dependencies/uia-worker/invoke-worker-mta.ps1",MAX_FILE),
    ]
    role_target={}; role_path={}
    for name,src,rel,lim in role_specs:
        h,n=copy_file(src,out/rel,lim); staged[rel]={"sha256":h,"bytes":n}; total+=n
        role_path[name]=out/rel; role_target[name]=win(A["installed_root"],rel)
    # Map source-local & donor Windows paths to installed namespace. External
    # measured plan/receipt/EXE/renderer remain outside packet by design.
    path_map={}
    for name,src,rel,lim in role_specs:
        path_map[str(src)]=role_target[name]; path_map[str(src.resolve())]=role_target[name]
    path_map.update({str(A["final_plan"]):args.external_plan_target,str(A["final_plan"].resolve()):args.external_plan_target,
                     str(A["final_receipt"]):args.external_receipt_target,str(A["final_receipt"].resolve()):args.external_receipt_target,
                     str(A["exe"]):args.external_exe_target,str(A["exe"].resolve()):args.external_exe_target,
                     str(A["renderer"]):args.external_renderer_target,str(A["renderer"].resolve()):args.external_renderer_target})
    # Also map exact donor path values found in fresh docs by typed basename only.
    fresh_docs=[load(p) for p in (A["binding"],A["tuple"],A["context"],A["capture_plan"],A["integration_bindings"])]
    old_paths=set(); [collect_path_values(d,old_paths) for d in fresh_docs]
    for old in old_paths:
        low=old.replace("\\","/").lower()
        for name,_,rel,_ in role_specs:
            if low.endswith("/"+Path(rel).name.lower()) or low.endswith("/"+Path(rel).as_posix().lower()): path_map.setdefault(old,role_target[name])
    path_map.update({str(A["final_plan"]):args.external_plan_target,str(A["final_receipt"]):args.external_receipt_target})
    # Rewrite fresh typed JSON in output, then reseal its refs using final target
    # paths. Canonical content hashes (case/recipe) remain content identities.
    for name in ("binding","tuple","context","capturePlan","integrationBindings"):
        p=role_path[name]; doc=rewrite_paths(load(p),path_map); write_json(p,doc)
    local_targets={}
    for name,p in role_path.items():
        h,n=digest(p,MAX_JSON if p.suffix==".json" else MAX_FILE); local_targets[role_target[name]]=(h,n)
    external_targets={args.external_plan_target:(plan_h,plan_n),args.external_receipt_target:(receipt_h,receipt_n),args.external_exe_target:(exe_h,exe_n),args.external_renderer_target:(renderer_h,renderer_n)}
    for name in ("binding","tuple","context","capturePlan","integrationBindings"):
        p=role_path[name]; write_json(p,refresh_refs(load(p),local_targets,external_targets))
    # Fresh SI is emitted as transport + installed package document. Its refs
    # always use installed/external Windows paths, never Mac output paths.
    def final_ref(name):
        p=role_path[name]; h,n=digest(p,MAX_JSON if p.suffix==".json" else MAX_FILE); return {"path":role_target[name],"sha256":"sha256:"+h,"bytes":n}
    si={"kind":"factory-circle-source-inputs-diagnostic-v5","count":1,"candidate":candidate,"tupleID":tuple_id,"caseID":case_id,
        "sourceHash":final_plan.get("sourceHash",manifest.get("sourceHash")),"runtimeSourceCommit":runtime,
        "planHash":plan_h,"compileReceiptHash":receipt_h,"tupleHash":digest(role_path["tuple"],MAX_JSON)[0],"bindingHash":digest(role_path["binding"],MAX_JSON)[0],
        "contextHash":digest(role_path["context"],MAX_JSON)[0],"caseHash":pref(manifest.get("case",{}).get("hash",case.get("hash"))),
        "recipeHash":pref(manifest.get("recipe",{}).get("hash",recipe.get("hash"))),"manifestHash":"sha256:"+manifest_h,
        "exeHash":exe_h,"rendererSha256":renderer_h,"rendererPath":args.external_renderer_target,"compiledHostPackagePath":args.external_plan_target.rsplit("\\",1)[0],
        "planRef":{"path":args.external_plan_target,"sha256":"sha256:"+plan_h,"bytes":plan_n},"receiptRef":{"path":args.external_receipt_target,"sha256":"sha256:"+receipt_h,"bytes":receipt_n},
        "compileRef":{"path":args.external_receipt_target,"sha256":"sha256:"+receipt_h,"bytes":receipt_n},"exeRef":{"path":args.external_exe_target,"sha256":"sha256:"+exe_h,"bytes":exe_n},"rendererRef":{"path":args.external_renderer_target,"sha256":"sha256:"+renderer_h,"bytes":renderer_n},
        "tupleRef":final_ref("tuple"),"bindingRef":final_ref("binding"),"contextRef":final_ref("context"),"caseRef":final_ref("case"),"manifestRef":final_ref("manifest"),"recipeRef":final_ref("recipe"),
        "capturePlanRef":final_ref("capturePlan"),"capturePlanPath":role_target["capturePlan"],"serializerRef":final_ref("serializer"),"serializerPath":role_target["serializer"],
        "integrationBindingsRef":final_ref("integrationBindings"),"buildPreflightRef":final_ref("buildPreflight"),"buildPreflightPath":role_target["buildPreflight"],
        "uiaWorkerPath":role_target["uiaWorker"],"uiaWorkerHash":digest(role_path["uiaWorker"])[0],"serializerControlSha256":digest(role_path["serializer"])[0],"buildPreflightHash":digest(role_path["buildPreflight"])[0],"capturePlanHash":digest(role_path["capturePlan"],MAX_JSON)[0],
        "diagnosticQualification":"diagnostic-native-only-not-qualified","sourceInputsTarget":args.source_inputs_target,"nativeActions":0,"compilerActions":0,"lockActions":0}
    si_local=out/"transport/source-inputs-v5.json"; write_json(si_local,si)
    si_pkg=out/"package/admission/source-inputs.json"; copy_file(si_local,si_pkg,MAX_JSON); staged["package/admission/source-inputs.json"]={"sha256":digest(si_pkg,MAX_JSON)[0],"bytes":digest(si_pkg,MAX_JSON)[1]}; total+=digest(si_pkg,MAX_JSON)[1]
    # Refresh staged role rows after rewrites.
    for rel in list(staged):
        p=out/rel; h,n=digest(p,MAX_FILE if p.suffix not in (".json",) else MAX_JSON); staged[rel]={"sha256":h,"bytes":n}
    if len(staged)>MAX_FILES or total>MAX_TOTAL: raise RuntimeError("packet bounds exceeded")
    graph={"kind":"factory-circle-incremental-diagnostic-source-graph-v5","candidate":candidate,"count":1,"diagnosticQualification":"diagnostic-native-only-not-qualified","plan":{"path":"external:"+args.external_plan_target,"sha256":"sha256:"+plan_h,"bytes":plan_n},"receipt":{"path":"external:"+args.external_receipt_target,"sha256":"sha256:"+receipt_h,"bytes":receipt_n},"exeRef":{"path":args.external_exe_target,"sha256":"sha256:"+exe_h,"bytes":exe_n},"rendererRef":{"path":args.external_renderer_target,"sha256":"sha256:"+renderer_h,"bytes":renderer_n},"runtimeSourceCommit":runtime,"sourceInputs":{"path":args.source_inputs_target,"sha256":"sha256:"+digest(si_pkg,MAX_JSON)[0],"bytes":digest(si_pkg,MAX_JSON)[1]},"cleanupV3":{"sha256":CLEANUP_SHA,"roles":2},"files":[{"path":k,"sha256":"sha256:"+v["sha256"],"bytes":v["bytes"]} for k,v in sorted(staged.items())],"nativeActions":0,"compilerActions":0,"lockActions":0}
    graph_p=out/"source-graph-v5.json"; gh,gn=write_json(graph_p,graph)
    stage={"kind":"factory-circle-incremental-diagnostic-stage-v5","status":"SOURCE_ONLY","stageRoot":args.installed_root,"candidate":candidate,"incrementalPlanKind":final_plan["kind"],"incrementalReceiptKind":final_receipt["kind"],"plan":graph["plan"],"receipt":graph["receipt"],"sourceGraph":{"path":"source-graph-v5.json","sha256":"sha256:"+gh,"bytes":gn},"files":graph["files"],"limits":{"maxFiles":MAX_FILES,"maxFileBytes":MAX_FILE,"maxTotalBytes":MAX_TOTAL,"maxJsonBytes":MAX_JSON},"nativeActions":0,"compilerActions":0,"lockActions":0}
    stage_p=Path(args.stage_manifest_path); sh,sn=write_json(stage_p,stage)
    payload=[(out/k,k) for k in staged]+[(graph_p,"source-graph-v5.json"),(stage_p,"stage-manifest-v5.json")]
    inv=[]; total_zip=0
    for p,rel in payload:
        h,n=digest(p); inv.append({"path":rel,"sha256":h,"bytes":n}); total_zip+=n
    if len(inv)>MAX_FILES or total_zip>MAX_TOTAL: raise RuntimeError("ZIP bounds exceeded")
    invp=out/"zip-inventory-v5.json"; ih,inb=write_json(invp,{"kind":"factory-circle-incremental-diagnostic-zip-inventory-v5","files":inv,"fileCount":len(inv),"payloadBytes":total_zip,"nativeActions":0,"compilerActions":0,"lockActions":0}); payload.append((invp,"zip-inventory-v5.json"))
    zp=Path(args.zip_path)
    if zp.exists(): raise RuntimeError("fresh ZIP required")
    zp.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(zp,"x",compression=zipfile.ZIP_DEFLATED) as z:
        for p,rel in payload: z.write(p,rel)
    zh,zn=digest(zp,MAX_TOTAL)
    template=overlay/"install-circle-diagnostic-root-v4.ps1"
    installer=Path(args.installer_path)
    if installer.exists(): raise RuntimeError("fresh installer required")
    old_stage=r"D:\Claude\swiftright\factory\native\windows\.work\circle-close-r11-r4"
    new_stage=str(args.installed_root).replace("/","\\")
    text=template.read_text(encoding="utf-8").replace("factory-circle-incremental-diagnostic-stage-v4","factory-circle-incremental-diagnostic-stage-v5").replace("source-graph-v4.json","source-graph-v5.json").replace(old_stage,new_stage).replace("build-circle-diagnostic-root-v4.ps1","build-circle-diagnostic-root-v5.ps1")
    installer.parent.mkdir(parents=True,exist_ok=True); installer.write_text(text,encoding="utf-8")
    inst_h,inst_n=digest(installer)
    print(json.dumps({"status":"SOURCE_ONLY_STAGED","kind":graph["kind"],"files":len(staged),"planSha256":plan_h,"receiptSha256":receipt_h,"exeSha256":exe_h,"rendererSha256":renderer_h,"cleanupV3Sha256":CLEANUP_SHA,"graphSha256":gh,"stageManifestSha256":sh,"zipSha256":zh,"zipBytes":zn,"installerSha256":inst_h,"installerBytes":inst_n,"nativeActions":0,"compilerActions":0,"lockActions":0},sort_keys=True))

if __name__=="__main__": main()
