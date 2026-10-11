$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\stack-lifecycle\package\build-lifecycle-r1'
$ob=Get-Content (Join-Path $root 'observation.json') -Raw|ConvertFrom-Json
$rows=@(Get-ChildItem -LiteralPath $root -Recurse -File|Where-Object{-not $_.FullName.StartsWith((Join-Path $root 'scratch')+'\',[StringComparison]::OrdinalIgnoreCase)}|ForEach-Object{@{path=$_.FullName.Substring($root.Length+1);bytes=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})
@{root=$root;rows=$rows;exeSha256=$ob.exeSha256;receiptSha256=(Get-FileHash (Join-Path $root 'observation.json')).Hash.ToLowerInvariant();exitCode=$ob.exitCode;ownedExited=$ob.ownedExited;error=$ob.error;cleanupError=$ob.cleanupError;streamDrainComplete=$ob.streamDrainComplete}|ConvertTo-Json -Depth 12
