$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$run='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r12b\run'
$files=@(Get-ChildItem -LiteralPath $run -File -Force)
if($files.Count -gt 32){throw 'run archive count cap'}
$rows=@();$total=[long]0
foreach($f in $files){
 if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $f.Length -gt 2097152){throw 'run archive regular file cap'}
 $total+=$f.Length;if($total -gt 4194304){throw 'run archive aggregate cap'}
 $hash=(Get-FileHash -LiteralPath $f.FullName).Hash.ToLowerInvariant();$raw=[IO.File]::ReadAllBytes($f.FullName)
 if($raw.Length -ne $f.Length -or (Get-FileHash -LiteralPath $f.FullName).Hash.ToLowerInvariant() -cne $hash){throw 'run archive changed during read'}
 $rows+=[ordered]@{path=$f.Name;bytes=$raw.Length;sha256=$hash;base64=[Convert]::ToBase64String($raw)}
}
[ordered]@{status='exported';files=$rows;bytes=$total;nativeActions=0;qualificationClaim=$false}|ConvertTo-Json -Depth 12
