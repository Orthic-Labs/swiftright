from pathlib import Path
import argparse
import hashlib
import json
import subprocess

p=argparse.ArgumentParser();p.add_argument('--revision',type=int,required=True);p.add_argument('--count',type=int,choices=(1,20),default=1);a=p.parse_args()
assert a.revision in range(1,6)
count=a.count;tag=('count1-r1' if count==1 else 'count20-r1');capture_tag=('r' if count==1 else 'count20-r')+str(a.revision)
repo=Path('/Volumes/D/claude/swiftright')
out=repo/('factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-color-capture-'+capture_tag)
admitted=out/'admission-actual';admitted.mkdir()
ns='D:/Claude/swiftright/.factory-work/hosts/rectangle/captures/color-'+capture_tag
items={
 'root-preflight.json':f'control-{tag}/root-preflight.json',
 'config-template.json':f'control-{tag}/config-template.json',
 'integration-controls.json':f'control-{tag}/integration-controls.json',
 'uia-mta-controls.json':f'control-{tag}/uia-mta-controls.json',
 'mta-config-controls.json':f'control-{tag}/mta-config-controls.json',
 'source-inputs.json':f'admission-{tag}/source-inputs.json',
 'issued-metadata.json':f'admission-{tag}/issued-metadata.json',
}
for name,rel in items.items():subprocess.run(['scp','-q','win:'+ns+'/'+rel,str(admitted/name)],check=True,timeout=15)
if count==20:
    subprocess.run(['scp','-q','win:D:/Claude/swiftright/.factory-work/hosts/rectangle/captures/color-r5/control-count1-r1/coordinator.json',str(admitted/'first-count1-r5.json')],check=True,timeout=15)
def sha(path):
    assert path.is_file() and not path.is_symlink() and path.stat().st_size<=2097152
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''):h.update(b)
    return h.hexdigest()
def load(name):
    path=admitted/name;assert path.stat().st_size<=2097152
    return json.loads(path.read_text(encoding='utf-8-sig'))
preflight=load('root-preflight.json');config=load('config-template.json');issued=load('issued-metadata.json');source_inputs=load('source-inputs.json');prep=json.loads((out/'preparation.json').read_text())
assert preflight['status']=='preflight-passed' and preflight['nativeActions']==preflight['lockActions']==0
assert preflight['templateHash']==sha(admitted/'config-template.json')
assert preflight['issuedMetadataHash']==sha(admitted/'issued-metadata.json')==config['issuedMetadataHash']
assert prep['count']==count and config['count']==count and issued['expectedCount']==count
assert config['compileReceiptHash']==prep['compileReceiptHash'] and config['exeHash']==prep['exeHash']
assert config['sourceInputsHash']==prep['sourceInputsHash'] and prep['sourceInputsHash']==sha(admitted/'source-inputs.json')
assert source_inputs['sourceHash']==prep['sourceHash']
assert source_inputs['compileReceiptHash']==prep['compileReceiptHash'] and source_inputs['exeHash']==prep['exeHash']
assert issued['sourceHash']==prep['sourceHash'] and issued['compile']['sha256']=='sha256:'+prep['compileReceiptHash'] and issued['exe']['sha256']=='sha256:'+prep['exeHash']
assert issued['serializerControlSha256']==prep['serializerControlSha256']
first_hash=None
if count==20:
    first=load('first-count1-r5.json');first_hash=sha(admitted/'first-count1-r5.json')
    assert first['count']==1 and first['status']=='completed-source-bound-observation' and first['lockReleased'] and first['wholeBatchExitConfirmed'] and not first['cleanupErrors']
    assert first['sourceInputsHash']==prep['firstCount1SourceInputsHash'] and first['compileReceiptHash']==prep['compileReceiptHash'] and first['exeHash']==prep['exeHash'] and first_hash==prep['firstCount1ProofHash']
