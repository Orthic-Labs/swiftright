$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\observer-r3'
if((Get-FileHash (Join-Path $root 'observer-source-r2.ps1')).Hash.ToLowerInvariant() -cne 'e44169ba5682350fa9029efef2c99cc4b34cdbbd2b866382ca695422568ef3cb'){throw 'observer pin'}
if((Get-FileHash (Join-Path $root 'one-run-plan-r1.json')).Hash.ToLowerInvariant() -cne 'f8b67f106b2b18d9a6609a921602181c647f66fa91be88ae1e7def03f33e91f0'){throw 'plan pin'}
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $root 'observer-source-r2.ps1') -PlanPath (Join-Path $root 'one-run-plan-r1.json') -OutputPath 'D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\observer-r3.json' -TransportHelperPath 'D:\Claude\swiftright\.factory-work\root-tools\transport-v1\controls-r4\Sr0RootTransportJobV1.cs' -TransportHelperSha256 'f70ab1ebe1f70ea4833bb1944a1195e89875684882ae0541a5f9a3da5904dd2c' -DeadlineSeconds 1000
exit $LASTEXITCODE
