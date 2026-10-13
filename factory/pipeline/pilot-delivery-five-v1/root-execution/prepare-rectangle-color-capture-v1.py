"""Rebind proven Count1 MTA capture to freshly compiled color-corrected host."""
from pathlib import Path
import base64
import argparse
import hashlib
import json
import subprocess
import zipfile

repo=Path('/Volumes/D/claude/swiftright')
cache=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/git-root')
build=repo/'factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-color-build-r2'
p=argparse.ArgumentParser();p.add_argument('--revision',type=int,choices=range(1,6),default=1);p.add_argument('--count',type=int,choices=(1,20),default=1);args=p.parse_args()
count=args.count
old_tag='count1-r12' if count==1 else 'count20-r4'
new_tag='count1-r1' if count==1 else 'count20-r1'
coordinator='coordinator-count1-v3.ps1' if count==1 else 'coordinator-count20-v1.ps1'
donor=repo/('factory/native/windows/pilot-rectangle-fixed-root-v2/capture-'+old_tag+'-sources')
out=repo/('factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-color-capture-'+('r' if count==1 else 'count20-r')+str(args.revision))
out.mkdir()
actual=out/'compile-actual';actual.mkdir()
def rd(p,cap=4194304):
    assert p.is_file() and not p.is_symlink() and p.stat().st_size<=cap
    return p.read_bytes()
def sha(b):return hashlib.sha256(b).hexdigest()
def jd(d):return (json.dumps(d,indent=2,sort_keys=True)+'\n').encode()
for n in ('observation.json','compile.stdout.bin','compile.stderr.bin'):
    subprocess.run(['scp','-q','win:D:/Claude/swiftright/.factory-work/hosts/rectangle/final-r3/'+n,str(actual/n)],check=True,timeout=15)
receipt_raw=rd(actual/'observation.json');receipt=json.loads(receipt_raw.decode('utf-8-sig'))
plan_raw=rd(build/'plan-final-v4.json');plan=json.loads(plan_raw)
assert receipt['exitCode']==0 and receipt['kernelWait']==0 and receipt['originalHandleRetained'] and receipt['ownedExited']
assert receipt['streamsSealed'] and receipt['streamDrainComplete'] and receipt['jobActiveCount']==receipt['cleanupJobActive']==0
assert receipt['planSha256']==sha(plan_raw) and 'sha256:'+receipt['exeSha256']==plan['expectedHostHash']
for stream in ('stdout','stderr'):
    b=rd(actual/('compile.'+stream+'.bin'))
    assert len(b)==receipt[stream+'Bytes'] and sha(b)==receipt[stream+'Sha256']
old_ns=r'D:\Claude\swiftright\factory\native\windows\.work\rectangle-fixed-r11-v2'
new_ns=r'D:\Claude\swiftright\.factory-work\hosts\rectangle\captures\color-'+('r' if count==1 else 'count20-r')+str(args.revision)
host=r'D:\Claude\swiftright\.factory-work\hosts\rectangle'
changes={old_ns:new_ns,old_tag:new_tag,
 '980b212bbdbda14623cfa6cde416c0af959246c574bbb3074599b9959d2991a8':sha(plan_raw),
 '21b08f393d3c1bc9650b960a5b32aea01be826c704ebf7b8cb52e1d62d32cd0c':sha(receipt_raw),
 '62aa7d5b9a5b9001d697822d26b2d102d8934de1de4a02103f810e756f71af66':receipt['exeSha256'],
 'sr1-rectangle-fixedviewport-v2-r11-paired20-20261011':plan['tuple']['id'],
 host+r'\final-r2':host+r'\final-r3',
 'final-r2\\':'final-r3\\',
 host+r'\preflight-capture-v2.ps1':new_ns+r'\overlay-'+new_tag+r'\preflight-color-r1.ps1',
}
def relocate(v):
    if isinstance(v,str):
        for a,b in changes.items():v=v.replace(a,b)
        return v
    if isinstance(v,list):return [relocate(x) for x in v]
    if isinstance(v,dict):return {k:relocate(x) for k,x in v.items()}
    return v
