$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$observer='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\observer-v5-r6.json'
$root='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v5-r6'
foreach($path in @($observer,(Join-Path $root 'launcher-receipt.json'),(Join-Path $root 'coordinator-receipt.json'),(Join-Path $root 'collector-receipt.json'))){if(Test-Path -LiteralPath $path){$i=Get-Item -LiteralPath $path;if($i.Length -gt 2MB){throw 'bounded inspection'};[ordered]@{path=$path;bytes=$i.Length;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant();data=(Get-Content -LiteralPath $path -Raw|ConvertFrom-Json)}|ConvertTo-Json -Depth 16}}
[ordered]@{lock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw)}|ConvertTo-Json
