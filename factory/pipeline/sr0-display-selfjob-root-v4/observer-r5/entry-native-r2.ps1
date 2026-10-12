$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\observer-r5'
if((Get-FileHash (Join-Path $root 'observer-source-r2.ps1')).Hash.ToLowerInvariant() -cne '0bf4ab3a1e0b3ebad5c97dd64ddac239031ab8650126e569c30dfe2e042c50b2'){throw 'observer pin'}
if((Get-FileHash (Join-Path $root 'one-run-plan-r1.json')).Hash.ToLowerInvariant() -cne 'f84fc7cefcf7070f77ad27e04c7aa06780fff5b096453a1c5607ec256341e44a'){throw 'plan pin'}
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'observer-source-r2.ps1') -PlanPath (Join-Path $root 'one-run-plan-r1.json') -OutputPath 'D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\observer-r5.json' -TransportHelperPath 'D:\Claude\swiftright\.factory-work\root-tools\transport-v1\controls-r4\Sr0RootTransportJobV1.cs' -TransportHelperSha256 'f70ab1ebe1f70ea4833bb1944a1195e89875684882ae0541a5f9a3da5904dd2c' -DeadlineSeconds 1000
exit $LASTEXITCODE
