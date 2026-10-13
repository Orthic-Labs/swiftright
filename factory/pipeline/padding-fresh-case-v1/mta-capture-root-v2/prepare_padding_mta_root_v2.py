#!/usr/bin/env python3
"""Prepare fresh Padding Count1 MTA source packet; never executes staged code.

Measured fresh-plan identity is supplied by completed Windows compile evidence; control-plan fixtures are refused."""
from __future__ import annotations
import argparse, hashlib, json, os, re, shutil, stat, zipfile
import difflib
from pathlib import Path
from typing import Any

MAX_FILE=8*1024*1024; MAX_TOTAL=32*1024*1024; MAX_FILES=256
HEX64=re.compile(r'^[0-9a-f]{64}$')
class Hold(RuntimeError): pass
def fail(s:str)->None: raise Hold(s)

HERE=Path(__file__).resolve().parent
_CLEANUP_REL=Path('factory/pipeline/pilot-next-source-v1/text-count20-r10-kernel-stage-v2/cleanup-kernel-authority-v3.ps1')
def resolve_repo_anchor(candidate:Path)->Path:
    """Accept only exact repo containing measured cleanup source; reject ancestors."""
    try: root=Path(candidate).resolve(strict=True)
    except OSError as e: fail(f'repository anchor missing: {candidate}: {e}')
    if root.name != 'swiftright': fail(f'repository anchor name mismatch: {root}')
    marker=root/_CLEANUP_REL
    try: st=marker.lstat()
    except OSError as e: fail(f'measured cleanup missing under repository anchor: {marker}: {e}')
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode): fail(f'unsafe measured cleanup anchor: {marker}')
    return root

REPO=resolve_repo_anchor(HERE.parents[3])
TEXT_DEFAULT=REPO/'factory/native/windows/pilot-text-paint-root-v2/capture-count1-r12-root-v7-sources'
DONOR_SNAPSHOT_DEFAULT=HERE/'donor-source-snapshot-v1.json'
CLEANUP=REPO/_CLEANUP_REL
MEASURED_FRESH_PLAN_SHA='214e73d4239604be7580add966c86fd387fa7985fef79ee307de81846a8b2433'
MEASURED_FRESH_PLAN_PATH=r'D:\Claude\swiftright\.factory-work\root-tools\padding-incremental-v4-r2\plan.json'
MEASURED_EXE_SHA='3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a'
APPROVED_ROOT_V3_CLEANUP_SHA='cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13'
APPROVED_RENDERER_FINAL_EXIT_SHA='94db73dadfaa998fe63eefc5e7ce416310fe9072cd2fd09689f2f923f81538b4'
APPROVED_WORKER_FINAL_EXIT_SHA='78b9edaf1b72c389f3c026a6c1e1606505568803bfe3ad67ae1e66416809475d'
APPROVED_WORKER_STREAM_SEAL_SHA='4e68ceab6611e6b919489f1f98f147594453257584c301cc65dacb80ca69c48d'

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
    def no_duplicates(pairs):
        out={}
        for k,v in pairs:
            if k in out: raise ValueError(f'duplicate JSON key: {k}')
            out[k]=v
        return out
    try: return json.loads(read(p,2*1024*1024).decode('utf-8-sig'), object_pairs_hook=no_duplicates)
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

def windows_join(root:str, rel:str)->str:
    """Build typed Windows stage paths; refs must never point at local Mac paths."""
    if not isinstance(root,str) or not re.fullmatch(r'(?i)(?:[a-z]:\\|\\\\)[^<>:"|?*]+',root):
        fail('Windows stage root must be absolute')
    if not isinstance(rel,str) or not rel or rel.startswith(('/', '\\')) or any(x in ('','.','..') for x in Path(rel.replace('\\','/')).parts):
        fail(f'unsafe staged reference: {rel}')
    return root.rstrip('\\/')+'\\'+rel.replace('/','\\')

def typed_ref(local:Path, staged:str, expected_sha:str|None=None, limit:int=MAX_FILE):
    h,n=digest(local,limit)
    if expected_sha is not None and h != expected_sha.lower().removeprefix('sha256:'):
        fail(f'typed reference hash drift: {local}')
    return {'path':staged,'sha256':'sha256:'+h,'bytes':n}

