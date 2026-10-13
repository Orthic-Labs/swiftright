"""Prepare centered Rectangle Count1/Count20 capture from final-r6 receipt.

Source-only packet builder. It consumes already archived local evidence; root
owns remote staging, preflight, native capture, SSH, compiler, & Git.
"""
from pathlib import Path
import argparse, base64, hashlib, json, zipfile, re

REPO=Path('/Volumes/D/claude/swiftright')
DONOR_ROOT=REPO/'factory/pipeline/pilot-delivery-five-v1/root-execution'
CACHE=REPO/'.factory-work/pilot-delivery-five-v1/centered-native-capture'

ap=argparse.ArgumentParser()
ap.add_argument('--final-plan',required=True)
ap.add_argument('--final-archive',required=True)
ap.add_argument('--count',type=int,choices=(1,20),default=1)
ap.add_argument('--revision',type=int,choices=range(1,21),default=1)
ap.add_argument('--count1-proof',help='required local Count1 coordinator receipt for Count20')
ap.add_argument('--count1-proof-remote-path',default=r'D:\Claude\swiftright\.factory-work\hosts\rectangle\captures\centered-r1\control-count1-r1\coordinator.json')
a=ap.parse_args()

def rd(path,cap=67108864):
    p=Path(path)
    if not p.is_file() or p.is_symlink() or p.stat().st_size>cap: raise SystemExit(f'bounded regular file required: {p}')
    return p.read_bytes()
def sha(data): return hashlib.sha256(data).hexdigest()
def jd(value): return (json.dumps(value,indent=2,sort_keys=True)+'\n').encode()
def load(path): return json.loads(rd(path,4194304).decode('utf-8-sig'))
def replace(value,changes):
    if isinstance(value,str):
        for old,new in changes: value=value.replace(old,new)
        return value
    if isinstance(value,list): return [replace(v,changes) for v in value]
    if isinstance(value,dict): return {k:replace(v,changes) for k,v in value.items()}
    return value
def req(obj,key):
    value=obj.get(key) if isinstance(obj,dict) else None
    if value in (None,''): raise SystemExit(f'missing {key}')
    return value

def _source_rel(raw, owner, names):
    """Resolve only staged source refs; external Windows refs stay external."""
    if not isinstance(raw,str) or not raw.strip(): return None
    text=raw.replace('\\','/').rstrip('/')
    exact=[]
    for rel in names:
        norm=rel.replace('\\','/')
        if text==norm or text.endswith('/'+norm): exact.append(rel)
    if exact: return exact[0] if len(exact)==1 else None
    leaf=text.rsplit('/',1)[-1]
    leaf_hits=[rel for rel in names if rel.rsplit('/',1)[-1]==leaf]
    if len(leaf_hits)==1:return leaf_hits[0]
    prefixes=[]
    if owner.startswith('producer/dependencies/uia-worker/'):
        prefixes.append('producer/dependencies/uia-worker/')
    elif owner.startswith('producer/'):
        prefixes.append('producer/')
    elif owner.startswith('overlay/'):
        prefixes.append('overlay/')
    elif owner.startswith('admission/'):
        prefixes.append('admission/')
    prefixes += ['producer/','overlay/','admission/']
    for prefix in prefixes:
        candidate=prefix+text
        if candidate in names:return candidate
    return None

