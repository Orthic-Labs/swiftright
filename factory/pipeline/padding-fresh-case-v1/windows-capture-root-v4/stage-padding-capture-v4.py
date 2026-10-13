#!/usr/bin/env python3
"""Windows-only source staging for fresh Padding capture.

Consumes explicit measured plan/receipt paths, preserves donor producer closure,
& emits no compiler/native/scheduler/desktop-lock action.
"""
from __future__ import annotations
import argparse, hashlib, json, os, re, shutil, stat
from pathlib import Path

MAX_FILE=64*1024*1024; MAX_JSON=2*1024*1024; MAX_TOTAL=128*1024*1024
class Hold(ValueError): pass

def digest(p:Path, limit=MAX_FILE):
    st=p.lstat()
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode) or st.st_size>limit: raise Hold(f'invalid/bounded file: {p}')
    h=hashlib.sha256(); n=0
    with p.open('rb') as f:
        while True:
            b=f.read(1024*1024)
            if not b: break
            n+=len(b); h.update(b)
            if n>limit: raise Hold(f'file grew: {p}')
    if n!=st.st_size: raise Hold(f'file changed: {p}')
    return h.hexdigest(),n

def readj(p,label):
    h,n=digest(p,MAX_JSON)
    try: d=json.loads(p.read_text(encoding='utf-8-sig'))
    except Exception as e: raise Hold(f'{label} invalid JSON') from e
    if not isinstance(d,dict): raise Hold(f'{label} object required')
    return d,h,n

def abs_win(p):
    s=os.path.abspath(str(p))
    if not os.path.isabs(s): raise Hold(f'absolute Windows path required: {p}')
    return s

def ref(p,label,limit=MAX_FILE):
    h,n=digest(p,limit); return {'path':abs_win(p),'sha256':'sha256:'+h,'bytes':n,'role':label}

def nested(d,key):
    if key in d: return d[key]
    for k in ('kernel','job','cleanup','process','streams','memory'):
        x=d.get(k)
        if isinstance(x,dict) and key in x: return x[key]
    return None

def copy_checked(src,dst,limit=MAX_FILE):
    h,n=digest(src,limit); dst.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(src,dst)
    h2,n2=digest(dst,limit)
    if (h,n)!=(h2,n2): raise Hold(f'copy changed: {src}')
    return h,n

def reseal_manifest(path, root):
    """Reseal donor-style manifest after every producer patch."""
    try: d=json.loads(path.read_text(encoding='utf-8-sig'))
    except Exception as e: raise Hold(f'manifest invalid: {path}') from e
    files=d.get('files')
    if not isinstance(files,list): raise Hold(f'manifest files missing: {path}')
    out=[]
    for row in files:
        if not isinstance(row,dict) or not isinstance(row.get('path'),str): raise Hold('manifest row malformed')
        rp=row['path'].replace('\\','/')
        if rp.startswith('producer/'):
            src=root/Path(rp[len('producer/'):])
            h,n=digest(src)
            out.append({'path':row['path'],'sha256':'sha256:'+h,'bytes':n})
        else: out.append(row)
    d['files']=out
    path.write_text(json.dumps(d,indent=2)+'\n',encoding='utf-8')
    return digest(path,MAX_JSON)

