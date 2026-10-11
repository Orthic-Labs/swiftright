<#
Parse every PowerShell file stage-tuple.ps1 invokes before any build or copy.
Read-only: Parser::ParseFile performs no script execution.
#>
param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path)
$ErrorActionPreference = 'Stop'
$relative = @(
  'probes\sr0-s\fresh-on-bridge\scripts\stage-tuple.ps1',
  'probes\sr0-s\fresh-on-bridge\scripts\audit-tuple.ps1',
  'probes\sr0-s\fresh-on-bridge\scripts\resume-tuple.ps1',
  'probes\sr0-s\fresh-on-bridge\scripts\preflight-ps1.ps1',
  'probes\sr0-s\fresh-on-bridge\scripts\verify-bridge-header.ps1',
  'probes\sr0-s\fresh-on-bridge\scripts\build-fresh.ps1',
  'probes\sr0-s\fresh-on-bridge\scripts\verify-artifacts.ps1',
  'probes\sr0-s\fresh-on-bridge\scripts\verify-manifest.ps1',
  'examples\BridgeSmoke\scripts\build-smoke.ps1',
  'examples\BridgeSmoke\scripts\build-pixels.ps1',
  'probes\sr0-b\workload\scripts\build-workload.ps1',
  'probes\sr0-b\workload\scripts\build-incremental.ps1',
  'probes\sr0-b\workload\scripts\verify-artifacts.ps1',
  'probes\sr0-b\workload\scripts\verify-manifest.ps1',
  'examples\BridgeGeoModal\scripts\build.ps1',
  'examples\SliceApp\scripts\build-windows.ps1'
)
$failed = $false
$count = 0
foreach ($rel in $relative) {
  $path = Join-Path $Root $rel
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Write-Output "PS_PARSE_MISSING $path"; $failed = $true; continue }
  $tokens = $null
  $parseErrors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors) | Out-Null
  if ($parseErrors.Count) {
    Write-Output "PS_PARSE_FAIL $path"
    $parseErrors | ForEach-Object { Write-Output ("  {0}:{1} {2}" -f $_.Extent.StartLineNumber, $_.Extent.StartColumnNumber, $_.Message) }
    $failed = $true
  } else {
    $sha = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpper()
    Write-Output "PS_PARSE_OK $path sha256=$sha"
    $count++
  }
}
if ($failed) { throw 'PowerShell parse preflight failed' }
Write-Output "PS_PARSE_ALL_OK count=$count root=$Root"