manifest=json.loads(rd(donor/'stage-manifest.json'))
assert len(manifest['files'])<=128 and sum(x['bytes'] for x in manifest['files'])<=4194304
files={}
for row in manifest['files']:
    rel=row['path'];assert '..' not in Path(rel).parts and not Path(rel).is_absolute()
    b=rd(donor/rel);assert len(b)==row['bytes'] and sha(b)==row['sha256']
    if rel.endswith('.json'):b=jd(relocate(json.loads(b.decode('utf-8-sig'))))
    elif rel.endswith('.ps1'):b=relocate(b.decode()).encode()
    files[rel]=b
if args.revision >= 3 or count==20:
    old_prefix = 'D:\\Claude\\swiftright\\factory\\native\\windows\\'
    # A fresh host namespace needs an equally narrow worker namespace.
    prefix = new_ns + '\\native\\'
    pins = {}
    for rel in ('overlay/uia-worker-invoke-v2.ps1',
                'producer/dependencies/uia-worker/invoke-worker-mta.ps1',
                'producer/dependencies/uia-worker/invoke-worker.ps1',
                'producer/dependencies/uia-worker/worker.ps1'):
        text = files[rel].decode()
        assert text.count(old_prefix) == 1
        previous = files[rel]
        files[rel] = text.replace(old_prefix, prefix).encode()
        pins[sha(previous)] = (sha(files[rel]), len(files[rel]))
    rel = 'producer/dependencies/uia-worker/worker-contract.json'
    previous_contract = files[rel]
    contract = json.loads(files[rel])
    for row in contract['sourceBindings']:
        data = files['producer/dependencies/uia-worker/' + row['path']]
        row.update(bytes=len(data), sha256=sha(data))
    files[rel] = jd(contract)
    pins[sha(previous_contract)] = (sha(files[rel]), len(files[rel]))
    def repin(v):
        if isinstance(v, str):
            for old, (new, _) in pins.items():
                v = v.replace(old, new)
            return v
        if isinstance(v, list):
            return [repin(x) for x in v]
        if isinstance(v, dict):
            old = str(v.get('sha256', '')).replace('sha256:', '')
            changed = {k: repin(x) for k, x in v.items()}
            if old in pins and 'bytes' in changed:
                changed['bytes'] = pins[old][1]
            return changed
        return v
    for rel, data in list(files.items()):
        if rel.endswith('.json'):
            files[rel] = jd(repin(json.loads(data.decode('utf-8-sig'))))
        elif rel.endswith('.ps1'):
            files[rel] = repin(data.decode()).encode()
preflight=relocate(rd(repo/'factory/native/windows/pilot-rectangle-fixed-root-v2/preflight-capture-v2.ps1').decode()).encode()
files['overlay/preflight-color-r1.ps1']=preflight
context=json.loads(files['admission/context.json']);context['windowsHostHash']=plan['expectedHostHash'];context['tupleID']=plan['tuple']['id'];files['admission/context.json']=jd(context)
tu=json.loads(files['admission/candidate-tuple.json']);tu['tuple']=plan['tuple'];tu['sourceInputs']['compiledPlan'].update(bytes=len(plan_raw),sha256='sha256:'+sha(plan_raw));tu['sourceInputs']['context'].update(bytes=len(files['admission/context.json']),sha256='sha256:'+sha(files['admission/context.json']));files['admission/candidate-tuple.json']=jd(tu)
binding=json.loads(files['admission/candidate-binding.json']);binding['canonicalTupleRef'].update(bytes=len(files['admission/candidate-tuple.json']),sha256='sha256:'+sha(files['admission/candidate-tuple.json']));files['admission/candidate-binding.json']=jd(binding)
cp=json.loads(files['producer/capture-plan.json']);cp['tuple']=plan['tuple'];files['producer/capture-plan.json']=jd(cp)
bindings=json.loads(files['producer/integration-bindings.json'])
for row in bindings['files']:
    data=files['producer/'+row['path']];row['bytes']=len(data);row['sha256']=sha(data)
