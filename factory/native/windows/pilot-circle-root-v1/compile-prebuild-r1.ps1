$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\circle'
if((Get-FileHash (Join-Path $stage 'build-circle-owned-v1.ps1')).Hash.ToLowerInvariant() -cne 'e8492ca270fa6f41efb6023fb12bdc2cde8d7580dc7c174dbc8c59f76c5774f3'){throw 'build source pin'}
& (Join-Path $stage 'build-circle-owned-v1.ps1') -PlanPath (Join-Path $stage 'package\plan-prebuild-v1.json') -PlanSha256 'f9747d06ad5120a71096ee99b2e1784e7eb247cdd3008cacb70a16273e59212d' -Phase prebuild -Attempt 1
