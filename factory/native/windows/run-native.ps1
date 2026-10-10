# Coordinator: bounded free-lock wait, owned interactive task, ownership-safe release.
param([Parameter(Mandatory=$true)][string]$Package,[Parameter(Mandatory=$true)][string]$RunRoot)
$ErrorActionPreference='Stop'
$factory='D:\Claude\swiftright\factory\native\windows\'
$packagePath=[IO.Path]::GetFullPath($Package);$runPath=[IO.Path]::GetFullPath($RunRoot)
if(-not $packagePath.StartsWith($factory,[StringComparison]::OrdinalIgnoreCase) -or -not $runPath.StartsWith($factory,[StringComparison]::OrdinalIgnoreCase)){throw 'Paths outside factory'}
if(Test-Path -LiteralPath $runPath){throw 'Use fresh run output'}
New-Item -ItemType Directory -Path $runPath|Out-Null
$lock='D:\Claude\desktop.lock'
$owner='alchemist-f7-'+[Guid]::NewGuid().ToString('N')
$task='AlchemistF7-'+[Guid]::NewGuid().ToString('N')
$log=[Collections.Generic.List[object]]::new()
function Change-Lock([string]$expected,[string]$replacement){
 try{$stream=[IO.File]::Open($lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{return $false}
 try{
  $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true,1024,$true)
  try{$state=$reader.ReadToEnd().Trim()}finally{$reader.Dispose()}
  if($state -ne $expected){return $false}
  $data=[Text.Encoding]::UTF8.GetBytes($replacement)
  $stream.Position=0;$stream.SetLength(0);$stream.Write($data,0,$data.Length);$stream.Flush($true)
  return $true
 }finally{$stream.Dispose()}
}
$acquired=$false;$started=$false;$result='hold-desktop-busy';$errorText=''
$deadline=[DateTime]::UtcNow.AddMinutes(6)
try{
 do{
  $acquired=Change-Lock 'free' $owner
  if($acquired){break}
  $state=try{(Get-Content -Raw $lock).Trim()}catch{'unreadable'}
  $log.Add([ordered]@{at=[DateTimeOffset]::UtcNow.ToString('o');state=$state;acquired=$false})
  if([DateTime]::UtcNow -ge $deadline){break}
  Start-Sleep -Seconds 3
 }while($true)
 if($acquired){
  [ordered]@{owner=$owner;package=$packagePath;runRoot=$runPath}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $runPath 'config.json')
  $config=Join-Path $runPath 'config.json'
  $script=Join-Path $factory 'native-task.ps1'
  $actionArguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$script+'" -Config "'+$config+'"'
  $action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $actionArguments
  $principal=New-ScheduledTaskPrincipal -UserId 'adrds' -LogonType Interactive -RunLevel Highest
  $settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
  Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings|Out-Null
  Start-ScheduledTask -TaskName $task;$started=$true
  $jobDeadline=[DateTime]::UtcNow.AddMinutes(10)
  $receipt=Join-Path $runPath 'task-result.json'
  do{
   if(Test-Path -LiteralPath $receipt){$result=(Get-Content -Raw $receipt|ConvertFrom-Json).status;break}
   if([DateTime]::UtcNow -ge $jobDeadline){$result='hold-native-timeout';Stop-ScheduledTask -TaskName $task;break}
   Start-Sleep -Seconds 3
  }while($true)
 }
}catch{$result='hold-harness-error';$errorText=[string]$_}
finally{
 if($started){
  $info=Get-ScheduledTaskInfo -TaskName $task -ErrorAction SilentlyContinue
  $info|Select-Object LastRunTime,LastTaskResult,NextRunTime|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $runPath 'scheduled-task-receipt.json')
 }
 if($result -like 'hold-*' -and $started){
  Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
  foreach($file in Get-ChildItem -LiteralPath $packagePath -Filter 'owned-process.json' -Recurse -File){
   $owned=Get-Content -Raw $file.FullName|ConvertFrom-Json
   $process=Get-Process -Id $owned.pid -ErrorAction SilentlyContinue
   if($process -and $process.Path -eq $owned.path -and $process.StartTime.ToUniversalTime().ToString('o') -eq $owned.startedAt){& taskkill /PID $process.Id /T /F|Out-Null}
  }
 }
 $released=if($acquired){Change-Lock $owner 'free'}else{$false}
 [ordered]@{kind='windows-native-dispatch';version='0.1';status=$result;owner=$owner;lockAcquired=$acquired;lockReleased=$released;taskName=$task;taskRetained=$started;windowedDispatch=$started;waitObservations=$log;error=$errorText;stageModified=$false}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $runPath 'dispatch.json')
}
