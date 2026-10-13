"""One missing bridge import correction; preserve failed candidate evidence."""
from pathlib import Path
import base64,hashlib,json
base=Path('/Volumes/D/claude/swiftright/factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-centered-build-r1')
out=base/'import-fix-r2';out.mkdir()
original=(base/'plan-prebuild-v4.json').read_bytes()
oldhash=hashlib.sha256(original).hexdigest();assert oldhash=='a8d83302168327bf6e3a38a7e5081e0155e6317edb5adc526ca6c256d2a48d8f'
adapter=(base/'FactoryCenteredLayout.swift').read_bytes()
assert adapter.count(b'import SwiftRightRuntime\n')==1
adapter=adapter.replace(b'import SwiftRightRuntime\n',b'import SwiftRightBridge\n')
adapterhash=hashlib.sha256(adapter).hexdigest()
plan=json.loads(original)
for row in plan['sourceBindings']:
    if row['path']=='Sources/FactoryProbe/FactoryCenteredLayout.swift':row['sha256']='sha256:'+adapterhash
plan['hostCorrection']['rootPlacement']['adapterHash']='sha256:'+adapterhash
plan['hostCorrection']['rootPlacement']['compilerCorrection']='Rect belongs to existing SwiftRightBridge; missing import fixed'
data=(json.dumps(plan,indent=2,sort_keys=True)+'\n').encode();planhash=hashlib.sha256(data).hexdigest()
script=r'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Stage='D:\Claude\swiftright\.factory-work\hosts\rectangle';$Package=Join-Path $Stage 'package';$Plan=Join-Path $Package 'plan-prebuild-v4.json';$Adapter=Join-Path $Package 'Sources\FactoryProbe\FactoryCenteredLayout.swift'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native lane busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop busy'}
function Hash([string]$P){(Get-FileHash -LiteralPath $P).Hash.ToLowerInvariant()}
if((Hash $Plan) -cne '__OLD__' -or (Hash $Adapter) -cne 'ee1ab5bd75daffe429653476afd8ff52a2bc8553ac28e2035879badab426aaf3'){throw 'prior centered candidate drift'}
$Old=Get-Content -LiteralPath $Plan -Raw|ConvertFrom-Json
foreach($R in @($Old.sourceBindings)){if((Hash (Join-Path $Package $R.path)) -cne $R.sha256.Replace('sha256:','')){throw ('source drift '+$R.path)}}
$Backup='D:\Claude\swiftright\.factory-work\retired\rectangle-centered-import-r1'
if((Test-Path -LiteralPath $Backup) -or (Test-Path -LiteralPath (Join-Path $Stage 'prebuild-r6'))){throw 'fresh stage required'}
[IO.Directory]::CreateDirectory($Backup)|Out-Null
Copy-Item -LiteralPath $Plan -Destination (Join-Path $Backup 'plan-prebuild-v4.json')
Copy-Item -LiteralPath $Adapter -Destination (Join-Path $Backup 'FactoryCenteredLayout.swift')
[IO.File]::WriteAllBytes($Adapter,[Convert]::FromBase64String('__ADAPTER__'))
[IO.File]::WriteAllBytes($Plan,[Convert]::FromBase64String('__PLAN__'))
if((Hash $Adapter) -cne '__ADAPTER_HASH__' -or (Hash $Plan) -cne '__PLAN_HASH__'){throw 'written bytes drift'}
$Builder=Join-Path $Stage 'build-owned-centered-v1.ps1'
if((Hash $Builder) -cne '__BUILDER_HASH__'){throw 'builder drift'}
& $Builder -PlanPath $Plan -PlanSha256 '__PLAN_HASH__' -Phase prebuild -Attempt 6 -PreflightOnly
& $Builder -PlanPath $Plan -PlanSha256 '__PLAN_HASH__' -Phase prebuild -Attempt 6
Get-Content -LiteralPath (Join-Path $Stage 'prebuild-r6\observation.json') -Raw
'''
for key,value in {'OLD':oldhash,'ADAPTER':base64.b64encode(adapter).decode(),'PLAN':base64.b64encode(data).decode(),
 'ADAPTER_HASH':adapterhash,'PLAN_HASH':planhash,'BUILDER_HASH':hashlib.sha256((base/'build-owned-centered-v1.ps1').read_bytes()).hexdigest()}.items():script=script.replace('__'+key+'__',value)
(out/'FactoryCenteredLayout.swift').write_bytes(adapter);(out/'plan-prebuild-v4.json').write_bytes(data)
(out/'stage-import-fix-r2.ps1').write_text(script)
(out/'correction.json').write_text(json.dumps({'kind':'factory-centered-host-import-correction-v1',
 'failedReceiptHash':'sha256:'+hashlib.sha256((base/'archive-prebuild-r5/observation.json').read_bytes()).hexdigest(),
 'planSha256':planhash,'adapterSha256':adapterhash,'nativeActions':0,'compilerActions':0},indent=2)+'\n')
print(json.dumps({'planSha256':planhash,'adapterSha256':adapterhash,'nativeActions':0}))
