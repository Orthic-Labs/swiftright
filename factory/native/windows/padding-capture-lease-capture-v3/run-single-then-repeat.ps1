# Root-owned execution entry; sequential source-gated first1 thenfresh20, no retries/promotion.
param([Parameter(Mandatory=$true)][string]$CompileReceiptHash,[Parameter(Mandatory=$true)][string]$ExeHash,[Parameter(Mandatory=$true)][string]$SerializerControlSha256)
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'coordinator.ps1') -Count 1 -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash -SerializerControlSha256 $SerializerControlSha256
# Coordinator20 independently replays strong original-success firstproof before acquiring fresh owner.
& (Join-Path $PSScriptRoot 'coordinator.ps1') -Count 20 -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash -SerializerControlSha256 $SerializerControlSha256
