$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\text-baseline'
if(@(Get-Process swift,swiftc,swift-build,swift-frontend,clang -ErrorAction SilentlyContinue).Count){throw 'compiler busy'}
if((Get-FileHash (Join-Path $stage 'build-text-style-r4.ps1')).Hash.ToLowerInvariant() -cne '21edf540b76c343dc41bb0400de37690d9842b9c925b81e82b5c6ad63351f25f'){throw 'compiler adapter pin'}
& (Join-Path $stage 'build-text-style-r4.ps1') -PlanPath (Join-Path $stage 'package\plan-prebuild-r4.json') -PlanSha256 '29276d6f310e8a9a9859167d09beaa9ad495f7f9af3a818277b21886a95497d7' -Phase prebuild -Attempt 4
