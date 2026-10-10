# Registers a one-shot INTERACTIVE scheduled task that runs a driver (GPUI, UIA and the popup menu / task dialog need the
# desktop session; DXGI is unavailable over SSH), waits for it, deletes the task and prints the result file.
# PHASE 2 ONLY: this starts windows on the Dell desktop. Do not run it before the desktop is released.
param(
  [Parameter(Mandatory = $true)][ValidateSet('textgeom', 'modal')][string]$Mode,
  [string]$Base = 'D:\Claude\sr0-geomodal',
  [string]$Tag = 'final',
  [int]$Runs = 20,
  [int]$MaxMinutes = 40
)
$ErrorActionPreference = 'Stop'
$task = "SR0GM-$Mode-$Tag"
$script = "$Base\examples\BridgeGeoModal\scripts\drive-$Mode.ps1"
$out = if ($Mode -eq 'textgeom') { "$Base\result-textgeom06final.txt" } else { "$Base\result-modal06final.txt" }
if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) { throw "task $task already exists" }
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Base `"$Base`" -Runs $Runs"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArgs -WorkingDirectory $Base
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes ($MaxMinutes + 5)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings -Force | Out-Null
"registered=$task at=$(Get-Date -Format o) runs=$Runs"
Start-ScheduledTask -TaskName $task
$deadline = (Get-Date).AddMinutes($MaxMinutes)
do { Start-Sleep -Seconds 3; $st = (Get-ScheduledTask -TaskName $task).State } while ($st -eq 'Running' -and (Get-Date) -lt $deadline)
$info = Get-ScheduledTaskInfo -TaskName $task
"state=$st last_result=$($info.LastTaskResult) ended=$(Get-Date -Format o)"
if ($st -eq 'Running') { Stop-ScheduledTask -TaskName $task; 'TIMEOUT: task stopped' }
Unregister-ScheduledTask -TaskName $task -Confirm:$false
"deleted=$task exists_after=$([bool](Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue))"
if (Test-Path $out) { Get-Content -Raw $out } else { 'no result file' }
