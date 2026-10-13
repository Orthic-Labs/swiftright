$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Stage='D:\Claude\swiftright\.factory-work\hosts\image-star-observation'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native stage busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'native session busy'}
if(Test-Path -LiteralPath $Stage){
 $OldExe=Join-Path $Stage 'package\build-bound-r1\scratch\x86_64-unknown-windows-msvc\release\FactoryProbe.exe'
 if((Get-FileHash -LiteralPath $OldExe).Hash.ToLowerInvariant() -cne '44824c3a2104a63748d9ab2c9dd3e051543a36e5788da31e6c2a1f9ab8daccd6'){throw 'retiring host identity drift'}
 $Retired='D:\Claude\swiftright\.factory-work\retired-hosts\image-star-observation-v9-20261013-r1'
 if(Test-Path -LiteralPath $Retired){throw 'retired destination already exists'}
 New-Item -ItemType Directory -Path (Split-Path $Retired) -Force | Out-Null
 Move-Item -LiteralPath $Stage -Destination $Retired
 Write-Output ('Retired terminal image v9 to '+$Retired)
}
if(@(Get-ChildItem -LiteralPath (Split-Path $Stage) -Directory).Count -ge 3){throw 'active host limit before stage'}
$Zip='D:\Claude\swiftright\.factory-work\image-star-observation-delivery-compile-r5.zip'
if((Get-FileHash -LiteralPath $Zip).Hash.ToLowerInvariant() -cne 'ad0148d34bd9d64a71deacec021b52d4999f79dd2878e418422a2794d19a7e26'){throw 'pilot zip drift'}
Expand-Archive -LiteralPath $Zip -DestinationPath $Stage
$M=Get-Content -LiteralPath (Join-Path $Stage 'stage-manifest.json') -Raw|ConvertFrom-Json
$Total=0;foreach($R in @($M.files)){$F=Get-Item -LiteralPath (Join-Path $Stage $R.path) -Force;$Total+=$F.Length;if($F.Length -ne $R.bytes -or ($F.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $F.FullName).Hash.ToLowerInvariant() -cne $R.sha256){throw 'pilot staged source drift'}}
if(@($M.files).Count -gt 128 -or $Total -gt 16777216){throw 'pilot stage cap'}
$Plan=Join-Path $Stage 'package\plan-prebuild-v4.json';$Builder=Join-Path $Stage 'build-owned-pilot-v1.ps1'
& $Builder -PlanPath $Plan -PlanSha256 '18a3fe6884e5a83cb3878b48279758e516ac81701515221631f48674b27a7855' -Phase prebuild -Attempt 1 -PreflightOnly
& $Builder -PlanPath $Plan -PlanSha256 '18a3fe6884e5a83cb3878b48279758e516ac81701515221631f48674b27a7855' -Phase prebuild -Attempt 1
Get-Content -LiteralPath (Join-Path $Stage 'prebuild-r1\observation.json') -Raw
