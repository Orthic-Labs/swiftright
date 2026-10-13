#!/usr/bin/env python3
"""Bounded Circle incremental Count1 source packer.

Reads only explicitly named donor/measured files, creates one fresh packet, and
never compiles, launches, locks, deletes, or discovers files recursively.
"""
from __future__ import annotations
import argparse, hashlib, json, re, stat, zipfile
from pathlib import Path

BUF=1024*1024; MAX_JSON=4*1024*1024; MAX_FILE=64*1024*1024
MAX_TOTAL=256*1024*1024; MAX_FILES=256

def regular(p:Path, limit:int=MAX_FILE):
    s=p.lstat()
    if not stat.S_ISREG(s.st_mode) or stat.S_ISLNK(s.st_mode): raise RuntimeError(f"unsafe input: {p}")
    if s.st_size>limit: raise RuntimeError(f"input exceeds bound: {p}")
    return s

def digest(p:Path, limit:int=MAX_FILE):
    s=regular(p,limit); h=hashlib.sha256(); n=0
    with p.open('rb') as f:
        while True:
            b=f.read(BUF)
            if not b: break
            n += len(b)
            if n>limit: raise RuntimeError(f"stream bound exceeded: {p}")
            h.update(b)
    if p.lstat().st_size != n: raise RuntimeError(f"input changed: {p}")
    return h.hexdigest(),n

def load(p:Path):
    digest(p,MAX_JSON)
    return json.loads(p.read_text(encoding='utf-8-sig'))

