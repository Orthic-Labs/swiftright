from pathlib import Path
import base64
import hashlib
import json
import subprocess

repo = Path('/Volumes/D/claude/swiftright')
root = repo/'factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-color-build-r2'
out = root/'prebuild-actual-r1'
out.mkdir()
remote = 'win:D:/Claude/swiftright/.factory-work/hosts/rectangle/prebuild-r4/'
def sha(p, cap=67108864):
    assert p.is_file() and not p.is_symlink() and p.stat().st_size <= cap
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''):h.update(b)
    return h.hexdigest()
for name in ('observation.json','compile.stdout.bin','compile.stderr.bin'):
    subprocess.run(['scp','-q',remote+name,str(out/name)],check=True,timeout=15)
receipt = json.loads((out/'observation.json').read_text(encoding='utf-8-sig'))
assert receipt['exitCode']==0 and receipt['kernelWait']==0 and receipt['originalHandleRetained'] and receipt['ownedExited']
assert receipt['streamsSealed'] and receipt['streamDrainComplete'] and receipt['jobActiveCount']==receipt['cleanupJobActive']==0
assert receipt['planSha256']==sha(root/'plan-prebuild-v4.json',65536)
for stream in ('stdout','stderr'):
    p=out/('compile.'+stream+'.bin')
    assert p.stat().st_size==receipt[stream+'Bytes'] and sha(p,8388608)==receipt[stream+'Sha256']
exe=out/'FactoryProbe.exe'
subprocess.run(['scp','-q','win:'+receipt['exePath'].replace('\\','/'),str(exe)],check=True,timeout=20)
assert exe.stat().st_size==receipt['exeBytes'] and sha(exe)==receipt['exeSha256']
plan=json.loads((root/'plan-prebuild-v4.json').read_text())
original=json.loads((repo/'factory/native/windows/pilot-rectangle-fixed-root-v2/plan-final-v4.json').read_text())
plan['phase']='final';plan['case']=original['case'];plan['expectedHostHash']='sha256:'+sha(exe)
plan['tuple']['hostHashes']['windows']=plan['expectedHostHash']
plan['prebuildReceiptHash']='sha256:'+sha(out/'observation.json',65536)
data=(json.dumps(plan,indent=2,sort_keys=True)+'\n').encode()
(root/'plan-final-v4.json').write_bytes(data)
plan_hash=hashlib.sha256(data).hexdigest()
script=r'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Stage='D:\Claude\swiftright\.factory-work\hosts\rectangle'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native stage busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop busy for rolling plan mutation'}
$PlanPath=Join-Path $Stage 'package\plan-final-v4.json'
if((Get-FileHash -LiteralPath $PlanPath).Hash.ToLowerInvariant() -cne '980b212bbdbda14623cfa6cde416c0af959246c574bbb3074599b9959d2991a8'){throw 'previous final plan drift'}
if((Get-FileHash -LiteralPath (Join-Path $Stage 'package\plan-prebuild-v4.json')).Hash.ToLowerInvariant() -cne '__PREBUILD__'){throw 'corrected prebuild plan drift'}
if((Get-FileHash -LiteralPath (Join-Path $Stage 'prebuild-r4\observation.json')).Hash.ToLowerInvariant() -cne '__RECEIPT__'){throw 'prebuild receipt drift'}
[IO.File]::WriteAllBytes($PlanPath,[Convert]::FromBase64String('__PLAN__'))
if((Get-FileHash -LiteralPath $PlanPath).Hash.ToLowerInvariant() -cne '__FINAL__'){throw 'new final plan drift'}
& (Join-Path $Stage 'build-owned-v4.ps1') -PlanPath $PlanPath -PlanSha256 '__FINAL__' -Phase final -Attempt 3 -PreflightOnly
& (Join-Path $Stage 'build-owned-v4.ps1') -PlanPath $PlanPath -PlanSha256 '__FINAL__' -Phase final -Attempt 3
Get-Content -LiteralPath (Join-Path $Stage 'final-r3\observation.json') -Raw
'''.replace('__PREBUILD__',sha(root/'plan-prebuild-v4.json')).replace('__RECEIPT__',sha(out/'observation.json')).replace('__PLAN__',base64.b64encode(data).decode()).replace('__FINAL__',plan_hash)
(root/'compile-final-r1.ps1').write_text(script)
print(json.dumps({'prebuildReceiptSha256':sha(out/'observation.json'),'exeSha256':sha(exe),'planSha256':plan_hash,'nativeActions':0,'qualification':'compile-only-not-native'}))
