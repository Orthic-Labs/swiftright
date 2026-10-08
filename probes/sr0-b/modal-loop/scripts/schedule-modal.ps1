# SR0-B modal-loop: register a one-shot INTERACTIVE scheduled task that runs run-modal.ps1,
# start it, wait for it to finish, then delete the task. Run this via `win` (SSH).
param(
  [string]$Base = 'D:\Claude\sr0b-modal-loop',
  [string]$Tag = 'run1'
)
$ErrorActionPreference = 'Stop'
$task = "SR0B-Modal-$Tag"
$out = "$Base\result-$Tag.txt"
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Base\scripts\run-modal.ps1`" -Out `"$out`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArgs -WorkingDirectory $Base
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings -Force | Out-Null
"registered=$task at=$(Get-Date -Format o)"
Start-ScheduledTask -TaskName $task
$deadline = (Get-Date).AddMinutes(4)
do { Start-Sleep -Seconds 2; $st = (Get-ScheduledTask -TaskName $task).State } while ($st -eq 'Running' -and (Get-Date) -lt $deadline)
$info = Get-ScheduledTaskInfo -TaskName $task
"state=$st last_result=$($info.LastTaskResult) last_run=$($info.LastRunTime.ToString('o'))"
Unregister-ScheduledTask -TaskName $task -Confirm:$false
"deleted=$task exists_after=$([bool](Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue))"
if (Test-Path $out) { Get-Content -Raw $out } else { 'no result file' }