def rebind_source_pin_graph(files, donor_rows):
    """Rebind typed child hashes before parent pins; reject cycles/self-pins.

    Hashes are changed only when a path-bearing ref identifies a staged child,
    or when an embedded PowerShell guard names that same child nearby. This
    keeps provenance hashes outside source graph untouched.
    """
    names=set(files); old_by_hash={}
    for row in donor_rows:
        old_by_hash.setdefault(row['sha256'],set()).add(row['path'])
    def current_hashes():
        return {rel:sha(data) for rel,data in files.items()}
    def unique_target(paths):
        vals={current_hashes()[x] for x in paths if x in files}
        return vals.pop() if len(vals)==1 else None
    def walk_refs(value,owner,edges,parent):
        if isinstance(value,dict):
            path=value.get('path')
            target=_source_rel(path,owner,names)
            if target:
                edges.append((parent,target))
                desired=sha(files[target])
                for key in list(value):
                    if key=='sha256' or key.lower().endswith('hash'):
                        if isinstance(value[key],str) and re.fullmatch(r'(?:sha256:)?[0-9a-f]{64}',value[key],re.I):
                            value[key]=('sha256:'+desired) if value[key].lower().startswith('sha256:') else desired
                    elif key.lower().endswith('bytes') and isinstance(value[key],(int,float)):
                        value[key]=len(files[target])
            for key,item in value.items(): walk_refs(item,owner,edges,parent)
        elif isinstance(value,list):
            for item in value: walk_refs(item,owner,edges,parent)
    def context_target(text,pos,owner):
        window=text[max(0,pos-140):min(len(text),pos+140)]
        hits=[]
        for rel in names:
            short=rel.split('/',1)[-1]
            if short.replace('/','\\') in window or short in window or rel in window:
                hits.append(rel)
        return hits[0] if len(hits)==1 else None
    def cycle_check(edges):
        graph={}
        for parent,target in edges:
            if parent==target: raise SystemExit(f'source pin self-reference: {parent}')
            graph.setdefault(parent,set()).add(target)
        state={}
        def visit(node):
            if state.get(node)==1: raise SystemExit(f'source pin cycle detected at {node}')
            if state.get(node)==2:return
            state[node]=1
            for child in graph.get(node,()): visit(child)
            state[node]=2
        for node in graph:visit(node)
    for iteration in range(16):
        before=dict(files); current=current_hashes(); edges=[]
        # Re-seal explicit source binding rows from child bytes first.
        for rel in ('producer/integration-bindings.json',):
            if rel in files:
                doc=json.loads(files[rel].decode('utf-8-sig'))
                for row in doc.get('files',[]):
                    target=_source_rel(row.get('path'),'producer/'+str(row.get('path','')),names)
                    if target:
                        row['bytes']=len(files[target]);row['sha256']=sha(files[target])
                        edges.append((rel,target))
                files[rel]=jd(doc)
        for rel in ('producer/dependencies/uia-worker/worker-contract.json',):
            if rel in files:
                doc=json.loads(files[rel].decode('utf-8-sig'))
                for row in doc.get('sourceBindings',[]):
                    target=_source_rel(row.get('path'),rel,names)
                    if target:
                        row['bytes']=len(files[target]);row['sha256']=sha(files[target]);edges.append((rel,target))
                files[rel]=jd(doc)
        current=current_hashes()
        for rel,data in list(files.items()):
            if rel.endswith('.json'):
                try: doc=json.loads(data.decode('utf-8-sig'))
                except Exception: continue
                walk_refs(doc,rel,edges,rel)
                if rel=='admission/source-inputs.json':
                    pairs={'contextHash':'admission/context.json','tupleHash':'admission/candidate-tuple.json','bindingHash':'admission/candidate-binding.json','recipeHash':'admission/recipe.json','integrationBindingsHash':'producer/integration-bindings.json'}
                    for key,target in pairs.items():
                        if target in files: doc[key]=sha(files[target])
                files[rel]=jd(doc)
            elif rel.endswith(('.ps1','.cs','.py','.md')):
                text=data.decode('utf-8-sig')
                for old,targets in old_by_hash.items():
                    live=[target for target in targets if target in files];desireds={current_hashes()[target] for target in live}
                    if not live or len(desireds)!=1: continue
                    desired=next(iter(desireds))
                    pattern=re.compile(r'(?<![0-9a-f])'+re.escape(old)+r'(?![0-9a-f])',re.I)
                    text=pattern.sub(lambda match: desired if context_target(text,match.start(),rel) in live else match.group(0),text)
                files[rel]=text.encode()
        cycle_check(edges)
        if files==before: break
    else:
        raise SystemExit('source pin graph did not converge; cycle or hidden self-pin')
    # Any donor source hash left beside its child path is an unresolved pin.
    for rel,data in files.items():
        if not rel.endswith(('.ps1','.cs','.py','.md')): continue
        text=data.decode('utf-8-sig')
        for old,targets in old_by_hash.items():
            live=[target for target in targets if target in files];desireds={sha(files[target]) for target in live}
            if not live or len(desireds)!=1: continue
            desired=next(iter(desireds))
            if old==desired: continue
            for match in re.finditer(r'(?<![0-9a-f])'+re.escape(old)+r'(?![0-9a-f])',text,re.I):
                if context_target(text,match.start(),rel) in live:
                    raise SystemExit(f'unresolved embedded source pin: {rel} -> {live[0]}')

plan_path=Path(a.final_plan); plan_path=plan_path if plan_path.is_absolute() else REPO/plan_path
plan_raw=rd(plan_path,4194304); plan=load(plan_path); plan_hash=sha(plan_raw)
archive=Path(a.final_archive); receipt_path=archive/'observation.json'; receipt_raw=rd(receipt_path,4194304); receipt=load(receipt_path); receipt_hash=sha(receipt_raw)
summary=load(archive/'archive-summary.json');remote_root=str(summary.get('remoteRoot','')).replace('/','\\');compile_tag=Path(remote_root.replace('\\','/')).name
if not re.fullmatch(r'final-r[0-9]+',compile_tag): raise SystemExit(f'actual compile receipt tag required: {compile_tag}')
compile_receipt_path=remote_root+'\\observation.json'
if plan.get('phase')!='final' or receipt.get('phase')!='final': raise SystemExit('centered final plan/receipt required')
if receipt.get('kind')!='factory-rectangle-owned-compile-v1' or receipt.get('planSha256')!=plan_hash: raise SystemExit('final receipt plan join failed')
if receipt.get('exitCode')!=0 or receipt.get('ownedExited') is not True or receipt.get('originalHandleRetained') is not True or receipt.get('streamDrainComplete') is not True or receipt.get('streamsSealed') is not True or receipt.get('jobActiveCount')!=0 or receipt.get('cleanupJobActive')!=0 or receipt.get('kernelWait')!=0 or receipt.get('nativeActions')!=0: raise SystemExit('final lifecycle receipt admission failed')
for stream in ('stdout','stderr'):
    data=rd(archive/f'compile.{stream}.bin');
    if len(data)!=receipt.get(f'{stream}Bytes') or sha(data)!=receipt.get(f'{stream}Sha256'): raise SystemExit(f'{stream} receipt bytes drift')
