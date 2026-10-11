# One-shot INTERACTIVE scheduled task running run-f1.ps1; waits; unregisters; prints the run log.
param([string]$Mode = 'tree', [string]$Tag = 'r1', [string]$Base = 'D:\Claude\swiftright\.work\sr0o-f1', [string]$Steps = 'D:\Claude\swiftright\.work\sr0o-f1\f1-steps-win.json',
      [string]$Recorder = 'D:\Claude\swiftright\.work\sr0o-f1\scratch\release\UIARecorder.exe',
      [string]$Bin = 'D:\Claude\sr0s-bridge\scratch\out\Products\Release-windows-x86_64')
$ErrorActionPreference = 'Stop'
$task = "SR0O-F1-$Mode-$Tag"
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Base\scripts\run-f1.ps1`" -Mode $Mode -Tag $Tag -Steps `"$Steps`" -Recorder `"$Recorder`" -Bin `"$Bin`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArgs -WorkingDirectory $Base
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings -Force | Out-Null
"registered=$task at=$(Get-Date -Format o)"
Start-ScheduledTask -TaskName $task
$deadline = (Get-Date).AddMinutes(4)
do { Start-Sleep -Seconds 2; $st = (Get-ScheduledTask -TaskName $task).State } while ($st -eq 'Running' -and (Get-Date) -lt $deadline)
$info = Get-ScheduledTaskInfo -TaskName $task
"state=$st last_result=$($info.LastTaskResult)"
Unregister-ScheduledTask -TaskName $task -Confirm:$false
"deleted=$task exists_after=$([bool](Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue))"
$l = "$Base\out\run-$Tag.log"
if (Test-Path $l) { Get-Content -Raw $l } else { 'no run log' }
