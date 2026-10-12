$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\text-baseline';$z=Join-Path $stage 'source-paint-r1.zip'
if((Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -cne 'free'){throw 'stage requires released desktop'}
if(@(Get-Process swift,swiftc,swift-build,swift-frontend,clang -ErrorAction SilentlyContinue).Count){throw 'compiler busy'}
if((Get-Item $z).Length -gt 1048576 -or (Get-FileHash $z).Hash.ToLowerInvariant() -cne '151d600c5bfcc7aad586d7bdc89d1ed702469b29b6e72953b97941fe83e9644f'){throw 'archive pin'}
if((Get-FileHash (Join-Path $stage 'package\Sources\FactoryProbe\main.swift')).Hash.ToLowerInvariant() -cne '46d801645d479cbf459f08bac1292c5f3c89d82acf56862f0ad1549aa5093a95'){throw 'predecessor main pin'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$a=[IO.Compression.ZipFile]::OpenRead($z)
try{foreach($e in $a.Entries){$f=Join-Path $stage $e.FullName;$i=$e.Open();$o=[IO.File]::Open($f,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$i.CopyTo($o,1048576)}finally{$o.Dispose();$i.Dispose()}}}finally{$a.Dispose()}
if((Get-FileHash (Join-Path $stage 'stage-manifest-r1.json')).Hash.ToLowerInvariant() -cne '4a51ad01516df998ae6744f5d7c3df6f52f0cc44103a4401d5ca2e70971fa5c0'){throw 'stage manifest pin'}
$m=Get-Content -Raw (Join-Path $stage 'stage-manifest-r1.json')|ConvertFrom-Json
foreach($r in $m.rows){$f=Join-Path $stage $r.path;if((Get-Item $f).Length -ne $r.bytes -or (Get-FileHash $f).Hash.ToLowerInvariant() -cne $r.sha256){throw 'source stage bytes'}}
& (Join-Path $stage 'build-text-paint-r6.ps1') -PlanPath (Join-Path $stage 'package\plan-prebuild-r6.json') -PlanSha256 'd5cbdc0e8bbdf2e4d8f0137f91afb02a4c26a01731314b4f0d06169c94747c54' -Phase prebuild -Attempt 6 -PreflightOnly
