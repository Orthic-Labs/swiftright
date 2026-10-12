$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$base='D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\incremental-v4-final-r2'
$rows=@();$total=[long]0
foreach($name in @('observation.json','compile.stdout.bin','compile.stderr.bin')){
 $path=Join-Path $base $name;$item=Get-Item -LiteralPath $path -Force
 if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -gt 1048576){throw 'bounded regular compile receipt required'}
 $total+=$item.Length;if($total -gt 2097152){throw 'aggregate compile export bound'}
 $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();$bytes=[IO.File]::ReadAllBytes($path)
 if($bytes.Length -ne $item.Length -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hash){throw 'compile receipt changed during export'}
 $rows+=[ordered]@{path=$name;bytes=$bytes.Length;sha256=$hash;base64=[Convert]::ToBase64String($bytes)}
}
$receipt=[IO.File]::ReadAllText((Join-Path $base 'observation.json'))|ConvertFrom-Json
if($receipt.kind -cne 'factory-padding-incremental-owned-compile-v4' -or $receipt.exitCode -ne 0 -or $receipt.kernelWait -ne 0 -or $receipt.kernelExitCodeRaw -ne 0 -or $receipt.streamsSealed -ne $true -or $receipt.jobActiveCount -ne 0 -or $receipt.jobActiveReadable -ne $true -or $receipt.error -or $receipt.cleanupError){throw 'compile terminal/quiescence certificate mismatch'}
[ordered]@{status='exported';files=$rows;bytes=$total;nativeActions=0;qualificationClaim=$false}|ConvertTo-Json -Depth 12
