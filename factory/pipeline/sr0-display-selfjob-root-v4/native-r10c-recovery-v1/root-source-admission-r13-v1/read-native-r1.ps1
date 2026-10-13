$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$factory='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r13'
$run=Join-Path $factory 'run'
$stage='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r13'
$paths=@(
 @('observer.json',(Join-Path $factory 'native-observer-r13.json')),
 @('run-manifest.json',(Join-Path $stage 'manifest-r12-run.json')),
 @('launcher.json',(Join-Path $run 'launcher-receipt.json')),
 @('collector.json',(Join-Path $run 'collector-receipt.json')),
 @('coordinator.json',(Join-Path $run 'coordinator-verdict.json'))
)
$inventory=@()
foreach($dir in @($factory,$run,(Join-Path $stage 'control-root'))){
 if(Test-Path -LiteralPath $dir -PathType Container){
  $files=@(Get-ChildItem -LiteralPath $dir -File -Force)
  if($files.Count -gt 64){throw 'bounded failure inventory count'}
  foreach($f in $files){
   if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'failure reparse file'}
   $inventory+=@{path=$f.FullName;bytes=$f.Length}
   if($f.Name -match '^(?:parent.*|.*receipt.*|.*verdict.*|.*certificate.*|.*stdout.*|.*stderr.*)$' -and $f.Length -le 1048576 -and @($paths|Where-Object{$_[1] -ceq $f.FullName}).Count -eq 0){$paths+=,@(('extra-'+$inventory.Count+'-'+$f.Name),$f.FullName)}
  }
 }
}
if($paths.Count -gt 32){throw 'bounded failure export count'}
$rows=@();$missing=@();$total=[long]0
foreach($pair in $paths){
 if(-not(Test-Path -LiteralPath $pair[1] -PathType Leaf)){$missing+=$pair[1];continue}
 $f=Get-Item -LiteralPath $pair[1] -Force
 if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $f.Length -gt 1048576){throw 'bounded regular failure export'}
 $total+=$f.Length;if($total -gt 4194304){throw 'aggregate failure export bound'}
 $hash=(Get-FileHash -LiteralPath $f.FullName).Hash.ToLowerInvariant();$raw=[IO.File]::ReadAllBytes($f.FullName)
 if($raw.Length -ne $f.Length -or (Get-FileHash -LiteralPath $f.FullName).Hash.ToLowerInvariant() -cne $hash){throw 'failure evidence changed during read'}
 $rows+=[ordered]@{path=$pair[0];bytes=$raw.Length;sha256=$hash;base64=[Convert]::ToBase64String($raw)}
}
$task=@(Get-ScheduledTask -TaskName 'SR0-factory-display-selfjob-v7-root-r13' -ErrorAction SilentlyContinue|Select-Object TaskName,State)
[ordered]@{status='exported';files=$rows;bytes=$total;missing=$missing;inventory=$inventory;desktopLock=[IO.File]::ReadAllText('D:\Claude\desktop.lock').Trim();scheduledTasks=$task;nativeActions=0;qualificationClaim=$false}|ConvertTo-Json -Depth 16
