#!/usr/bin/env python3
"""Prepare fresh Padding Count1 MTA source packet; never executes staged code."""
from __future__ import annotations
import argparse, hashlib, json, os, re, shutil, stat, zipfile
from pathlib import Path
from typing import Any

MAX_FILE=8*1024*1024; MAX_TOTAL=32*1024*1024; MAX_FILES=256
HEX64=re.compile(r'^[0-9a-f]{64}$')
HERE=Path(__file__).resolve().parent; REPO=HERE.parents[4]
TEXT=REPO/'factory/native/windows/pilot-text-paint-root-v2/capture-count1-r12-root-v7-sources'
CLEANUP=REPO/'factory/pipeline/pilot-next-source-v1/text-count20-r10-kernel-stage-v2/cleanup-kernel-authority-v3.ps1'

class Hold(RuntimeError): pass
def fail(s:str)->None: raise Hold(s)
def reg(p:Path, limit=MAX_FILE):
    try: st=p.lstat()
    except OSError as e: fail(f'stat failed: {p}: {e}')
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode): fail(f'unsafe input: {p}')
    if st.st_size>limit: fail(f'file exceeds bound: {p}')
    return st
def digest(p:Path, limit=MAX_FILE):
    st=reg(p,limit); h=hashlib.sha256(); n=0
    with p.open('rb') as f:
        while True:
            b=f.read(1024*1024)
            if not b: break
            n+=len(b)
            if n>limit: fail(f'file grew beyond bound: {p}')
            h.update(b)
    if n!=st.st_size: fail(f'file changed during hash: {p}')
    return h.hexdigest(),n
def read(p:Path,limit=MAX_FILE):
    st=reg(p,limit)
    with p.open('rb') as f: b=f.read(limit+1)
    if len(b)!=st.st_size: fail(f'file changed during read: {p}')
    return b
def jload(p:Path):
    try: return json.loads(read(p,2*1024*1024).decode('utf-8-sig'))
    except Exception as e: fail(f'bad JSON {p}: {e}')
def safe(raw:str)->Path:
    p=Path(raw)
    if not raw or p.is_absolute() or '\\' in raw or any(x in ('','.','..') for x in p.parts): fail(f'unsafe relative path: {raw}')
    return p
def write_new(p:Path,b:bytes):
    if p.exists() or p.is_symlink(): fail(f'fresh output collision: {p}')
    p.parent.mkdir(parents=True,exist_ok=True)
    with p.open('xb') as f:f.write(b)
def dump_new(p:Path,o:Any): write_new(p,(json.dumps(o,indent=2,ensure_ascii=False)+'\n').encode())
def copy_new(src:Path,dst:Path):
    st=reg(src); dst.parent.mkdir(parents=True,exist_ok=True)
    if dst.exists() or dst.is_symlink(): fail(f'fresh output collision: {dst}')
    n=0
    with src.open('rb') as a,dst.open('xb') as b:
        while True:
            x=a.read(1024*1024)
            if not x:break
            n+=len(x)
            if n>MAX_FILE:fail(f'copy bound: {src}')
            b.write(x)
    if n!=st.st_size:fail(f'copy changed: {src}')
def replace_fresh(src:Path,dst:Path):
    """Replace only inside new stage; donor remains immutable."""
    reg(src); dst.parent.mkdir(parents=True,exist_ok=True)
    tmp=dst.with_name(dst.name+'.mta-rewrite')
    if tmp.exists() or tmp.is_symlink(): fail(f'rewrite collision: {tmp}')
    copy_new(src,tmp); os.replace(tmp,dst)
def canonical_case(manifest:dict[str,Any])->str:
    # Canonical hash is supplied by fresh manifest; raw case JSON hash is separate.
    ident=manifest.get('case',{}).get('hash')
    if not isinstance(ident,str) or not ident.startswith('sha256:') or not HEX64.fullmatch(ident[7:]): fail('canonical case hash missing')
    return ident

def source_rows(root:Path):
    m=jload(root/'source-manifest.json'); rows=m.get('files')
    if not isinstance(rows,list) or not rows or len(rows)>MAX_FILES:fail('donor source manifest rows')
    total=0; out=[]; seen=set()
    for r in rows:
        rel=r.get('path') if isinstance(r,dict) else None
        if not isinstance(rel,str) or rel in seen:fail('donor row path')
        safe(rel); seen.add(rel); p=root/rel; got,n=digest(p); total+=n
        if total>MAX_TOTAL:fail('donor source total bound')
        if r.get('bytes')!=n or str(r.get('sha256','')).lower()!=got:fail(f'donor row drift: {rel}')
        out.append((Path(rel),got,n))
    return out

