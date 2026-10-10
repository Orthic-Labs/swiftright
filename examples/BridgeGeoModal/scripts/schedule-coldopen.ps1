# Registers a one-shot INTERACTIVE scheduled task that runs drive-coldopen.ps1 in the desktop session, waits, disables (never deletes) the task it made, prints the result.
# Take D:\Claude\desktop.lock first (the Dell rule); this script does not touch it.
param([string]$Base = 'D:\Claude\sr0-t10', [string]$Scripts = 'D:\Claude\sr0-t10\examples\BridgeGeoModal\scripts', [string]$Bin = '', [int]$MaxMinutes = 40, [string]$ExtraArgs = '')
$ErrorActionPreference = 'Stop'
$task = 'SR0T10-coldopen-' + (Get-Date -Format 'yyyyMMddHHmmss')
if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) { throw "task $task already exists" }
$a = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Scripts\drive-coldopen.ps1`" -Base `"$Base`" -Bin `"$Bin`" $ExtraArgs"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $a -WorkingDirectory $Base
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes ($MaxMinutes + 5)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings -Force | Out-Null
"registered=$task at=$(Get-Date -Format o)"
Start-ScheduledTask -TaskName $task
$deadline = (Get-Date).AddMinutes($MaxMinutes)
do { Start-Sleep -Seconds 3; $st = (Get-ScheduledTask -TaskName $task).State } while ($st -eq 'Running' -and (Get-Date) -lt $deadline)
"state=$st last_result=$((Get-ScheduledTaskInfo -TaskName $task).LastTaskResult) ended=$(Get-Date -Format o)"
if ($st -eq 'Running') { Stop-ScheduledTask -TaskName $task; 'TIMEOUT: task stopped' }
Disable-ScheduledTask -TaskName $task | Out-Null      # the Dell rule: nothing is deleted; a disabled one-shot task is left behind
"disabled=$task"
