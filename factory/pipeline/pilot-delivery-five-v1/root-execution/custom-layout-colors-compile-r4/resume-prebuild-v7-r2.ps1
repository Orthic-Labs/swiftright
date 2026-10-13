# Root-owned resume after source-only staging; historical failed entry remains immutable.
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\custom-layout-colors'
$pkg=Join-Path $stage 'package'
$plan=Join-Path $pkg 'plan-prebuild-v4.json'
$packagePlan=Join-Path $pkg 'plan.json'
$builder=Join-Path $stage 'build-owned-pilot-v1.ps1'
$helper=Join-Path $stage 'Sr0OwnedJobProcess.cs'
function Hash([string]$p) {
  $f=Get-Item -LiteralPath $p -Force
  if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $f.Length -gt 67108864){throw 'bounded regular file required'}
  (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
}
foreach($p in @($plan,$packagePlan,$builder,$helper)){if(-not (Test-Path -LiteralPath $p -PathType Leaf)){throw ('missing installed input: '+$p)}}
if((Hash $plan) -cne 'b12e789843ccd6a31b1c214c4ab6c2b8523418b5110f698395ebe1364d37e241'){throw 'compile plan hash drift'}
if((Hash $packagePlan) -cne '6eae21b6d888c3c7f8abd7e564c62d259eafa45cc7d93ac185ce46da6fea701c'){throw 'package plan hash drift'}
if((Hash $builder) -cne '9c15fd8a6c1b43fe3f1b4a728f674e1dea0a3d5d3616c46903e9f72a07f166a2'){throw 'builder hash drift'}
if((Hash $helper) -cne '112e5775dc01282b0938dada7b9cec20412f82744257177f0a7846c2a723c69e'){throw 'helper hash drift'}
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native lane busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop busy'}
$preflight=& $builder -PlanPath $plan -PlanSha256 'b12e789843ccd6a31b1c214c4ab6c2b8523418b5110f698395ebe1364d37e241' -Phase prebuild -Attempt 1 -PreflightOnly
$preflightRecord=$preflight|ConvertFrom-Json
if($preflightRecord.status -cne 'passed' -or $preflightRecord.compilerStarted -ne $false -or $preflightRecord.nativeActions -ne 0 -or $preflightRecord.memoryCapBytes -ne 1073741824){throw 'prebuild preflight status failed'}
$preflightRecord|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $stage 'prebuild-preflight-r2.json') -Encoding UTF8
& $builder -PlanPath $plan -PlanSha256 'b12e789843ccd6a31b1c214c4ab6c2b8523418b5110f698395ebe1364d37e241' -Phase prebuild -Attempt 1
