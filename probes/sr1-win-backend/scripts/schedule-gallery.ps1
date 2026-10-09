# Runs SR1Gallery.exe --screen <name> --self-test in a one-shot INTERACTIVE scheduled task (the renderer needs the
# desktop session), waits for it, deletes the task and prints the captured stdout. Not run by the SR1 head start.
#   -Screen toggle|image|editor|label|list-single|list-multi|list-delete|menu|alert|dialog|shortcut|disabled
#   -Tag <unique run tag>
param(
  [string]$Base = 'D:\Claude\sr1-gallery',
  [string]$Screen = 'toggle',
  [string]$Tag = 'run1'
)
$ErrorActionPreference = 'Stop'
# build-gallery.ps1 records the release bin directory it built into; run the build first.
$bin = (Get-Content -Raw "$Base\bin-path.txt").Trim()
if (-not (Test-Path "$bin\SR1Gallery.exe")) { throw "SR1Gallery.exe missing under $bin; run build-gallery.ps1 first" }
$task = "SR1-Gal-$Screen-$Tag"
$out = "$Base\result-$Screen-$Tag.txt"
# Hidden PowerShell host: no visible console window (workspace rule for background automation).
$psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command `"& '$bin\SR1Gallery.exe' --screen $Screen --self-test *> '$out'`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs -WorkingDirectory $bin
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
if (Test-Path $out) { Get-Content -Raw $out } else { 'no result file' }
