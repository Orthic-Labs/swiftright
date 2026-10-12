$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\text-baseline'
if(@(Get-Process swift,swiftc,swift-build,swift-frontend,clang -ErrorAction SilentlyContinue).Count){throw 'compiler busy'}
if((Get-FileHash (Join-Path $stage 'build-text-paint-r7.ps1')).Hash.ToLowerInvariant() -cne '6a96adbd27539dd034a21b6bb13040e2beb452bacc0096c6dc63f437460fa321'){throw 'compiler adapter pin'}
& (Join-Path $stage 'build-text-paint-r7.ps1') -PlanPath (Join-Path $stage 'package\plan-final-r7.json') -PlanSha256 'de8660b0c55a717d52171ec476b833881919696f434c3ceba077ba3b77fbc642' -Phase final -Attempt 7
