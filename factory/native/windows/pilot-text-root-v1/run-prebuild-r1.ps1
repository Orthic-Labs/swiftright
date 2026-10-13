$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\text-baseline'
& (Join-Path $stage 'build-text-r1.ps1') -PlanPath (Join-Path $stage 'package\plan-prebuild.json') -PlanSha256 '38a699dcb022f8740a242c82a8402200fd36953f2ea07401d722edad20ffc4cd' -Phase prebuild
Get-Content -Raw (Join-Path $stage 'prebuild-r1\observation.json')
