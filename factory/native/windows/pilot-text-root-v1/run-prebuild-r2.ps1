$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\text-baseline'
& (Join-Path $stage 'build-text-r2.ps1') -PlanPath (Join-Path $stage 'package\plan-prebuild-r2.json') -PlanSha256 '7ef11e3921290d8872dad95e8f16d5bb16c03430dfe72671206020c2df0a107a' -Phase prebuild -Attempt 2
Get-Content -Raw (Join-Path $stage 'prebuild-r2\observation.json')
