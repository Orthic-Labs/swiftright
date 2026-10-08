$ErrorActionPreference = 'Stop'
$id = 'run-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$base = 'D:\Claude\sr0b-text-geometry'
$runDir = Join-Path $base $id
New-Item -ItemType Directory -Force $runDir | Out-Null
$src = 'D:\.rightkit-managed\rightkit-build-control\ws\24f0adfca6aa\g\001\target\x86_64-pc-windows-msvc\release\sr0b-text-geometry.exe'
if (-not (Test-Path $src)) { throw "exe missing: $src" }
$exe = Join-Path $runDir 'sr0b-text-geometry.exe'
Copy-Item $src $exe
$task = 'SR0B-TextGeometry-' + $id
$script = Join-Path $base 'scripts\run-desktop.ps1'
$resultPath = Join-Path $base 'result.json'
$arg = '-NoProfile -ExecutionPolicy Bypass -File "' + $script + '" -Exe "' + $exe + '" -RunDir "' + $runDir + '" -ResultPath "' + $resultPath + '" -TaskName "' + $task + '"'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$principal = New-ScheduledTaskPrincipal -UserId 'adrds' -LogonType Interactive -RunLevel Limited
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddYears(1)
Register-ScheduledTask -TaskName $task -Action $action -Principal $principal -Trigger $trigger -Force | Out-Null
Start-ScheduledTask -TaskName $task
Write-Output "task=$task runDir=$runDir exe=$exe"
for ($i = 0; $i -lt 150; $i++) {
  Start-Sleep -Seconds 2
  if (Test-Path (Join-Path $runDir 'result.json')) { break }
}
Start-Sleep -Seconds 8
Get-ScheduledTask | Where-Object { $_.TaskName -eq $task } | Unregister-ScheduledTask -Confirm:$false -ErrorAction SilentlyContinue
Write-Output ("result_exists=" + (Test-Path (Join-Path $runDir 'result.json')))
$t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
Write-Output ("task_still_registered=" + ($t -ne $null))