exe_data=rd(archive/'FactoryProbe.exe');exe_hash=sha(exe_data);exe_bytes=len(exe_data)
if exe_hash!=receipt.get('exeSha256') or exe_bytes!=receipt.get('exeBytes') or ('sha256:'+exe_hash)!=plan.get('expectedHostHash'): raise SystemExit('final executable join failed')
if receipt.get('case')!=plan.get('case') or receipt.get('sourceHash')!=plan.get('sourceHash'): raise SystemExit('final case/source join failed')
tuple_obj=req(plan,'tuple')
if tuple_obj.get('hostHashes',{}).get('windows')!='sha256:'+exe_hash: raise SystemExit('final tuple Windows hash drift')
if a.count==20:
    if not a.count1_proof: raise SystemExit('Count20 requires --count1-proof')
    proof_path=Path(a.count1_proof);proof_raw=rd(proof_path,4194304);proof=load(proof_path);proof_hash=sha(proof_raw)
    if proof.get('count')!=1 or proof.get('status') not in ('completed-source-bound-observation','preflight-passed') or proof.get('lockReleased') is not True or proof.get('wholeBatchExitConfirmed') is not True or proof.get('cleanupErrors'): raise SystemExit('Count1 proof is not closed')
    if proof.get('exeHash') not in (exe_hash,'sha256:'+exe_hash) or proof.get('compileReceiptHash') not in (receipt_hash,'sha256:'+receipt_hash): raise SystemExit('Count1 proof build join failed')
else:
    proof_path=proof=None;proof_raw=b'';proof_hash=None

donor=DONOR_ROOT/('rectangle-color-capture-r5' if a.count==1 else 'rectangle-color-capture-count20-r1')/'sources'
manifest=load(donor/'stage-manifest.json');rows=manifest.get('files',[])
if len(rows)!=47 or sum(int(row['bytes']) for row in rows)>16777216: raise SystemExit('proven capture donor manifest drift')
old_ns=r'D:\Claude\swiftright\.factory-work\hosts\rectangle\captures\color-'+('r5' if a.count==1 else 'count20-r1')
tag=('centered-r'+str(a.revision)) if a.count==1 else ('centered-count20-r'+str(a.revision))
new_ns=r'D:\Claude\swiftright\.factory-work\hosts\rectangle\captures'+'\\'+tag
new_roots={k:new_ns+'\\'+k+'-'+tag for k in ('producer','admission','overlay')}
old_inputs=load(donor/'admission/source-inputs.json')
changes=[(old_ns,new_ns),('color-r5',tag),('color-count20-r1',tag),
         ('802d064cfd971585e73d1f7d9fce969876029b93d04e7296f22a64f71b211c30',plan_hash),
         (old_inputs.get('compileReceiptHash',''),receipt_hash),(old_inputs.get('exeHash',''),exe_hash),
         (old_inputs.get('tupleID',''),tuple_obj['id'])]
changes += [(f'final-r{i}',compile_tag) for i in range(1,11) if f'final-r{i}' != compile_tag]
changes=[pair for pair in changes if pair[0] and pair[0]!=pair[1]]
files={}
for row in rows:
    rel=row['path']; data=rd(donor/rel,67108864)
    if sha(data)!=row['sha256'] or len(data)!=row['bytes']: raise SystemExit(f'donor row drift: {rel}')
    if rel.endswith('.json'): data=jd(replace(json.loads(data.decode('utf-8-sig')),changes))
    elif rel.endswith(('.ps1','.cs','.py','.md')): data=replace(data.decode(),changes).encode()
    files[rel]=data

for _rel,_data in files.items():
    if _rel.endswith(('.ps1','.json','.cs','.py','.md')):
        _text=_data.decode('utf-8-sig',errors='strict')
        _bad=sorted(set(x for x in re.findall(r'final-r[0-9]+',_text) if x != compile_tag))
        if _bad: raise SystemExit(f'operative compile receipt tag drift in {_rel}: {_bad}')

