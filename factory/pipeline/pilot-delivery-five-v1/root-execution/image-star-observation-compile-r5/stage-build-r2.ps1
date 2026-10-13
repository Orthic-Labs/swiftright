$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Stage='D:\Claude\swiftright\.factory-work\hosts\image-star-observation'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native stage busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'native session busy'}
$Root=Split-Path $Stage
$Expected=@('circle','circle-close-r1','custom-layout-colors','image','padding-fresh-r11-r3','padding-settled','padding-window-diagnosis','rectangle','rounded-stroke','rounded-stroke-centered','rounded-stroke-circular','stack-lifecycle','system-star-fill','text-baseline')
$Actual=@(Get-ChildItem -LiteralPath $Root -Directory|Select-Object -ExpandProperty Name)
if(@(Compare-Object $Expected $Actual).Count){throw 'terminal cohort inventory drift'}
$Old='D:\Claude\swiftright\.factory-work\retired-hosts\terminal-cohort-20261013-r1'
if(Test-Path -LiteralPath $Old){throw 'terminal cohort destination already exists'}
New-Item -ItemType Directory -Path $Old | Out-Null
foreach($Name in $Expected){if($Name -notin @('custom-layout-colors','rectangle')){
 Move-Item -LiteralPath (Join-Path $Root $Name) -Destination (Join-Path $Old $Name)
}}
Write-Output ('Moved terminal host cohort: '+($Expected|Where-Object{$_ -notin @('custom-layout-colors','rectangle')}|ConvertTo-Json -Compress))
if(Test-Path -LiteralPath $Stage){throw 'fresh pilot host stage required'}
if(@(Get-ChildItem -LiteralPath $Root -Directory).Count -ge 3){throw 'active host limit before stage'}
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
