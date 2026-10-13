"""One bounded source correction against proven rolling Rectangle compiler stage."""
from pathlib import Path
import base64
import argparse
import copy
import hashlib
import json

REPO = Path('/Volumes/D/claude/swiftright')
p = argparse.ArgumentParser()
p.add_argument('--revision', type=int, choices=range(1, 5), default=1)
a = p.parse_args()
OUT = REPO / ('factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-color-build-r' + str(a.revision))
BASE = REPO / 'factory/native/windows/pilot-rectangle-fixed-root-v2/plan-final-v4.json'
FILL = REPO / 'factory/pipeline/pilot-delivery-five-v1/text-shape-image/rectangle-host-fix-v1/FactoryFill.swift'

def read(p, cap):
    assert p.is_file() and not p.is_symlink() and p.stat().st_size <= cap
    return p.read_bytes()

original = read(BASE, 65536)
assert hashlib.sha256(original).hexdigest() == '980b212bbdbda14623cfa6cde416c0af959246c574bbb3074599b9959d2991a8'
fill = read(FILL, 8192)
fill_hash = hashlib.sha256(fill).hexdigest()
assert fill_hash == '21da245416c4bc6bd04981269546236e2a4c9d06dea4ecf2bd0664bf4dccf96f'
plan = copy.deepcopy(json.loads(original))
plan['phase'] = 'prebuild'
plan['case'] = None
plan['expectedHostHash'] = None
plan['tuple']['id'] = 'sr1-rectangle-color-fix-r11-20261012-r1'
plan['tuple']['hostHashes']['windows'] = None
plan['hostCorrection'] = {
    'scope': 'factory-only semantic system.red mapping; unchanged Swift witness/runtime/renderer',
    'previousFillHash': 'e06af75e3e8ecd0a28d55bb5520fff10e222ba84bfe3b8a52a5e1898fc9e3147',
    'fillHash': fill_hash,
    'reference': 'paired-rectangle-fixed-r11-root-v3: Mac RGB 255,56,60; previous Windows RGB 255,59,48',
    'qualification': 'pending fresh native pixels',
}
for row in plan['sourceBindings']:
    if row['path'] == 'Sources/FactoryProbe/FactoryFill.swift':
        row['sha256'] = 'sha256:' + fill_hash
plan['observationScope'] = 'Prospective corrected Windows factory host; original Mac reference unchanged; fresh native observation required'
plan['executionEligible'] = False
plan['nativeParity'] = 'hold'
data = (json.dumps(plan, indent=2, sort_keys=True) + '\n').encode()
sha = hashlib.sha256(data).hexdigest()
script = r'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Stage='D:\Claude\swiftright\.factory-work\hosts\rectangle'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native stage busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop busy for rolling stage mutation'}
function Get-FactoryPinnedHash([string]$P){$I=Get-Item -LiteralPath $P -Force;if($I.Length -gt 67108864 -or $I.PSIsContainer -or ($I.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'bounded regular input required'};(Get-FileHash -LiteralPath $P).Hash.ToLowerInvariant()}
$OldPlan=Join-Path $Stage 'package\plan-final-v4.json'
if((Get-FactoryPinnedHash $OldPlan) -cne '980b212bbdbda14623cfa6cde416c0af959246c574bbb3074599b9959d2991a8'){throw 'previous rolling plan drift'}
if((Get-FactoryPinnedHash (Join-Path $Stage 'build-owned-v4.ps1')) -cne 'f88932bcaaeb536f3dd7103b8401221cf1a27384fec75e928ebfd397dac53c7d'){throw 'compiler adapter drift'}
$Fill=Join-Path $Stage 'package\Sources\FactoryProbe\FactoryFill.swift'
if((Get-FactoryPinnedHash $Fill) -cne 'e06af75e3e8ecd0a28d55bb5520fff10e222ba84bfe3b8a52a5e1898fc9e3147'){throw 'previous fill source drift'}
$Old=Get-Content -LiteralPath $OldPlan -Raw|ConvertFrom-Json
foreach($R in @($Old.sourceBindings)) {if((Get-FactoryPinnedHash (Join-Path (Join-Path $Stage 'package') $R.path)) -cne $R.sha256.Replace('sha256:','')){throw ('previous source drift '+$R.path)}}
$Backup='D:\Claude\swiftright\.factory-work\retired\rectangle-color-source-r1'
if(Test-Path -LiteralPath $Backup){throw 'fresh backup required'}
[IO.Directory]::CreateDirectory($Backup)|Out-Null
Copy-Item -LiteralPath $Fill -Destination (Join-Path $Backup 'FactoryFill.swift')
foreach($Name in @('plan-prebuild-v4.json','plan-final-v4.json')) {$P=Join-Path $Stage ('package\'+$Name);if(Test-Path -LiteralPath $P){Copy-Item -LiteralPath $P -Destination (Join-Path $Backup $Name)}}
[IO.File]::WriteAllBytes($Fill,[Convert]::FromBase64String('__FILL__'))
$PlanPath=Join-Path $Stage 'package\plan-prebuild-v4.json'
[IO.File]::WriteAllBytes($PlanPath,[Convert]::FromBase64String('__PLAN__'))
if((Get-FactoryPinnedHash $Fill) -cne '__FILL_HASH__' -or (Get-FactoryPinnedHash $PlanPath) -cne '__PLAN_HASH__'){throw 'written bytes drift'}
& (Join-Path $Stage 'build-owned-v4.ps1') -PlanPath $PlanPath -PlanSha256 '__PLAN_HASH__' -Phase prebuild -Attempt 4 -PreflightOnly
& (Join-Path $Stage 'build-owned-v4.ps1') -PlanPath $PlanPath -PlanSha256 '__PLAN_HASH__' -Phase prebuild -Attempt 4
Get-Content -LiteralPath (Join-Path $Stage 'prebuild-r4\observation.json') -Raw
'''.replace('__FILL__', base64.b64encode(fill).decode()).replace('__PLAN__', base64.b64encode(data).decode()).replace('__FILL_HASH__', fill_hash).replace('__PLAN_HASH__', sha)
OUT.mkdir()
(OUT/'plan-prebuild-v4.json').write_bytes(data)
(OUT/'stage-prebuild-r1.ps1').write_text(script)
(OUT/'preparation.json').write_text(json.dumps({'kind':'factory-rectangle-color-preparation-v1','planSha256':sha,'fillSha256':fill_hash,'sourceDeltaFiles':1,'nativeActions':0,'desktopActions':0,'compilerActions':0,'qualification':'pending-root-build'},indent=2)+'\n')
print(json.dumps({'script':str(OUT/'stage-prebuild-r1.ps1'),'planSha256':sha,'fillSha256':fill_hash}))
