$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\image-star-observation'
$builder=Join-Path $stage 'build-owned-pilot-v1.ps1';$plan=Join-Path $stage 'package\plan-prebuild-v4.json'
if((Get-FileHash -LiteralPath $builder).Hash.ToLowerInvariant() -cne 'c2e0469bd5960a805714463413d4d70748768efac15ca6e88ec0049f64259750'){throw 'v9 builder drift'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop busy'}
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native lane busy'}
& $builder -PlanPath $plan -PlanSha256 '50796e95331c12822536db5b02862bbb97a450ea679484c1f2079fd136725c04' -Phase prebuild -Attempt 3 -PreflightOnly
& $builder -PlanPath $plan -PlanSha256 '50796e95331c12822536db5b02862bbb97a450ea679484c1f2079fd136725c04' -Phase prebuild -Attempt 3
Get-Content -LiteralPath (Join-Path $stage 'prebuild-r3\observation.json') -Raw
