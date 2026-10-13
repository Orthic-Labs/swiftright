$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$sourceStage='D:\Claude\swiftright\.work\sr0-incremental-v6-controls-r1';$stage='D:\Claude\swiftright\.work\sr0-r12-workload-v1'
$deriver=Join-Path $sourceStage 'workload-incremental-v6\derive-release-metadata.ps1';$receipt=Join-Path $stage 'build-r1-receipt.json';$manifest=Join-Path $stage 'compiled-source-manifest.json'
foreach($r in @(@($deriver,'a16e700f9eb75864151facaa5b6cd7a96d4cc9a24dfd2eef35852585d6aa00d9'),@($receipt,'14789302c49ca5a1ebd405715a12006f5eb249913cf524b6fa754581fabbb579'),@($manifest,'26705e8f1fdd0164a9963c9cb0f730fda2e313e5c07348097c8fe8ab3ef7e468'))){$i=Get-Item -LiteralPath $r[0];if($i.Length -gt 2MB -or (Get-FileHash -LiteralPath $r[0]).Hash.ToLowerInvariant() -cne $r[1]){throw 'Sealed metadata input drift'}}
$out=Join-Path $stage 'release-build-metadata-v6-r1.json'
& $deriver -StageRoot $stage -Receipt $receipt -CompiledManifest $manifest -Out $out|Out-Null
$i=Get-Item -LiteralPath $out;$m=[IO.File]::ReadAllText($out)|ConvertFrom-Json
[ordered]@{kind='root-sr0-derived-metadata-v6-v1';status='passed';path=$out;sha256=(Get-FileHash -LiteralPath $out).Hash.ToLowerInvariant();bytes=$i.Length;metadata=$m;nativeWindowActions=0;compilerActions=0;lockActions=0}|ConvertTo-Json -Depth 8