remote=ns.replace('/','\\');native_root=remote+'\\native';run_root=native_root+'\\count%d-r1'%count;control_root=remote+'\\control-'+tag;coordinator=remote+'\\overlay-'+tag+'\\'+('coordinator-count1-v3.ps1' if count==1 else 'coordinator-count20-v1.ps1')
script=r'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$ExpectedCount=__COUNT__; $Control='__CONTROL__'; $NativeRoot='__NATIVE_ROOT__'; $ExpectedRunRoot='__RUN_ROOT__'; $Preflight=Join-Path $Control 'root-preflight.json'
if((Get-FileHash -LiteralPath $Preflight).Hash.ToLowerInvariant() -cne '__PREFLIGHT__'){throw 'root admission proof drift'}
$P=Get-Content -LiteralPath $Preflight -Raw|ConvertFrom-Json
if($P.status -cne 'preflight-passed' -or $P.nativeActions -ne 0 -or $P.lockActions -ne 0 -or $P.templateHash -cne '__TEMPLATE__'){throw 'actual source admission required'}
$Template=Join-Path $Control 'config-template.json';if((Get-FileHash -LiteralPath $Template).Hash.ToLowerInvariant() -cne '__TEMPLATE__'){throw 'actual template drift'}
$C=Get-Content -LiteralPath $Template -Raw|ConvertFrom-Json
if($C.count -ne $ExpectedCount -or $C.outputRoot -cne $NativeRoot -or $C.runRoot -cne $ExpectedRunRoot -or $C.compileReceiptHash -cne '__COMPILE__' -or $C.exeHash -cne '__EXE__' -or $C.sourceInputsHash -cne '__SOURCE_INPUTS__'){throw 'count-specific source pins mismatch'}
$IssuedPath=$C.issuedMetadataPath;if((Get-FileHash -LiteralPath $IssuedPath).Hash.ToLowerInvariant() -cne $C.issuedMetadataHash){throw 'issued metadata path/hash mismatch'};$I=Get-Content -LiteralPath $IssuedPath -Raw|ConvertFrom-Json
if($I.expectedCount -ne $ExpectedCount -or $I.sourceHash -cne '__SOURCE_HASH__' -or $I.compile.sha256 -cne ('sha256:'+'__COMPILE__') -or $I.exe.sha256 -cne ('sha256:'+'__EXE__')){throw 'issued metadata pins mismatch'}
if($ExpectedCount -eq 20){$First='D:\Claude\swiftright\.factory-work\hosts\rectangle\captures\color-r5\control-count1-r1\coordinator.json';if((Get-FileHash -LiteralPath $First).Hash.ToLowerInvariant() -cne '__FIRST__'){throw 'fresh Count1 r5 prerequisite drift'};$F=Get-Content -LiteralPath $First -Raw|ConvertFrom-Json;if($F.count -ne 1 -or $F.status -cne 'completed-source-bound-observation' -or -not $F.lockReleased -or -not $F.wholeBatchExitConfirmed -or @($F.cleanupErrors).Count -ne 0 -or $F.sourceInputsHash -cne '__FIRST_SOURCE_INPUTS__' -or $F.compileReceiptHash -cne '__COMPILE__' -or $F.exeHash -cne '__EXE__'){throw 'fresh Count1 r5 prerequisite missing'}}
& '__COORDINATOR__' -Template $Template -TemplateHash '__TEMPLATE__'
Get-Content -LiteralPath (Join-Path $Control 'coordinator.json') -Raw
'''
for key,val in {'COUNT':str(count),'CONTROL':control_root,'NATIVE_ROOT':native_root,'RUN_ROOT':run_root,'PREFLIGHT':sha(admitted/'root-preflight.json'),'TEMPLATE':sha(admitted/'config-template.json'),'COORDINATOR':coordinator,'COMPILE':prep['compileReceiptHash'],'EXE':prep['exeHash'],'SOURCE_INPUTS':prep['sourceInputsHash'],'SOURCE_HASH':prep['sourceHash'],'FIRST':first_hash or '','FIRST_SOURCE_INPUTS':prep.get('firstCount1SourceInputsHash','')}.items():script=script.replace('__'+key+'__',val)
entry_name='native-entry-r1.ps1' if count==1 else 'native-entry-count20-r1.ps1';(out/entry_name).write_text(script)
print(json.dumps({'entry':str(out/entry_name),'entrySha256':sha(out/entry_name),'count':count,'qualification':'pending-native-count'+str(count)}))
