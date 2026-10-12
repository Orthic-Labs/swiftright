$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\circle'
if(@(Get-Process swift,swiftc,swift-build,swift-frontend,clang -ErrorAction SilentlyContinue).Count){throw 'compiler busy'}
if((Get-FileHash (Join-Path $stage 'build-circle-owned-v2.ps1')).Hash.ToLowerInvariant() -cne '3d4b4d4cee16ad0ee974b624d6fb0eee2c2ce77ac82a7ed8d719b09d34c12808'){throw 'compiler adapter pin'}
& (Join-Path $stage 'build-circle-owned-v2.ps1') -PlanPath (Join-Path $stage 'package\plan-final-v2.json') -PlanSha256 '23f99cc23c81b2bb49b8bbe60a77123a94b840c8f2a0851073cd981760a5e308' -Phase final -Attempt 2 
