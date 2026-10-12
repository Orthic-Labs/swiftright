$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\observer-r6'
if((Get-FileHash (Join-Path $root 'observer-source-r2.ps1')).Hash.ToLowerInvariant() -cne '986e2c306d1a05dcd92d39469d201dab280f7c29e61f3b6452fb69e439a599d1'){throw 'observer pin'}
if((Get-FileHash (Join-Path $root 'one-run-plan-r1.json')).Hash.ToLowerInvariant() -cne 'b019e593852242870682f573c8208c4ea93bdae0e6738d9bcea5ad5ea5c0c15f'){throw 'plan pin'}
$plan=Get-Content -LiteralPath (Join-Path $root 'one-run-plan-r1.json') -Raw|ConvertFrom-Json
$run=[IO.Path]::GetFullPath([string]$plan.runRoot);$prefix=[IO.Path]::GetFullPath([string]$plan.factoryRoot).TrimEnd('\')+'\'
if(-not $run.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $run)){throw 'fresh owned run root required'}
[IO.Directory]::CreateDirectory($run)|Out-Null
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'observer-source-r2.ps1') -PlanPath (Join-Path $root 'one-run-plan-r1.json') -OutputPath 'D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\observer-r6.json' -TransportHelperPath 'D:\Claude\swiftright\.factory-work\root-tools\transport-v1\controls-r4\Sr0RootTransportJobV1.cs' -TransportHelperSha256 'f70ab1ebe1f70ea4833bb1944a1195e89875684882ae0541a5f9a3da5904dd2c' -DeadlineSeconds 1000
exit $LASTEXITCODE
