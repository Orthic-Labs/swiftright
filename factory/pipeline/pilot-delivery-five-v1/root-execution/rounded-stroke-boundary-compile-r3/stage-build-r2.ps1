$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Stage='D:\Claude\swiftright\.factory-work\hosts\rounded-stroke-boundary'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native stage busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'native session busy'}
$OldStage='D:\Claude\swiftright\.factory-work\hosts\image-star-observation'
$Retired='D:\Claude\swiftright\.factory-work\retired-hosts\image-v10-observed-20261013-r7'
if(Test-Path -LiteralPath $Retired){throw 'retired destination already exists'}
if(-not(Test-Path -LiteralPath $OldStage)){throw 'expected terminal image stage missing'}
$Co=Get-Content -LiteralPath (Join-Path $OldStage 'captures\count1-r7\control-count1-r7\coordinator.json') -Raw|ConvertFrom-Json
if($Co.status -ne 'completed-source-bound-observation' -or -not $Co.lockReleased -or -not $Co.wholeBatchExitConfirmed -or @($Co.cleanupErrors).Count){throw 'image stage not terminal'}
Move-Item -LiteralPath $OldStage -Destination $Retired
if(@(Get-ChildItem -LiteralPath (Split-Path $Stage) -Directory).Count -ge 3){throw 'active host limit'}
if(Test-Path -LiteralPath $Stage){throw 'fresh pilot host stage required'}
$Zip='D:\Claude\swiftright\.factory-work\rounded-stroke-boundary-delivery-compile-r3.zip'
if((Get-FileHash -LiteralPath $Zip).Hash.ToLowerInvariant() -cne '13c83bd5bb574a2d74ec52d42dd5e95117e5e6b66eef038a6e8585d8e75459a3'){throw 'pilot zip drift'}
Expand-Archive -LiteralPath $Zip -DestinationPath $Stage
$M=Get-Content -LiteralPath (Join-Path $Stage 'stage-manifest.json') -Raw|ConvertFrom-Json
$Total=0;foreach($R in @($M.files)){$F=Get-Item -LiteralPath (Join-Path $Stage $R.path) -Force;$Total+=$F.Length;if($F.Length -ne $R.bytes -or ($F.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $F.FullName).Hash.ToLowerInvariant() -cne $R.sha256){throw 'pilot staged source drift'}}
if(@($M.files).Count -gt 128 -or $Total -gt 16777216){throw 'pilot stage cap'}
$Plan=Join-Path $Stage 'package\plan-prebuild-v4.json';$Builder=Join-Path $Stage 'build-owned-pilot-v1.ps1'
& $Builder -PlanPath $Plan -PlanSha256 'dab81b2e3facc60d3d59228c17aba2cb3d266ac3979023b5bebe1d3e7366872c' -Phase prebuild -Attempt 1 -PreflightOnly
& $Builder -PlanPath $Plan -PlanSha256 'dab81b2e3facc60d3d59228c17aba2cb3d266ac3979023b5bebe1d3e7366872c' -Phase prebuild -Attempt 1
Get-Content -LiteralPath (Join-Path $Stage 'prebuild-r1\observation.json') -Raw
