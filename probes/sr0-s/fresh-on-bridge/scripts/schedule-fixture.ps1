# Registers a one-shot INTERACTIVE scheduled task that runs drive-fixture.ps1 for one fixture (the renderer and
# UI Automation need the desktop session), waits for it, deletes the task, and prints the result file.
#   -Fixture F1..F9   -Variant (see drive-fixture.ps1)   -Tag <unique run tag>
#   -Class sr0|diagnostic   -ExpectExe / -ExpectDll  SHA-256 the build tree must hold (checked before the run)
# The result file gets a first line "ARTIFACT base=... exe_sha256=... dll_sha256=... class=... fixture=... tag=...".
param(
  [string]$Base = 'D:\Claude\sr0s-bridge',
  [string]$Fixture = 'F1',
  [string]$Variant = '',
  [string]$Tag = 'run1',
  [string]$KeyMode = 'char',
  [Parameter(Mandatory)][string]$ExpectExe,
  [Parameter(Mandatory)][string]$ExpectDll,
  [ValidateSet('sr0', 'diagnostic')][string]$Class = 'sr0'
)
$ErrorActionPreference = 'Stop'
# Artifact identity first: a run never starts on a tree whose exe or renderer DLL differs from the expected hashes.
$verify = & "$PSScriptRoot\verify-artifacts.ps1" -Base $Base -ExpectExe $ExpectExe -ExpectDll $ExpectDll
$verify
# $LASTEXITCODE is not set by a script invoked with &, so test the printed verdict instead.
if ($verify -notcontains 'ARTIFACT_OK') { throw "artifact check failed; no task registered" }
$artifactLine = ($verify | Where-Object { $_ -like 'ARTIFACT base=*' } | Select-Object -First 1).Trim()
$task = "SR0S-Fix-$Tag"
$out = "$Base\result-$Fixture-$Tag.txt"
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Base\probes\sr0-s\fresh-on-bridge\scripts\drive-fixture.ps1`" -Base `"$Base`" -Fixture $Fixture -Variant `"$Variant`" -Out `"$out`" -KeyMode $KeyMode"
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
if (Test-Path -LiteralPath $out) {
  $header = "$artifactLine class=$Class fixture=$Fixture variant=$Variant tag=$Tag"
  $body = Get-Content -Raw -LiteralPath $out
  [IO.File]::WriteAllText($out, $header + "`r`n" + $body, (New-Object Text.UTF8Encoding $false))
  Get-Content -Raw -LiteralPath $out
} else { 'no result file' }
