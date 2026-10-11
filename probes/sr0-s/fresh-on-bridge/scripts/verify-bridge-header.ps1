<#
Read-only bridge-header preflight. Accepts a regular file or a resolved symlink;
rejects Git-for-Windows one-line symlink text before any build/copy.
#>
param(
  [Parameter(Mandatory = $true)][string]$Header,
  [string]$ExpectedSha256 = '',
  [int]$ExpectedBytes = 41937
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Header -PathType Leaf)) { throw "header missing: $Header" }
$item = Get-Item -LiteralPath $Header -Force
$resolved = (Resolve-Path -LiteralPath $Header).Path
$bytes = [IO.File]::ReadAllBytes($resolved)
$sha = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLower()
$text = [Text.Encoding]::ASCII.GetString($bytes)
if ($bytes.Length -lt 1024 -or $text -notmatch '(?m)^#ifndef SWIFTRIGHT_H\s*$' -or $text -notmatch '(?m)^#define SWIFTRIGHT_H\s*$') {
  throw "header is not dereferenced swiftright.h content: $resolved"
}
if ($ExpectedBytes -gt 0 -and $bytes.Length -ne $ExpectedBytes) { throw "header byte count $($bytes.Length) != expected $ExpectedBytes" }
if ($ExpectedSha256 -and $sha -ne $ExpectedSha256.ToLower()) { throw "header hash $sha != expected $($ExpectedSha256.ToLower())" }
$link = if ($item.PSObject.Properties.Name -contains 'LinkType') { [string]$item.LinkType } else { '' }
Write-Output "BRIDGE_HEADER_OK path=$resolved bytes=$($bytes.Length) sha256=$sha linkType=$link"
