$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Stage='D:\Claude\swiftright\.factory-work\hosts\custom-layout-centered'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native stage busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'native session busy'}
if(Test-Path -LiteralPath $Stage){throw 'fresh pilot host stage required'}
$Zip='D:\Claude\swiftright\.factory-work\custom-layout-centered-delivery-compile-r1.zip'
if((Get-FileHash -LiteralPath $Zip).Hash.ToLowerInvariant() -cne '6a49dcb41afcafd86b237eb567e6a9676f32114ab65d85f399daeaf85ba75b7c'){throw 'pilot zip drift'}
Expand-Archive -LiteralPath $Zip -DestinationPath $Stage
$M=Get-Content -LiteralPath (Join-Path $Stage 'stage-manifest.json') -Raw|ConvertFrom-Json
$Total=0;foreach($R in @($M.files)){$F=Get-Item -LiteralPath (Join-Path $Stage $R.path) -Force;$Total+=$F.Length;if($F.Length -ne $R.bytes -or ($F.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $F.FullName).Hash.ToLowerInvariant() -cne $R.sha256){throw 'pilot staged source drift'}}
if(@($M.files).Count -gt 128 -or $Total -gt 16777216){throw 'pilot stage cap'}
$Plan=Join-Path $Stage 'package\plan-prebuild-v4.json';$Builder=Join-Path $Stage 'build-owned-pilot-v1.ps1'
& $Builder -PlanPath $Plan -PlanSha256 'ff5827c1a0f6d78cd08b0723aede875bd35fddd6b2fcba715e0fd8a440c18753' -Phase prebuild -Attempt 1 -PreflightOnly
& $Builder -PlanPath $Plan -PlanSha256 'ff5827c1a0f6d78cd08b0723aede875bd35fddd6b2fcba715e0fd8a440c18753' -Phase prebuild -Attempt 1
Get-Content -LiteralPath (Join-Path $Stage 'prebuild-r1\observation.json') -Raw
