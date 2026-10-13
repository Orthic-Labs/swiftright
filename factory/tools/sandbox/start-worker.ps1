# start-worker.ps1 - Dell host. Starts the ONE long-lived Windows Sandbox that runs every SwiftRight Windows GUI test job (capture | w08 | command),
# minimised and never in front of the desktop. Run it at most once per day (the Sandbox keeps running; jobs go through the queue). Run it over SSH or directly:
#   powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\swiftright\.sandbox\start-worker.ps1 [-Status]
# * If a worker heartbeat is fresh the script exits 0 and does nothing (never restarts a running Sandbox).
# * If Sandbox processes exist but the heartbeat is stale it reports and exits 2; it never kills or relaunches by itself.
# * Windows Sandbox needs the interactive session, so it is started through a one-shot Interactive/Limited hidden task (lib-interactive.ps1) running launch-sandbox.ps1.
# * -Status only prints the heartbeat age and the window state (IsIconic / GetForegroundWindow, read in the interactive session) and exits.
# vGPU: 'Disable' (software rendering) is the default: with vGPU Enable the Sandbox client shows 'Warning' and the guest never logs on (2026-10-13 test on this Dell,
# same as the R5 finding for vGPU Default), so the LogonCommand never runs. Pass -Vgpu Enable to retest after a driver change.
# Layout under this folder: guest\ (scripts the guest runs; the Mac client syncs them), queue\, results\, state\ (hb.json, worker.log, launch.log, worker.wsb).
# Mapped into the guest: C:\sbq (this folder, rw), C:\hostfw (.factory-work, ro), C:\swiftrt (Swift 6.4.0 runtime DLLs, ro), C:\w08t2 (W08 packages and feeds, ro).
param([switch]$Status, [switch]$NoVerify, [int]$StartTimeoutSec = 60, [string]$Vgpu = 'Disable', [int]$MemoryMB = 8192, [ValidateSet('offscreen', 'min', 'bottom')][string]$FinalHide = 'min')
$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Utf8 = New-Object Text.UTF8Encoding($false)
. (Join-Path $Root 'lib-interactive.ps1')
$State = Join-Path $Root 'state'
foreach ($d in 'queue', 'results', 'state', 'guest') { New-Item -ItemType Directory -Force -Path (Join-Path $Root $d) | Out-Null }
$Hb = Join-Path $State 'hb.json'
function Get-HbAge {
    try { return [math]::Round(((Get-Date).ToUniversalTime() - (Get-Item -LiteralPath $Hb).LastWriteTimeUtc).TotalSeconds, 1) } catch { return 99999 }   # file mtime: robust against PS 5.1/7 JSON date handling
}
function Get-SandboxProcs { return @(Get-Process | Where-Object { $_.ProcessName -match '^WindowsSandbox' }) }   # vmmemWindowsSandbox alone (a VM still tearing down after a close) does not block a start
function Get-WindowState([double]$Sample = 3) {
    $out = Join-Path $State 'window-state.json'
    if (Test-Path -LiteralPath $out) { Move-Item -LiteralPath $out -Destination ('D:\Claude\swiftright\.work\sandbox-window-state-' + (Get-Date -Format 'yyyyMMddHHmmssfff') + '.json') -Force }
    $rc = Invoke-Interactive -File (Join-Path $Root 'window-state.ps1') -FileArgs ('-Out "' + $out + '" -SampleSeconds ' + $Sample) -WorkDir (Join-Path $State 'task') -TimeoutSec 60
    if (Test-Path -LiteralPath $out) { return (Get-Content -LiteralPath $out -Raw) } else { return "window-state failed rc=$rc" }
}

if ($Status) {
    'heartbeat_age_s=' + (Get-HbAge)
    'sandbox_processes=' + ((Get-SandboxProcs | ForEach-Object { $_.ProcessName + '#' + $_.Id }) -join ',')
    Get-WindowState 3
    exit 0
}

