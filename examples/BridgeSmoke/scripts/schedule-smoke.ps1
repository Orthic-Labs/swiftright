# Registers a one-shot INTERACTIVE scheduled task that runs drive-smoke.ps1 (GPUI needs the
# desktop session; DXGI is unavailable over SSH), waits for it, then deletes the task.
param([string]$Base = 'D:\Claude\sr0b-abi0', [string]$Tag = 'run1')
$ErrorActionPreference = 'Stop'
$task = "SR0B-Smoke-$Tag"
$out = "$Base\result-smoke-$Tag.txt"
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Base\examples\BridgeSmoke\scripts\drive-smoke.ps1`" -Out `"$out`""
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
if (Test-Path $out) { Get-Content -Raw $out } else { 'no result file' }