def patch_producer(stage, cap, binding_hash, canonical_hash, package_path):
    producer=stage/'producer'; capture=producer/'capture-repeat.ps1'; coordinator=producer/'coordinator.ps1'; issue=producer/'issue-before-launch.ps1'
    plan_hash=cap['compilePlanHash'].replace('sha256:',''); receipt_hash=cap['compileReceiptHash'].replace('sha256:','')
    def load(path):
        if not path.is_file(): raise Hold(f'producer source missing: {path}')
        return path.read_text(encoding='utf-8-sig')
    def save(path,s): path.write_text(s,encoding='utf-8')
    s=load(capture)
    s="$capturePlan=Get-Content -Raw (Join-Path $PSScriptRoot 'capture-plan.json')|ConvertFrom-Json\n"+s
    s=s.replace("if(-not $outputPath.StartsWith('D:\\Claude\\swiftright\\factory\\native\\windows\\padding-capture-lease-capture-v1\\',[StringComparison]::OrdinalIgnoreCase)){throw 'Output outside first capture lane'}", "if(-not $outputPath.StartsWith(([IO.Path]::GetFullPath($PSScriptRoot)+'\\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Output outside fresh capture lane'}")
    old="if(-not $packagePath.StartsWith('D:\\Claude\\swiftright\\.factory-work\\hosts\\',[StringComparison]::OrdinalIgnoreCase)){throw 'Package outside compiled host workspace'}"
    if old not in s: raise Hold('capture package guard missing')
    s=s.replace(old,"if($packagePath -cne $capturePlan.compiledHostPackagePath){throw 'Exact measured operational package required'}")
    old="$approved=@{caseID='swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258';sourceHash='sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b';planHash='ee83748cd42326e57676e47d8fec777bd8466706ba2c72a01eb9b5b71292de10';receiptRelative='build-capture-lease-r1\\observation.json'}"
    if old not in s: raise Hold('capture approved identity missing')
    s=s.replace(old,"$approved=@{caseID='"+cap['case']['id']+"';sourceHash='"+cap['sourceHash']+"';planHash='"+plan_hash+"';receiptRelative=$capturePlan.compileReceiptPath}")
    s=s.replace('$compiled.planSha256','$compiled.freshPlanSha256')
    s=s.replace("Join-Path $packagePath $receiptRelative", "$capturePlan.compileReceiptPath")
    s=s.replace("Join-Path $packagePath 'plan.json'", "$capturePlan.compilePlanPath")
    s=s.replace("Join-Path $plan.compiledHostPackagePath 'build-capture-lease-r1\\observation.json'", "$capturePlan.compileReceiptPath")
    s=re.sub(r"if\(\(Get-FileHash -LiteralPath \(Join-Path \$PSScriptRoot 'integration-bindings\.json'\)\)\.Hash\.ToLowerInvariant\(\) -cne '[0-9a-f]{64}'\)\{throw 'Integration binding manifest drift'\}", "if(-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'integration-bindings.json') -PathType Leaf)){throw 'Integration binding manifest missing'}", s)
    s=s.replace("if($plan.runtimeSourceCommit -ne '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'", "if($plan.runtimeSourceCommit -ne '"+str(cap.get('runtimeSourceCommit',''))+"'")
    s=s.replace("Join-Path $package $approved.receiptRelative", "$capturePlan.compileReceiptPath")
    save(capture,s)
    s=load(coordinator); s="$capturePlan=Get-Content -Raw (Join-Path $PSScriptRoot 'capture-plan.json')|ConvertFrom-Json\n"+s
    old="$expectedHere='D:\\Claude\\swiftright\\factory\\native\\windows\\padding-capture-lease-capture-v1'\nif($here -cne $expectedHere){throw 'Exact capture coordinator lane required'}"
    if old not in s: raise Hold('coordinator root guard missing')
    s=s.replace(old,"if(-not (Test-Path -LiteralPath (Join-Path $here 'capture-plan.json') -PathType Leaf)){throw 'Fresh capture coordinator lane required'}")
    s=s.replace('$compiled.planSha256','$compiled.freshPlanSha256'); s=s.replace("Join-Path $package $approved.receiptRelative", "$capturePlan.compileReceiptPath")
    s=s.replace("$receiptPath=Join-Path $plan.compiledHostPackagePath 'build-capture-lease-r1\\observation.json'", "$receiptPath=$capturePlan.compileReceiptPath")
    save(coordinator,s)
    s=load(issue)
    old="$builder='D:\\Claude\\swiftright\\.factory-work\\hosts\\padding-window-diagnosis'\n$metadataRoot=Join-Path $builder 'metadata'\n$preflight=Join-Path $builder 'preflight.ps1'"
    if old not in s: raise Hold('issue builder source missing')
    s=s.replace(old,"$capturePlan=Get-Content -Raw (Join-Path $PSScriptRoot 'capture-plan.json')|ConvertFrom-Json\n$builder=Split-Path -Parent $capturePlan.compiledHostPackagePath\n$metadataRoot=Join-Path $PSScriptRoot 'metadata'\n$preflight=$capturePlan.launchPreflightPath")
    s=s.replace("$allowedRoot='D:\\Claude\\swiftright\\factory\\native\\windows\\padding-capture-lease-capture-v1\\'", "$allowedRoot=([IO.Path]::GetFullPath($PSScriptRoot)+'\\')")
    s=s.replace("if((Get-FileHash -LiteralPath $preflight).Hash.ToLowerInvariant() -cne '37ed4ec43f7b3e27db423d1b5564155ec58b0d5c61b021fa602a5919ebd15c6b'){throw 'Exact lease launch preflight required'}", "if((Get-FileHash -LiteralPath $preflight).Hash.ToLowerInvariant() -cne $capturePlan.launchPreflightSha256.Replace('sha256:','')){throw 'Exact fresh launch preflight required'}")
    s=s.replace("$package=Join-Path $builder 'package';$planPath=Join-Path $package 'plan.json';$plan=Get-Content -Raw $planPath|ConvertFrom-Json", "$package=$capturePlan.compiledHostPackagePath;$planPath=$capturePlan.compilePlanPath;$plan=Get-Content -Raw $planPath|ConvertFrom-Json")
    s=s.replace("$receiptPath=Join-Path $package 'build-capture-lease-r1\\observation.json';$receipt=Get-Content -Raw $receiptPath|ConvertFrom-Json", "$receiptPath=$capturePlan.compileReceiptPath;$receipt=Get-Content -Raw $receiptPath|ConvertFrom-Json")
    s=s.replace("$capturePlan.compiledHostPackagePath+'\\plan.json'", "$capturePlan.compilePlanPath")
    s=s.replace("$capturePlan.compiledHostPackagePath+'\\build-capture-lease-r1\\observation.json'", "$capturePlan.compileReceiptPath")
    s=s.replace("$bindingPath=Join-Path $metadataRoot 'source-binding.json'", "$bindingPath=Join-Path $metadataRoot 'source-binding.json';$tuplePath=Join-Path (Split-Path -Parent $PSScriptRoot) 'fresh-inputs\\tuple.json'")
    s=s.replace('sourceBoundCandidateTuple=Raw-Ref $bindingPath;producedRuntimeModules','sourceBoundCandidateTuple=Raw-Ref $bindingPath;candidateTuple=Raw-Ref $tuplePath;producedRuntimeModules')
    s=s.replace("if((Get-FileHash -LiteralPath (Join-Path $metadataRoot 'source-binding.json')).Hash.ToLowerInvariant() -cne '21fe0b64c8d9d5886fb4c2470274959793b5c7a53d31039d862947b20a8dd4c4' -or (Get-FileHash -LiteralPath (Join-Path $metadataRoot 'canonical-inputs-manifest.json')).Hash.ToLowerInvariant() -cne '208689e04f06a0e397ccd611bb8aca3828e0cf7ec15fd7df0a4dab8436389efa')", "if((Get-FileHash -LiteralPath (Join-Path $metadataRoot 'source-binding.json')).Hash.ToLowerInvariant() -cne '"+binding_hash.replace('sha256:','')+"' -or (Get-FileHash -LiteralPath (Join-Path $metadataRoot 'canonical-inputs-manifest.json')).Hash.ToLowerInvariant() -cne '"+canonical_hash.replace('sha256:','')+"')")
    s=s.replace("Join-Path $package 'plan.json'", "$capturePlan.compilePlanPath").replace("Join-Path $package 'build-capture-lease-r1\\observation.json'", "$capturePlan.compileReceiptPath")
    save(issue,s)
    # Replace metadata validator with one that consumes explicit measured refs, never package-relative receipt.
    integ=producer/'support'/'integration.ps1'; s=load(integ)
    start=s.find('function Assert-LeaseIssuedMetadata'); end=s.find('function Test-FactoryParentOrdering',start)
    if start<0 or end<0: raise Hold('integration validator missing')
    body="""function Assert-LeaseIssuedMetadata([string]$Path,[string]$Hash,[string]$RunRoot,[int]$Count,[string]$CompileHash,[string]$ExeHash,[string]$SerializerHash){
 $captureRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot));$capturePlan=Get-Content -Raw (Join-Path $captureRoot 'capture-plan.json')|ConvertFrom-Json
 if($Hash -cnotmatch '^[0-9a-f]{64}$' -or (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant() -cne $Hash){throw 'Issued metadata raw hash mismatch'}
 $m=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json
 if($m.kind -cne 'factory-prelaunch-capture-metadata-v2' -or $m.runRoot -cne $RunRoot -or $m.expectedCount -ne $Count -or $m.frozenTupleBound -or $m.compile.sha256 -ne ('sha256:'+$CompileHash) -or $m.exe.sha256 -ne ('sha256:'+$ExeHash) -or $m.serializerControlSha256 -ne $SerializerHash -or @($m.hostArguments).Count -ne 1 -or $m.hostArguments[0] -cne '--factory-capture-lease-seconds=40'){throw 'Issued metadata admitted context mismatch'}
 $plan=Get-Content -Raw -LiteralPath $capturePlan.compilePlanPath|ConvertFrom-Json;$compiled=Get-Content -Raw -LiteralPath $capturePlan.compileReceiptPath|ConvertFrom-Json
 $compiledPlanHash=[string]$compiled.freshPlanSha256;if([string]::IsNullOrWhiteSpace($compiledPlanHash)){$compiledPlanHash=[string]$compiled.planSha256}
 if($m.sourceHash -cne $plan.sourceHash -or $m.case.id -cne $plan.case.id -or $m.case.hash -cne $plan.case.hash -or $m.historicalTemplateTupleClosed -or $m.qualification -cne 'sourceBoundCandidate-observation-only' -or $compiledPlanHash -ne $capturePlan.sourcePlanSha256.Replace('sha256:','')){throw 'Issued metadata fresh source identity mismatch'}
 foreach($pair in @(@('plan',$capturePlan.compilePlanPath),@('compile',$capturePlan.compileReceiptPath),@('exe',$capturePlan.operationalExePath),@('renderer',$capturePlan.renderer.rollingInputPath))){$ref=$m.($pair[0]);$required=$pair[1];if($ref.path -cne $required -or $ref.sha256 -ne ('sha256:'+(Get-FileHash -LiteralPath $required).Hash.ToLowerInvariant()) -or $ref.bytes -ne (Get-Item -LiteralPath $required).Length){throw 'Issued metadata exact measured reference mismatch'}}
 $rows=@($m.captures);if($rows.Count -ne $Count -or @($rows.captureID|Select-Object -Unique).Count -ne $Count -or @($rows.imageID|Select-Object -Unique).Count -ne $Count){throw 'Unique preallocated capture identities required'}
 for($i=1;$i -le $Count;$i++){$r=@($rows|Where-Object{$_.run -eq $i});if($r.Count -ne 1 -or $r[0].measurementStatus -cne 'pending-actual-launch-joins'){throw 'Planned identities must await measured launch joins'}}
 return $m
}
"""
    save(integ,s[:start]+body+s[end:])

