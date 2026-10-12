$ErrorActionPreference='Stop'
$stage='D:\Claude\swiftright\.factory-work\hosts\stack-overlay-colors'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'owned lane busy'}
if((Get-Content 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop busy'}
if(Test-Path (Join-Path $stage 'final-r1\observation.json')){throw 'actual final receipt exists; preserve before reuse'}
$saved=Join-Path $stage 'failed-final-source-r1'
if(Test-Path $saved){throw 'fresh archive required'}
New-Item -ItemType Directory -Path $saved|Out-Null
foreach($name in @('requests-final-r1','prebuild-archive-attempt-2','package\plan-final-v4.json','build-owned-final-v1.ps1')){
 $path=Join-Path $stage $name
 if(-not(Test-Path -LiteralPath $path)){throw "expected failed final input missing: $name"}
 Move-Item -LiteralPath $path -Destination (Join-Path $saved (Split-Path $name -Leaf))
}
[ordered]@{status='passed';compilerJobs=0;nativeActions=0;deleted=0;preserved=$saved;reason='stale strict builder candidate rejected before compiler'}|ConvertTo-Json -Compress
