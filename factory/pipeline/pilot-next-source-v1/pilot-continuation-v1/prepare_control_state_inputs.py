#!/usr/bin/env python3
"""Prepare source-bound Toggle/disabled host input & adapter plans.
No compiler, capture, provider, or native action is performed."""
from __future__ import annotations
import argparse, hashlib, json, os, stat
from pathlib import Path

MAX_SOURCE = 64 * 1024 * 1024
MAX_JSON = 2 * 1024 * 1024
CHUNK = 1024 * 1024
EXPECTED = {
    "toggle": {"block":"swiftui.toggle", "witness":"Witness_toggle", "candidate":"factory.probes.smoke.swiftui.toggle", "recipe":"swiftui.toggle.recipe", "caseInputs":{"initial":False,"style":"automatic"}},
    "disabled": {"block":"swiftui.disabled", "witness":"Witness_disabled", "candidate":"factory.probes.smoke.swiftui.disabled", "recipe":"swiftui.disabled.recipe", "caseInputs":{"disabled":True,"color-scheme":"light"}},
}

def fail(msg): raise SystemExit("control-state-inputs: " + msg)
def regular(p, limit):
    st=p.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode): fail(f"regular non-symlink required: {p}")
    if st.st_size > limit: fail(f"size bound exceeded: {p}")
    return st.st_size

def read_bytes(p, limit):
    before=regular(p,limit); h=hashlib.sha256(); parts=[]; total=0
    with p.open('rb') as f:
        while True:
            b=f.read(CHUNK)
            if not b: break
            total += len(b)
            if total > limit: fail(f"growth bound exceeded: {p}")
            h.update(b); parts.append(b)
    after=regular(p,limit)
    if before != after or total != before: fail(f"source changed while reading: {p}")
    return b''.join(parts), h.hexdigest()

def read_json(p):
    raw,sha=read_bytes(p,MAX_JSON)
    try: value=json.loads(raw.decode('utf-8-sig'))
    except Exception as e: fail(f"invalid JSON {p}: {e}")
    if not isinstance(value,dict): fail(f"JSON object required: {p}")
    return value,raw,sha

def canonical(v): return json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
def write_new(p,raw):
    if p.exists() or p.is_symlink(): fail(f"refusing overwrite: {p}")
    p.parent.mkdir(parents=True,exist_ok=True); p.write_bytes(raw)

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--block',choices=sorted(EXPECTED),required=True)
    ap.add_argument('--source',type=Path,required=True)
    ap.add_argument('--manifest',type=Path,required=True)
    ap.add_argument('--recipe',type=Path,required=True)
    ap.add_argument('--output',type=Path,required=True)
    args=ap.parse_args(); exp=EXPECTED[args.block]
    if args.output.exists(): fail(f"output exists: {args.output}")
    source,source_sha=read_bytes(args.source,MAX_SOURCE)
    manifest,_,_=read_json(args.manifest); recipe,_,recipe_sha=read_json(args.recipe)
    if manifest.get('block') != exp['block'] or manifest.get('candidate') != exp['candidate'] or manifest.get('witnessType') != exp['witness']:
        fail('manifest block/candidate/witness mismatch')
    if manifest.get('caseInputs') != exp['caseInputs'] or manifest.get('executionEligible') is not False:
        fail('manifest inputs must equal held generated candidate')
    if manifest.get('sourceHash') != 'sha256:'+source_sha: fail('manifest source hash mismatch')
    if manifest.get('recipe',{}).get('id') != exp['recipe'] or manifest.get('recipe',{}).get('hash') != 'sha256:'+hashlib.sha256(canonical(recipe)).hexdigest():
        fail('recipe canonical hash/id mismatch')
    if recipe.get('id') != exp['recipe']: fail('recipe id mismatch')
    refs={
      'source': {'path':str(args.source), 'bytes':len(source), 'sha256':'sha256:'+source_sha},
      'manifest': {'path':str(args.manifest), 'bytes':args.manifest.stat().st_size, 'sha256':'sha256:'+read_json(args.manifest)[2]},
      'recipe': {'path':str(args.recipe), 'bytes':args.recipe.stat().st_size, 'sha256':'sha256:'+recipe_sha},
    }
    adapters={
      'mac': {'status':'source-adapter-contract-only','planBuilder':'factory/pipeline/pilot-next-source-v1/pilot-generic-capture-v1/text/prepare-plan.py','captureProtocol':'factory/pipeline/pilot-next-source-v1/mac-capture-same-group-v1/capture_origin_rectangle_r1.py','requiresFreshHostReceipt':True,'nativeActions':0},
      'windows': {'status':'source-adapter-contract-only','planBuilder':'factory/pipeline/pilot-next-source-v1/pilot-generic-capture-v1/text/prepare-plan.py','captureProtocol':'factory/pipeline/pilot-next-source-v1/pilot-generic-capture-v1/text/capture-single.ps1','requiresMtaWorkerClosure':True,'requiresFreshHostReceipt':True,'nativeActions':0},
    }
    host={'schema':'control-state-host-inputs-v1','status':'source-prepared-held','qualification':'held','block':exp['block'],'candidate':exp['candidate'],'witnessType':exp['witness'],'caseInputs':exp['caseInputs'],'source':refs,'runtime':{'commit':'37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b','rendererAbi':'0.6','rendererHash':'sha256:e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'},'adapters':adapters,'freshness':{'count1BeforeCount20':True,'captureIds':None,'tuple':None,'compileReceipt':None,'macHost':None,'windowsHost':None},'executionEligible':False,'effects':{'compilerActions':0,'nativeActions':0,'remoteActions':0,'guiActions':0,'lockActions':0}}
    write_new(args.output/'host-inputs.json',canonical(host))
    plan={'schema':'control-state-adapter-plan-v1','status':'source-contract-only','qualification':'held','block':exp['block'],'sourceInputs':'host-inputs.json','requiredJoins':['source','manifest','recipe','case','tuple','compilerReceipt','runtimeSourceTree','renderer','macHost','windowsHost','serializer','integrationBindings'],'forbidden':['historical-ID reuse','source-only eligibility','synthetic provider evidence','renderer ABI change'],'countOrder':[1,20],'adapters':adapters,'apiAvailability':{'toggle':['SwiftUI.Toggle','Binding<Bool>','labelsHidden','toggleStyle(.automatic)'],'disabled':['View.disabled(Bool)','Button','.colorScheme','.light']},'nativeActions':0}
    write_new(args.output/'adapter-plan.json',canonical(plan))
    print(json.dumps({'status':'source-prepared-held','block':exp['block'],'hostInputsSha256':'sha256:'+hashlib.sha256(canonical(host)).hexdigest(),'adapterPlanSha256':'sha256:'+hashlib.sha256(canonical(plan)).hexdigest()}))
if __name__=='__main__': main()
