$ErrorActionPreference='Stop';$s='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\controls-r1'
. (Join-Path $s 'receipt-parser-v4.ps1')
Parse-WorkloadReceipt -Path (Join-Path $s 'archived-v7.txt') -Runs 3|ConvertTo-Json -Depth 8
$text=Read-BoundedReceipt (Join-Path $s 'archived-v7.txt')
@{length=$text.Length;prefix=$text.Substring(0,[Math]::Min(200,$text.Length));literalCrLf=$text.Contains('\r\n');actualLF=$text.Contains("`n")}|ConvertTo-Json
