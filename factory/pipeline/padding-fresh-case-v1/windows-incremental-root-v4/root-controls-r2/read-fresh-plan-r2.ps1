[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$path='D:\Claude\swiftright\.factory-work\root-tools\padding-incremental-v4-r2\plan.json'
$expected='214e73d4239604be7580add966c86fd387fa7985fef79ee307de81846a8b2433'
$item=Get-Item -LiteralPath $path -Force
if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -gt 65536){throw 'bounded regular fresh plan required'}
$bytes=[IO.File]::ReadAllBytes($path)
$hasher=[Security.Cryptography.SHA256]::Create()
try {$hash=([BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()} finally {$hasher.Dispose()}
if($bytes.Length -ne $item.Length -or $hash -cne $expected){throw 'measured fresh compile plan hash mismatch'}
$document=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
if($document.kind -cne 'windows-padding-fresh-compile-plan-v1'){throw 'fresh compile plan schema mismatch'}
[ordered]@{
 kind='factory-padding-measured-fresh-plan-export-v1'
 status='measured-source-export'
 sourcePath=$path
 sha256=$hash
 bytes=$bytes.Length
 base64=[Convert]::ToBase64String($bytes)
 nativeActions=0
 compilerActions=0
 lockActions=0
} | ConvertTo-Json -Depth 8 -Compress
