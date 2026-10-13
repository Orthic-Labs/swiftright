$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Stage='D:\Claude\swiftright\.factory-work\hosts\rounded-stroke-boundary'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native stage busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'native session busy'}
$Retired='D:\Claude\swiftright\.factory-work\retired-hosts\rounded-failed-compile-r3-20261013'
if(Test-Path -LiteralPath $Retired){throw 'retired stage exists'}
$Previous=Get-Content -LiteralPath (Join-Path $Stage 'prebuild-r1\observation.json') -Raw|ConvertFrom-Json
if($Previous.exitCode -ne 1 -or -not $Previous.ownedExited -or -not $Previous.streamsSealed -or $Previous.kernelWait -ne 0 -or $Previous.cleanupJobActive -ne 0){throw 'failed compile not terminal'}
Move-Item -LiteralPath $Stage -Destination $Retired
if(@(Get-ChildItem -LiteralPath (Split-Path $Stage) -Directory).Count -ge 3){throw 'active host limit'}
if(Test-Path -LiteralPath $Stage){throw 'fresh pilot host stage required'}
$Zip='D:\Claude\swiftright\.factory-work\rounded-stroke-boundary-delivery-compile-r4.zip'
if((Get-FileHash -LiteralPath $Zip).Hash.ToLowerInvariant() -cne '91605c42d7dfeb60739211e254ba779923bd1e6d7724cf6a13821600c8e219e4'){throw 'pilot zip drift'}
Expand-Archive -LiteralPath $Zip -DestinationPath $Stage
$M=Get-Content -LiteralPath (Join-Path $Stage 'stage-manifest.json') -Raw|ConvertFrom-Json
$Total=0;foreach($R in @($M.files)){$F=Get-Item -LiteralPath (Join-Path $Stage $R.path) -Force;$Total+=$F.Length;if($F.Length -ne $R.bytes -or ($F.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $F.FullName).Hash.ToLowerInvariant() -cne $R.sha256){throw 'pilot staged source drift'}}
if(@($M.files).Count -gt 128 -or $Total -gt 16777216){throw 'pilot stage cap'}
$Plan=Join-Path $Stage 'package\plan-prebuild-v4.json';$Builder=Join-Path $Stage 'build-owned-pilot-v1.ps1'
& $Builder -PlanPath $Plan -PlanSha256 '2aa2bf57a7d1fe6b4dedfab8939b5848bdf446646867f1e911804b5ed3ff6ecd' -Phase prebuild -Attempt 1 -PreflightOnly
& $Builder -PlanPath $Plan -PlanSha256 '2aa2bf57a7d1fe6b4dedfab8939b5848bdf446646867f1e911804b5ed3ff6ecd' -Phase prebuild -Attempt 1
Get-Content -LiteralPath (Join-Path $Stage 'prebuild-r1\observation.json') -Raw
