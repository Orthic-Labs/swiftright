# One-shot INTERACTIVE scheduled task (GUI + UIA need the desktop session; not reachable over SSH). Deleted afterwards.
param([string]$Mode = 'record', [string]$Tag = 'run1', [string]$Base = 'D:\Claude\sr0o-uia',
      [string]$Steps = "D:\Claude\sr0o-uia\uia-recorder\fixtures\bridgesmoke-steps.json")
$ErrorActionPreference = 'Stop'
$task = "SR0O-UIA-$Mode-$Tag"
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Base\uia-recorder\scripts\run-record.ps1`" -Mode $Mode -Tag $Tag -Steps `"$Steps`""
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
$log = "$Base\out\run-$Tag.log"
if (Test-Path $log) { Get-Content -Raw $log } else { 'no run log' }