files['producer/integration-bindings.json']=jd(bindings)
si=json.loads(files['admission/source-inputs.json'])
si['planRef'].update(bytes=len(plan_raw),sha256='sha256:'+sha(plan_raw));si['compileRef'].update(bytes=len(receipt_raw),sha256='sha256:'+sha(receipt_raw))
si['exeRef'].update(bytes=receipt['exeBytes'],sha256=plan['expectedHostHash'])
si['buildPreflightHash']=sha(preflight);si['capturePlanHash']=sha(files['producer/capture-plan.json'])
for name,rel in [('contextRef','admission/context.json'),('tupleRef','admission/candidate-tuple.json'),('bindingRef','admission/candidate-binding.json'),('recipeRef','admission/recipe.json'),('integrationBindingsRef','producer/integration-bindings.json')]:
    si[name].update(bytes=len(files[rel]),sha256='sha256:'+sha(files[rel]))
for name,ref in [('tupleHash','tupleRef'),('bindingHash','bindingRef'),('recipeHash','recipeRef'),('integrationBindingsHash','integrationBindingsRef')]:si[name]=si[ref]['sha256'][7:]
files['admission/source-inputs.json']=jd(si)
config=relocate(json.loads(rd(repo/('factory/native/windows/pilot-rectangle-fixed-root-v2/actual-'+old_tag+'/control/config-template.json')).decode('utf-8-sig')))
config['issuedMetadataHash']=None;config['sourceInputsHash']=sha(files['admission/source-inputs.json'])
config['integrationGuardHash']=sha(files['overlay/integration-fresh-rectangle-v1.ps1'])
config['sourceBindings']=[{'path':n[8:],'bytes':len(b),'sha256':sha(b)} for n,b in files.items() if n.startswith('overlay/')]
for n,b in files.items():
    dest=out/'sources'/n;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b)
roots={k:new_ns+'\\'+k+'-'+new_tag for k in ('producer','admission','overlay')}
rows=[{'path':n,'bytes':len(b),'sha256':sha(b)} for n,b in files.items()]
stage={'kind':'factory-rectangle-color-source-stage-v1','files':rows,'roots':roots,'count':count,'nativeActions':0,'compilerActions':0,'lockActions':0}
files['stage-manifest.json']=jd(stage)
(out/'sources/stage-manifest.json').write_bytes(files['stage-manifest.json'])
z=cache/('rectangle-color-count'+str(count)+'-r'+str(args.revision)+'.zip')
with zipfile.ZipFile(z,'x',zipfile.ZIP_DEFLATED) as a:
    for n,b in files.items():a.writestr(n,b)
