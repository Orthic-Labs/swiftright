[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$CollectorPath,
  [Parameter(Mandatory)][string]$CoordinatorPath,
  [Parameter(Mandatory)][string]$LauncherPath,
  [Parameter(Mandatory)][string]$TaskName,
  [Parameter(Mandatory)][string]$OutputPath,
  [int64]$MaxJsonBytes = 1048576
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'r12-failure-admission-v1.ps1')
if (Test-Path -LiteralPath $OutputPath) { throw "fresh output required: $OutputPath" }
$parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
$verdict = Test-R12OriginalFailureQuiescence -CollectorPath $CollectorPath -CoordinatorPath $CoordinatorPath -LauncherPath $LauncherPath -TaskName $TaskName -MaxJsonBytes $MaxJsonBytes
$tmp = "$OutputPath.$PID.$([guid]::NewGuid().ToString('N')).tmp"
if (Test-Path -LiteralPath $tmp) { throw "fresh temporary output required: $tmp" }
$json = $verdict | ConvertTo-Json -Depth 12
$s = [IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try { $b = [Text.Encoding]::UTF8.GetBytes("$json`r`n"); $s.Write($b,0,$b.Length); $s.Flush($true) } finally { $s.Dispose() }
[IO.File]::Move($tmp,$OutputPath)
if ([string]$verdict.status -ne 'early-failure-held') { exit 17 }
exit 0
