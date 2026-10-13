$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\text-baseline'
if((Get-FileHash (Join-Path $stage 'build-text-style-r5.ps1')).Hash.ToLowerInvariant() -cne '96737f5f0ac6f7ed1cd1655b864f81dd7e7789cc2d7d465be1b0e6d2ed209d68'){throw 'compiler adapter pin'}
& (Join-Path $stage 'build-text-style-r5.ps1') -PlanPath (Join-Path $stage 'package\plan-final-r5.json') -PlanSha256 '5d5b555ed1fbc52d87393f8d19fe1e7445e039888df90d9c54f7b835163a3e91' -Phase final -Attempt 5 -PreflightOnly
