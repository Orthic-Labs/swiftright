#!/usr/bin/env python3
"""Reseal explicit incremental Circle graph after cleanup-v2 substitution.

Only named JSON rows are rewritten. No recursive discovery, compiler, native,
remote, lock, or historical-source mutation is performed.
"""
from __future__ import annotations
import argparse, hashlib, json, stat
from pathlib import Path
BUF=1024*1024; MAX_JSON=4*1024*1024; MAX_FILE=64*1024*1024
CLEANUP="cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13"
JSON_TARGETS=("package/producer/integration-bindings.json","package/producer/dependencies/uia-worker/worker-contract.json","package/producer/capture-plan.json","package/overlay/root-v3/admission/source-inputs.json")

def regular(p,limit=MAX_FILE):
    st=p.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode) or st.st_size>limit: raise RuntimeError(f"unsafe/big: {p}")
    return st

def digest(p,limit=MAX_FILE):
    st=regular(p,limit); h=hashlib.sha256(); n=0
    with p.open("rb") as f:
        while (b:=f.read(BUF)):
            n+=len(b)
            if n>limit: raise RuntimeError(f"grew beyond bound: {p}")
            h.update(b)
    if p.lstat().st_size!=n: raise RuntimeError(f"changed during read: {p}")
    return h.hexdigest(),n

def load(p):
    digest(p,MAX_JSON); return json.loads(p.read_text(encoding="utf-8-sig"))

def normalize(value):
    s=str(value).lower(); return s[7:] if s.startswith("sha256:") else s

def patch_rows(value):
    changed=0
    if isinstance(value,dict):
        path=value.get("path")
        if isinstance(path,str) and path.replace("\\","/").lower() in ("support/cleanup.ps1","dependencies/uia-worker/support/cleanup.ps1","producer/support/cleanup.ps1","producer/dependencies/uia-worker/support/cleanup.ps1"):
            if "sha256" in value: value["sha256"]=CLEANUP
            if "hash" in value: value["hash"]=CLEANUP
            # bytes are filled by caller from measured staged helper bytes.
            changed+=1
        for child in value.values(): changed+=patch_rows(child)
    elif isinstance(value,list):
        for child in value: changed+=patch_rows(child)
    return changed

def write_json(p,obj):
    text=json.dumps(obj,indent=2,ensure_ascii=False)+"\n"
    p.write_text(text,encoding="utf-8")
    digest(p,MAX_JSON)

def assert_ref(doc, field, root):
    ref=doc.get(field)
    if not isinstance(ref,dict) or not isinstance(ref.get("path"),str):
        raise RuntimeError(f"missing explicit ref: {field}")
    p=Path(ref["path"])
    if not p.is_absolute(): p=root/p
    got,n=digest(p,MAX_FILE)
    if normalize(ref.get("sha256"))!=got or int(ref.get("bytes",-1))!=n:
        raise RuntimeError(f"ref drift: {field}")
    return p,got,n

def assert_input_graph(root, si):
    for name in ("planRef","receiptRef","tupleRef","bindingRef","contextRef","recipeRef","manifestRef","rendererRef","exeRef","serializerRef","integrationBindingsRef","buildPreflightRef"):
        assert_ref(si,name,root)
    serializer_path,serializer_hash,_=assert_ref(si,"serializerRef",root)
    if normalize(si.get("serializerControlSha256"))!=serializer_hash:
        raise RuntimeError("serializer control hash is not bound to serializerRef")
    preflight_path,preflight_hash,_=assert_ref(si,"buildPreflightRef",root)
    if normalize(si.get("buildPreflightHash"))!=preflight_hash:
        raise RuntimeError("build preflight hash is not bound to buildPreflightRef")
    capture_path,capture_hash,_=assert_ref(si,"capturePlanRef",root)
    if normalize(si.get("capturePlanHash"))!=capture_hash:
        raise RuntimeError("capture plan hash is not bound to capturePlanRef")
    plan_path,plan_hash,_=assert_ref(si,"planRef",root)
    receipt_path,receipt_hash,_=assert_ref(si,"receiptRef",root)
    tuple_path,tuple_hash,_=assert_ref(si,"tupleRef",root)
    if normalize(si.get("planHash"))!=plan_hash or normalize(si.get("compileReceiptHash"))!=receipt_hash or normalize(si.get("tupleHash"))!=tuple_hash:
        raise RuntimeError("source input primary hash drift")
    plan=load(plan_path); receipt=load(receipt_path); tup=load(tuple_path)
    if str(plan.get("candidate"))!=str(si.get("candidate")) or str(tup.get("id"))!=str(si.get("tupleID")):
        raise RuntimeError("source input candidate/tuple identity drift")
    if normalize(plan.get("expectedHostHash"))!=normalize(si.get("exeHash")) or normalize(receipt.get("exeSha256"))!=normalize(si.get("exeHash")):
        raise RuntimeError("source input executable join drift")
    if normalize(plan.get("rendererSha256"))!=normalize(si.get("rendererSha256")):
        raise RuntimeError("source input renderer join drift")
    return {"serializer":str(serializer_path),"preflight":str(preflight_path),"capturePlan":str(capture_path)}