def main():
    ap=argparse.ArgumentParser()
    for n in ('donor-root','case','manifest','tuple','recipe','source','compile-plan','compile-receipt','operational-package','operational-exe','preflight','serializer-control','output'):
        ap.add_argument('--'+n,dest=n.replace('-','_'),required=True,type=Path)
    ap.add_argument('--windows-stage-root',required=True)
    ap.add_argument('--count',type=int,choices=(1,20),default=1)
    a=ap.parse_args()
    donor=a.donor_root; out=a.output; stage=Path(a.windows_stage_root)
    if out.exists() or not donor.is_dir(): raise Hold('fresh output/donor roots required')
    if abs_win(out).casefold()!=abs_win(stage).casefold(): raise Hold('output & Windows stage root must be identical')
    case,case_h,case_b=readj(a.case,'fresh case'); man,man_h,man_b=readj(a.manifest,'fresh manifest'); tup,tup_h,tup_b=readj(a.tuple,'fresh tuple'); plan,plan_h,plan_b=readj(a.compile_plan,'measured compile plan'); rec,rec_h,rec_b=readj(a.compile_receipt,'measured compile receipt')
    recipe_h,recipe_b=digest(a.recipe,MAX_JSON); source_h,source_b=digest(a.source); preflight_h,preflight_b=digest(a.preflight,MAX_JSON); serializer_h,serializer_b=digest(a.serializer_control)
    tv=tup.get('tuple');
    if not isinstance(tv,dict) or not isinstance(tv.get('id'),str) or not tv['id']: raise Hold('nested tuple.id required')
    tuple_id=tv['id']
    if case.get('id')!=man.get('case',{}).get('id') or tup.get('case',{}).get('id')!=case.get('id'): raise Hold('fresh case joins mismatch')
    if plan.get('kind')!='windows-padding-fresh-compile-plan-v1' or plan.get('case',{}).get('id')!=case.get('id') or plan.get('case',{}).get('hash')!=man.get('case',{}).get('hash') or (man.get('sourceHash') and man.get('sourceHash')!=plan.get('sourceHash')): raise Hold('measured plan identity mismatch')
    if not isinstance(plan.get('sourceHash'),str) or not plan['sourceHash']: raise Hold('measured plan sourceHash missing')
    if isinstance(plan.get('tuple'),dict) and plan['tuple'].get('id') not in (None,tuple_id): raise Hold('measured plan nested tuple.id mismatch')
    fresh_plan_values={plan_h,'sha256:'+plan_h,plan_h.replace('sha256:','')}
    if rec.get('kind')!='factory-padding-incremental-owned-compile-v4' or str(rec.get('freshPlanSha256')) not in fresh_plan_values: raise Hold('measured receipt plan mismatch')
    for key,want in [('exitCode',0),('kernelWait',0),('kernelExitCodeRaw',0),('kernelExitCodeSigned',0),('jobActiveCount',0)]:
        if nested(rec,key)!=want: raise Hold(f'measured receipt {key} mismatch')
    for key in ('streamsSealed','streamDrainComplete','ownedExited','originalHandleRetained'):
        if nested(rec,key) is not True: raise Hold(f'measured receipt {key} missing')
    if nested(rec,'timedOut') is True or nested(rec,'outputCapExceeded') is True: raise Hold('measured receipt timeout/output cap')
    if rec.get('sourceHash')!=plan.get('sourceHash') or rec.get('rendererSha256')!=plan.get('rendererSha256'): raise Hold('measured source/renderer mismatch')
    pkg=rec.get('operationalPackage'); exe=rec.get('exePath')
    if not isinstance(pkg,str) or not isinstance(exe,str): raise Hold('measured operational package/executable missing')
    if abs_win(a.operational_package).casefold()!=os.path.abspath(pkg).casefold(): raise Hold('operational package path drift')
    if abs_win(a.operational_exe).casefold()!=os.path.abspath(exe).casefold(): raise Hold('operational executable path drift')
    exe_h,exe_b=digest(a.operational_exe)
    if exe_h!=str(rec.get('exeSha256','')).replace('sha256:','').lower() or ('exeBytes' in rec and int(rec['exeBytes'])!=exe_b): raise Hold('operational executable bytes/hash drift')
    donor_manifest,_,_=readj(donor/'root-stage-manifest.json','donor stage manifest'); entries=donor_manifest.get('files')
    if not isinstance(entries,list) or not entries: raise Hold('donor stage manifest files missing')
    out.mkdir(parents=True); producer=out/'producer'; total=0; rows=[]
    donor_prefix='factory/native/windows/padding-capture-lease-capture-v1/'; donor_abs=abs_win(donor).replace('\\','/')+'/'
    for row in entries:
        if not isinstance(row,dict) or not isinstance(row.get('path'),str): raise Hold('donor manifest path malformed')
        p=row['path'].replace('\\','/')
        if p.startswith(donor_prefix): rel=Path(p[len(donor_prefix):])
        elif p.startswith(donor_abs): rel=Path(p[len(donor_abs):])
        elif row.get('external') is True: continue
        else: raise Hold('donor manifest path outside donor')
        h,n=copy_checked(donor/rel,producer/rel); total+=n
        if total>MAX_TOTAL or (row.get('hash') and str(row['hash']).lower()!='sha256:'+h) or (row.get('bytes') is not None and int(row['bytes'])!=n): raise Hold('donor closure hash/size drift')
        rows.append({'path':'producer/'+rel.as_posix(),'sha256':'sha256:'+h,'bytes':n})
    inputs=out/'fresh-inputs'; metadata=out/'metadata'; inputs.mkdir(); metadata.mkdir()
    fresh_refs={}
    for name,src,lim in [('case.json',a.case,MAX_JSON),('manifest.json',a.manifest,MAX_JSON),('tuple.json',a.tuple,MAX_JSON),('recipe.json',a.recipe,MAX_JSON),('source.swift',a.source,MAX_FILE),('compile-plan.json',a.compile_plan,MAX_JSON),('compile-receipt.json',a.compile_receipt,MAX_JSON),('serializer-control.json',a.serializer_control,MAX_FILE)]:
        h,n=copy_checked(src,inputs/name,lim); fresh_refs[name]={'path':abs_win(inputs/name),'sha256':'sha256:'+h,'bytes':n}
    pfh,pfb=copy_checked(a.preflight,producer/'preflight.ps1',MAX_JSON); copy_checked(a.serializer_control,producer/'metadata'/'serializer-control.json')
    stage_s=abs_win(stage); stage_ref=lambda rel: os.path.join(stage_s,*str(rel).replace('/','\\').split('\\'))
    host_hashes=tv.get('hostHashes',{}) if isinstance(tv.get('hostHashes',{}),dict) else {}
    binding={'kind':'factory-source-bound-candidate-binding-v1','case':man['case'],'caseID':case['id'],'caseHash':man['case']['hash'],'tupleID':tuple_id,'candidateID':tup.get('candidateID'),'sourceHash':plan['sourceHash'],'planHash':'sha256:'+plan_h,'compileReceiptHash':'sha256:'+rec_h,'recipeHash':'sha256:'+recipe_h,'sourceFileHash':'sha256:'+source_h,'runtimeSourceCommit':rec.get('runtimeSourceCommit'),'rendererSha256':str(rec.get('rendererSha256','')).replace('sha256:',''),'exeSha256':str(rec.get('exeSha256','')).replace('sha256:',''),'macHostHash':host_hashes.get('macos'),'windowsHostHash':host_hashes.get('windows'),'tupleContext':{'tupleID':tuple_id,'macosHostHash':host_hashes.get('macos'),'windowsHostHash':host_hashes.get('windows'),'runtimeCommit':rec.get('runtimeSourceCommit'),'rendererHash':'sha256:'+str(rec.get('rendererSha256','')).replace('sha256:','')},'canonicalTupleRef':{'path':stage_ref('fresh-inputs/tuple.json'),'sha256':'sha256:'+tup_h,'bytes':tup_b},'frozenTupleBound':False,'nativeActions':0,'lockActions':0}
    (metadata/'source-binding.json').write_text(json.dumps(binding,indent=2)+'\n'); binding_h,binding_b=digest(metadata/'source-binding.json',MAX_JSON)
    canonical={'kind':'factory-padding-source-inputs-v2','status':'fresh-source-bound-staged','case':man['case'],'tupleID':tuple_id,'files':fresh_refs,'sourceBindingHash':'sha256:'+binding_h,'nativeActions':0,'lockActions':0}
    (metadata/'canonical-inputs-manifest.json').write_text(json.dumps(canonical,indent=2)+'\n'); canonical_h,canonical_b=digest(metadata/'canonical-inputs-manifest.json',MAX_JSON)
    renderer_path=str(plan.get('rendererPath') or rec.get('rendererPath') or '')
    if not renderer_path: raise Hold('measured renderer path missing')
    renderer_h,renderer_b=digest(Path(renderer_path))
    cap={'kind':'padding-capture-lease-capture-source-plan-v1','case':man['case'],'tupleID':tuple_id,'sourceHash':plan['sourceHash'],'sourcePackagePath':pkg,'compiledHostPackagePath':pkg,'operationalPackagePath':pkg,'operationalExePath':abs_win(a.operational_exe),'requestedCompilePackagePath':plan.get('compileRequest',{}).get('packagePath'),'compilePlanPath':abs_win(a.compile_plan),'compilePlanHash':'sha256:'+plan_h,'compileReceiptPath':abs_win(a.compile_receipt),'compileReceiptHash':'sha256:'+rec_h,'sourcePlanSha256':'sha256:'+plan_h,'compiledPlanSha256':'sha256:'+plan_h,'launchPreflightPath':stage_ref('producer/preflight.ps1'),'launchPreflightSha256':'sha256:'+pfh,'captureRoot':stage_ref('producer'),'renderer':{'rollingInputPath':renderer_path,'sha256':'sha256:'+renderer_h,'bytes':renderer_b},'serializerControl':{'path':stage_ref('producer/metadata/serializer-control.json'),'relativePath':'metadata/serializer-control.json','sha256':'sha256:'+serializer_h,'bytes':serializer_b},'dispatch':{'first':{'count':1,'runRoot':stage_ref('producer/actual-single-r1')},'retries':False,'repeat':{'count':20,'runRoot':stage_ref('producer/actual-repeat-r1'),'firstProofRequired':True}},'qualification':'fresh-source-bound-observation-only; no parity or frozen tuple claim','hostArguments':['--factory-capture-lease-seconds=40'],'freshInputRefs':fresh_refs,'sourceBindingHash':'sha256:'+binding_h,'canonicalInputsHash':'sha256:'+canonical_h,'memoryBudget':{'bytes':1073741824,'jobLimitFlags':512,'killOnJobClose':False},'runtimeSourceCommit':rec.get('runtimeSourceCommit'),'nativeActions':0,'compilerActions':0,'lockActions':0}
    (producer/'capture-plan.json').write_text(json.dumps(cap,indent=2)+'\n'); cap_h,cap_b=digest(producer/'capture-plan.json',MAX_JSON)
    patch_cap=dict(cap); patch_cap['_planHash']=plan_h; patch_cap['_receiptHash']=rec_h; patch_producer(out,patch_cap,'sha256:'+binding_h,'sha256:'+canonical_h,pkg)
    # All producer patches happened; reseal integration bindings & donor closure now.
    integ_manifest=producer/'integration-bindings.json'
    if integ_manifest.is_file(): reseal_manifest(integ_manifest,producer)
    root_manifest=producer/'root-stage-manifest.json'
    final_rows=[]
    for fp in sorted(producer.rglob('*')):
        if fp.is_file() and fp != root_manifest:
            h,n=digest(fp); final_rows.append({'path':'producer/'+fp.relative_to(producer).as_posix(),'sha256':'sha256:'+h,'bytes':n})
    root_manifest.write_text(json.dumps({'kind':'factory-padding-source-producer-manifest-v1','status':'fresh-source-bound-staged','files':final_rows,'nativeActions':0,'compilerActions':0,'lockActions':0},indent=2)+'\n')
    root_h,root_b=digest(root_manifest,MAX_JSON)
    integ_h,integ_b=(digest(integ_manifest,MAX_JSON) if integ_manifest.is_file() else ('',0))
    helper_ref={'path':stage_ref('producer/root-stage-manifest.json'),'sha256':'sha256:'+root_h,'bytes':root_b}
    binding_ref={'path':stage_ref('metadata/source-binding.json'),'sha256':'sha256:'+binding_h,'bytes':binding_b}; canonical_ref={'path':stage_ref('metadata/canonical-inputs-manifest.json'),'sha256':'sha256:'+canonical_h,'bytes':canonical_b}
    source={'kind':'factory-padding-source-inputs-v2','status':'fresh-source-bound-prelaunch','count':a.count,'caseID':case['id'],'caseHash':man['case']['hash'],'sourceHash':plan['sourceHash'],'tupleID':tuple_id,'candidateID':tup.get('candidateID'),'windowsHostHash':host_hashes.get('windows'),'runtimeSourceCommit':rec.get('runtimeSourceCommit'),'compiledHostPackagePath':pkg,'rendererPath':renderer_path,'rendererSha256':renderer_h,'serializerControlSha256':serializer_h,'exeHash':exe_h,'planHash':plan_h,'compileReceiptHash':rec_h,'caseRef':fresh_refs['case.json'],'manifestRef':fresh_refs['manifest.json'],'tupleRef':fresh_refs['tuple.json'],'planRef':fresh_refs['compile-plan.json'],'compileRef':fresh_refs['compile-receipt.json'],'exeRef':ref(a.operational_exe,'operational executable'),'rendererRef':ref(Path(renderer_path),'renderer'),'serializerRef':fresh_refs['serializer-control.json'],'bindingRef':binding_ref,'recipeRef':fresh_refs['recipe.json'],'sourceRef':fresh_refs['source.swift'],'tupleHash':tup_h,'candidateTupleHash':tup_h,'bindingHash':binding_h,'recipeHash':recipe_h,'contextRef':binding_ref,'integrationBindingsRef':({'path':stage_ref('producer/integration-bindings.json'),'sha256':'sha256:'+integ_h,'bytes':integ_b} if integ_h else None),'integrationBindingsHash':integ_h,'helperManifestPath':helper_ref['path'],'helperManifestHash':root_h,'helperManifestRef':helper_ref,'capturePlanPath':stage_ref('producer/capture-plan.json'),'capturePlanHash':cap_h,'buildPreflightPath':stage_ref('producer/preflight.ps1'),'buildPreflightHash':pfh,'compilePlanPath':abs_win(a.compile_plan),'compileReceiptPath':abs_win(a.compile_receipt),'operationalPackagePath':pkg,'operationalExePath':abs_win(a.operational_exe),'refs':{'case':fresh_refs['case.json'],'manifest':fresh_refs['manifest.json'],'tuple':fresh_refs['tuple.json'],'plan':fresh_refs['compile-plan.json'],'compile':fresh_refs['compile-receipt.json'],'exe':ref(a.operational_exe,'operational executable'),'renderer':ref(Path(renderer_path),'renderer'),'serializer':fresh_refs['serializer-control.json'],'binding':binding_ref,'recipe':fresh_refs['recipe.json'],'source':fresh_refs['source.swift'],'context':binding_ref,'integration':({'path':stage_ref('producer/integration-bindings.json'),'sha256':'sha256:'+integ_h,'bytes':integ_b} if integ_h else None),'helperManifest':helper_ref},'freshIDsRequired':True,'historicalCaseReuse':False,'nativeActions':0,'compilerActions':0,'lockActions':0}
    sip=metadata/'source-inputs.json'; sip.write_text(json.dumps(source,indent=2)+'\n'); sip_h,sip_b=digest(sip,MAX_JSON)
    rows_out=[]
    for p in sorted(out.rglob('*')):
        if p.is_file():
            h,n=digest(p); rows_out.append({'path':p.relative_to(out).as_posix(),'sha256':'sha256:'+h,'bytes':n})
    final={'kind':'factory-padding-fresh-capture-stage-manifest-v4','status':'source-only-native-pending','files':rows_out,'count':len(rows_out),'case':man['case'],'tupleID':tuple_id,'compilePlanHash':'sha256:'+plan_h,'compileReceiptHash':'sha256:'+rec_h,'exeSha256':'sha256:'+exe_h,'nativeActions':0,'compilerActions':0,'lockActions':0}
    (out/'source-manifest-v4.json').write_text(json.dumps(final,indent=2)+'\n')
    print(json.dumps({'kind':final['kind'],'output':abs_win(out),'files':len(rows_out),'caseHash':man['case']['hash'],'tupleID':tuple_id,'compilePlanHash':'sha256:'+plan_h,'compileReceiptHash':'sha256:'+rec_h,'exeSha256':'sha256:'+exe_h,'nativeActions':0,'compilerActions':0,'lockActions':0},separators=(',',':')))

if __name__=='__main__':
    try: main()
    except Exception as e: raise SystemExit('HOLD: '+str(e))
