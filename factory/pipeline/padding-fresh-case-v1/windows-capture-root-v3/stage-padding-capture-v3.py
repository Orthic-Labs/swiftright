#!/usr/bin/env python3
"""Materialize fresh Padding capture sources from measured plan/receipt & donor producer.

Source-only: copies explicitly listed donor files, writes fresh metadata, & performs no
compiler, native, scheduler, desktop-lock, or process action.
"""
from __future__ import annotations
import argparse, hashlib, json, re, shutil, stat
from pathlib import Path

MAX_FILE = 64 * 1024 * 1024; MAX_JSON = 2 * 1024 * 1024; MAX_TOTAL = 128 * 1024 * 1024
class Hold(ValueError): pass

def digest(p: Path, limit=MAX_FILE):
    st=p.lstat()
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode) or st.st_size>limit: raise Hold(f"invalid/bounded file: {p}")
    h=hashlib.sha256(); n=0
    with p.open('rb') as f:
        while True:
            b=f.read(1024*1024)
            if not b: break
            h.update(b); n+=len(b)
            if n>limit: raise Hold(f"file grew: {p}")
    if n!=st.st_size: raise Hold(f"file changed: {p}")
    return h.hexdigest(),n

def readj(p,label):
    h,n=digest(p,MAX_JSON)
    try: d=json.loads(p.read_text(encoding='utf-8-sig'))
    except Exception as e: raise Hold(f"{label} invalid JSON") from e
    if not isinstance(d,dict): raise Hold(f"{label} object required")
    return d,h,n

def ref(p,label,limit=MAX_FILE):
    h,n=digest(p,limit); return {'path':str(p.resolve()),'sha256':'sha256:'+h,'bytes':n,'role':label}

def nested(d,key):
    if key in d: return d[key]
    for k in ('kernel','job','cleanup','process','streams','memory'):
        x=d.get(k)
        if isinstance(x,dict) and key in x: return x[key]
    return None

def copy_checked(src,dst):
    h,n=digest(src); dst.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(src,dst)
    h2,n2=digest(dst)
    if (h,n)!=(h2,n2): raise Hold(f"copy changed: {src}")
    return h,n

def patch_once(text,old,new,label):
    if text.count(old)!=1: raise Hold(f"expected one {label} source match")
    return text.replace(old,new)

