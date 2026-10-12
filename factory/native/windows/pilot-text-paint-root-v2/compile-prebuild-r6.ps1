$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\text-baseline'
if(@(Get-Process swift,swiftc,swift-build,swift-frontend,clang -ErrorAction SilentlyContinue).Count){throw 'compiler busy'}
if((Get-FileHash (Join-Path $stage 'build-text-paint-r6.ps1')).Hash.ToLowerInvariant() -cne 'd49b3d60493170c69fd232921666760fbb276da633c79e5c140cffd13ed52e80'){throw 'compiler adapter pin'}
& (Join-Path $stage 'build-text-paint-r6.ps1') -PlanPath (Join-Path $stage 'package\plan-prebuild-r6.json') -PlanSha256 'd5cbdc0e8bbdf2e4d8f0137f91afb02a4c26a01731314b4f0d06169c94747c54' -Phase prebuild -Attempt 6
