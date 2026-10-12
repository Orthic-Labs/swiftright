$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r12b'
$factory='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r12b'
$inputs=@(
 @('plan.json',(Join-Path $stage 'one-run-plan-r12.json')),
 @('admission-manifest.json',(Join-Path $stage 'manifest-r12-admission.json')),
 @('source-input-rows.json',(Join-Path $stage 'source-input-rows.json')),
 @('preflight.json',(Join-Path $stage 'source-preflight-r12.json')),
 @('drain-controls.json',(Join-Path $factory 'drain-controls-r11.json')),
 @('collector-controls.json',(Join-Path $factory 'collector-controls-r11.json'))
)
$rows=@();$total=[long]0
foreach($pair in $inputs){
 $item=Get-Item -LiteralPath $pair[1] -Force
 if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -gt 1048576){throw 'bounded regular admission file required'}
 $total+=$item.Length;if($total -gt 4194304){throw 'aggregate admission export bound'}
 $hash=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant();$bytes=[IO.File]::ReadAllBytes($item.FullName)
 if($bytes.Length -ne $item.Length -or (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $hash){throw 'admission bytes changed during export'}
 $rows+=[ordered]@{path=$pair[0];bytes=$bytes.Length;sha256=$hash;base64=[Convert]::ToBase64String($bytes)}
}
[ordered]@{status='exported';files=$rows;bytes=$total;nativeActions=0;qualificationClaim=$false}|ConvertTo-Json -Depth 12