def patch_producer(stage, plan, receipt, binding_hash, integration_hash):
    producer=stage/'producer'; capture=producer/'capture-repeat.ps1'; coordinator=producer/'coordinator.ps1'; issue=producer/'issue-before-launch.ps1'
    s=capture.read_text(encoding='utf-8-sig')
    s=patch_once(s,"if(-not $outputPath.StartsWith('D:\\Claude\\swiftright\\factory\\native\\windows\\padding-capture-lease-capture-v1\\',[StringComparison]::OrdinalIgnoreCase)){throw 'Output outside first capture lane'}", "if(-not $outputPath.StartsWith(([IO.Path]::GetFullPath($PSScriptRoot)+'\\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Output outside fresh capture lane'}",'capture output guard')
    s=patch_once(s,"if(-not $packagePath.StartsWith('D:\\Claude\\swiftright\\.factory-work\\hosts\\',[StringComparison]::OrdinalIgnoreCase)){throw 'Package outside compiled host workspace'}", "if([string]::IsNullOrWhiteSpace($packagePath)){throw 'Compiled host package required'}",'capture package guard')
    old="$approved=@{caseID='swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258';sourceHash='sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b';planHash='ee83748cd42326e57676e47d8fec777bd8466706ba2c72a01eb9b5b71292de10';receiptRelative='build-capture-lease-r1\\observation.json'}"
    new="$approved=@{caseID='"+plan['case']['id']+"';sourceHash='"+plan['sourceHash']+"';planHash='"+plan['_planHash']+"';receiptRelative='build-capture-lease-r1\\observation.json'}"
    s=patch_once(s,old,new,'capture approved identity')
    s=s.replace('$compiled.planSha256','$compiled.freshPlanSha256')
    s=s.replace("if($plan.runtimeSourceCommit -ne '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'", "if($plan.runtimeSourceCommit -ne '"+plan['runtimeSourceCommit']+"'")
    capture.write_text(s,encoding='utf-8')
    s=coordinator.read_text(encoding='utf-8-sig')
    s=patch_once(s,"$expectedHere='D:\\Claude\\swiftright\\factory\\native\\windows\\padding-capture-lease-capture-v1'\nif($here -cne $expectedHere){throw 'Exact capture coordinator lane required'}", "if(-not (Test-Path -LiteralPath (Join-Path $here 'capture-plan.json') -PathType Leaf)){throw 'Fresh capture coordinator lane required'}",'coordinator root guard')
    s=s.replace('$compiled.planSha256','$compiled.freshPlanSha256')
    coordinator.write_text(s,encoding='utf-8')
    s=issue.read_text(encoding='utf-8-sig')
    old="$builder='D:\\Claude\\swiftright\\.factory-work\\hosts\\padding-window-diagnosis'\n$metadataRoot=Join-Path $builder 'metadata'\n$preflight=Join-Path $builder 'preflight.ps1'"
    new="$capturePlan=Get-Content -Raw (Join-Path $PSScriptRoot 'capture-plan.json')|ConvertFrom-Json\n$builder=Split-Path -Parent $capturePlan.compiledHostPackagePath\n$metadataRoot=Join-Path $PSScriptRoot 'metadata'\n$preflight=$capturePlan.launchPreflightPath"
    s=patch_once(s,old,new,'issue builder')
    s=s.replace("$allowedRoot='D:\\Claude\\swiftright\\factory\\native\\windows\\padding-capture-lease-capture-v1\\'", "$allowedRoot=([IO.Path]::GetFullPath($PSScriptRoot)+'\\')")
    s=s.replace("if((Get-FileHash -LiteralPath $preflight).Hash.ToLowerInvariant() -cne '37ed4ec43f7b3e27db423d1b5564155ec58b0d5c61b021fa602a5919ebd15c6b'){throw 'Exact lease launch preflight required'}", "if((Get-FileHash -LiteralPath $preflight).Hash.ToLowerInvariant() -cne $capturePlan.launchPreflightSha256.Replace('sha256:','')){throw 'Exact fresh launch preflight required'}")
    s=s.replace("$package=Join-Path $builder 'package';$planPath=Join-Path $package 'plan.json';$plan=Get-Content -Raw $planPath|ConvertFrom-Json", "$package=$capturePlan.compiledHostPackagePath;$planPath=Join-Path $package 'plan.json';$plan=Get-Content -Raw $planPath|ConvertFrom-Json")
    s=s.replace("$bindingPath=Join-Path $metadataRoot 'source-binding.json'", "$bindingPath=Join-Path $metadataRoot 'source-binding.json';$tuplePath=Join-Path (Split-Path -Parent $PSScriptRoot) 'fresh-inputs\\tuple.json'")
    s=s.replace("sourceBoundCandidateTuple=Raw-Ref $bindingPath;producedRuntimeModules", "sourceBoundCandidateTuple=Raw-Ref $bindingPath;candidateTuple=Raw-Ref $tuplePath;producedRuntimeModules")
    old_hash="if((Get-FileHash -LiteralPath (Join-Path $metadataRoot 'source-binding.json')).Hash.ToLowerInvariant() -cne '21fe0b64c8d9d5886fb4c2470274959793b5c7a53d31039d862947b20a8dd4c4' -or (Get-FileHash -LiteralPath (Join-Path $metadataRoot 'canonical-inputs-manifest.json')).Hash.ToLowerInvariant() -cne '208689e04f06a0e397ccd611bb8aca3828e0cf7ec15fd7df0a4dab8436389efa'){throw 'Prospective source-bound tuple reference drift'}"
    new_hash="if((Get-FileHash -LiteralPath (Join-Path $metadataRoot 'source-binding.json')).Hash.ToLowerInvariant() -cne '"+binding_hash.replace('sha256:','')+"' -or (Get-FileHash -LiteralPath (Join-Path $metadataRoot 'canonical-inputs-manifest.json')).Hash.ToLowerInvariant() -cne '"+integration_hash.replace('sha256:','')+"'){throw 'Fresh source-bound input reference drift'}"
    s=patch_once(s,old_hash,new_hash,'issue source reference hashes')
    issue.write_text(s,encoding='utf-8')
    # Keep integration assertions exact while replacing historical builder/plan joins.
    integ=producer/'support'/'integration.ps1'; s=integ.read_text(encoding='utf-8-sig')
    start=s.index('function Assert-LeaseIssuedMetadata')
    end=s.index('function Test-FactoryParentOrdering',start)
    body="""function Assert-LeaseIssuedMetadata([string]$Path,[string]$Hash,[string]$RunRoot,[int]$Count,[string]$CompileHash,[string]$ExeHash,[string]$SerializerHash){
 $captureRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot));$capturePlan=Get-Content -Raw (Join-Path $captureRoot 'capture-plan.json')|ConvertFrom-Json
 if($Hash -cnotmatch '^[0-9a-f]{64}$' -or (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant() -cne $Hash){throw 'Issued metadata raw hash mismatch'}
 $m=Get-Content -Raw -LiteralPath $Path|ConvertFrom-Json
 if($m.kind -cne 'factory-prelaunch-capture-metadata-v2' -or $m.runRoot -cne $RunRoot -or $m.expectedCount -ne $Count -or $m.frozenTupleBound -or $m.compile.sha256 -ne ('sha256:'+$CompileHash) -or $m.exe.sha256 -ne ('sha256:'+$ExeHash) -or $m.serializerControlSha256 -ne $SerializerHash -or @($m.hostArguments).Count -ne 1 -or $m.hostArguments[0] -cne '--factory-capture-lease-seconds=40'){throw 'Issued metadata admitted context mismatch'}
 $planPath=$capturePlan.compiledHostPackagePath+'\\plan.json';$receiptPath=$capturePlan.compiledHostPackagePath+'\\build-capture-lease-r1\\observation.json';$plan=Get-Content -Raw $planPath|ConvertFrom-Json;$compiled=Get-Content -Raw $receiptPath|ConvertFrom-Json
 $compiledPlanHash=[string]$compiled.freshPlanSha256;if([string]::IsNullOrWhiteSpace($compiledPlanHash)){$compiledPlanHash=[string]$compiled.planSha256}
 if($m.sourceHash -cne $plan.sourceHash -or $m.case.id -cne $plan.case.id -or $m.case.hash -cne $plan.case.hash -or $m.historicalTemplateTupleClosed -or $m.qualification -cne 'sourceBoundCandidate-observation-only' -or $compiledPlanHash -ne $capturePlan.sourcePlanSha256.Replace('sha256:','')){throw 'Issued metadata fresh source identity mismatch'}
 foreach($pair in @(@('plan',$planPath),@('compile',$receiptPath),@('exe',$compiled.exePath),@('renderer',$capturePlan.renderer.rollingInputPath))){$ref=$m.($pair[0]);$required=$pair[1];if($ref.path -cne $required -or $ref.sha256 -ne ('sha256:'+(Get-FileHash -LiteralPath $required).Hash.ToLowerInvariant()) -or $ref.bytes -ne (Get-Item -LiteralPath $required).Length){throw 'Issued metadata exact raw reference mismatch'}}
 $rows=@($m.captures);if($rows.Count -ne $Count -or @($rows.captureID|Select-Object -Unique).Count -ne $Count -or @($rows.imageID|Select-Object -Unique).Count -ne $Count){throw 'Unique preallocated capture identities required'}
 for($i=1;$i -le $Count;$i++){$r=@($rows|Where-Object{$_.run -eq $i});if($r.Count -ne 1 -or $r[0].measurementStatus -cne 'pending-actual-launch-joins'){throw 'Planned identities must await measured launch joins'}}
 return $m
}
"""
    integ.write_text(s[:start]+body+s[end:],encoding='utf-8')

