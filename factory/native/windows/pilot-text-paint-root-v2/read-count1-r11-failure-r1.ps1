$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count1-r11'
$pairs=@();$inventory=@()
foreach($relative in @('control-count1-r5','native\count1-r5','native\count1-r5\native-01')){
 $dir=Join-Path $root $relative
 if(-not(Test-Path -LiteralPath $dir -PathType Container)){continue}
 $files=@(Get-ChildItem -LiteralPath $dir -File -Force)
 if($files.Count -gt 64){throw 'failure inventory bound'}
 foreach($file in $files){
  if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'failure reparse rejected'}
  $inventory+=@{path=$file.FullName;bytes=$file.Length}
  if($file.Name -match '\.(json|txt|log)$' -and $file.Length -le 1048576){$pairs+=,@(($relative.Replace('\','-')+'-'+$file.Name),$file.FullName)}
 }
}
if($pairs.Count -gt 32){throw 'failure export file count bound'}
$rows=@();$total=[long]0
foreach($pair in $pairs){
 $file=Get-Item -LiteralPath $pair[1] -Force;$total+=$file.Length
 if($total -gt 4194304){throw 'failure export aggregate bound'}
 $hash=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant();$bytes=[IO.File]::ReadAllBytes($file.FullName)
 if($bytes.Length -ne $file.Length -or (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant() -cne $hash){throw 'failure evidence changed'}
 $rows+=@{path=$pair[0];bytes=$bytes.Length;sha256=$hash;base64=[Convert]::ToBase64String($bytes)}
}
[ordered]@{status='exported';files=$rows;bytes=$total;inventory=$inventory;desktopLock=[IO.File]::ReadAllText('D:\Claude\desktop.lock').Trim();nativeActions=0;qualificationClaim=$false}|ConvertTo-Json -Depth 18
