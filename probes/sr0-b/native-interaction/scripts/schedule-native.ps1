# Registers a one-shot INTERACTIVE scheduled task that runs one native-interaction driver inside the desktop session
# (UIA, the renderer window and the IME need it), waits for it, deletes the task, and prints the result file.
#   -Check ime-f7 | ime-f7live | ime-f8 | narrator      -Tag <unique run tag>
#   -ExpectExe / -ExpectDll  SHA-256 the build tree must hold (checked here before registering, and again by the driver)
# Same pattern as probes/sr0-s/fresh-on-bridge/scripts/schedule-fixture.ps1. Run it through `win` as a file; it needs the
# desktop lane to be free (nothing else may use the Dell desktop while it runs: it types real keys into the probe window).
param(
  [string]$Base = 'D:\Claude\sr0s-bridge06b',
  [Parameter(Mandatory)][ValidateSet('ime-f7', 'ime-f7live', 'ime-f7live-down', 'ime-f7live-syscaret', 'ime-f7live-tsf-caret', 'ime-ref-edge', 'ime-f8', 'narrator')][string]$Check,
  [string]$Tag = 'run1',
  [Parameter(Mandatory)][string]$ExpectExe,
  [Parameter(Mandatory)][string]$ExpectDll
)
$ErrorActionPreference = 'Stop'
$verify = & "$Base\probes\sr0-s\fresh-on-bridge\scripts\verify-artifacts.ps1" -Base $Base -ExpectExe $ExpectExe -ExpectDll $ExpectDll
$verify
if (@($verify) -cnotcontains 'ARTIFACT_OK') { throw 'artifact check failed; no task registered' }
$artifactLine = ($verify | Where-Object { $_ -like 'ARTIFACT base=*' } | Select-Object -First 1).Trim()
$scripts = "$Base\probes\sr0-b\native-interaction\scripts"
$out = "$Base\result-native-$Check-$Tag.txt"
foreach ($f in @('NativeHelpers.cs', 'native-common.ps1', 'drive-ime.ps1', 'drive-ime-ref.ps1', 'drive-narrator.ps1')) { if (-not (Test-Path -LiteralPath "$scripts\$f")) { throw "missing $scripts\$f (stage the scripts first, see run-native.sh)" } }
switch ($Check) {
  'ime-f7' { $drv = 'drive-ime.ps1'; $extra = '-Fixture F7' }
  'ime-f7live' { $drv = 'drive-ime.ps1'; $extra = '-Fixture F7live' }
  'ime-f7live-down' { $drv = 'drive-ime.ps1'; $extra = '-Fixture F7live -DownAfterMove' }
  'ime-ref-edge' { $drv = 'drive-ime-ref.ps1'; $extra = '' }
  'ime-f7live-syscaret' { $drv = 'drive-ime.ps1'; $extra = '-Fixture F7live -SysCaret' }
  'ime-f7live-tsf-caret' { $drv = 'drive-ime.ps1'; $extra = '-Fixture F7live -SysCaret -Tsf' }
  'ime-f8' { $drv = 'drive-ime.ps1'; $extra = '-Fixture F8' }
  'narrator' { $drv = 'drive-narrator.ps1'; $extra = '' }
}
$task = "SR0N-$Check-$Tag"
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scripts\$drv`" -Base `"$Base`" $extra -Out `"$out`" -ExpectExe $ExpectExe -ExpectDll $ExpectDll"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $taskArgs -WorkingDirectory $Base
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 6) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }
Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Settings $settings -Force | Out-Null
"registered=$task at=$(Get-Date -Format o)"
Start-ScheduledTask -TaskName $task
$deadline = (Get-Date).AddMinutes(5)
do { Start-Sleep -Seconds 2; $st = (Get-ScheduledTask -TaskName $task).State } while ($st -eq 'Running' -and (Get-Date) -lt $deadline)
$info = Get-ScheduledTaskInfo -TaskName $task
"state=$st last_result=$($info.LastTaskResult)"
if ($st -eq 'Running') { Stop-ScheduledTask -TaskName $task; 'task stopped: exceeded 5 minutes' }
Unregister-ScheduledTask -TaskName $task -Confirm:$false
"deleted=$task exists_after=$([bool](Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue))"
if (Test-Path -LiteralPath $out) {
  $body = Get-Content -Raw -Encoding UTF8 -LiteralPath $out
  [IO.File]::WriteAllText($out, "$artifactLine class=native check=$Check tag=$Tag`r`n" + $body, (New-Object Text.UTF8Encoding $false))
  Get-Content -Raw -Encoding UTF8 -LiteralPath $out
} else { 'no result file' }
