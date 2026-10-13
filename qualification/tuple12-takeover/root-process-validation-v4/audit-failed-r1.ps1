$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.work\sr0-incremental-v4-controls-r1'
$proof=Join-Path $stage 'actual-job-controls-r1\positive\supervisor.json'
$item=Get-Item -LiteralPath $proof;if($item.Length -gt 64KB){throw 'Proof bound'}
$p=[IO.File]::ReadAllText($proof)|ConvertFrom-Json
if(-not $p.quiescent -or -not $p.terminal -or -not $p.streamsDrained -or -not $p.activeReadable -or $p.activeProcesses -ne 0){throw 'Failed job cleanup not proven'}
$p|ConvertTo-Json -Depth 5