script=r'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Stage='D:\Claude\swiftright\.factory-work\hosts\rectangle';$Capture='__NS__'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native stage busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop busy for rolling capture stage'}
if(Test-Path -LiteralPath $Capture){throw 'fresh capture stage required'}
$OldPlan=Join-Path $Stage 'package\plan.json'
$CurrentPlanHash=(Get-FileHash -LiteralPath $OldPlan).Hash.ToLowerInvariant()
if($CurrentPlanHash -ceq '980b212bbdbda14623cfa6cde416c0af959246c574bbb3074599b9959d2991a8'){
 Copy-Item -LiteralPath $OldPlan -Destination 'D:\Claude\swiftright\.factory-work\retired\rectangle-color-source-r1\plan-capture-base.json'
 Copy-Item -LiteralPath (Join-Path $Stage 'package\plan-final-v4.json') -Destination $OldPlan
}elseif($CurrentPlanHash -cne '__PLAN_HASH__'){throw 'previous capture plan drift'}
if((Get-FileHash -LiteralPath $OldPlan).Hash.ToLowerInvariant() -cne '__PLAN_HASH__'){throw 'new capture plan drift'}
$Zip='D:\Claude\swiftright\.factory-work\__ZIP_NAME__'
if((Get-FileHash -LiteralPath $Zip).Hash.ToLowerInvariant() -cne '__ZIP_HASH__'){throw 'zip drift'}
$Temp=Join-Path $Capture 'source-stage';Expand-Archive -LiteralPath $Zip -DestinationPath $Temp
$M=Get-Content -LiteralPath (Join-Path $Temp 'stage-manifest.json') -Raw|ConvertFrom-Json
foreach($Row in @($M.files)){$F=Join-Path $Temp $Row.path;if((Get-Item -LiteralPath $F).Length -ne $Row.bytes -or (Get-FileHash -LiteralPath $F).Hash.ToLowerInvariant() -cne $Row.sha256){throw 'stage byte drift'}}
foreach($N in @('producer','admission','overlay')){[IO.Directory]::CreateDirectory($M.roots.$N)|Out-Null;Copy-Item -Path (Join-Path $Temp ($N+'\*')) -Destination $M.roots.$N -Recurse}
$Control=Join-Path $Capture 'control-count1-r1';[IO.Directory]::CreateDirectory($Control)|Out-Null
foreach($Row in @($M.files|Where-Object {$_.path.StartsWith('overlay/') -and $_.path.EndsWith('.ps1')})){$T=$null;$E=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $M.roots.overlay $Row.path.Substring(8)),[ref]$T,[ref]$E);if($E.Count){throw ($E|Out-String)}}
$Source=Join-Path $M.roots.admission 'source-inputs.json';$Si=Get-Content -LiteralPath $Source -Raw|ConvertFrom-Json;$Guard=Join-Path $M.roots.overlay 'integration-fresh-rectangle-v1.ps1'
& (Join-Path $M.roots.overlay 'test-rectangle-integration-controls.ps1') -GuardPath $Guard -Root $M.roots.producer -SourceInputsPath $Source|Out-File (Join-Path $Control 'integration-controls.json') -Encoding UTF8
& (Join-Path $M.roots.overlay 'test-uia-mta-controls.ps1') -WorkerPath (Join-Path $M.roots.producer 'dependencies\uia-worker\worker.ps1') -InvokerPath (Join-Path $M.roots.overlay 'uia-worker-invoke-v2.ps1') -SchemaPath (Join-Path $M.roots.producer 'dependencies\uia-worker\schema.ps1')|Out-File (Join-Path $Control 'uia-mta-controls.json') -Encoding UTF8
& (Join-Path $M.roots.overlay 'test-mta-config-admission.ps1') -OutputPath (Join-Path $Control 'mta-config-controls.json')
. $Guard;Assert-FactoryIntegrationSources $M.roots.producer $Si|Out-Null
$Par=@{Count=1;SourceInputsPath=$Source;SourceInputsHash='__SOURCE_HASH__';OutputPath=(Join-Path $M.roots.admission 'issued-metadata.json');RunRoot='__RUN__';PlanPath=$Si.planRef.path;PlanHash=$Si.planHash;CompileReceiptPath=$Si.compileRef.path;CompileReceiptHash=$Si.compileReceiptHash;ExePath=$Si.exeRef.path;ExeHash=$Si.exeHash;RendererPath=$Si.rendererRef.path;RendererHash=$Si.rendererSha256;SerializerPath=$Si.serializerRef.path;SerializerHash=$Si.serializerControlSha256;TuplePath=$Si.tupleRef.path;TupleHash=$Si.tupleHash;BindingPath=$Si.bindingRef.path;BindingHash=$Si.bindingHash;RecipePath=$Si.recipeRef.path;RecipeHash=$Si.recipeHash}
& (Join-Path $M.roots.overlay 'issue-rectangle-metadata-v1.ps1') @Par
$C='__CONFIG__'|ConvertFrom-Json;$C.issuedMetadataHash=(Get-FileHash -LiteralPath $C.issuedMetadataPath).Hash.ToLowerInvariant();$Template=Join-Path $Control 'config-template.json';$C|ConvertTo-Json -Depth 32|Set-Content -LiteralPath $Template -Encoding UTF8;$Pin=(Get-FileHash -LiteralPath $Template).Hash.ToLowerInvariant()
& (Join-Path $M.roots.overlay 'coordinator-count1-v3.ps1') -Template $Template -TemplateHash $Pin -PreflightOnly
[ordered]@{status='preflight-passed';templatePath=$Template;templateHash=$Pin;sourceInputsHash=$C.sourceInputsHash;issuedMetadataHash=$C.issuedMetadataHash;nativeActions=0;lockActions=0}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $Control 'root-preflight.json') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $Control 'root-preflight.json') -Raw
'''
for key,val in {'NS':new_ns,'PLAN_HASH':sha(plan_raw),'ZIP_NAME':z.name,'ZIP_HASH':sha(rd(z)),'SOURCE_HASH':config['sourceInputsHash'],'RUN':config['runRoot'],'CONFIG':json.dumps(config,separators=(',',':'))}.items():script=script.replace('__'+key+'__',val)
first_proof=None;first_proof_hash=None;first_proof_path=None;first_proof_source_inputs_hash=None
if count==20:
    script=script.replace('control-count1-r1','control-'+new_tag).replace("Count=1;SourceInputsPath", "Count=20;SourceInputsPath").replace('coordinator-count1-v3.ps1',coordinator)
    first=out/'first-count1-actual.json'
    subprocess.run(['scp','-q','win:D:/Claude/swiftright/.factory-work/hosts/rectangle/captures/color-r5/control-count1-r1/coordinator.json',str(first)],check=True,timeout=15)
    proof=json.loads(rd(first).decode('utf-8-sig'))
    assert proof['count']==1 and proof['status']=='completed-source-bound-observation' and proof['lockReleased'] and proof['wholeBatchExitConfirmed'] and not proof['cleanupErrors']
    assert proof['exeHash']==receipt['exeSha256'] and proof['compileReceiptHash']==sha(receipt_raw)
    assert proof['taskParentProof']['kernelWait']==proof['taskParentProof']['kernelExitCode']==proof['taskParentProof']['dotNetExitCode']==0
    first_proof=proof;first_proof_hash=sha(rd(first));first_proof_path=r'D:\Claude\swiftright\.factory-work\hosts\rectangle\captures\color-r5\control-count1-r1\coordinator.json';first_proof_source_inputs_hash=proof['sourceInputsHash']
    guard="\n$First='D:\\Claude\\swiftright\\.factory-work\\hosts\\rectangle\\captures\\color-r5\\control-count1-r1\\coordinator.json'\nif((Get-FileHash -LiteralPath $First).Hash.ToLowerInvariant() -cne '"+sha(rd(first))+"'){throw 'fresh Count1 proof drift'}\n"
    script=script.replace("$Stage='D:\\Claude\\swiftright\\.factory-work\\hosts\\rectangle';", guard+"$Stage='D:\\Claude\\swiftright\\.factory-work\\hosts\\rectangle';",1)
install_name='install-count1-r1.ps1' if count==1 else 'install-count20-r1.ps1'
(out/install_name).write_text(script)
(out/'preparation.json').write_bytes(jd({'kind':stage['kind'],'count':count,'rows':len(rows),'compileReceiptHash':sha(receipt_raw),'exeHash':receipt['exeSha256'],'planHash':sha(plan_raw),'sourceInputsHash':config['sourceInputsHash'],'sourceHash':si['sourceHash'],'serializerControlSha256':si['serializerControlSha256'],'firstCount1ProofPath':first_proof_path,'firstCount1ProofHash':first_proof_hash,'firstCount1SourceInputsHash':first_proof_source_inputs_hash,'firstCount1CompileReceiptHash':None if first_proof is None else first_proof['compileReceiptHash'],'firstCount1ExeHash':None if first_proof is None else first_proof['exeHash'],'nativeActions':0,'lockActions':0,'qualification':'pending-root-capture'}))
subprocess.run(['scp','-q',str(z),'win:D:/Claude/swiftright/.factory-work/'+z.name],check=True,timeout=20)
print(json.dumps({'installer':str(out/install_name),'rows':len(rows),'zipBytes':z.stat().st_size,'nativeActions':0}))
