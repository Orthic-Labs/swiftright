$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\text-baseline'
if(@(Get-Process swift,swiftc,swift-build,swift-frontend,clang -ErrorAction SilentlyContinue).Count){throw 'compiler busy'}
if((Get-FileHash (Join-Path $stage 'build-text-style-r4.ps1')).Hash.ToLowerInvariant() -cne '21edf540b76c343dc41bb0400de37690d9842b9c925b81e82b5c6ad63351f25f'){throw 'compiler adapter pin'}
& (Join-Path $stage 'build-text-style-r4.ps1') -PlanPath (Join-Path $stage 'package\plan-final-r4.json') -PlanSha256 '6377778a44a46d3bf9b1d3b2fcc6eed83fee0742cb5c64d71f5a95c7e035dd23' -Phase final -Attempt 4
