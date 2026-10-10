# One-shot INTERACTIVE scheduled task running run-cross.ps1 for one config; waits; unregisters its own task; prints the run log.
# Take D:\Claude\desktop.lock before calling (the caller owns the lock protocol).
param([string]$Config = 'F1', [string]$Tag = 'r1', [string]$Base = 'D:\Claude\sr0o-f1',
      [string]$Recorder = 'D:\Claude\sr0o-f1\scratch\release\UIARecorder.exe',
      [string]$Bin = 'D:\Claude\sr0-r11\src\scratch\out\Products\Release-windows-x86_64')
$ErrorActionPreference = 'Stop'
$task = "SR0O-CROSS-$Config-$Tag"
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Base\scripts\run-cross.ps1`" -Config $Config -Tag $Tag -Recorder `"$Recorder`" -Bin `"$Bin`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArgs -WorkingDirectory $Base
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 6) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings -Force | Out-Null
"registered=$task at=$(Get-Date -Format o)"
Start-ScheduledTask -TaskName $task
$deadline = (Get-Date).AddMinutes(5)
do { Start-Sleep -Seconds 2; $st = (Get-ScheduledTask -TaskName $task).State } while ($st -eq 'Running' -and (Get-Date) -lt $deadline)
$info = Get-ScheduledTaskInfo -TaskName $task
"state=$st last_result=$($info.LastTaskResult)"
Unregister-ScheduledTask -TaskName $task -Confirm:$false
"deleted=$task exists_after=$([bool](Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue))"
$l = "$Base\out\run-$Tag.log"
if (Test-Path $l) { Get-Content -Raw $l } else { 'no run log' }