def transform_text(p:Path):
    try:t=read(p).decode('utf-8')
    except UnicodeDecodeError:return
    # Exact stale type only; no global namespace/path substitution.
    t2=t.replace('FactoryProcessWaitV5','FactoryProcessWaitV6')
    if t2!=t:
        # New packet output may be rewritten via temp; source donor remains immutable.
        tmp=p.with_name(p.name+'.rewrite')
        write_new(tmp,t2.encode()); os.replace(tmp,p)

def main()->int:
    ap=argparse.ArgumentParser()
    ap.add_argument('--padding-source-root',type=Path,required=True)
    ap.add_argument('--case',type=Path,required=True); ap.add_argument('--manifest',type=Path,required=True)
    ap.add_argument('--tuple',dest='tuple_path',type=Path,required=True); ap.add_argument('--plan',type=Path,required=True)
    ap.add_argument('--receipt',type=Path,required=True); ap.add_argument('--source-witness',type=Path,required=True)
    ap.add_argument('--output-root',type=Path,required=True); ap.add_argument('--output-zip',type=Path,required=True)
    ap.add_argument('--namespace',required=True)
    ap.add_argument('--installer',type=Path,required=True)
    a=ap.parse_args(); donor=a.padding_source_root.resolve(); out=a.output_root.resolve()
    if not donor.is_dir():fail('Padding source root missing')
    for p in (a.case,a.manifest,a.tuple_path,a.plan,a.receipt,a.source_witness): reg(p.resolve(),2*1024*1024 if p.suffix.lower()=='.json' else MAX_FILE)
    for p in (out,a.output_zip.resolve(),a.installer.resolve()):
        if p.exists() or p.is_symlink():fail(f'fresh output collision: {p}')
    case=jload(a.case.resolve()); manifest=jload(a.manifest.resolve()); tup=jload(a.tuple_path.resolve()); plan=jload(a.plan.resolve()); receipt=jload(a.receipt.resolve())
    case_hash=canonical_case(manifest); case_id=case.get('id')
    if not isinstance(case_id,str):fail('case id')
    if manifest.get('case',{}).get('id')!=case_id or manifest.get('case',{}).get('hash')!=case_hash:fail('manifest canonical case identity drift')
    if manifest.get('sourceHash')!='sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b':fail('source witness hash drift')
    if plan.get('kind')!='windows-padding-fresh-compile-plan-v1' or plan.get('case',{}).get('id')!=case_id or plan.get('case',{}).get('hash')!=case_hash:fail('fresh plan identity drift')
    if plan.get('sourceHash')!=manifest.get('sourceHash'):fail('fresh plan source drift')
    if receipt.get('kind')!='factory-padding-incremental-owned-compile-v4' or receipt.get('exitCode')!=0 or receipt.get('ownedExited') is not True or receipt.get('kernelWait')!=0 or receipt.get('jobActiveCount')!=0 or receipt.get('streamsSealed') is not True or receipt.get('streamDrainComplete') is not True:fail('fresh compile receipt not successful')
    ph,_=digest(a.plan.resolve()); rh,_=digest(a.receipt.resolve())
    fresh_plan_hash='sha256:'+ph
    if str(receipt.get('freshPlanSha256','')).replace('sha256:','')!=ph:fail('receipt/fresh plan hash drift')
    wh=plan.get('expectedHostHashes',{}).get('windows'); ex=receipt.get('exeSha256')
    if not isinstance(wh,str) or not isinstance(ex,str) or wh.replace('sha256:','').lower()!=ex.lower():fail('fresh executable hash drift')
    tdoc=tup.get('tuple',tup)
    if tdoc.get('id')!='sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011':fail('tuple id drift')
    if tdoc.get('hostHashes',{}).get('windows','').replace('sha256:','').lower()!=ex.lower():fail('tuple/windows host drift')
    rows=source_rows(donor); stage=out; stage.mkdir(parents=True)
    for rel,_,_ in rows: copy_new(donor/rel,stage/rel)
    # Measured Text v7 MTA lifecycle controls & worker closure are additive.
    overlay=stage/'overlay'; worker=stage/'producer/dependencies/uia-worker'; support=stage/'producer/support'
    overlay.mkdir(parents=True,exist_ok=True); worker.mkdir(parents=True,exist_ok=True); (worker/'support').mkdir(parents=True,exist_ok=True)
    overlay_names=('final-exit-certificate-mta-v1.ps1','test-mta-config-admission.ps1','test-uia-mta-controls.ps1','test-factory-process-wait-v7.ps1','test-mta-stage-closure-v7.ps1','uia-worker-invoke-v2.ps1')
    for name in overlay_names: copy_new(TEXT/'overlay'/name,overlay/name)
    worker_names=('worker.ps1','invoke-worker-mta.ps1','read-uia.ps1','schema.ps1','stream-seal.ps1','worker-contract.json')
    for name in worker_names: replace_fresh(TEXT/'producer/dependencies/uia-worker'/name,worker/name)
    for name in ('final-exit-certificate.ps1','stream-seal.ps1'): replace_fresh(TEXT/'producer/dependencies/uia-worker/support'/name,worker/'support'/name)
    replace_fresh(TEXT/'producer/dependencies/uia-worker/support/cleanup.ps1',worker/'support/cleanup.ps1')
    # Root-v3 cleanup is distinct from renderer final-exit helper.
    replace_fresh(CLEANUP,support/'cleanup.ps1'); copy_new(CLEANUP,worker/'support/cleanup-kernel-authority-v3.ps1')
    for p in list(stage.rglob('*.ps1')): transform_text(p)
    binding_paths=['support/cleanup.ps1','support/final-exit-certificate.ps1','overlay/uia-worker-invoke-v2.ps1','dependencies/uia-worker/worker.ps1','dependencies/uia-worker/invoke-worker-mta.ps1','dependencies/uia-worker/read-uia.ps1','dependencies/uia-worker/schema.ps1','dependencies/uia-worker/stream-seal.ps1','dependencies/uia-worker/worker-contract.json','dependencies/uia-worker/support/cleanup.ps1','dependencies/uia-worker/support/final-exit-certificate.ps1']
    bindings=[]
    for rel in binding_paths:
        p=stage/rel if rel.startswith('overlay/') else stage/'producer'/rel
        h,n=digest(p); bindings.append({'path':rel,'bytes':n,'sha256':h})
    dump_new(stage/'producer/integration-bindings.json',{'kind':'factory-padding-mta-integration-bindings-v1','files':bindings,'nativeActions':0,'compilerActions':0,'lockActions':0})
    # Fresh measured graph documents, with raw byte refs retained separately from canonical IDs.
    fresh=stage/'fresh-inputs'; fresh.mkdir()
    for src,name in ((a.case,'case.json'),(a.manifest,'manifest.json'),(a.tuple_path,'tuple.json'),(a.plan,'plan-incremental-v4.json'),(a.receipt,'compile-receipt.json'),(a.source_witness,'Witness.swift')): copy_new(src.resolve(),fresh/name)
    phash,pbytes=digest(fresh/'plan-incremental-v4.json'); rsha,rbytes=digest(fresh/'compile-receipt.json'); csha,cbytes=digest(fresh/'case.json'); msha,mbytes=digest(fresh/'manifest.json'); tsha,tbytes=digest(fresh/'tuple.json'); wsha,wbytes=digest(fresh/'Witness.swift')
    cap={'kind':'factory-padding-fresh-count1-mta-capture-plan-v1','count':1,'case':{'id':case_id,'hash':case_hash},'tuple':{'id':tdoc['id'],'hash':'sha256:'+tsha},'sourceHash':manifest['sourceHash'],'freshPlanRef':{'path':'fresh-inputs/plan-incremental-v4.json','sha256':'sha256:'+phash,'bytes':pbytes},'compileReceiptRef':{'path':'fresh-inputs/compile-receipt.json','sha256':'sha256:'+rsha,'bytes':rbytes},'caseFileRef':{'path':'fresh-inputs/case.json','sha256':'sha256:'+csha,'bytes':cbytes,'canonicalHash':case_hash},'manifestRef':{'path':'fresh-inputs/manifest.json','sha256':'sha256:'+msha,'bytes':mbytes},'tupleRef':{'path':'fresh-inputs/tuple.json','sha256':'sha256:'+tsha,'bytes':tbytes},'witnessRef':{'path':'fresh-inputs/Witness.swift','sha256':'sha256:'+wsha,'bytes':wbytes},'memoryBudget':{'bytes':1073741824,'jobLimitFlags':512,'killOnJobClose':False},'timing':{'rendererCloseSeconds':15,'streamDrainSeconds':5},'nativeActions':0,'compilerActions':0,'lockActions':0,'qualification':'held-observational-only'}
    dump_new(stage/'producer/capture-plan.json',cap)
    ibh,ibb=digest(stage/'producer/integration-bindings.json')
    si={'kind':'factory-padding-source-inputs-mta-v1','count':1,'caseID':case_id,'caseCanonicalHash':case_hash,'caseFileSha256':csha,'sourceHash':manifest['sourceHash'],'tupleID':tdoc['id'],'tupleFileSha256':tsha,'planSha256':phash,'compileReceiptSha256':rsha,'exeSha256':ex.lower(),'rendererSha256':plan.get('rendererSha256'),'runtimeSourceCommit':plan.get('runtimeSourceCommit'),'canonicalRecipeHash':manifest.get('recipeHash'),'freshInputRoot':'fresh-inputs','integrationBindingsRef':{'path':'producer/integration-bindings.json','sha256':'sha256:'+ibh,'bytes':ibb},'capturePlanRef':{'path':'producer/capture-plan.json','sha256':'pending','bytes':0},'mtaInvokerRef':{'path':'producer/dependencies/uia-worker/invoke-worker-mta.ps1','sha256':digest(worker/'invoke-worker-mta.ps1')[0]},'cleanupRef':{'path':'producer/support/cleanup.ps1','sha256':digest(support/'cleanup.ps1')[0]},'workerCleanupRef':{'path':'producer/dependencies/uia-worker/support/cleanup-kernel-authority-v3.ps1','sha256':digest(worker/'support/cleanup-kernel-authority-v3.ps1)[0]},'nativeActions':0,'compilerActions':0,'lockActions':0,'status':'source-only-pending-root-admission'}
    cap_hash, cap_bytes = digest(stage/'producer/capture-plan.json')
    si['capturePlanRef']={'path':'producer/capture-plan.json','sha256':'sha256:'+cap_hash,'bytes':cap_bytes}
    dump_new(stage/'admission/source-inputs.json',si); sd, sb=digest(stage/'admission/source-inputs.json')
    # Fresh source manifest is sealed after all transformations; no native effect.
    files=[]; total=0
    for p in sorted(stage.rglob('*')):
        if p.is_file() and p.name not in ('stage-manifest.json','source-manifest.json'):
            rel=p.relative_to(stage).as_posix(); safe(rel); h,n=digest(p); total+=n; files.append({'path':rel,'bytes':n,'sha256':h})
    if len(files)>MAX_FILES or total>MAX_TOTAL:fail('fresh packet bounds')
    dump_new(stage/'stage-manifest.json',{'kind':'factory-padding-count1-mta-stage-v1','files':files,'limits':{'maxFiles':MAX_FILES,'maxFileBytes':MAX_FILE,'maxTotalBytes':MAX_TOTAL},'mtaWorker':'producer/dependencies/uia-worker/invoke-worker-mta.ps1','rendererFinalExit':'producer/support/final-exit-certificate.ps1','workerFinalExit':'producer/dependencies/uia-worker/support/final-exit-certificate.ps1','cleanupV3':'producer/support/cleanup.ps1','nativeActions':0})
    a.output_zip.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(a.output_zip,'x',compression=zipfile.ZIP_DEFLATED) as z:
        for p in sorted(stage.rglob('*')):
            if p.is_file(): z.write(p,p.relative_to(stage).as_posix())
    zsha,zbytes=digest(a.output_zip,64*1024*1024)
    installer=("# Source-only Padding MTA installer; no compiler/native/lock actions.\n"
      "param([Parameter(Mandatory=$true)][string]$PackageZip,[Parameter(Mandatory=$true)][string]$StageRoot)\n"
      "$ErrorActionPreference='Stop';$ExpectedZipSha256='"+zsha+"';"
      "if(-not(Test-Path -LiteralPath $PackageZip -PathType Leaf)){throw 'package missing'};"
      "if((Get-FileHash -LiteralPath $PackageZip).Hash.ToLowerInvariant() -cne $ExpectedZipSha256){throw 'package hash drift'};"
      "if(Test-Path -LiteralPath $StageRoot){throw 'fresh stage collision'};"
      "Expand-Archive -LiteralPath $PackageZip -DestinationPath $StageRoot;"
      "$m=Get-Content -Raw -LiteralPath (Join-Path $StageRoot 'stage-manifest.json')|ConvertFrom-Json;"
      "foreach($r in $m.files){$p=Join-Path $StageRoot $r.path;$i=Get-Item -LiteralPath $p -Force;if($i.Length -ne $r.bytes -or (Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -cne $r.sha256){throw ('stage drift '+$r.path)}};"
      "[ordered]@{status='source-package-installed';nativeActions=0;compilerActions=0;lockActions=0;packageSha256=$ExpectedZipSha256;packageBytes="+str(zbytes)+"}|ConvertTo-Json -Depth 8")
    write_new(a.installer.resolve(),installer.encode())
    print(json.dumps({'status':'source-only-ready','caseCanonicalHash':case_hash,'caseFileSha256':csha,'planSha256':phash,'receiptSha256':rsha,'exeSha256':ex.lower(),'sourceInputsSha256':sd,'stageRoot':str(stage),'nativeActions':0},indent=2))
    return 0
if __name__=='__main__':
    try: raise SystemExit(main())
    except Hold as e: raise SystemExit('HOLD: '+str(e))