def write_json(p:Path, obj):
    if p.exists(): raise RuntimeError(f"fresh destination collision: {p}")
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(obj,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    return digest(p,MAX_JSON)

def replace_json(p:Path, obj):
    """Atomically replace one explicitly-owned staged JSON file."""
    p.parent.mkdir(parents=True,exist_ok=True)
    if p.is_symlink() or (p.exists() and not p.is_file()):
        raise RuntimeError(f"unsafe JSON replacement target: {p}")
    tmp=p.with_name(p.name+'.v8-rewrite')
    if tmp.exists() or tmp.is_symlink(): raise RuntimeError(f"replacement collision: {tmp}")
    data=(json.dumps(obj,indent=2,ensure_ascii=False)+'\n').encode('utf-8')
    if len(data)>MAX_JSON: raise RuntimeError(f"generated JSON exceeds bound: {p}")
    with tmp.open('xb') as f: f.write(data)
    tmp.replace(p)
    return digest(p,MAX_JSON)

def copy_bounded(src:Path,dst:Path,limit:int=MAX_FILE):
    h,n=digest(src,limit); dst.parent.mkdir(parents=True,exist_ok=True)
    if dst.exists(): raise RuntimeError(f"fresh destination collision: {dst}")
    with src.open('rb') as a,dst.open('xb') as b:
        copied=0
        while True:
            block=a.read(BUF)
            if not block: break
            copied += len(block)
            if copied>limit: raise RuntimeError(f"copy bound exceeded: {src}")
            b.write(block)
    if digest(dst,limit)!=(h,n): raise RuntimeError(f"copy seal mismatch: {src}")
    return h,n

def sha(v):
    x=str(v).lower(); return x[7:] if x.startswith('sha256:') else x

def pref(v):
    x=sha(v)
    if not re.fullmatch(r'[0-9a-f]{64}',x): raise RuntimeError(f"bad SHA-256: {v}")
    return 'sha256:'+x

def win(root,rel): return str(root).rstrip('\\/')+'\\'+str(rel).replace('/','\\')

def safe_rel(v):
    s=str(v).replace('\\','/')
    if not s or s.startswith('/') or re.match(r'^[A-Za-z]:',s): raise RuntimeError(f"unsafe row: {v}")
    parts=s.split('/')
    if any(x in ('','.','..') for x in parts): raise RuntimeError(f"unsafe row: {v}")
    return Path(*parts)

def transform(v, mapping):
    if isinstance(v,dict):
        out={k:transform(x,mapping) for k,x in v.items()}
        if isinstance(out.get('path'),str) and out['path'] in mapping: out['path']=mapping[out['path']]
        return out
    if isinstance(v,list): return [transform(x,mapping) for x in v]
    return v

def refresh(v, refs):
    if isinstance(v,dict):
        out={k:refresh(x,refs) for k,x in v.items()}
        if isinstance(out.get('path'),str) and out['path'] in refs:
            h,n=refs[out['path']]; out['sha256']='sha256:'+h; out['bytes']=n
        return out
    if isinstance(v,list): return [refresh(x,refs) for x in v]
    return v

def main():
    ap=argparse.ArgumentParser()
    for n in ('donor-root','overlay-root','output-root','source-inputs','final-plan','final-receipt','tuple','manifest','recipe','binding','context','capture-plan','serializer','integration-bindings','build-preflight','uia-worker','renderer','exe','cleanup-v2','renderer-cleanup-v2','installed-root','external-plan-target','external-receipt-target','external-exe-target','external-renderer-target','zip-path','installer-path','stage-manifest-path'):
        ap.add_argument('--'+n,required=True)
    args=ap.parse_args(); A={k.replace('-','_'):Path(v) if k not in ('installed_root','external_plan_target','external_receipt_target','external_exe_target','external_renderer_target') else v for k,v in vars(args).items()}
    donor=A['donor_root']; overlay=A['overlay_root']; out=A['output_root']
    if out.exists(): raise RuntimeError(f"fresh output required: {out}")
    if not donor.is_dir() or not overlay.is_dir(): raise RuntimeError('donor/overlay root missing')
    plan=load(A['final_plan']); receipt=load(A['final_receipt']); tup=load(A['tuple']); manifest=load(A['manifest']); recipe=load(A['recipe']); donor_si=load(A['source_inputs'])
    ph,pb=digest(A['final_plan'],MAX_JSON); rh,rb=digest(A['final_receipt'],MAX_JSON); th,tb=digest(A['tuple'],MAX_JSON); mh,mb=digest(A['manifest'],MAX_JSON); qh,qb=digest(A['recipe'],MAX_JSON); eh,eb=digest(A['exe']); xh,xb=digest(A['renderer'])
    cleanup_h,cleanup_b=digest(A['cleanup_v2'],MAX_FILE); renderer_cleanup_h,renderer_cleanup_b=digest(A['renderer_cleanup_v2'],MAX_FILE)
    if cleanup_h != renderer_cleanup_h or cleanup_b != renderer_cleanup_b: raise RuntimeError('renderer/UIA cleanup helper drift')
    if plan.get('kind')!='factory-circle-incremental-compile-plan-v1' or plan.get('phase')!='final': raise RuntimeError('incremental final plan required')
    if receipt.get('kind')!='factory-circle-incremental-owned-compile-v1' or receipt.get('phase')!='final': raise RuntimeError('incremental final receipt required')
    if plan.get('executionEligible') is not True or plan.get('qualification')!='diagnostic-native-only-not-qualified': raise RuntimeError('diagnostic eligibility drift')
    candidate=str(plan.get('candidate',''))
    if not candidate.startswith('swiftui.circle.fixed.pilot-next.close-diagnostic-r1'): raise RuntimeError('Circle diagnostic candidate mismatch')
    if sha(plan.get('expectedHostHash'))!=eh or sha(receipt.get('exeSha256'))!=eh: raise RuntimeError('EXE hash join mismatch')
    if sha(plan.get('rendererSha256'))!=xh or sha(receipt.get('rendererSha256'))!=xh: raise RuntimeError('renderer hash join mismatch')
    if tup.get('id')!=manifest.get('tuple',{}).get('id'): raise RuntimeError('tuple ID join mismatch')
    tuple_id=str(tup.get('id','')); case_obj=manifest.get('case',{}); case_id=str(case_obj.get('id',''))
    if not tuple_id or not case_id: raise RuntimeError('fresh tuple/case missing')
    if str(plan.get('case',{}).get('id'))!=case_id or str(receipt.get('case',{}).get('id'))!=case_id: raise RuntimeError('case ID join mismatch')
    if sha(tup.get('hostHashes',{}).get('windows'))!=eh or sha(tup.get('rendererHash'))!=xh: raise RuntimeError('tuple host join mismatch')
    if str(tup.get('runtimeCommit'))!=str(plan.get('runtimeSourceCommit')): raise RuntimeError('tuple runtime join mismatch')
    if sha(manifest.get('sourceHash'))!=sha(plan.get('sourceHash')) or sha(recipe.get('witness',{}).get('sha256'))!=sha(plan.get('sourceHash')): raise RuntimeError('source join mismatch')
    if sha(plan.get('manifestHash'))!=mh: raise RuntimeError('manifest raw hash mismatch')
    if sha(plan.get('recipe',{}).get('hash'))!=sha(recipe.get('hash')) or sha(plan.get('recipe',{}).get('sha256'))!=qh: raise RuntimeError('recipe hash join mismatch')
    stage=out/'package'; stage.mkdir(parents=True)
    donor_manifest=load(donor/'stage-manifest.json'); rows=donor_manifest.get('files',[])
    if not isinstance(rows,list) or len(rows)>MAX_FILES: raise RuntimeError('donor stage manifest invalid')
    # Donor rows are copied first, then measured roles are copied exactly once.
    # Keep every role that gets replaced out of donor copy set; this prevents
    # serializer/preflight/UIA collisions while preserving unrelated donor rows.
    replace_rows={'admission/candidate-binding.json','admission/candidate-tuple.json','admission/context.json','admission/recipe.json','admission/source-inputs.json','producer/capture-plan.json','producer/serializer-control.json','producer/integration-bindings.json','producer/dependencies/uia-worker/invoke-worker-mta.ps1','overlay/capture-build-preflight.ps1','host-plan.json'}
    staged={}; total=0
    for row in rows:
        rel=safe_rel(row.get('path','')); rels=rel.as_posix()
        if rels in replace_rows: continue
        src=donor/rel; h,n=digest(src)
        if h!=sha(row.get('sha256')) or n!=int(row.get('bytes',-1)): raise RuntimeError(f'donor row drift: {rels}')
        copy_bounded(src,stage/rel); staged['package/'+rels]={'sha256':h,'bytes':n}; total+=n
    # Install v8 guard/issuer/coordinator overlay beside donor files; same-name donor
    # controls remain untouched, so admission selects these explicit paths.
    custom = [
        'diagnostic-profile.ps1','diagnostic-profile-root-v8.ps1',
        'integration-fresh-circle-diagnostic-v8.ps1','final-plan-eligibility-diagnostic-v8.ps1',
        'capture-circle-diagnostic-single-v8.ps1','dispatch-circle-diagnostic-single-v8.ps1',
        'coordinator-count1-diagnostic-v8.ps1','capture-build-preflight-diagnostic-v8.ps1',
        'issue-circle-diagnostic-metadata-v8.ps1','interactive-task-circle-single-v8.ps1',
        'build-circle-diagnostic-root-v8.ps1','test-circle-diagnostic-controls-v8.ps1',
        'test-circle-diagnostic-controls-root-v8.ps1','test-circle-diagnostic-reference-controls-v8.ps1',
        'Sr0OwnedJobProcess-v15.cs'
    ]
    for name in custom:
        src=overlay/name
        if not src.is_file(): raise RuntimeError(f'v8 overlay source missing: {name}')
        h,n=copy_bounded(src,stage/'overlay/root-v8'/name,MAX_FILE)
        staged['package/overlay/root-v8/'+name]={'sha256':h,'bytes':n}; total+=n
    # Fresh plan is JSON evidence; binary/compiler/renderer remain external refs.
    copy_bounded(A['final_plan'],stage/'plan.json',MAX_JSON); hp,hn=digest(stage/'plan.json',MAX_JSON); staged['package/plan.json']={'sha256':hp,'bytes':hn}; total+=hn
    # Explicit measured source roles. Existing donor controls are copied once.
    role_specs=[('case',A['manifest'],'package/admission/case.json',MAX_JSON),('manifest',A['manifest'],'package/admission/manifest.json',MAX_JSON),('binding',A['binding'],'package/admission/candidate-binding.json',MAX_JSON),('tuple',A['tuple'],'package/admission/candidate-tuple.json',MAX_JSON),('context',A['context'],'package/admission/context.json',MAX_JSON),('recipe',A['recipe'],'package/admission/recipe.json',MAX_JSON),('capturePlan',A['capture_plan'],'package/producer/capture-plan.json',MAX_JSON),('serializer',A['serializer'],'package/producer/serializer-control.json',MAX_JSON),('integrationBindings',A['integration_bindings'],'package/producer/integration-bindings.json',MAX_JSON),('buildPreflight',A['build_preflight'],'package/overlay/capture-build-preflight.ps1',MAX_FILE),('uiaWorker',A['uia_worker'],'package/producer/dependencies/uia-worker/invoke-worker-mta.ps1',MAX_FILE)]
    local={}; targets={}; mapping={}
    for name,src,rel,lim in role_specs:
        h,n=copy_bounded(src,out/rel,lim); local[name]=out/rel; targets[name]=win(A['installed_root'],rel); staged[rel]={'sha256':h,'bytes':n}; total+=n; mapping[str(src)]=targets[name]; mapping[str(src.resolve())]=targets[name]
    # Case/manifest roles are explicit generated evidence; case derives only from manifest identity.
    case_path=out/'package/admission/case.json'; case_path.write_text(json.dumps(case_obj,indent=2,ensure_ascii=False)+'\n',encoding='utf-8'); case_h,case_n=digest(case_path,MAX_JSON); staged['package/admission/case.json']={'sha256':case_h,'bytes':case_n}; total+=case_n
    # Rebuild fresh candidate docs from donor shape, preserving schema/kinds.
    bind=load(A['binding']); context=load(A['context']); capture=load(A['capture_plan']); integ=load(A['integration_bindings'])
    bind['case']={'id':case_id,'hash':pref(case_obj.get('hash'))}; bind['sourceHash']=plan['sourceHash']; bind['runtime']={'sourceCommit':plan['runtimeSourceCommit'],'sourceTreeHash':plan['runtimeSourceTreeHash']}; bind['renderer']={'sha256':'sha256:'+xh}
    context.update({'case':{'id':case_id,'hash':pref(case_obj.get('hash'))},'tupleID':tuple_id,'sourceHash':plan['sourceHash'],'windowsHostHash':pref(tup['hostHashes']['windows']),'macHostHash':pref(tup['hostHashes']['macos']),'qualified':False})
    tuple_doc=dict(tup); tuple_doc['sourceInputs']={'compiledPlan':{'path':A['external_plan_target'],'sha256':'sha256:'+ph,'bytes':pb},'context':{'path':targets['context'],'sha256':'sha256:'+digest(local['context'],MAX_JSON)[0],'bytes':digest(local['context'],MAX_JSON)[1]}}
    # Role destinations already exist from explicit copy; replace only their fresh bytes.
    for _path,_obj in ((local['binding'],bind),(local['context'],context),(local['tuple'],tuple_doc)):
        _path.write_text(json.dumps(_obj,indent=2,ensure_ascii=False)+'\n',encoding='utf-8'); digest(_path,MAX_JSON)
    # Candidate binding must point at fresh tuple bytes, never donor tuple.
    _th,_tn=digest(local['tuple'],MAX_JSON); bind['canonicalTupleRef']={'path':targets['tuple'],'sha256':'sha256:'+_th,'bytes':_tn}
    local['binding'].write_text(json.dumps(bind,indent=2,ensure_ascii=False)+'\n',encoding='utf-8'); digest(local['binding'],MAX_JSON)
    # Recipe role was copied once; preserve measured bytes exactly.
    refs={}
    for name,p in local.items(): refs[targets[name]]=digest(p,MAX_JSON if p.suffix=='.json' else MAX_FILE)
    # Refresh exact typed refs in tuple/binding/context only after all writes.
    for name in ('binding','context','tuple'):
        p=local[name]; obj=refresh(load(p),refs); p.write_text(json.dumps(obj,indent=2,ensure_ascii=False)+'\n',encoding='utf-8'); digest(p,MAX_JSON)
    # SI retains donor kind family while rebinding every local typed role to
    # this installed package. External measured plan/receipt/binaries stay
    # outside package and are validated by installer arguments.
    role_refs={name:{'path':targets[name],'sha256':'sha256:'+digest(local[name],MAX_JSON if local[name].suffix=='.json' else MAX_FILE)[0],'bytes':digest(local[name],MAX_JSON if local[name].suffix=='.json' else MAX_FILE)[1]} for name in ('capturePlan','serializer','integrationBindings','buildPreflight','uiaWorker')}
    si=dict(donor_si); si.update({'kind':'factory-circle-source-inputs-diagnostic-v8','count':1,'candidate':candidate,'tupleID':tuple_id,'caseID':case_id,'sourceHash':plan['sourceHash'],'runtimeSourceCommit':plan['runtimeSourceCommit'],'planHash':ph,'compileReceiptHash':rh,'tupleHash':digest(local['tuple'],MAX_JSON)[0],'bindingHash':digest(local['binding'],MAX_JSON)[0],'contextHash':digest(local['context'],MAX_JSON)[0],'caseHash':pref(case_obj.get('hash')),'recipeHash':pref(recipe.get('hash')),'manifestHash':'sha256:'+mh,'exeHash':eh,'rendererSha256':xh,'rendererPath':A['external_renderer_target'],'compiledHostPackagePath':A['external_plan_target'].rsplit('\\',1)[0],'planRef':{'path':A['external_plan_target'],'sha256':'sha256:'+ph,'bytes':pb},'compileReceiptPath':A['external_receipt_target'],'compileRef':{'path':A['external_receipt_target'],'sha256':'sha256:'+rh,'bytes':rb},'receiptRef':{'path':A['external_receipt_target'],'sha256':'sha256:'+rh,'bytes':rb},'exeRef':{'path':A['external_exe_target'],'sha256':'sha256:'+eh,'bytes':eb},'rendererRef':{'path':A['external_renderer_target'],'sha256':'sha256:'+xh,'bytes':xb},'tupleRef':{'path':targets['tuple'],'sha256':'sha256:'+digest(local['tuple'],MAX_JSON)[0],'bytes':digest(local['tuple'],MAX_JSON)[1]},'bindingRef':{'path':targets['binding'],'sha256':'sha256:'+digest(local['binding'],MAX_JSON)[0],'bytes':digest(local['binding'],MAX_JSON)[1]},'contextRef':{'path':targets['context'],'sha256':'sha256:'+digest(local['context'],MAX_JSON)[0],'bytes':digest(local['context'],MAX_JSON)[1]},'recipeRef':{'path':targets['recipe'],'sha256':'sha256:'+qh,'bytes':qb},'caseRef':{'path':targets['case'],'sha256':'sha256:'+case_h,'bytes':case_n},'manifestRef':{'path':targets['manifest'],'sha256':'sha256:'+mh,'bytes':mb},'capturePlanPath':targets['capturePlan'],'capturePlanRef':role_refs['capturePlan'],'serializerPath':targets['serializer'],'serializerRef':role_refs['serializer'],'integrationBindingsRef':role_refs['integrationBindings'],'buildPreflightPath':targets['buildPreflight'],'buildPreflightRef':role_refs['buildPreflight'],'uiaWorkerPath':targets['uiaWorker'],'uiaWorkerRef':role_refs['uiaWorker'],'serializerControlSha256':digest(local['serializer'],MAX_FILE)[0],'buildPreflightHash':digest(local['buildPreflight'],MAX_FILE)[0],'uiaWorkerHash':digest(local['uiaWorker'],MAX_FILE)[0],'capturePlanHash':digest(local['capturePlan'],MAX_JSON)[0],'diagnosticQualification':'diagnostic-native-only-not-qualified','nativeActions':0,'compilerActions':0,'lockActions':0})
    si_path=out/'package/admission/source-inputs.json'; sh,sn=replace_json(si_path,si); staged['package/admission/source-inputs.json']={'sha256':sh,'bytes':sn}; total+=sn
    config_path=out/'package/overlay/root-v8/diagnostic-config-template.json'
    source_bindings=[{'path':k[len('package/overlay/root-v8/'):], 'sha256':v['sha256'], 'bytes':v['bytes']} for k,v in sorted(staged.items()) if k.startswith('package/overlay/root-v8/')]
    guard_rel='package/overlay/root-v8/integration-fresh-circle-diagnostic-v8.ps1'
    guard_hash=staged[guard_rel]['sha256']
    config={'kind':'factory-circle-diagnostic-config-v8','count':1,'candidate':candidate,
      'controlRoot':win(A['installed_root'],'control'),'producerRoot':win(A['installed_root'],'package/producer'),
      'admissionRoot':win(A['installed_root'],'package/admission'),'overlayRoot':win(A['installed_root'],'package/overlay/root-v8'),
      'package':win(A['installed_root'],'package'),'outputRoot':win(A['installed_root'],'native'),
      'sourceInputsPath':win(A['installed_root'],'package/admission/source-inputs.json'),'sourceInputsHash':sh,
      'planPath':A['external_plan_target'],'planHash':ph,'receiptPath':A['external_receipt_target'],'compileReceiptHash':rh,
      'exePath':A['external_exe_target'],'exeHash':eh,'rendererPath':A['external_renderer_target'],'rendererHash':xh,
      'serializerControlSha256':si['serializerControlSha256'],'runRoot':win(A['installed_root'],'replays/r1'),
      'issuedMetadataPath':win(A['installed_root'],'package/admission/issued-metadata.json'),'issuedMetadataHash':'pending-issued-metadata',
      # Config is consumed from installed namespace root; package/ is part of
      # installed path. Stripping it points coordinator outside package.
      'integrationGuardPath':win(A['installed_root'],guard_rel),'integrationGuardHash':guard_hash,
      'sourceBindings':source_bindings,'nativeActions':0,'compilerActions':0,'lockActions':0}
    ch,cn=replace_json(config_path,config); staged['package/overlay/root-v8/diagnostic-config-template.json']={'sha256':ch,'bytes':cn}; total+=cn
    # Patch fresh copies only: incremental plan/receipt accepted, v8 SI required.
    for p in (out/'package/overlay/final-plan-eligibility.ps1',out/'package/overlay/integration-fresh-circle-v1.ps1',out/'package/overlay/capture-circle-single-v3.ps1',out/'package/overlay/dispatch-circle-single-v3.ps1',out/'package/overlay/issue-circle-metadata-v1.ps1'):
        if p.exists():
            text=p.read_text(encoding='utf-8')
            text=text.replace("'factory-circle-source-inputs-diagnostic-v8'","'factory-circle-source-inputs-diagnostic-v8'")
            # Replace strict old kind predicates with explicit incremental-or-historical branches.
            text=text.replace("$Plan.kind -cne 'factory-circle-compiler-plan-v1'", "($Plan.kind -cne 'factory-circle-compiler-plan-v1' -and $Plan.kind -cne 'factory-circle-incremental-compile-plan-v1')")
            text=text.replace("$plan.kind -ne 'factory-circle-incremental-compile-plan-v1'", "($plan.kind -ne 'factory-circle-incremental-compile-plan-v1' -and $plan.kind -ne 'factory-circle-compiler-plan-v1')")
            text=text.replace("$sourceDocument.kind -cne 'factory-circle-source-inputs-diagnostic-v8'","$sourceDocument.kind -cne 'factory-circle-source-inputs-diagnostic-v8'")
            p.write_text(text,encoding='utf-8')
    # stage refreshed rows after mutations
    for rel in list(staged):
        p=out/rel; staged[rel]={'sha256':digest(p,MAX_JSON if p.suffix=='.json' else MAX_FILE)[0],'bytes':digest(p,MAX_JSON if p.suffix=='.json' else MAX_FILE)[1]}
    if len(staged)>MAX_FILES or sum(v['bytes'] for v in staged.values())>MAX_TOTAL: raise RuntimeError('packet bound exceeded')
    graph={'kind':'factory-circle-incremental-diagnostic-source-graph-v8','candidate':candidate,'count':1,'diagnosticQualification':'diagnostic-native-only-not-qualified','plan':{'path':A['external_plan_target'],'sha256':'sha256:'+ph,'bytes':pb},'receipt':{'path':A['external_receipt_target'],'sha256':'sha256:'+rh,'bytes':rb},'exeRef':{'path':A['external_exe_target'],'sha256':'sha256:'+eh,'bytes':eb},'rendererRef':{'path':A['external_renderer_target'],'sha256':'sha256:'+xh,'bytes':xb},'cleanup':{'renderer':{'path':str(A['renderer_cleanup_v2']),'sha256':'sha256:'+renderer_cleanup_h,'bytes':renderer_cleanup_b},'uia':{'path':str(A['cleanup_v2']),'sha256':'sha256:'+cleanup_h,'bytes':cleanup_b}},'sourceInputs':{'path':win(A['installed_root'],'package/admission/source-inputs.json'),'sha256':'sha256:'+sh,'bytes':sn},'incrementalPlanKind':plan['kind'],'incrementalReceiptKind':receipt['kind'],'nativeActions':0,'compilerActions':0,'lockActions':0,'files':[{'path':k,'sha256':'sha256:'+v['sha256'],'bytes':v['bytes']} for k,v in sorted(staged.items())]}
    graph_p=out/'source-graph-v8.json'; gh,gn=write_json(graph_p,graph)
    stage_doc={'kind':'factory-circle-incremental-diagnostic-stage-v8','status':'SOURCE_ONLY','stageRoot':A['installed_root'],'candidate':candidate,'incrementalPlanKind':plan['kind'],'incrementalReceiptKind':receipt['kind'],'plan':graph['plan'],'receipt':graph['receipt'],'sourceGraph':{'path':'source-graph-v8.json','sha256':'sha256:'+gh,'bytes':gn},'files':graph['files'],'limits':{'maxFiles':MAX_FILES,'maxFileBytes':MAX_FILE,'maxTotalBytes':MAX_TOTAL,'maxJsonBytes':MAX_JSON},'nativeActions':0,'compilerActions':0,'lockActions':0}
    stage_p=A['stage_manifest_path']; stage_p.parent.mkdir(parents=True,exist_ok=True); sh2,sn2=write_json(stage_p,stage_doc)
    # Installer accepts package-root-only archives; metadata stays under package.
    payload=[(out/k,k) for k in staged]+[(graph_p,'package/source-graph-v8.json'),(stage_p,'package/stage-manifest-v8.json')]
    inv=[]; ztotal=0
    for p,rel in payload:
        h,n=digest(p); inv.append({'path':rel,'sha256':h,'bytes':n}); ztotal+=n
    invp=out/'zip-inventory-v8.json'; ih,inb=write_json(invp,{'kind':'factory-circle-incremental-diagnostic-zip-inventory-v8','files':inv,'fileCount':len(inv),'payloadBytes':ztotal,'nativeActions':0,'compilerActions':0,'lockActions':0}); payload.append((invp,'package/zip-inventory-v8.json'))
    zp=A['zip_path']; zp.parent.mkdir(parents=True,exist_ok=True)
    if zp.exists(): raise RuntimeError('fresh ZIP required')
    with zipfile.ZipFile(zp,'x',compression=zipfile.ZIP_DEFLATED) as z:
        for p,rel in payload: z.write(p,rel)
    zh,zn=digest(zp,MAX_TOTAL)
    installer=A['installer_path']; template=overlay/'install-circle-diagnostic-root-v8.ps1'; text=template.read_text(encoding='utf-8').replace('factory-circle-incremental-diagnostic-stage-v4','factory-circle-incremental-diagnostic-stage-v8').replace('source-graph-v4.json','source-graph-v8.json').replace('build-circle-diagnostic-root-v4.ps1','build-circle-diagnostic-root-v8.ps1').replace('circle-close-r11-r8',str(A['installed_root']).replace('/','\\'))
    if installer.exists(): raise RuntimeError('fresh installer required')
    installer.parent.mkdir(parents=True,exist_ok=True); installer.write_text(text,encoding='utf-8'); ih2,in2=digest(installer)
    print(json.dumps({'status':'SOURCE_ONLY_STAGED','kind':graph['kind'],'files':len(staged),'planSha256':ph,'receiptSha256':rh,'exeSha256':eh,'rendererSha256':xh,'graphSha256':gh,'stageManifestSha256':sh2,'zipSha256':zh,'zipBytes':zn,'installerSha256':ih2,'installerBytes':in2,'nativeActions':0,'compilerActions':0,'lockActions':0},sort_keys=True))

if __name__=='__main__': main()
