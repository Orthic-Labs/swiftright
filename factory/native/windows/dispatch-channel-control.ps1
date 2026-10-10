# Execute eligible owned package under existing wait-reserve token. Never writes lock.
param([Parameter(Mandatory=$true)][string]$Package,[Parameter(Mandatory=$true)][string]$RunRoot,[Parameter(Mandatory=$true)][string]$ReservationRoot)
$ErrorActionPreference='Stop';$factory='D:\Claude\swiftright\factory\native\windows\'
foreach($path in @($Package,$RunRoot,$ReservationRoot)){if(-not [IO.Path]::GetFullPath($path).StartsWith($factory,[StringComparison]::OrdinalIgnoreCase)){throw 'Owned factory paths required'}}
if(Test-Path -LiteralPath $RunRoot){throw 'Fresh dispatch root required'}
$ready=Get-Content -Raw (Join-Path $ReservationRoot 'lock-ready.json')|ConvertFrom-Json
if((Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -ne $ready.owner){throw 'Reservation ownership lost'}
if(([DateTimeOffset]$ready.leaseDeadline) -lt [DateTimeOffset]::UtcNow.AddMinutes(11)){throw 'Insufficient reservation lease'}
$plan=Get-Content -Raw (Join-Path $Package 'plan.json')|ConvertFrom-Json
if($plan.synthetic -or -not $plan.tupleIndependent -or $plan.executionEligible -or $plan.purpose -notin @('fixed qualification host measurement','fixed channel control host')){throw 'Fixed compile-only channel control required'}
New-Item -ItemType Directory -Path $RunRoot|Out-Null
$config=Join-Path $RunRoot 'config.json'
[ordered]@{owner=$ready.owner;package=$Package;runRoot=$RunRoot}|ConvertTo-Json|Set-Content -Encoding UTF8 $config
$task='AlchemistF7ChannelControl-'+[Guid]::NewGuid().ToString('N');$started=$false;$status='hold-harness-error';$errorText=''
try{
 $command='powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $factory 'channel-task.ps1')+'" -Config "'+$config+'"'
 $vbs=Join-Path $RunRoot 'hidden-control.vbs'
 ('WScript.Quit CreateObject("WScript.Shell").Run("'+$command.Replace('"','""')+'", 0, True)')|Set-Content -Encoding ASCII $vbs
 $action=New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('//B //Nologo "'+$vbs+'"')
 $principal=New-ScheduledTaskPrincipal -UserId 'adrds' -LogonType Interactive -RunLevel Highest
 $settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
 Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings|Out-Null
 Start-ScheduledTask -TaskName $task;$started=$true;$deadline=[DateTime]::UtcNow.AddMinutes(10)
 while([DateTime]::UtcNow -lt $deadline){
  if((Get-Content -Raw 'D:\Claude\desktop.lock').Trim() -ne $ready.owner){throw 'Reservation ownership lost'}
  $receipt=Join-Path $RunRoot 'task-result.json'
  if(Test-Path -LiteralPath $receipt){$status=(Get-Content -Raw $receipt|ConvertFrom-Json).status;break}
  $taskState=(Get-ScheduledTask -TaskName $task).State;$taskInfo=Get-ScheduledTaskInfo -TaskName $task
  if($taskState -ne 'Running' -and $taskInfo.LastRunTime -gt [DateTime]::Now.AddMinutes(-2) -and $taskInfo.LastTaskResult -ne 267009){$status='hold-task-ended-without-receipt';break}
  Start-Sleep -Seconds 2
 }
 if($status -eq 'hold-harness-error'){$status='hold-native-timeout'}
}catch{$errorText=[string]$_}
finally{
 if($started -and $status -ne 'completed-observational-channel-control'){
  Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
  foreach($file in Get-ChildItem -LiteralPath $RunRoot -Filter '*owned-process.json' -Recurse -File){
   $owned=Get-Content -Raw $file.FullName|ConvertFrom-Json;$process=Get-Process -Id $owned.pid -ErrorAction SilentlyContinue
   if($process -and $process.Path -eq $owned.path -and $process.StartTime.ToUniversalTime().ToString('o') -eq $owned.startedAt){& taskkill /PID $process.Id /T /F|Out-Null}
  }
 }
 if($started){Get-ScheduledTaskInfo -TaskName $task|Select-Object LastRunTime,LastTaskResult,NextRunTime|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $RunRoot 'scheduled-task-receipt.json')}
 [ordered]@{kind='windows-reserved-channel-control-dispatch';status=$status;error=$errorText;owner=$ready.owner;taskName=$task;taskRetained=$started;lockModified=$false;stageModified=$false;finishedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $RunRoot 'dispatch.json')
}
