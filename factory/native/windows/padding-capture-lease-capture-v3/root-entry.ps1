# Hash-pinned offline admission entry; no helper executes before bundle gates pass.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$map=Join-Path $here 'source-bundle-map.json';$manifest=Join-Path $here 'root-stage-manifest.json';$gate=Join-Path $here 'root-entry-gate.json'
if(-not(Test-Path -LiteralPath $map -PathType Leaf)-or -not(Test-Path -LiteralPath $manifest -PathType Leaf)-or -not(Test-Path -LiteralPath $gate -PathType Leaf)){throw 'Pinned source bundle gate missing'}
$pin=Get-Content -Raw -LiteralPath $gate|ConvertFrom-Json
if($pin.kind -cne 'factory-source-bundle-root-entry-gate-v1' -or $pin.sourceBundleMap.path -cne 'factory/native/windows/padding-capture-lease-capture-v3/source-bundle-map.json' -or $pin.rootStageManifest.path -cne 'factory/native/windows/padding-capture-lease-capture-v3/root-stage-manifest.json'){throw 'Root entry gate binding drift'}
if((Get-FileHash -LiteralPath $map).Hash.ToLowerInvariant() -cne $pin.sourceBundleMap.sha256.Replace('sha256:','') -or (Get-FileHash -LiteralPath $manifest).Hash.ToLowerInvariant() -cne $pin.rootStageManifest.sha256.Replace('sha256:','')){throw 'Root entry pinned bundle hash mismatch'}
$mapDoc=Get-Content -Raw -LiteralPath $map|ConvertFrom-Json;$manifestDoc=Get-Content -Raw -LiteralPath $manifest|ConvertFrom-Json
$mapRows=@($mapDoc.files);$manifestRows=@($manifestDoc.files)
if($mapRows.Count -lt 1 -or $manifestRows.Count -lt 1){throw 'Empty source bundle membership'}
$manifestByPath=@{};foreach($row in $manifestRows){if($manifestByPath.ContainsKey($row.path)){throw 'Duplicate root manifest path'};$manifestByPath[$row.path]=$row}
$mapByPath=@{};foreach($row in $mapRows){if($mapByPath.ContainsKey($row.path)){throw 'Duplicate source map path'};$mapByPath[$row.path]=$row}
foreach($row in $mapRows){
 $externalAllow=@('factory/native/windows/padding-capture-lease-build-v1/root-stage-manifest.json','factory/native/windows/padding-capture-lease-build-v1/root-transfer-v1/transfer-manifest.json','factory/native/windows/padding-capture-lease-build-v1/actual-build-r1/observation.json','factory/native/windows/padding-capture-lease-capture-v1/root-stage-manifest.json')
 if(($row.path -notmatch '^factory/native/windows/padding-capture-lease-capture-v3/' -and $externalAllow -notcontains $row.path) -or $row.path -match '\.factory-work|[\r\n]'){throw 'Unsafe source bundle path'}
 if(-not $manifestByPath.ContainsKey($row.path)){throw ('Map/manifest membership gap: '+$row.path)}
 $joined=$manifestByPath[$row.path];if($joined.bytes -ne $row.bytes -or $joined.sha256 -cne $row.sha256){throw ('Map/manifest row drift: '+$row.path)}
 $full=Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))) ($row.path -replace '/','\')
 if(-not(Test-Path -LiteralPath $full -PathType Leaf) -or (Get-Item -LiteralPath $full).Length -ne $row.bytes -or (Get-FileHash -LiteralPath $full).Hash.ToLowerInvariant() -cne $row.sha256.Replace('sha256:','')){throw ('Source bundle byte drift: '+$row.path)}
}
foreach($row in $manifestRows){if($row.path -ne $map -and $row.path -notmatch '^factory/native/windows/padding-capture-lease-capture-v3/' -and $externalAllow -notcontains $row.path){throw ('Manifest path outside allowlist: '+$row.path)};$full=Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $here)))) ($row.path -replace '/','\');if(-not(Test-Path -LiteralPath $full -PathType Leaf) -or (Get-Item -LiteralPath $full).Length -ne $row.bytes -or (Get-FileHash -LiteralPath $full).Hash.ToLowerInvariant() -cne $row.sha256.Replace('sha256:','')){throw ('Root manifest byte drift: '+$row.path)}}
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh root entry output required'}
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
& (Join-Path $here 'test-source-string-controls.ps1') -OutputPath (Join-Path $OutputRoot 'source-string-controls.json')
& (Join-Path $here 'test-producer-fault-controls.ps1') -OutputPath (Join-Path $OutputRoot 'producer-fault-controls.json')
[ordered]@{kind='factory-consumer-schema-controls-v1';status='held-unrun-on-windows';command='factory/.venv/bin/python factory/native/windows/padding-capture-lease-capture-v3/test-candidate-fault-controls.py';reason='Consumer adapter/jsonschema dependency closure is locally verified only'}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'consumer-schema-controls.json')
& (Join-Path $here 'run-controls.ps1') -OutputRoot (Join-Path $OutputRoot 'headless-controls')
[ordered]@{kind='factory-source-bundle-root-entry-v3';status='passed-source-gates-consumer-held';qualification='hold-consumer-schema-and-native';sourceBundleMapPath=$map;sourceBundleMapSha256=(Get-FileHash -LiteralPath $map).Hash.ToLowerInvariant();rootStageManifestPath=$manifest;rootStageManifestSha256=(Get-FileHash -LiteralPath $manifest).Hash.ToLowerInvariant();nativeWindowActions=0;swiftRustHostBuildActions=0;compilerActions='PowerShell Add-Type fixture compilation occurs in run-controls';guiActions=0;remoteActions=0;lockActions=0}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'root-entry.json')
