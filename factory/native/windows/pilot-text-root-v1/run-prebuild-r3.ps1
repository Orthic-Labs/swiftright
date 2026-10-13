$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\text-baseline'
& (Join-Path $stage 'build-text-r3.ps1') -PlanPath (Join-Path $stage 'package\plan-prebuild-r3.json') -PlanSha256 '801b58fbb2e5560d48c7573a396501bc10d10e443852888644081e5e1b0ecff6' -Phase prebuild -Attempt 3
Get-Content -Raw (Join-Path $stage 'prebuild-r3\observation.json')