$age = Get-HbAge
if ($age -lt 15) { "worker already running (heartbeat $age s old); nothing to do. Sandbox is NOT restarted."; exit 0 }
$procs = Get-SandboxProcs
if ($procs.Count -gt 0) {
    "a Windows Sandbox is already present but the worker heartbeat is stale ($age s): " + (($procs | ForEach-Object { $_.ProcessName + '#' + $_.Id }) -join ', ')
    'refusing to relaunch or kill; decide with the lead (a stuck or foreign Sandbox blocks a second instance).'
    exit 2
}
foreach ($need in 'guest-worker.ps1', 'logon.cmd', 'job-capture.ps1', 'job-w08.ps1', 'job-command.ps1') { if (-not (Test-Path -LiteralPath (Join-Path $Root "guest\$need"))) { throw "missing guest\$need (run the Mac client: python3 factory/tools/sandbox/client.py sync)" } }
$swiftRt = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin'
$map = @(
    @{ h = $Root; g = 'C:\sbq'; ro = 'false' },
    @{ h = 'D:\Claude\swiftright\.factory-work'; g = 'C:\hostfw'; ro = 'true' },
    @{ h = $swiftRt; g = 'C:\swiftrt'; ro = 'true' },
    @{ h = 'D:\Claude\swiftright\.work\w08t2'; g = 'C:\w08t2'; ro = 'true' }
)
$mf = ($map | ForEach-Object {
        if (-not (Test-Path -LiteralPath $_.h)) { throw "host folder missing: $($_.h)" }
        '    <MappedFolder><HostFolder>' + [Security.SecurityElement]::Escape($_.h) + '</HostFolder><SandboxFolder>' + $_.g + '</SandboxFolder><ReadOnly>' + $_.ro + '</ReadOnly></MappedFolder>'
    }) -join "`r`n"
$wsb = @"
<Configuration>
  <vGPU>$Vgpu</vGPU>
  <Networking>Enable</Networking>
  <AudioInput>Disable</AudioInput>
  <VideoInput>Disable</VideoInput>
  <ProtectedClient>Disable</ProtectedClient>
  <PrinterRedirection>Disable</PrinterRedirection>
  <ClipboardRedirection>Disable</ClipboardRedirection>
  <MemoryInMB>$MemoryMB</MemoryInMB>
  <MappedFolders>
$mf
  </MappedFolders>
  <LogonCommand>
    <Command>C:\sbq\guest\logon.cmd</Command>
  </LogonCommand>
</Configuration>
"@
[void][xml]$wsb
$wsbPath = Join-Path $State 'worker.wsb'
[IO.File]::WriteAllText($wsbPath, $wsb, $Utf8)

if (-not $NoVerify) { 'window state BEFORE launch: ' + (Get-WindowState 1) }
$t0 = Get-Date
"launching Windows Sandbox (z-order bottom while booting, no activation; then $FinalHide) at $(Get-Date -Format o)"
$rc = Invoke-Interactive -File (Join-Path $Root 'launch-sandbox.ps1') -FileArgs ('-Wsb "' + $wsbPath + '" -StateDir "' + $State + '" -WatchSeconds 300 -Hide bottom') -WorkDir (Join-Path $State 'task') -TimeoutSec 400
"launcher rc=$rc"
$dl = (Get-Date).AddSeconds($StartTimeoutSec)
while ((Get-HbAge) -gt 15 -and (Get-Date) -lt $dl) { Start-Sleep -Seconds 2 }
$a = Get-HbAge
if ($a -gt 15) { "worker heartbeat did not appear within $StartTimeoutSec s; see $State\launch.log"; Get-Content -LiteralPath (Join-Path $State 'launch.log') -ErrorAction SilentlyContinue; exit 3 }
"worker up (heartbeat $a s old) after $([math]::Round(((Get-Date) - $t0).TotalSeconds, 1)) s"
Get-Content -LiteralPath (Join-Path $State 'launch.log') -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
$rc2 = Invoke-Interactive -File (Join-Path $Root 'window-set.ps1') -FileArgs ('-Mode ' + $FinalHide + ' -Seconds 3 -Out "' + (Join-Path $State 'window-set.txt') + '"') -WorkDir (Join-Path $State 'task') -TimeoutSec 60
'final hide (' + $FinalHide + ') rc=' + $rc2 + ' ' + (Get-Content -LiteralPath (Join-Path $State 'window-set.txt') -ErrorAction SilentlyContinue)
if (-not $NoVerify) { 'window state AFTER start: ' + (Get-WindowState 5) }
exit 0