def main():
    ap=argparse.ArgumentParser()
    for n in ('donor-root','fresh-root','recipe','source','compile-plan','compile-receipt','preflight','output','windows-stage-root'):
        ap.add_argument('--'+n,dest=n.replace('-','_'),required=True,type=Path if n!='windows-stage-root' else str)
    ap.add_argument('--serializer-control',dest='serializer_control',required=True,type=Path)
    ap.add_argument('--count',type=int,choices=(1,20),default=1); a=ap.parse_args()
    donor=a.donor_root.resolve(); fresh=a.fresh_root.resolve(); out=a.output.resolve(); stage_root=a.windows_stage_root
    if out.exists() or not donor.is_dir() or not fresh.is_dir(): raise Hold('fresh output/donor/input roots required')
    case,case_h,_=readj(fresh/'case.json','fresh case'); manifest,manifest_h,_=readj(fresh/'manifest.json','fresh manifest'); tup,tup_h,tup_b=readj(fresh/'tuple.json','fresh tuple'); plan,plan_h,_=readj(a.compile_plan,'compile plan'); receipt,receipt_h,_=readj(a.compile_receipt,'compile receipt'); recipe_h,recipe_b=digest(a.recipe,MAX_JSON); source_h,source_b=digest(a.source); serializer_h,serializer_b=digest(a.serializer_control,MAX_FILE)
    if manifest.get('case',{}).get('id')!=case.get('id') or tup.get('case',{}).get('id')!=case.get('id'): raise Hold('fresh case joins mismatch')
    if plan.get('kind')!='windows-padding-fresh-compile-plan-v1' or plan.get('case',{}).get('id')!=case.get('id') or plan.get('manifestHash')!=plan.get('case',{}).get('hash'): raise Hold('fresh plan identity mismatch')
    if receipt.get('kind')!='factory-padding-incremental-owned-compile-v4' or receipt.get('freshPlanSha256') not in (plan_h,plan.get('freshPlanSha256'),plan_h.replace('sha256:','')): raise Hold('fresh compile receipt plan mismatch')
    for key,want in [('exitCode',0),('kernelWait',0),('kernelExitCodeRaw',0),('kernelExitCodeSigned',0),('jobActiveCount',0)]:
        if nested(receipt,key)!=want: raise Hold(f'compile receipt {key} mismatch')
    for key in ('streamsSealed','streamDrainComplete','ownedExited','originalHandleRetained'):
        if nested(receipt,key) is not True: raise Hold(f'compile receipt {key} missing')
    if nested(receipt,'timedOut') is True or nested(receipt,'outputCapExceeded') is True: raise Hold('compile receipt timeout/output cap')
    if receipt.get('sourceHash')!=plan.get('sourceHash') or receipt.get('rendererSha256')!=plan.get('rendererSha256'): raise Hold('compile source/renderer mismatch')
    if not isinstance(receipt.get('exePath'),str) or receipt.get('exeSha256') is None or receipt.get('exeBytes') is None: raise Hold('compiled executable receipt fields missing')
    # Donor manifest is explicit authority for producer closure; no recursive discovery.
    donor_manifest,_,_=readj(donor/'root-stage-manifest.json','donor stage manifest'); entries=donor_manifest.get('files');
    if not isinstance(entries,list) or not entries: raise Hold('donor stage manifest files missing')
    total=0; rows=[]; external_rows=[]; out.mkdir(parents=True); producer=out/'producer'
    # Historical manifest stores repository-relative donor paths; accept only its exact donor prefix.
    donor_prefix='factory/native/windows/padding-capture-lease-capture-v1/'
    abs_prefix=str(donor).replace('\\','/')+'/'
    for row in entries:
        p=row.get('path') if isinstance(row,dict) else None
        if not isinstance(p,str): raise Hold('donor manifest path outside donor')
        pn=p.replace('\\','/')
        if pn.startswith(donor_prefix): rel=Path(pn[len(donor_prefix):])
        elif pn.startswith(abs_prefix): rel=Path(pn[len(abs_prefix):])
        elif row.get('external') is True:
            declared=str(row.get('hash','')).lower(); declared_bytes=row.get('bytes')
            if not re.fullmatch(r'sha256:[0-9a-f]{64}',declared) or not isinstance(declared_bytes,int) or declared_bytes<0: raise Hold('external donor ref malformed')
            external_rows.append({'path':pn,'sha256':declared,'bytes':declared_bytes,'external':True}); continue
        else: raise Hold('donor manifest path outside donor')
        src=donor/rel
        h,n=copy_checked(src,producer/rel)
        if row.get('hash') and str(row.get('hash')).lower()!='sha256:'+h: raise Hold('donor manifest hash drift')
        if row.get('bytes') is not None and int(row.get('bytes'))!=n: raise Hold('donor manifest byte drift')
        total+=n
        if total>MAX_TOTAL: raise Hold('donor source total bound')
        rows.append({'path':'producer/'+rel.as_posix(),'sha256':'sha256:'+h,'bytes':n})
    # Replace historical repository-relative manifest with fresh staged absolute refs.
    staged_manifest={'kind':'factory-padding-fresh-producer-stage-manifest-v3','status':'fresh-source-bound-staged','files':[{'path':str((producer/Path(r['path'][len('producer/'):])).resolve()),'sha256':r['sha256'],'bytes':r['bytes']} for r in rows]+external_rows,'nativeActions':0,'compilerActions':0,'lockActions':0}
    (producer/'root-stage-manifest.json').write_text(json.dumps(staged_manifest,indent=2)+'\n')
    mh,mn=digest(producer/'root-stage-manifest.json',MAX_JSON); rows.append({'path':'producer/root-stage-manifest.json','sha256':'sha256:'+mh,'bytes':mn})
    inputs=out/'fresh-inputs'; inputs.mkdir()
    fresh_refs={}
    for name,p in [('case.json',fresh/'case.json'),('manifest.json',fresh/'manifest.json'),('tuple.json',fresh/'tuple.json'),('recipe.json',a.recipe),('source.swift',a.source),('compile-plan.json',a.compile_plan),('compile-receipt.json',a.compile_receipt),('serializer-control.json',a.serializer_control)]:
        h,n=copy_checked(p,inputs/name); fresh_refs[name]={'path':'fresh-inputs/'+name,'sha256':'sha256:'+h,'bytes':n}
    # Bind preflight & metadata under fresh producer namespace.
    pfh,pfb=copy_checked(a.preflight,producer/'preflight.ps1');
    tv=tup.get('tuple',tup); host_hashes=tv.get('hostHashes',{}) if isinstance(tv,dict) else {}
    binding={'kind':'factory-source-bound-candidate-binding-v1','case':manifest['case'],'caseID':case.get('id'),'caseHash':manifest['case'].get('hash'),'tupleID':tup.get('candidateID'),'sourceHash':plan.get('sourceHash'),'planHash':'sha256:'+plan_h,'compileReceiptHash':'sha256:'+receipt_h,'recipeHash':'sha256:'+recipe_h,'sourceFileHash':'sha256:'+source_h,'runtimeSourceCommit':receipt.get('runtimeSourceCommit'),'rendererSha256':str(receipt.get('rendererSha256','')).replace('sha256:',''),'exeSha256':str(receipt.get('exeSha256','')).replace('sha256:',''),'macHostHash':host_hashes.get('macos'),'windowsHostHash':host_hashes.get('windows'),'tupleContext':{'tupleID':tup.get('candidateID'),'macosHostHash':host_hashes.get('macos'),'windowsHostHash':host_hashes.get('windows'),'runtimeCommit':receipt.get('runtimeSourceCommit'),'rendererHash':'sha256:'+str(receipt.get('rendererSha256','')).replace('sha256:','')},'canonicalTupleRef':{'path':str((out/'fresh-inputs'/'tuple.json').resolve()),'sha256':'sha256:'+tup_h,'bytes':tup_b},'frozenTupleBound':False,'nativeActions':0,'lockActions':0}
    metadata=out/'metadata';metadata.mkdir();(metadata/'source-binding.json').write_text(json.dumps(binding,indent=2)+'\n')
    bh,bn=digest(metadata/'source-binding.json',MAX_JSON); ch,cn=digest(a.compile_plan,MAX_JSON)
    (metadata/'canonical-inputs-manifest.json').write_text(json.dumps({'kind':'factory-padding-fresh-inputs-v3','case':manifest['case'],'tupleID':tup.get('candidateID'),'files':fresh_refs,'sourceBindingHash':'sha256:'+bh,'nativeActions':0,'lockActions':0},indent=2)+'\n')
    cih,cin=digest(metadata/'canonical-inputs-manifest.json',MAX_JSON)
    # Build fresh capture plan using measured Windows paths from plan/receipt, never guessed binary values.
    # Receipt's operational package is measured launch authority; requested fresh plan path stays metadata only.
    pkg=receipt.get('operationalPackage') or plan.get('compileRequest',{}).get('packagePath');
    if not isinstance(pkg,str): raise Hold('fresh Windows package path missing')
    serializer_ref={'path':str((producer/'metadata'/'serializer-control.json').resolve()),'sha256':'sha256:'+serializer_h,'bytes':serializer_b,'role':'serializer-control'}
    copy_checked(a.serializer_control,producer/'metadata'/'serializer-control.json')
    cap={'kind':'padding-capture-lease-capture-source-plan-v3','case':manifest['case'],'sourcePackagePath':pkg,'requestedCompilePackagePath':plan.get('compileRequest',{}).get('packagePath'),'sourcePlanSha256':'sha256:'+plan_h,'compiledPlanSha256':'sha256:'+plan_h,'compiledHostPackagePath':pkg,'launchPreflightPath':stage_root+'\\producer\\preflight.ps1','launchPreflightSha256':'sha256:'+pfh,'captureRoot':stage_root+'\\producer','renderer':{'rollingInputPath':plan.get('rendererPath') or receipt.get('rendererPath'),'sha256':'sha256:'+str(receipt['rendererSha256']).replace('sha256:','')},'serializerControl':{'path':stage_root+'\\producer\\metadata\\serializer-control.json','relativePath':'metadata/serializer-control.json','sha256':'sha256:'+serializer_h,'bytes':serializer_b},'dispatch':{'first':{'count':1,'runRoot':stage_root+'\\producer\\actual-single-r1'},'retries':False,'repeat':{'count':20,'runRoot':stage_root+'\\producer\\actual-repeat-r1','firstProofRequired':True}},'qualification':'fresh-source-bound-observation-only; no parity or frozen tuple claim','integration':{'workerContractSha256':next((x['sha256'].replace('sha256:','') for x in rows if x['path'].endswith('worker-contract.json')),None),'workerInvokerSha256':next((x['sha256'].replace('sha256:','') for x in rows if x['path'].endswith('invoke-worker.ps1')),None),'finalExitHelperSha256':next((x['sha256'].replace('sha256:','') for x in rows if x['path']=='producer/support/final-exit-certificate.ps1'),None),'combinedReleaseHelperSha256':next((x['sha256'].replace('sha256:','') for x in rows if x['path']=='producer/support/all-owned-release.ps1'),None)},'hostArguments':['--factory-capture-lease-seconds=40'],'freshInputRefs':fresh_refs,'sourceBindingHash':'sha256:'+bh,'canonicalInputsHash':'sha256:'+cih,'memoryBudget':{'bytes':1073741824,'jobLimitFlags':512,'killOnJobClose':False},'nativeActions':0,'compilerActions':0,'lockActions':0}
    cap['_planHash']=plan_h
    (producer/'capture-plan.json').write_text(json.dumps(cap,indent=2)+'\n')
    cap.pop('_planHash')
    # Flat v3 source-input manifest bridges existing v1/v2 controllers to fresh staged refs.
    binding_ref={'path':str((metadata/'source-binding.json').resolve()),'sha256':'sha256:'+bh,'bytes':bn}
    canonical_ref={'path':str((metadata/'canonical-inputs-manifest.json').resolve()),'sha256':'sha256:'+cih,'bytes':cin}
    # Issued metadata points at exact operational package refs, so source-input v3 does too.
    package_plan=Path(pkg)/'plan.json'; package_receipt=Path(pkg)/'build-capture-lease-r1'/'observation.json'; package_exe=Path(str(receipt.get('exePath'))); package_renderer=Path(plan.get('rendererPath') or receipt.get('rendererPath')); package_recipe=Path(pkg)/'witness.manifest.json'
    exe_hash=str(receipt.get('exeSha256','')).replace('sha256:',''); renderer_hash=str(receipt.get('rendererSha256','')).replace('sha256:','')
    plan_ref=ref(package_plan,'operational package plan',MAX_JSON); receipt_ref=ref(package_receipt,'operational compile receipt',MAX_JSON); exe_ref=ref(package_exe,'operational executable'); renderer_ref=ref(package_renderer,'operational renderer'); recipe_ref=ref(package_recipe,'operational witness recipe',MAX_JSON)
    if plan_ref['sha256']!='sha256:'+plan_h or receipt_ref['sha256']!='sha256:'+receipt_h or exe_ref['sha256']!='sha256:'+exe_hash: raise Hold('operational package refs differ from measured fresh receipt')
    case_ref=ref(inputs/'case.json','fresh case',MAX_JSON); manifest_ref=ref(inputs/'manifest.json','fresh manifest',MAX_JSON); tuple_ref=ref(inputs/'tuple.json','fresh tuple',MAX_JSON); recipe_ref=ref(inputs/'recipe.json','recipe',MAX_JSON); source_ref=ref(inputs/'source.swift','source')
    integrations=producer/'integration-bindings.json'; ih,inb=digest(integrations,MAX_JSON); helper_manifest=producer/'root-stage-manifest.json'; hh,hb=digest(helper_manifest,MAX_JSON)
    exe_hash=str(receipt.get('exeSha256','')).replace('sha256:',''); renderer_hash=str(receipt.get('rendererSha256','')).replace('sha256:','')
    cph,cpb=digest(producer/'capture-plan.json',MAX_JSON)
    renderer_bytes=((plan.get('measuredSourceEvidence') or {}).get('renderer') or {}).get('bytes')
    if not isinstance(renderer_bytes,int) or renderer_bytes<0: raise Hold('measured renderer byte count missing')
    integration_ref={'path':str(integrations.resolve()),'sha256':'sha256:'+ih,'bytes':inb}; helper_ref={'path':str(helper_manifest.resolve()),'sha256':'sha256:'+hh,'bytes':hb}
    source_inputs={'kind':'factory-padding-source-inputs-v3','status':'fresh-source-bound-staged','count':a.count,'caseID':case.get('id'),'caseHash':manifest['case'].get('hash'),'sourceHash':plan.get('sourceHash'),'tupleID':tup.get('candidateID'),'windowsHostHash':host_hashes.get('windows'),'runtimeSourceCommit':receipt.get('runtimeSourceCommit'),'compiledHostPackagePath':pkg,'rendererPath':plan.get('rendererPath') or receipt.get('rendererPath'),'rendererSha256':renderer_hash,'serializerControlSha256':serializer_h,'exeHash':exe_hash,'planHash':plan_h,'compileReceiptHash':receipt_h,'caseRef':case_ref,'manifestRef':manifest_ref,'tupleRef':tuple_ref,'planRef':plan_ref,'compileRef':receipt_ref,'exeRef':exe_ref,'rendererRef':renderer_ref,'serializerRef':serializer_ref,'bindingRef':binding_ref,'recipeRef':recipe_ref,'sourceRef':source_ref,'tupleHash':tup_h,'bindingHash':bh,'recipeHash':recipe_h,'contextRef':binding_ref,'integrationBindingsRef':integration_ref,'integrationBindingsHash':ih,'helperManifestPath':str(helper_manifest.resolve()),'helperManifestHash':hh,'helperManifestRef':helper_ref,'capturePlanPath':str((producer/'capture-plan.json').resolve()),'capturePlanHash':cph,'buildPreflightPath':str((producer/'preflight.ps1').resolve()),'buildPreflightHash':pfh,'refs':{'case':case_ref,'manifest':manifest_ref,'tuple':tuple_ref,'plan':plan_ref,'compile':receipt_ref,'exe':exe_ref,'renderer':renderer_ref,'serializer':serializer_ref,'binding':binding_ref,'recipe':recipe_ref,'source':source_ref,'context':binding_ref,'integration':integration_ref,'helperManifest':helper_ref},'freshIDsRequired':True,'historicalCaseReuse':False,'nativeActions':0,'compilerActions':0,'lockActions':0}
    sip=metadata/'source-inputs-v3.json';sip.write_text(json.dumps(source_inputs,indent=2)+'\n')
    # Patch producer identity guards using measured fresh plan/receipt values.
    plan_for_patch={**cap,'_planHash':plan_h,'runtimeSourceCommit':receipt.get('runtimeSourceCommit','')}
    patch_producer(out,plan_for_patch,receipt,'sha256:'+bh,'sha256:'+cih)
    rows=[]
    for p in sorted(out.rglob('*')):
        if p.is_file() and p.name not in ('source-manifest-v3.json',):
            h,n=digest(p);rows.append({'path':p.relative_to(out).as_posix(),'sha256':'sha256:'+h,'bytes':n})
    manifest_out={'kind':'factory-padding-fresh-capture-stage-manifest-v3','status':'source-only-native-pending','files':rows,'count':len(rows),'case':manifest['case'],'tupleID':tup.get('candidateID'),'compileReceiptHash':'sha256:'+receipt_h,'exeSha256':receipt.get('exeSha256'),'nativeActions':0,'compilerActions':0,'lockActions':0}
    (out/'source-manifest-v3.json').write_text(json.dumps(manifest_out,indent=2)+'\n')
    print(json.dumps({'kind':manifest_out['kind'],'output':str(out),'files':len(rows),'caseHash':manifest['case']['hash'],'compileReceiptHash':'sha256:'+receipt_h,'exeSha256':receipt.get('exeSha256'),'nativeActions':0,'lockActions':0},separators=(',',':')))

if __name__=='__main__':
    try: main()
    except Exception as e: raise SystemExit('HOLD: '+str(e))
