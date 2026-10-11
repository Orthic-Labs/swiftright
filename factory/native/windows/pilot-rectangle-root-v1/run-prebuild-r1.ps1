$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\rectangle'
& (Join-Path $root 'build-owned.ps1') -PlanPath (Join-Path $root 'package\plan-prebuild.json') -PlanSha256 '89b3f012bedd09154b5f78ab7d7cdcbfd0f3b97d46e8d221fafcd9a5aa1671d9'
