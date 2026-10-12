$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\observer-r4'
if((Get-FileHash (Join-Path $root 'observer-source-r2.ps1')).Hash.ToLowerInvariant() -cne '5bf73c1a2401ad13372b6bb6eac6f07e14afb7998aa9e32cf21f06059ca0a837'){throw 'observer pin'}
if((Get-FileHash (Join-Path $root 'one-run-plan-r1.json')).Hash.ToLowerInvariant() -cne '7bf90ad999ee6ef0ccfc305f7c0c4b409633cd874716cbe7a1b048f4c8cc7bf1'){throw 'plan pin'}
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'observer-source-r2.ps1') -PlanPath (Join-Path $root 'one-run-plan-r1.json') -OutputPath 'D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\observer-r4.json' -TransportHelperPath 'D:\Claude\swiftright\.factory-work\root-tools\transport-v1\controls-r4\Sr0RootTransportJobV1.cs' -TransportHelperSha256 'f70ab1ebe1f70ea4833bb1944a1195e89875684882ae0541a5f9a3da5904dd2c' -DeadlineSeconds 1000
exit $LASTEXITCODE