def main():
    ap=argparse.ArgumentParser();ap.add_argument("--source-root",required=True);ap.add_argument("--cleanup-v2",required=True);ap.add_argument("--renderer-cleanup-v2",required=True);a=ap.parse_args()
    root=Path(a.source_root);cleanup=Path(a.cleanup_v2);renderer=Path(a.renderer_cleanup_v2)
    if not root.is_dir(): raise RuntimeError("source root missing")
    ch,cb=digest(cleanup);rh,rb=digest(renderer)
    if ch!=CLEANUP or rh!=CLEANUP or cb!=rb: raise RuntimeError("cleanup-v2 seal/role mismatch")
    graph_path=root/"source-graph-v3.json";graph=load(graph_path)
    if graph.get("kind")!="factory-circle-incremental-diagnostic-source-graph-v3": raise RuntimeError("graph kind mismatch")
    si_path=root/"package/overlay/root-v3/admission/source-inputs.json"
    if not si_path.is_file(): raise RuntimeError("source-inputs missing before reseal")
    si=load(si_path);assert_input_graph(root,si)
    changed=[]
    for rel in JSON_TARGETS:
        p=root/rel
        if not p.is_file():
            # donor layouts may keep producer rows under package; absent targets are a hard hold.
            raise RuntimeError(f"required reseal target missing: {rel}")
        doc=load(p); n=patch_rows(doc)
        if rel.endswith("capture-plan.json") or rel.endswith("source-inputs.json"):
            doc["cleanupV2"]={"renderer":{"path":"producer/support/cleanup.ps1","sha256":CLEANUP,"bytes":rb},"uia":{"path":"producer/dependencies/uia-worker/support/cleanup.ps1","sha256":CLEANUP,"bytes":cb}}
            n=1
        elif n==0:
            raise RuntimeError(f"no cleanup rows in explicit target: {rel}")
        # Add explicit role refs without hiding original rows.
        if rel.endswith("integration-bindings.json"):
            doc.setdefault("diagnosticCleanupV2",{})["renderer"]={"path":"support/cleanup.ps1","sha256":CLEANUP,"bytes":rb}
            doc.setdefault("diagnosticCleanupV2",{})["uia"]={"path":"dependencies/uia-worker/support/cleanup.ps1","sha256":CLEANUP,"bytes":cb}
        write_json(p,doc); actual,size=digest(p,MAX_JSON);changed.append({"path":rel,"bytes":size,"sha256":actual,"rows":n})
    graph["resealedCleanupV2"]={"renderer":{"path":"package/producer/support/cleanup.ps1","sha256":CLEANUP,"bytes":rb},"uia":{"path":"package/producer/dependencies/uia-worker/support/cleanup.ps1","sha256":CLEANUP,"bytes":cb}}
    graph["resealedJson"] = changed
    for row in graph.get("files",[]):
        for item in changed:
            if row.get("path")==item["path"]: row.update({"sha256":item["sha256"],"bytes":item["bytes"]})
    write_json(graph_path,graph)
    print(json.dumps({"status":"SOURCE_ONLY_RESEALED","kind":graph["kind"],"cleanupV2Sha256":CLEANUP,"roles":2,"targets":changed,"nativeActions":0,"compilerActions":0,"lockActions":0},sort_keys=True))

if __name__=="__main__":main()
