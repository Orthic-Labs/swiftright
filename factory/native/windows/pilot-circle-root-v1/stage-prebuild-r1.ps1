$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\circle';$zip=Join-Path $stage 'package-r3.zip';$package=Join-Path $stage 'package'
if((Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -cne 'free'){throw 'stage requires released desktop'}
if((Get-Item $zip).Length -gt 16777216 -or (Get-FileHash $zip).Hash.ToLowerInvariant() -cne '51c401e6df46987fdcf97a56950d50de32598875f9445ca02bf558dd45d66456'){throw 'bounded package archive pin'}
if(Test-Path $package){throw 'fresh Circle package required'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($zip,$package)
if((Get-FileHash (Join-Path $stage 'build-circle-owned-v1.ps1')).Hash.ToLowerInvariant() -cne 'e8492ca270fa6f41efb6023fb12bdc2cde8d7580dc7c174dbc8c59f76c5774f3'){throw 'build source pin'}
& (Join-Path $stage 'build-circle-owned-v1.ps1') -PlanPath (Join-Path $package 'plan-prebuild-v1.json') -PlanSha256 'f9747d06ad5120a71096ee99b2e1784e7eb247cdd3008cacb70a16273e59212d' -Phase prebuild -PreflightOnly