def source_rows(root:Path,snapshot_path:Path):
    m=jload(root/'source-manifest.json'); rows=m.get('files')
    if not isinstance(rows,list) or not rows or len(rows)>MAX_FILES:fail('donor source manifest rows')
    manifest_sha,_=digest(root/'source-manifest.json',2*1024*1024)
    snap=jload(snapshot_path)
    if snap.get('kind')!='factory-padding-donor-source-snapshot-v1' or snap.get('status')!='CURRENT_REVIEWED_SOURCE_SNAPSHOT' or snap.get('historicalManifestSha256')!=manifest_sha: fail('donor snapshot/historical manifest join')
    snap_rows=snap.get('rows');
    if not isinstance(snap_rows,list) or len(snap_rows)!=len(rows): fail('donor snapshot row count')
    old_by={r.get('path'):r for r in rows}; snap_by={r.get('path'):r for r in snap_rows}
    if set(old_by)!=set(snap_by): fail('donor snapshot row set')
    mismatch_by={r.get('path'):r for r in snap.get('mismatches',[]) if isinstance(r,dict)}
    if len(mismatch_by)!=len(snap.get('mismatches',[])): fail('donor snapshot duplicate/invalid mismatch rows')
    for rel,review in mismatch_by.items():
        if rel not in old_by or not isinstance(review.get('diff'),str) or not review['diff']: fail(f'donor snapshot review diff missing: {rel}')
        if review.get('diffSha256') != hashlib.sha256(review['diff'].encode()).hexdigest(): fail(f'donor snapshot review diff hash: {rel}')
    changed_paths=set()
    for rel,old in old_by.items():
        changed=(old.get('bytes')!=snap_by[rel].get('bytes') or str(old.get('sha256','')).lower()!=str(snap_by[rel].get('sha256','')).lower())
        if changed: changed_paths.add(rel)
        if changed and (rel not in mismatch_by or not mismatch_by[rel].get('reason') or not mismatch_by[rel].get('diffSha256')): fail(f'donor snapshot mismatch review missing: {rel}')
        if not changed and rel in mismatch_by: fail(f'donor snapshot false mismatch: {rel}')
    if set(mismatch_by)!=changed_paths: fail('donor snapshot mismatch set drift')
    total=0; out=[]
    for r in rows:
        rel=r.get('path') if isinstance(r,dict) else None
        if not isinstance(rel,str):fail('donor row path')
        safe(rel); p=root/rel; got,n=digest(p); total+=n
        if total>MAX_TOTAL:fail('donor source total bound')
        sr=snap_by[rel]
        if sr.get('bytes')!=n or str(sr.get('sha256','')).lower()!=got: fail(f'donor snapshot/current drift: {rel}')
        out.append((Path(rel),got,n))
    return out,snap

def transform_text(p:Path):
    try:t=read(p).decode('utf-8')
    except UnicodeDecodeError:return
    # Exact stale type only; caller supplies production lifecycle paths.
    t2=t.replace('FactoryProcessWaitV5','FactoryProcessWaitV6')
    if t2!=t:
        # New packet output may be rewritten via temp; source donor remains immutable.
        tmp=p.with_name(p.name+'.rewrite')
        write_new(tmp,t2.encode()); os.replace(tmp,p)

