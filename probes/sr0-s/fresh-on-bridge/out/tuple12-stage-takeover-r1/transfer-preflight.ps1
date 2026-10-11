$ErrorActionPreference = 'Stop'
$p = 'D:\Claude\swiftright\.work\sr0-stage-tools'
if (Test-Path -LiteralPath $p) { throw 'stage tools destination already exists; root must inspect before reuse' }
if (-not (Test-Path -LiteralPath 'D:\Claude\swiftright\.work' -PathType Container)) { throw 'workspace parent missing' }
Write-Output 'TRANSFER_DESTINATION_CLEAR'
