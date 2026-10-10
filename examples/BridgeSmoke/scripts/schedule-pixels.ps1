# Registers a one-shot INTERACTIVE scheduled task that runs drive-pixels.ps1 in the desktop session, waits for it, and DISABLES (never deletes) the task.
# Take D:\Claude\desktop.lock first (the Dell rule); this script does not touch it.
param([ValidateSet('Smoke', 'Pixels')][string]$Target = 'Smoke', [Parameter(Mandatory = $true)][string]$Scripts, [Parameter(Mandatory = $true)][string]$Bin, [string]$Out = '', [string]$OutDir = '', [int]$Runs = 10, [int]$MaxMinutes = 20)
$ErrorActionPreference = 'Stop'
$task = 'SR0T4-pixels-' + $Target + '-' + (Get-Date -Format 'yyyyMMddHHmmss')
$a = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Scripts\drive-pixels.ps1`" -Target $Target -Bin `"$Bin`" -Runs $Runs" + $(if ($Out) { " -Out `"$Out`"" } else { '' }) + $(if ($OutDir) { " -OutDir `"$OutDir`"" } else { '' })
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $a
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes ($MaxMinutes + 5)) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings -Force | Out-Null
"registered=$task at=$(Get-Date -Format o)"
Start-ScheduledTask -TaskName $task
$deadline = (Get-Date).AddMinutes($MaxMinutes)
do { Start-Sleep -Seconds 3; $st = (Get-ScheduledTask -TaskName $task).State } while ($st -eq 'Running' -and (Get-Date) -lt $deadline)
"state=$st last_result=$((Get-ScheduledTaskInfo -TaskName $task).LastTaskResult) ended=$(Get-Date -Format o)"
if ($st -eq 'Running') { Stop-ScheduledTask -TaskName $task; 'TIMEOUT: task stopped' }
Disable-ScheduledTask -TaskName $task | Out-Null
"disabled=$task"