def main()->int:
    ap=argparse.ArgumentParser()
    ap.add_argument('--padding-source-root',type=Path,required=True)
    ap.add_argument('--donor-snapshot',type=Path,default=DONOR_SNAPSHOT_DEFAULT)
    ap.add_argument('--text-mta-donor-root',type=Path,default=TEXT_DEFAULT)
    ap.add_argument('--case',type=Path,required=True); ap.add_argument('--manifest',type=Path,required=True)
    ap.add_argument('--tuple',dest='tuple_path',type=Path,required=True); ap.add_argument('--plan',type=Path,required=True)
    ap.add_argument('--fresh-plan-sha256',default=MEASURED_FRESH_PLAN_SHA)
    ap.add_argument('--receipt',type=Path,required=True); ap.add_argument('--source-witness',type=Path,required=True)
    ap.add_argument('--recipe',type=Path,required=True)
    ap.add_argument('--preflight',type=Path,required=True)
    ap.add_argument('--serializer-control',type=Path,required=True)
    ap.add_argument('--renderer',type=Path,required=True)
    ap.add_argument('--windows-stage-root',required=True)
    ap.add_argument('--output-root',type=Path,required=True); ap.add_argument('--output-zip',type=Path,required=True)
    ap.add_argument('--namespace',required=True)
    ap.add_argument('--installer',type=Path,required=True)
    a=ap.parse_args(); donor=a.padding_source_root.resolve(); text=a.text_mta_donor_root.resolve(); out=a.output_root.resolve()
    expected_plan_sha=str(a.fresh_plan_sha256).lower().removeprefix('sha256:')
    if not HEX64.fullmatch(expected_plan_sha) or expected_plan_sha != MEASURED_FRESH_PLAN_SHA: fail('fresh plan SHA must equal measured completed-compile pin')
    if not donor.is_dir() or not text.is_dir():fail('Padding source root or measured Text MTA donor missing')
    if not a.donor_snapshot.is_file():fail('explicit donor source snapshot missing')
    for p in (a.case,a.manifest,a.tuple_path,a.plan,a.receipt,a.recipe,a.serializer_control): reg(p.resolve(),2*1024*1024)
    for p in (a.source_witness,a.preflight): reg(p.resolve(),MAX_FILE)
    reg(a.renderer.resolve(),32*1024*1024)
    for p in (out,a.output_zip.resolve(),a.installer.resolve()):
        if p.exists() or p.is_symlink():fail(f'fresh output collision: {p}')
    case=jload(a.case.resolve()); manifest=jload(a.manifest.resolve()); tup=jload(a.tuple_path.resolve()); plan=jload(a.plan.resolve()); receipt=jload(a.receipt.resolve())
    case_hash=canonical_case(manifest); case_id=case.get('id')
    if not isinstance(case_id,str):fail('case id')
    if manifest.get('case',{}).get('id')!=case_id or manifest.get('case',{}).get('hash')!=case_hash:fail('manifest canonical case identity drift')
    if manifest.get('sourceHash')!='sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b':fail('source witness hash drift')
    witness_sha,_=digest(a.source_witness.resolve())
    if witness_sha != manifest.get('sourceHash','').removeprefix('sha256:'): fail('witness/source hash drift')
    if plan.get('kind')!='windows-padding-fresh-compile-plan-v1' or plan.get('case',{}).get('id')!=case_id or plan.get('case',{}).get('hash')!=case_hash:fail('fresh plan identity drift')
    if plan.get('sourceHash')!=manifest.get('sourceHash'):fail('fresh plan source drift')
    if plan.get('compileRequest',{}).get('maxParallelJobs') != 1: fail('fresh plan maxParallelJobs must be 1')
    if plan.get('compileRequest',{}).get('maxFrontendThreadsObserved') not in (None,): fail('fresh plan frontend observation must remain null')
    if plan.get('memoryBudget',{}).get('bytes') != 1073741824 or plan.get('memoryBudget',{}).get('jobLimitFlags') != 512 or plan.get('memoryBudget',{}).get('killOnJobClose') is not False: fail('fresh plan memory policy drift')
    if receipt.get('kind')!='factory-padding-incremental-owned-compile-v4' or receipt.get('exitCode')!=0 or receipt.get('ownedExited') is not True or receipt.get('kernelWait')!=0 or receipt.get('jobActiveCount')!=0 or receipt.get('streamsSealed') is not True or receipt.get('streamDrainComplete') is not True:fail('fresh compile receipt not successful')
    if receipt.get('freshPlanSha256','').lower().removeprefix('sha256:') != expected_plan_sha: fail('receipt/fresh plan measured hash drift')
    if receipt.get('freshPlanPath') != MEASURED_FRESH_PLAN_PATH: fail('receipt/fresh plan path is not measured Windows compile path')
    for k,v in (('memoryCapBytes',1073741824),('jobFlags',512),('maxParallelJobs',1),('nativeActions',0)):
        if k in receipt and receipt.get(k) != v: fail(f'fresh compile receipt {k} drift')
    ph,_=digest(a.plan.resolve()); rh,_=digest(a.receipt.resolve())
    if ph != expected_plan_sha: fail('supplied plan is not measured fresh compile plan; control-plan fixture refused')
    fresh_plan_hash='sha256:'+ph
    recipe_h,recipe_bytes=digest(a.recipe.resolve(),2*1024*1024)
    preflight_h,preflight_bytes=digest(a.preflight.resolve())
    serializer_h,serializer_bytes=digest(a.serializer_control.resolve())
    # Measured renderer is ~11.9 MiB; verify exact bytes without copying it.
    renderer_h,renderer_bytes=digest(a.renderer.resolve(),32*1024*1024)
    expected_renderer=str(plan.get('rendererSha256','')).lower().removeprefix('sha256:')
    if not HEX64.fullmatch(expected_renderer) or renderer_h != expected_renderer: fail('measured renderer bytes/hash drift')
    renderer_path=str(plan.get('rendererPath',''))
    if not renderer_path: fail('measured renderer path missing')
    recipe_doc=jload(a.recipe.resolve())
    recipe_expected=str(manifest.get('recipeHash') or manifest.get('recipe',{}).get('hash',''))
    if recipe_expected and recipe_doc.get('hash') != recipe_expected: fail('measured recipe canonical identity drift')
    windows_stage_root=str(a.windows_stage_root)
    windows_join(windows_stage_root,'fresh-inputs/case.json')
    wh=plan.get('expectedHostHashes',{}).get('windows'); ex=receipt.get('exeSha256')
    if not isinstance(wh,str) or not isinstance(ex,str) or wh.replace('sha256:','').lower()!=ex.lower():fail('fresh executable hash drift')
    if ex.lower().removeprefix('sha256:') != MEASURED_EXE_SHA: fail('fresh executable is not measured Padding host')
    tdoc=tup.get('tuple',tup)
    if tdoc.get('id')!='sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011':fail('tuple id drift')
    if tdoc.get('hostHashes',{}).get('windows','').replace('sha256:','').lower()!=ex.lower():fail('tuple/windows host drift')
    # These roles are measured in Text v7 stage-manifest; bind by exact path
    # & hash before copying, rather than assuming a Padding overlay filename.
    text_manifest=jload(text/'stage-manifest.json'); text_rows={str(r.get('path')):r for r in text_manifest.get('files',[]) if isinstance(r,dict)}
    mta_required=(
      'overlay/final-exit-certificate-mta-v1.ps1','overlay/test-mta-config-admission.ps1',
      'overlay/test-uia-mta-controls.ps1','overlay/test-factory-process-wait-v7.ps1',
      'overlay/test-mta-stage-closure-v7.ps1','overlay/uia-worker-invoke-v2.ps1',
      'producer/dependencies/uia-worker/worker.ps1','producer/dependencies/uia-worker/invoke-worker-mta.ps1',
      'producer/dependencies/uia-worker/read-uia.ps1','producer/dependencies/uia-worker/schema.ps1',
      'producer/dependencies/uia-worker/worker-contract.json',
      'producer/dependencies/uia-worker/support/final-exit-certificate.ps1',
      'producer/dependencies/uia-worker/support/stream-seal.ps1',
      'producer/dependencies/uia-worker/support/cleanup.ps1')
    for rel in mta_required:
        p=text/rel; row=text_rows.get(rel)
        if not p.is_file() or not isinstance(row,dict): fail(f'MTA lifecycle source missing from measured Text stage: {rel}')
        h,n=digest(p)
        if row.get('bytes') != n or str(row.get('sha256','')).lower() != h: fail(f'MTA lifecycle source drift: {rel}')
    expected_mta_helpers={
      'producer/support/final-exit-certificate.ps1':APPROVED_RENDERER_FINAL_EXIT_SHA,
      'producer/dependencies/uia-worker/support/final-exit-certificate.ps1':APPROVED_WORKER_FINAL_EXIT_SHA,
      'producer/dependencies/uia-worker/support/stream-seal.ps1':APPROVED_WORKER_STREAM_SEAL_SHA,
    }
    for rel, expected in expected_mta_helpers.items():
        if str(text_rows[rel].get('sha256','')).lower() != expected: fail(f'approved MTA helper drift: {rel}')
    cleanup_h,cleanup_n=digest(CLEANUP)
    if cleanup_h != APPROVED_ROOT_V3_CLEANUP_SHA: fail('approved root-v3 cleanup helper drift')
    control_plan=a.plan.resolve()
    if control_plan.as_posix().lower().endswith('/root-controls-r1/plan-incremental-v4.json'):
        fail(f'measured fresh plan required from {MEASURED_FRESH_PLAN_PATH}; root-controls-r1 control fixture is refused')
    rows,donor_snapshot=source_rows(donor,a.donor_snapshot.resolve()); stage=out; stage.mkdir(parents=True)
    for rel,_,_ in rows: copy_new(donor/rel,stage/rel)
    # Measured Text v7 MTA lifecycle controls & worker closure are additive.
    overlay=stage/'overlay'; worker=stage/'producer/dependencies/uia-worker'; support=stage/'producer/support'
    overlay.mkdir(parents=True,exist_ok=True); worker.mkdir(parents=True,exist_ok=True); (worker/'support').mkdir(parents=True,exist_ok=True)
    overlay_names=('final-exit-certificate-mta-v1.ps1','test-mta-config-admission.ps1','test-uia-mta-controls.ps1','test-factory-process-wait-v7.ps1','test-mta-stage-closure-v7.ps1','uia-worker-invoke-v2.ps1')
    # Overlay rows may already exist in the Padding donor. Replace only inside
    # fresh stage so donor stays immutable & staged bytes remain exact Text rows.
    for name in overlay_names:
        src=text/'overlay'/name; dst=overlay/name
        if dst.exists(): replace_fresh(src,dst)
        else: copy_new(src,dst)
    worker_names=('worker.ps1','invoke-worker-mta.ps1','read-uia.ps1','schema.ps1','worker-contract.json')
    for name in worker_names: replace_fresh(text/'producer/dependencies/uia-worker'/name,worker/name)
    for name in ('final-exit-certificate.ps1','stream-seal.ps1'): replace_fresh(text/'producer/dependencies/uia-worker/support'/name,worker/'support'/name)
    replace_fresh(text/'producer/dependencies/uia-worker/support/cleanup.ps1',worker/'support/cleanup.ps1')
    # Root-v3 cleanup is distinct from renderer final-exit helper.
    replace_fresh(CLEANUP,support/'cleanup.ps1'); copy_new(CLEANUP,worker/'support/cleanup-kernel-authority-v3.ps1')
    # V6 migration is limited to production lifecycle implementations.  Controls
    # retain their original V5 literals so negative fixtures cannot be rewritten.
    production_wait_paths=(
      stage/'capture-padding-count1.ps1',
      stage/'capture-padding-repeat.ps1',
      stage/'producer/support/cleanup.ps1',
      stage/'producer/dependencies/uia-worker/invoke-worker.ps1',
      stage/'producer/dependencies/uia-worker/invoke-worker-mta.ps1',
      stage/'producer/dependencies/uia-worker/support/cleanup.ps1',
    )
    for p in production_wait_paths:
        if p.is_file(): transform_text(p)
    binding_paths=['support/cleanup.ps1','support/final-exit-certificate.ps1','overlay/final-exit-certificate-mta-v1.ps1','overlay/test-factory-process-wait-v7.ps1','overlay/test-mta-stage-closure-v7.ps1','overlay/uia-worker-invoke-v2.ps1','dependencies/uia-worker/worker.ps1','dependencies/uia-worker/invoke-worker-mta.ps1','dependencies/uia-worker/read-uia.ps1','dependencies/uia-worker/schema.ps1','dependencies/uia-worker/support/stream-seal.ps1','dependencies/uia-worker/worker-contract.json','dependencies/uia-worker/support/cleanup.ps1','dependencies/uia-worker/support/final-exit-certificate.ps1']
    bindings=[]
    for rel in binding_paths:
        p=stage/rel if rel.startswith('overlay/') else stage/'producer'/rel
        h,n=digest(p); bindings.append({'path':rel,'bytes':n,'sha256':h})
    # Padding integration guard requires complete closure (>=23 rows). Add
    # every current staged source once, preserving relative paths & hashes;
    # integration manifest itself is excluded to avoid circular sealing.
    bound={r['path'] for r in bindings}
    for p in sorted(stage.rglob('*')):
        if not p.is_file() or p == stage/'producer/integration-bindings.json': continue
        rel=p.relative_to(stage).as_posix()
        if rel in bound: continue
        h,n=digest(p); bindings.append({'path':rel,'bytes':n,'sha256':h}); bound.add(rel)
    dump_new(stage/'producer/integration-bindings.json',{'kind':'factory-padding-mta-integration-bindings-v2','files':bindings,'nativeActions':0,'compilerActions':0,'lockActions':0})
    # Fresh measured graph documents, with raw byte refs retained separately from canonical IDs.
    fresh=stage/'fresh-inputs'; fresh.mkdir()
    for src,name in ((a.case,'case.json'),(a.manifest,'manifest.json'),(a.tuple_path,'tuple.json'),(a.recipe,'recipe.json'),(a.serializer_control,'serializer-control.json'),(a.plan,'fresh-compile-plan.json'),(a.receipt,'compile-receipt.json'),(a.source_witness,'Witness.swift')): copy_new(src.resolve(),fresh/name)
    copy_new(a.preflight.resolve(),stage/'producer/preflight.ps1')
    copy_new(a.donor_snapshot.resolve(),fresh/'donor-source-snapshot.json')
    phash,pbytes=digest(fresh/'fresh-compile-plan.json'); rsha,rbytes=digest(fresh/'compile-receipt.json'); csha,cbytes=digest(fresh/'case.json'); msha,mbytes=digest(fresh/'manifest.json'); tsha,tbytes=digest(fresh/'tuple.json'); wsha,wbytes=digest(fresh/'Witness.swift'); recipe_h,recipe_bytes=digest(fresh/'recipe.json'); serializer_h,serializer_bytes=digest(fresh/'serializer-control.json'); preflight_h,preflight_bytes=digest(stage/'producer/preflight.ps1')
    def packet_ref(rel: str, path: Path):
        h,n=digest(path); return {'path':rel,'sha256':'sha256:'+h,'bytes':n}
    # Full source-bound graph consumed by Padding admission guards.
    stage_win=lambda rel: windows_join(windows_stage_root,rel)
    host_hashes=tdoc.get('hostHashes',{}) if isinstance(tdoc.get('hostHashes',{}),dict) else {}
    context={
      'kind':'factory-padding-source-context-v1','caseID':case_id,'caseHash':case_hash,
      'tupleID':tdoc['id'],'sourceHash':manifest['sourceHash'],
      'macosHostHash':host_hashes.get('macos'),'windowsHostHash':host_hashes.get('windows'),
      'runtimeSourceCommit':plan.get('runtimeSourceCommit'),
      'rendererSha256':'sha256:'+renderer_h,
      'tupleContext':{'tupleID':tdoc['id'],'macosHostHash':host_hashes.get('macos'),'windowsHostHash':host_hashes.get('windows'),'runtimeCommit':plan.get('runtimeSourceCommit'),'rendererHash':'sha256:'+renderer_h},
      'nativeActions':0,'compilerActions':0,'lockActions':0,
    }
    dump_new(stage/'fresh-inputs/context.json',context)
    context_h,context_bytes=digest(stage/'fresh-inputs/context.json')
    fresh_refs={
      'case':typed_ref(stage/'fresh-inputs/case.json',stage_win('fresh-inputs/case.json')),
      'manifest':typed_ref(stage/'fresh-inputs/manifest.json',stage_win('fresh-inputs/manifest.json')),
      'tuple':typed_ref(stage/'fresh-inputs/tuple.json',stage_win('fresh-inputs/tuple.json')),
      'plan':typed_ref(stage/'fresh-inputs/fresh-compile-plan.json',stage_win('fresh-inputs/fresh-compile-plan.json')),
      'compile':typed_ref(stage/'fresh-inputs/compile-receipt.json',stage_win('fresh-inputs/compile-receipt.json')),
      'recipe':typed_ref(stage/'fresh-inputs/recipe.json',stage_win('fresh-inputs/recipe.json')),
      'serializer':typed_ref(stage/'fresh-inputs/serializer-control.json',stage_win('fresh-inputs/serializer-control.json')),
      'source':typed_ref(stage/'fresh-inputs/Witness.swift',stage_win('fresh-inputs/Witness.swift')),
      'context':typed_ref(stage/'fresh-inputs/context.json',stage_win('fresh-inputs/context.json')),
    }
    binding={
      'kind':'factory-source-bound-candidate-binding-v1','case':manifest['case'],'caseID':case_id,'caseHash':case_hash,
      'tupleID':tdoc['id'],'candidateID':tup.get('candidateID'),'sourceHash':manifest['sourceHash'],
      'planHash':'sha256:'+phash,'compileReceiptHash':'sha256:'+rh,'recipeHash':'sha256:'+recipe_h,
      'sourceFileHash':'sha256:'+wsha,'runtimeSourceCommit':plan.get('runtimeSourceCommit'),
      'rendererSha256':renderer_h,'exeSha256':ex.lower().removeprefix('sha256:'),
      'macHostHash':host_hashes.get('macos'),'windowsHostHash':host_hashes.get('windows'),
      'tupleContext':context['tupleContext'],'canonicalTupleRef':fresh_refs['tuple'],'frozenTupleBound':False,
      'nativeActions':0,'lockActions':0,
    }
    dump_new(stage/'metadata/source-binding.json',binding)
    binding_h,binding_bytes=digest(stage/'metadata/source-binding.json')
    canonical={'kind':'factory-padding-source-inputs-v2','status':'fresh-source-bound-staged','case':manifest['case'],'tupleID':tdoc['id'],'files':fresh_refs,'sourceBindingHash':'sha256:'+binding_h,'nativeActions':0,'lockActions':0}
    dump_new(stage/'metadata/canonical-inputs-manifest.json',canonical)
    canonical_h,canonical_bytes=digest(stage/'metadata/canonical-inputs-manifest.json')
    mta_manifest_sha,mta_manifest_bytes=digest(text/'stage-manifest.json')
    cap={'kind':'factory-padding-fresh-count1-mta-capture-plan-v2','count':1,'case':{'id':case_id,'hash':case_hash},'tuple':{'id':tdoc['id'],'hash':'sha256:'+tsha},'sourceHash':manifest['sourceHash'],'freshPlanRef':{'path':'fresh-inputs/fresh-compile-plan.json','sha256':'sha256:'+phash,'bytes':pbytes},'compileReceiptRef':{'path':'fresh-inputs/compile-receipt.json','sha256':'sha256:'+rsha,'bytes':rbytes},'caseFileRef':{'path':'fresh-inputs/case.json','sha256':'sha256:'+csha,'bytes':cbytes,'canonicalHash':case_hash},'manifestRef':{'path':'fresh-inputs/manifest.json','sha256':'sha256:'+msha,'bytes':mbytes},'tupleRef':{'path':'fresh-inputs/tuple.json','sha256':'sha256:'+tsha,'bytes':tbytes},'witnessRef':{'path':'fresh-inputs/Witness.swift','sha256':'sha256:'+wsha,'bytes':wbytes},'mtaLifecycle':{'source':str(text),'donorStageManifest':{'path':'stage-manifest.json','sha256':'sha256:'+mta_manifest_sha,'bytes':mta_manifest_bytes},'rendererFinalExit':packet_ref('producer/support/final-exit-certificate.ps1',support/'final-exit-certificate.ps1'),'workerFinalExit':packet_ref('producer/dependencies/uia-worker/support/final-exit-certificate.ps1',worker/'support/final-exit-certificate.ps1'),'rootCleanupV3':packet_ref('producer/support/cleanup.ps1',support/'cleanup.ps1'),'workerCleanupV3':packet_ref('producer/dependencies/uia-worker/support/cleanup-kernel-authority-v3.ps1',worker/'support/cleanup-kernel-authority-v3.ps1'),'processWaitControl':packet_ref('overlay/test-factory-process-wait-v7.ps1',overlay/'test-factory-process-wait-v7.ps1'),'stageClosureControl':packet_ref('overlay/test-mta-stage-closure-v7.ps1',overlay/'test-mta-stage-closure-v7.ps1'),'waitVersion':'FactoryProcessWaitV6','rendererCloseSeconds':15,'streamDrainSeconds':5},'memoryBudget':{'bytes':1073741824,'jobLimitFlags':512,'killOnJobClose':False},'timing':{'rendererCloseSeconds':15,'streamDrainSeconds':5},'nativeActions':0,'compilerActions':0,'lockActions':0,'qualification':'held-observational-only'}
    cap.update({'sourcePlanSha256':'sha256:'+phash,'compiledPlanSha256':'sha256:'+phash,
      'compilePlanPath':str(MEASURED_FRESH_PLAN_PATH),'compileReceiptPath':stage_win('fresh-inputs/compile-receipt.json'),
      'compilePlanHash':'sha256:'+phash,'compileReceiptHash':'sha256:'+rh,
      'launchPreflightPath':stage_win('producer/preflight.ps1'),'launchPreflightSha256':'sha256:'+preflight_h,
      'captureRoot':stage_win('producer'),'rendererPath':renderer_path,'rendererSha256':'sha256:'+renderer_h,
      'serializerControl':{'path':stage_win('fresh-inputs/serializer-control.json'),'sha256':'sha256:'+serializer_h,'bytes':serializer_bytes},
      'sourceBindingHash':'sha256:'+binding_h,'canonicalInputsHash':'sha256:'+canonical_h,
      'freshInputRefs':fresh_refs,'runtimeSourceCommit':plan.get('runtimeSourceCommit')})
    dump_new(stage/'producer/capture-plan.json',cap)
    ibh,ibb=digest(stage/'producer/integration-bindings.json')
    # Seal producer closure before admission source-inputs references it.
    root_manifest=stage/'producer/root-stage-manifest.json'
    root_rows=[]
    for p in sorted((stage/'producer').rglob('*')):
        if p.is_file() and p != root_manifest:
            h,n=digest(p); root_rows.append({'path':'producer/'+p.relative_to(stage/'producer').as_posix(),'sha256':'sha256:'+h,'bytes':n})
    dump_new(root_manifest,{'kind':'factory-padding-source-producer-manifest-v1','status':'fresh-source-bound-staged','files':root_rows,'nativeActions':0,'compilerActions':0,'lockActions':0})
    root_h,root_bytes=digest(root_manifest)
    exe_path=str(receipt.get('exePath',''))
    exe_bytes=int(receipt.get('exeBytes',0))
    if not exe_path or exe_bytes<=0: fail('measured executable path/bytes missing')
    exe_ref={'path':exe_path,'sha256':'sha256:'+ex.lower().removeprefix('sha256:'),'bytes':exe_bytes}
    renderer_ref={'path':renderer_path,'sha256':'sha256:'+renderer_h,'bytes':renderer_bytes}
    integration_ref={'path':stage_win('producer/integration-bindings.json'),'sha256':'sha256:'+ibh,'bytes':ibb}
    helper_ref={'path':stage_win('producer/root-stage-manifest.json'),'sha256':'sha256:'+root_h,'bytes':root_bytes}
    binding_ref={'path':stage_win('metadata/source-binding.json'),'sha256':'sha256:'+binding_h,'bytes':binding_bytes}
    canonical_ref={'path':stage_win('metadata/canonical-inputs-manifest.json'),'sha256':'sha256:'+canonical_h,'bytes':canonical_bytes}
    context_ref=fresh_refs['context']
    source_ref={
      'path':stage_win('admission/source-inputs.json'),
      'sha256':'pending','bytes':0,
    }
    si={
      # v3 is existing production discriminator; retain it while emitting full
      # v4 graph fields so frozen Padding guards continue accepting source kind.
      'kind':'factory-padding-source-inputs-v3','status':'fresh-source-bound-prelaunch','count':1,
      'caseID':case_id,'caseHash':case_hash,'sourceHash':manifest['sourceHash'],'tupleID':tdoc['id'],
      'candidateID':tup.get('candidateID'),'windowsHostHash':host_hashes.get('windows'),
      'runtimeSourceCommit':plan.get('runtimeSourceCommit'),'compiledHostPackagePath':str(receipt.get('operationalPackage','')),
      'rendererPath':renderer_path,'rendererSha256':renderer_h,'serializerControlSha256':serializer_h,
      'exeHash':ex.lower().removeprefix('sha256:'),'planHash':phash,'compileReceiptHash':rh,
      'caseRef':fresh_refs['case'],'manifestRef':fresh_refs['manifest'],'tupleRef':fresh_refs['tuple'],
      'planRef':fresh_refs['plan'],'compileRef':fresh_refs['compile'],'exeRef':exe_ref,'rendererRef':renderer_ref,
      'serializerRef':fresh_refs['serializer'],'bindingRef':binding_ref,'recipeRef':fresh_refs['recipe'],
      'sourceRef':fresh_refs['source'],'tupleHash':tsha,'candidateTupleHash':tsha,
      'bindingHash':binding_h,'recipeHash':recipe_h,'contextRef':context_ref,
      'integrationBindingsRef':integration_ref,'integrationBindingsHash':ibh,
      'helperManifestPath':helper_ref['path'],'helperManifestHash':root_h,'helperManifestRef':helper_ref,
      'capturePlanPath':stage_win('producer/capture-plan.json'),'capturePlanHash':'pending',
      'buildPreflightPath':stage_win('producer/preflight.ps1'),'buildPreflightHash':preflight_h,
      'compilePlanPath':str(MEASURED_FRESH_PLAN_PATH),'compileReceiptPath':stage_win('fresh-inputs/compile-receipt.json'),
      'operationalPackagePath':str(receipt.get('operationalPackage','')),'operationalExePath':exe_path,
      'refs':{'case':fresh_refs['case'],'manifest':fresh_refs['manifest'],'tuple':fresh_refs['tuple'],'plan':fresh_refs['plan'],'compile':fresh_refs['compile'],'exe':exe_ref,'renderer':renderer_ref,'serializer':fresh_refs['serializer'],'binding':binding_ref,'recipe':fresh_refs['recipe'],'source':fresh_refs['source'],'context':context_ref,'integration':integration_ref,'helperManifest':helper_ref},
      'freshIDsRequired':True,'historicalCaseReuse':False,'nativeActions':0,'compilerActions':0,'lockActions':0,
    }
    cap_hash, cap_bytes = digest(stage/'producer/capture-plan.json')
    si['capturePlanHash']=cap_hash; si['capturePlanRef']={'path':stage_win('producer/capture-plan.json'),'sha256':'sha256:'+cap_hash,'bytes':cap_bytes}
    dump_new(stage/'admission/source-inputs.json',si); sd, sb=digest(stage/'admission/source-inputs.json')
    # Fresh source manifest is sealed after all transformations; no native effect.
    files=[]; total=0
    for p in sorted(stage.rglob('*')):
        if p.is_file() and p.name not in ('stage-manifest.json','source-manifest.json'):
            rel=p.relative_to(stage).as_posix(); safe(rel); h,n=digest(p); total+=n; files.append({'path':rel,'bytes':n,'sha256':h})
    if len(files)>MAX_FILES or total>MAX_TOTAL:fail('fresh packet bounds')
    dump_new(stage/'stage-manifest.json',{'kind':'factory-padding-count1-mta-stage-v2','files':files,'limits':{'maxFiles':MAX_FILES,'maxFileBytes':MAX_FILE,'maxTotalBytes':MAX_TOTAL},'mtaWorker':'producer/dependencies/uia-worker/invoke-worker-mta.ps1','rendererFinalExit':'producer/support/final-exit-certificate.ps1','workerFinalExit':'producer/dependencies/uia-worker/support/final-exit-certificate.ps1','cleanupV3':'producer/support/cleanup.ps1','nativeActions':0})
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