ctx=json.loads(files['admission/context.json'].decode('utf-8-sig'));ctx.update(case=plan['case'],sourceHash=plan['sourceHash'],tupleID=tuple_obj['id'],windowsHostHash='sha256:'+exe_hash,macHostHash=tuple_obj['hostHashes'].get('macos'),qualified=False,qualification='observational-hold-pending-native-capture');files['admission/context.json']=jd(ctx)
tu=json.loads(files['admission/candidate-tuple.json'].decode('utf-8-sig'));tu['case']=plan['case'];tu['tuple']=tuple_obj;tu['sourceInputs']['compiledPlan']={'bytes':len(plan_raw),'path':r'D:\Claude\swiftright\.factory-work\hosts\rectangle\package\plan.json','sha256':'sha256:'+plan_hash};tu['sourceInputs']['context']={'bytes':len(files['admission/context.json']),'path':new_roots['admission']+'\\context.json','sha256':'sha256:'+sha(files['admission/context.json'])};files['admission/candidate-tuple.json']=jd(tu)
binding=json.loads(files['admission/candidate-binding.json'].decode('utf-8-sig'));binding['case']=plan['case'];binding['canonicalTupleRef']={'bytes':len(files['admission/candidate-tuple.json']),'path':new_roots['admission']+'\\candidate-tuple.json','sha256':'sha256:'+sha(files['admission/candidate-tuple.json'])};files['admission/candidate-binding.json']=jd(binding)
si=json.loads(files['admission/source-inputs.json'].decode('utf-8-sig'));si.update(count=a.count,caseID=plan['case']['id'],caseHash=plan['case']['hash'],sourceHash=plan['sourceHash'],tupleID=tuple_obj['id'],planHash=plan_hash,compileReceiptHash=receipt_hash,compileReceiptPath=compile_receipt_path,exeHash=exe_hash,compiledHostPackagePath=plan['compileRequest']['packagePath'])
si['planRef']={'bytes':len(plan_raw),'path':r'D:\Claude\swiftright\.factory-work\hosts\rectangle\package\plan.json','sha256':'sha256:'+plan_hash};si['compileRef']={'bytes':len(receipt_raw),'path':si['compileReceiptPath'],'sha256':'sha256:'+receipt_hash};si['recipeRef']={'bytes':len(files['admission/recipe.json']),'path':new_roots['admission']+'\\recipe.json','sha256':'sha256:'+sha(files['admission/recipe.json'])};si['exeRef']['path']=receipt['exePath'];si['exeRef']['bytes']=exe_bytes;si['exeRef']['sha256']='sha256:'+exe_hash;si['buildPreflightPath']=new_roots['overlay']+'\\preflight-color-r1.ps1';si['buildPreflightHash']=sha(files['overlay/preflight-color-r1.ps1']);si['capturePlanPath']=new_roots['producer']+'\\capture-plan.json';si['capturePlanHash']=sha(files['producer/capture-plan.json']);si['contextRef']={'bytes':len(files['admission/context.json']),'path':new_roots['admission']+'\\context.json','sha256':'sha256:'+sha(files['admission/context.json'])};si['tupleRef']={'bytes':len(files['admission/candidate-tuple.json']),'path':new_roots['admission']+'\\candidate-tuple.json','sha256':'sha256:'+sha(files['admission/candidate-tuple.json'])};si['bindingRef']={'bytes':len(files['admission/candidate-binding.json']),'path':new_roots['admission']+'\\candidate-binding.json','sha256':'sha256:'+sha(files['admission/candidate-binding.json'])}
files['admission/source-inputs.json']=jd(si)
for rel in ('producer/integration-bindings.json',):
    bind=json.loads(files[rel].decode('utf-8-sig'))
    for row in bind['files']:
        data=files['producer/'+row['path']];row.update(bytes=len(data),sha256=sha(data))
    files[rel]=jd(bind)
si=json.loads(files['admission/source-inputs.json'].decode('utf-8-sig'));si['integrationBindingsRef']={'bytes':len(files['producer/integration-bindings.json']),'path':new_roots['producer']+'\\integration-bindings.json','sha256':'sha256:'+sha(files['producer/integration-bindings.json'])};si['integrationBindingsHash']=sha(files['producer/integration-bindings.json']);si['contextHash']=sha(files['admission/context.json']);si['tupleHash']=sha(files['admission/candidate-tuple.json']);si['bindingHash']=sha(files['admission/candidate-binding.json']);si['recipeHash']=sha(files['admission/recipe.json']);files['admission/source-inputs.json']=jd(si)

# Rebind every typed child/parent pin after metadata edits. Compile receipt
# tag is derived from measured archive path; no capture revision is used here.
rebind_source_pin_graph(files, rows)
for rel in files:
    if rel.endswith(('.ps1','.json','.cs','.py','.md')):
        tags=sorted(set(re.findall(r'final-r[0-9]+',files[rel].decode('utf-8-sig'))))
        if any(tag != compile_tag for tag in tags):
            raise SystemExit(f'operative compile receipt tag drift in {rel}: {tags}')
si=json.loads(files['admission/source-inputs.json'].decode('utf-8-sig'))

# Positive source-side joins: every internal ref must equal staged bytes before
# installer emission; external refs retain measured final-r6 paths above.
for key,rel in (('contextRef','admission/context.json'),('tupleRef','admission/candidate-tuple.json'),('bindingRef','admission/candidate-binding.json'),('recipeRef','admission/recipe.json'),('integrationBindingsRef','producer/integration-bindings.json')):
    ref=si[key];data=files[rel]
    if ref['bytes']!=len(data) or ref['sha256']!='sha256:'+sha(data): raise SystemExit(f'source ref drift: {key}')
for rel,data in files.items():
    if rel.endswith(('.ps1','.json','.cs','.py')) and b'__' in data.replace(b'__file__',b''):
        raise SystemExit(f'unresolved source placeholder: {rel}')

