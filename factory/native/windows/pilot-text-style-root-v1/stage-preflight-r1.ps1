$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\text-baseline';$z=Join-Path $stage 'source-style-r1.zip'
if((Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -cne 'free'){throw 'stage requires released desktop'}
if(@(Get-Process swift,swiftc,swift-build,swift-frontend,clang -ErrorAction SilentlyContinue).Count){throw 'compiler busy'}
if((Get-Item $z).Length -gt 1048576 -or (Get-FileHash $z).Hash.ToLowerInvariant() -cne 'b0f5cbba9e280f5cb545db421b37bb3772c14406f566ffd394f0046f68fa5c9b'){throw 'archive pin'}
if((Get-FileHash (Join-Path $stage 'package\Sources\FactoryProbe\main.swift')).Hash.ToLowerInvariant() -cne '98492c1059c7734df79cbdccfb7c56211aadb9da32b2bdca6403719faab3d0ba'){throw 'predecessor main pin'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$a=[IO.Compression.ZipFile]::OpenRead($z)
try{foreach($e in $a.Entries){$f=Join-Path $stage $e.FullName;$i=$e.Open();$o=[IO.File]::Open($f,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$i.CopyTo($o,1048576)}finally{$o.Dispose();$i.Dispose()}}}finally{$a.Dispose()}
if((Get-FileHash (Join-Path $stage 'stage-manifest-r1.json')).Hash.ToLowerInvariant() -cne '619761f83ef260ea6f2d94ac3ae3df29bcff23bd1d9d5b47f2ef9e0d4cb2d3bf'){throw 'stage manifest pin'}
$m=Get-Content -Raw (Join-Path $stage 'stage-manifest-r1.json')|ConvertFrom-Json
foreach($r in $m.rows){$f=Join-Path $stage $r.path;if((Get-Item $f).Length -ne $r.bytes -or (Get-FileHash $f).Hash.ToLowerInvariant() -cne $r.sha256){throw 'source stage bytes'}}
& (Join-Path $stage 'build-text-style-r4.ps1') -PlanPath (Join-Path $stage 'package\plan-prebuild-r4.json') -PlanSha256 '29276d6f310e8a9a9859167d09beaa9ad495f7f9af3a818277b21886a95497d7' -Phase prebuild -Attempt 4 -PreflightOnly