out=DONOR_ROOT/f'rectangle-centered-capture-{("r" if a.count==1 else "count20-r")}{a.revision}'
if out.exists(): raise SystemExit(f'fresh output required: {out}')
(out/'sources').mkdir(parents=True)
for rel,data in files.items(): dest=out/'sources'/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
rows=[{'path':rel,'bytes':len(data),'sha256':sha(data)} for rel,data in files.items()]
stage={'kind':'factory-rectangle-centered-capture-source-stage-v1','host':'rectangle-centered','count':a.count,'revision':a.revision,'files':rows,'roots':new_roots,'planHash':plan_hash,'compileReceiptHash':receipt_hash,'exeHash':exe_hash,'nativeActions':0,'compilerActions':0,'lockActions':0,'qualification':'pending-root-native-capture'}
stage_bytes=jd(stage);(out/'sources/stage-manifest.json').write_bytes(stage_bytes)
CACHE.mkdir(parents=True,exist_ok=True);zip_path=CACHE/f'rectangle-centered-count{a.count}-r{a.revision}.zip'
with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED) as z:
    for rel,data in files.items(): z.writestr(rel,data)
    z.writestr('stage-manifest.json',stage_bytes)
script=r'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Capture='@@NS@@';$Package='D:\Claude\swiftright\.factory-work\hosts\rectangle\package';$Zip='D:\Claude\swiftright\.factory-work\@@ZIP@@';$Count=@@COUNT@@
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native stage busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop busy for rolling capture stage'}
if(Test-Path -LiteralPath $Capture){throw 'fresh centered capture namespace required'}
$OldPlan=Join-Path $Package 'plan.json';$CurrentPlanHash=(Get-FileHash -LiteralPath $OldPlan).Hash.ToLowerInvariant()
if($CurrentPlanHash -ceq '@@BASE_PLAN_HASH@@'){New-Item -ItemType Directory -Path (Join-Path $Capture 'retired') -Force|Out-Null;Copy-Item -LiteralPath $OldPlan -Destination (Join-Path $Capture 'retired\plan-old.json');Copy-Item -LiteralPath (Join-Path $Package 'plan-final-v4.json') -Destination $OldPlan -Force}elseif($CurrentPlanHash -cne '@@PLAN_HASH@@'){throw 'previous centered capture plan drift'}
if((Get-FileHash -LiteralPath $OldPlan).Hash.ToLowerInvariant() -cne '@@PLAN_HASH@@'){throw 'centered plan install drift'}
$PlanFinal=Join-Path $Package 'plan-final-v4.json';if((Get-FileHash -LiteralPath $PlanFinal).Hash.ToLowerInvariant() -cne '@@PLAN_HASH@@'){throw 'centered final plan drift'}
if((Get-FileHash -LiteralPath $Zip).Hash.ToLowerInvariant() -ne '@@ZIP_HASH@@'){throw 'centered source zip drift'}
$Temp=Join-Path $Capture 'source-stage';Expand-Archive -LiteralPath $Zip -DestinationPath $Temp
$M=Get-Content -LiteralPath (Join-Path $Temp 'stage-manifest.json') -Raw|ConvertFrom-Json
foreach($Row in @($M.files)){$F=Get-Item -LiteralPath (Join-Path $Temp $Row.path);if($F.Length -ne $Row.bytes -or (Get-FileHash -LiteralPath $F.FullName).Hash.ToLowerInvariant() -ne $Row.sha256){throw ('centered source stage drift: '+$Row.path)}}
foreach($N in @('producer','admission','overlay')){$D=[string]$M.roots.$N;New-Item -ItemType Directory -Path $D -Force|Out-Null;foreach($F in @(Get-ChildItem -LiteralPath (Join-Path $Temp $N) -Force)){Copy-Item -LiteralPath $F.FullName -Destination (Join-Path $D $F.Name) -Recurse -Force}}
$Control=Join-Path $Capture '@@CONTROL_TAG@@';New-Item -ItemType Directory -Path $Control -Force|Out-Null
foreach($Row in @($M.files|Where-Object {$_.path.StartsWith('overlay/') -and $_.path.EndsWith('.ps1')})){$T=$null;$E=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $M.roots.overlay $Row.path.Substring(8)),[ref]$T,[ref]$E);if($E.Count){throw ($E|Out-String)}}
$Source=Join-Path $M.roots.admission 'source-inputs.json';$Si=Get-Content -LiteralPath $Source -Raw|ConvertFrom-Json
foreach($K in @('planHash','compileReceiptHash','exeHash','tupleHash','bindingHash','recipeHash','integrationBindingsHash','rendererSha256','serializerControlSha256')){if([string]::IsNullOrWhiteSpace([string]$Si.$K)){throw ('source input missing: '+$K)}}
$Guard=@(Get-ChildItem -LiteralPath $M.roots.overlay -Filter 'integration-fresh-*.ps1' -File);if($Guard.Count -ne 1){throw 'centered integration guard cardinality drift'};$Guard=$Guard[0].FullName;$GuardHash=(Get-FileHash -LiteralPath $Guard).Hash.ToLowerInvariant()
& (Join-Path $M.roots.overlay 'test-rectangle-integration-controls.ps1') -GuardPath $Guard -Root $M.roots.producer -SourceInputsPath $Source|Out-File (Join-Path $Control 'integration-controls.json') -Encoding UTF8
& (Join-Path $M.roots.overlay 'test-uia-mta-controls.ps1') -WorkerPath (Join-Path $M.roots.producer 'dependencies\uia-worker\worker.ps1') -InvokerPath (Join-Path $M.roots.overlay 'uia-worker-invoke-v2.ps1') -SchemaPath (Join-Path $M.roots.producer 'dependencies\uia-worker\schema.ps1')|Out-File (Join-Path $Control 'uia-mta-controls.json') -Encoding UTF8
& (Join-Path $M.roots.overlay 'test-mta-config-admission.ps1') -OutputPath (Join-Path $Control 'mta-config-controls.json')
. $Guard;Assert-FactoryIntegrationSources $M.roots.producer $Si|Out-Null
$Par=@{Count=$Count;SourceInputsPath=$Source;SourceInputsHash=(Get-FileHash -LiteralPath $Source).Hash.ToLowerInvariant();OutputPath=(Join-Path $M.roots.admission 'issued-metadata.json');RunRoot='@@RUN_ROOT@@';PlanPath=$Si.planRef.path;PlanHash=$Si.planHash;CompileReceiptPath=$Si.compileRef.path;CompileReceiptHash=$Si.compileReceiptHash;ExePath=$Si.exeRef.path;ExeHash=$Si.exeHash;RendererPath=$Si.rendererRef.path;RendererHash=$Si.rendererSha256;SerializerPath=$Si.serializerRef.path;SerializerHash=$Si.serializerControlSha256;TuplePath=$Si.tupleRef.path;TupleHash=$Si.tupleHash;BindingPath=$Si.bindingRef.path;BindingHash=$Si.bindingHash;RecipePath=$Si.recipeRef.path;RecipeHash=$Si.recipeHash}
& (Join-Path $M.roots.overlay 'issue-rectangle-metadata-v1.ps1') @Par
$Bindings=@();foreach($Row in @($M.files|Where-Object {$_.path.StartsWith('overlay/') -and ($_.path.EndsWith('.ps1') -or $_.path.EndsWith('.cs'))})){$Rel=$Row.path.Substring(8);$Local=Join-Path $M.roots.overlay $Rel;if((Get-Item -LiteralPath $Local).Length -ne $Row.bytes -or (Get-FileHash -LiteralPath $Local).Hash.ToLowerInvariant() -ne $Row.sha256){throw ('source binding drift: '+$Rel)};$Bindings+=@([ordered]@{path=$Rel;bytes=[int64]$Row.bytes;sha256=$Row.sha256})}
$C=[ordered]@{kind='factory-rectangle-centered-admission-v1';admissionRoot=[string]$M.roots.admission;compileReceiptHash=$Si.compileReceiptHash;controlRoot=$Control;count=$Count;exeHash=$Si.exeHash;integrationGuardHash=$GuardHash;integrationGuardPath=$Guard;issuedMetadataHash=$null;issuedMetadataPath=(Join-Path $M.roots.admission 'issued-metadata.json');outputRoot='@@NATIVE_ROOT@@';overlayRoot=[string]$M.roots.overlay;owner='pending-root-lock';package=$Package;producerRoot=[string]$M.roots.producer;runRoot='@@RUN_ROOT@@';serializerControlSha256=$Si.serializerControlSha256;sourceBindings=$Bindings;sourceInputsHash=(Get-FileHash -LiteralPath $Source).Hash.ToLowerInvariant();sourceInputsPath=$Source}
$C.issuedMetadataHash=(Get-FileHash -LiteralPath $C.issuedMetadataPath).Hash.ToLowerInvariant();$Template=Join-Path $Control 'config-template.json';$C|ConvertTo-Json -Depth 32|Set-Content -LiteralPath $Template -Encoding UTF8;$Pin=(Get-FileHash -LiteralPath $Template).Hash.ToLowerInvariant()
& (Join-Path $M.roots.overlay '@@COORDINATOR@@') -Template $Template -TemplateHash $Pin -PreflightOnly
if(Test-Path -LiteralPath (Join-Path $Control 'coordinator.json')){$Co=Get-Content -LiteralPath (Join-Path $Control 'coordinator.json') -Raw|ConvertFrom-Json;if($Co.nativeActions -ne 0 -or $Co.lockActions -ne 0){throw 'preflight performed native or lock action'}}
[ordered]@{status='preflight-passed';templatePath=$Template;templateHash=$Pin;sourceInputsHash=$C.sourceInputsHash;issuedMetadataHash=$C.issuedMetadataHash;nativeActions=0;lockActions=0}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $Control 'root-preflight.json') -Encoding UTF8
$PreflightHash=(Get-FileHash -LiteralPath (Join-Path $Control 'root-preflight.json')).Hash.ToLowerInvariant();[ordered]@{kind='factory-rectangle-centered-admission-pins-v1';count=$Count;namespace=$Capture;controlRoot=$Control;templateHash=$Pin;preflightHash=$PreflightHash;coordinatorPath=(Join-Path $M.roots.overlay '@@COORDINATOR@@');sourceInputsHash=$C.sourceInputsHash;issuedMetadataHash=$C.issuedMetadataHash;compileReceiptHash=$C.compileReceiptHash;exeHash=$C.exeHash;nativeActions=0;lockActions=0}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Control 'native-entry-pins.json') -Encoding UTF8
[ordered]@{status='source-admission-closed';count=$Count;controlRoot=$Control;templateHash=$Pin;preflightHash=$PreflightHash;sourceInputsHash=$C.sourceInputsHash;issuedMetadataHash=$C.issuedMetadataHash;nativeActions=0;lockActions=0}|ConvertTo-Json
'''
count1_path=a.count1_proof_remote_path if proof_path else '';count1_hash=proof_hash or ''
for k,v in {'@@NS@@':new_ns,'@@ZIP@@':zip_path.relative_to(REPO/'.factory-work').as_posix().replace('/','\\'),'@@COUNT@@':str(a.count),'@@PLAN_HASH@@':plan_hash,'@@BASE_PLAN_HASH@@':'980b212bbdbda14623cfa6cde416c0af959246c574bbb3074599b9959d2991a8','@@ZIP_HASH@@':sha(rd(zip_path)),'@@CONTROL_TAG@@':('control-count1-r'+str(a.revision)) if a.count==1 else ('control-count20-r'+str(a.revision)),'@@RUN_ROOT@@':new_ns+'\\native\\'+('count1-r1' if a.count==1 else 'count20-r1'),'@@NATIVE_ROOT@@':new_ns+'\\native','@@COORDINATOR@@':'coordinator-count1-v3.ps1' if a.count==1 else 'coordinator-count20-v1.ps1'}.items():script=script.replace(k,v)
entry = r"""$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Root='@@NS@@';$Control='@@CONTROL@@';$Template=Join-Path $Control 'config-template.json';$PinsPath=Join-Path $Control 'native-entry-pins.json';$Preflight=Join-Path $Control 'root-preflight.json';$Coordinator='@@COORDINATOR_PATH@@';$ExpectedCount=@@COUNT@@
if(-not(Test-Path -LiteralPath $PinsPath)){throw 'closed source admission pins missing'};$Pins=Get-Content -LiteralPath $PinsPath -Raw|ConvertFrom-Json
if((Get-FileHash -LiteralPath $Template).Hash.ToLowerInvariant() -ne $Pins.templateHash){throw 'closed template drift'}
if((Get-FileHash -LiteralPath $Preflight).Hash.ToLowerInvariant() -ne $Pins.preflightHash){throw 'closed preflight drift'};$P=Get-Content -LiteralPath $Preflight -Raw|ConvertFrom-Json
if($P.status -ne 'preflight-passed' -or $P.nativeActions -ne 0 -or $P.lockActions -ne 0){throw 'closed source admission required'}
$C=Get-Content -LiteralPath $Template -Raw|ConvertFrom-Json;if($C.count -ne $ExpectedCount -or $C.runRoot -ne '@@RUN_ROOT@@' -or $C.outputRoot -ne '@@NATIVE_ROOT@@' -or $C.sourceInputsHash -ne $Pins.sourceInputsHash -or $C.issuedMetadataHash -ne $Pins.issuedMetadataHash){throw 'closed source pins mismatch'}
if((Get-FileHash -LiteralPath $C.sourceInputsPath).Hash.ToLowerInvariant() -ne $C.sourceInputsHash){throw 'source inputs drift'};if((Get-FileHash -LiteralPath $C.issuedMetadataPath).Hash.ToLowerInvariant() -ne $C.issuedMetadataHash){throw 'issued metadata drift'};$I=Get-Content -LiteralPath $C.issuedMetadataPath -Raw|ConvertFrom-Json
if($I.expectedCount -ne $ExpectedCount -or $I.compile.sha256 -ne ('sha256:'+$C.compileReceiptHash) -or $I.exe.sha256 -ne ('sha256:'+$C.exeHash)){throw 'issued metadata pins mismatch'}
if($ExpectedCount -eq 20){$First='@@COUNT1_PATH@@';if((Get-FileHash -LiteralPath $First).Hash.ToLowerInvariant() -ne '@@COUNT1_HASH@@'){throw 'fresh Count1 prerequisite drift'};$F=Get-Content -LiteralPath $First -Raw|ConvertFrom-Json;if($F.count -ne 1 -or $F.status -ne 'completed-source-bound-observation' -or -not $F.lockReleased -or -not $F.wholeBatchExitConfirmed -or @($F.cleanupErrors).Count -ne 0){throw 'fresh Count1 prerequisite missing'}}
& $Coordinator -Template $Template -TemplateHash $Pins.templateHash
Get-Content -LiteralPath (Join-Path $Control 'coordinator.json') -Raw
"""
archive = r"""$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Root='@@NS@@';$Control='@@CONTROL@@';$Count=@@COUNT@@;$Tag='@@COUNT_TAG@@';$Zip=Join-Path $Root ('actual-native-centered-count'+$Count+'.zip');$Manifest=Join-Path $Root ('actual-native-centered-count'+$Count+'-manifest.json')
if(Test-Path -LiteralPath $Zip){throw 'fresh native archive required'};$Co=Get-Content -LiteralPath (Join-Path $Control 'coordinator.json') -Raw|ConvertFrom-Json
if($Co.status -ne 'completed-source-bound-observation' -or $Co.count -ne $Count -or -not $Co.lockReleased -or -not $Co.wholeBatchExitConfirmed -or @($Co.cleanupErrors).Count -ne 0 -or $Co.taskParentProof.kernelWait -ne 0 -or $Co.taskParentProof.kernelExitCode -ne 0 -or $Co.taskParentProof.dotNetExitCode -ne 0){throw 'fresh native completion required'}
$C=Get-Content -LiteralPath (Join-Path $Control 'config-template.json') -Raw|ConvertFrom-Json;$Rows=@();$Total=[int64]0
foreach($Rel in @((Split-Path -Leaf $Control),(Join-Path 'native' ('count'+$Count+'-r1')))){foreach($F in @(Get-ChildItem -LiteralPath (Join-Path $Root $Rel) -File -Recurse)){$Total+=$F.Length;if($Rows.Count -ge 1600 -or $F.Length -gt 16777216 -or $Total -gt 33554432 -or ($F.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'archive size/path cap'};$Rows+=@([ordered]@{path=$F.FullName.Substring($Root.Length+1).Replace('\','/');bytes=[int64]$F.Length;sha256=(Get-FileHash -LiteralPath $F.FullName).Hash.ToLowerInvariant()})}}
Add-Type -AssemblyName System.IO.Compression;Add-Type -AssemblyName System.IO.Compression.FileSystem;$Z=[IO.Compression.ZipFile]::Open($Zip,[IO.Compression.ZipArchiveMode]::Create);try{foreach($R in $Rows){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Z,(Join-Path $Root $R.path),$R.path,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}}finally{$Z.Dispose()}
$M=[ordered]@{kind='factory-rectangle-centered-actual-native-archive-v1';root=$Root;count=$Count;files=$Rows;bytes=$Total;zipBytes=(Get-Item -LiteralPath $Zip).Length;zipSha256=(Get-FileHash -LiteralPath $Zip).Hash.ToLowerInvariant();sourceInputsHash=$C.sourceInputsHash;exeHash=$Co.exeHash;compileReceiptHash=$Co.compileReceiptHash;lockReleased=$Co.lockReleased;qualified=$false};$M|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $Manifest -Encoding UTF8
[ordered]@{count=$Count;files=$Rows.Count;bytes=$Total;manifestSha256=(Get-FileHash -LiteralPath $Manifest).Hash.ToLowerInvariant();zipSha256=$M.zipSha256;qualified=$false}|ConvertTo-Json
"""
for _k,_v in {'@@NS@@':new_ns,'@@CONTROL@@':new_ns+'\\'+('control-count1-r'+str(a.revision) if a.count==1 else 'control-count20-r'+str(a.revision)),'@@COORDINATOR_PATH@@':new_roots['overlay']+'\\'+('coordinator-count1-v3.ps1' if a.count==1 else 'coordinator-count20-v1.ps1'),'@@COUNT@@':str(a.count),'@@RUN_ROOT@@':new_ns+'\\native\\'+('count1-r1' if a.count==1 else 'count20-r1'),'@@NATIVE_ROOT@@':new_ns+'\\native','@@COUNT1_PATH@@':count1_path,'@@COUNT1_HASH@@':count1_hash,'@@COUNT_TAG@@':('count1-r'+str(a.revision) if a.count==1 else 'count20-r'+str(a.revision))}.items():
    entry=entry.replace(_k,_v);archive=archive.replace(_k,_v)
entry_path=out/f'native-entry-centered-count{a.count}-r{a.revision}.ps1';archive_path=out/f'archive-native-centered-count{a.count}-r{a.revision}.ps1';entry_path.write_text(entry);archive_path.write_text(archive)
(out/f'install-centered-count{a.count}-r{a.revision}.ps1').write_text(script)
(out/'preparation.json').write_bytes(jd({'kind':stage['kind'],'count':a.count,'revision':a.revision,'planHash':plan_hash,'compileReceiptHash':receipt_hash,'exeHash':exe_hash,'sourceRows':len(files),'zip':str(zip_path),'count1ProofPath':count1_path or None,'count1ProofHash':count1_hash or None,'nativeActions':0,'compilerActions':0,'qualification':'pending-root-native-capture','nativeEntry':str(entry_path),'archiveNative':str(archive_path)}))
print(json.dumps({'output':str(out),'installer':str(out/f'install-centered-count{a.count}-r{a.revision}.ps1'),'zip':str(zip_path),'count':a.count,'planHash':'sha256:'+plan_hash,'compileReceiptHash':'sha256:'+receipt_hash,'exeHash':'sha256:'+exe_hash,'nativeActions':0,'nativeEntry':str(entry_path),'archiveNative':str(archive_path)}))
