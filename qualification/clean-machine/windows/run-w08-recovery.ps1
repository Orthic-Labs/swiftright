# run-w08-recovery.ps1 - Dell host launcher for ONE W08-recovery Windows Sandbox run on the final packages (SR0 T12). Networking is enabled (the
# AppInstallerFile methods need the guest-local https feed; nothing leaves the guest). Run it NON-ELEVATED in the desktop session
# (run-unelevated-task.ps1), with D:\Claude\desktop.lock held.
#
# Stages <OutRoot>\<RunId>\staging\{harness,packages} and receipts\, writes <run>\w08-recovery.wsb from clean-machine.wsb.tmpl, starts WindowsSandbox.exe,
# waits for receipts\DONE (the guest writes it last and then stops itself). One method per run; every run is a fresh Sandbox.
# Host-desktop rule (the host owner works on the Dell): the Sandbox window is never allowed to stay in front. sandbox-background.ps1 is started BEFORE the Sandbox, and this
# launcher (an interactive-session task, so session 1) runs one pass every 150 ms until the Sandbox is gone: every Sandbox window is sent to HWND_BOTTOM with
# SWP_NOACTIVATE|SWP_NOMOVE|SWP_NOSIZE, never minimized, and the foreground goes back to the window that had it. Log: <run>\sandbox-background.log.
# The packages must hash to the expected values (the tuple 08 MSIX pair); nothing is deleted or recycled.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('settings-probe', 'settings-repair', 'settings-repair-same', 'settings-repair-path', 'platform-register', 'reset', 'reinstall-same', 'appinstaller-same')][string]$Method,
    [Parameter(Mandatory = $true)][string]$RunId,
    [Parameter(Mandatory = $true)][string]$OldMsix,
    [Parameter(Mandatory = $true)][string]$NewMsix,
    [Parameter(Mandatory = $true)][string]$FeedDir,        # SliceApp.0.appinstaller and SliceApp.1.appinstaller (the R5 feed files, localhost https)
    [Parameter(Mandatory = $true)][string]$ExpectOldSha256,
    [Parameter(Mandatory = $true)][string]$ExpectNewSha256,
    [int]$HoldMinutes = 0,                                  # platform-register only: wait this long before the launch attempt
    [int]$TimeoutMinutes = 60,
    [string]$OutRoot = (Join-Path $PSScriptRoot 'runs-w08-recovery'),
    [string]$SliceAppDir = (Join-Path $PSScriptRoot '..\..\..\examples\SliceApp')
)
$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
. (Join-Path $PSScriptRoot 'sandbox-background.ps1') -Library
foreach ($pair in @(@($OldMsix, $ExpectOldSha256), @($NewMsix, $ExpectNewSha256))) {
    $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $pair[0]).Hash
    if ($h -ne $pair[1].ToUpper()) { throw ('sha256 mismatch ' + $pair[0] + ': ' + $h + ' (expected ' + $pair[1].ToUpper() + ')') }
}
foreach ($f in 'SliceApp.0.appinstaller', 'SliceApp.1.appinstaller') { if (-not (Test-Path -LiteralPath (Join-Path $FeedDir $f))) { throw "missing $f in $FeedDir" } }
$feedScript = Join-Path $SliceAppDir 'scripts\serve-local-feed.ps1'
if (-not (Test-Path -LiteralPath $feedScript)) { throw "missing $feedScript" }
$running = @(Get-Process | Where-Object { $_.ProcessName -match '^WindowsSandbox' })
if ($running.Count -gt 0) { throw ('a Windows Sandbox is already running: ' + (($running | ForEach-Object { $_.ProcessName + '#' + $_.Id }) -join ', ')) }

$RunDir = Join-Path $OutRoot $RunId
if (Test-Path -LiteralPath $RunDir) { throw "run dir exists: $RunDir" }
$Harness = Join-Path $RunDir 'staging\harness'
$Pkgs = Join-Path $RunDir 'staging\packages'
$Rec = Join-Path $RunDir 'receipts'
New-Item -ItemType Directory -Force -Path $Harness, $Pkgs, (Join-Path $Pkgs 'feed'), $Rec | Out-Null
$g = Join-Path $PSScriptRoot 'guest'
Copy-Item -LiteralPath (Join-Path $g 'w08-recovery-guest.ps1'), (Join-Path $g 'w08-recovery-watchdog.ps1') -Destination $Harness
Copy-Item -LiteralPath $feedScript -Destination $Harness
Copy-Item -LiteralPath (Join-Path $g 'logon-w08-recovery.cmd') -Destination (Join-Path $Harness 'logon.cmd')
[IO.File]::WriteAllText((Join-Path $Harness 'method.txt'), ($Method + $(if ($HoldMinutes -gt 0) { "`r`n$HoldMinutes" } else { '' }) + "`r`n"), $Utf8)
Copy-Item -LiteralPath $OldMsix -Destination (Join-Path $Pkgs 'old.msix')
Copy-Item -LiteralPath $NewMsix -Destination (Join-Path $Pkgs 'new.msix')
Copy-Item -LiteralPath $OldMsix -Destination (Join-Path $Pkgs 'feed\SliceApp_0.1.0.0_x64.msix')
Copy-Item -LiteralPath $NewMsix -Destination (Join-Path $Pkgs 'feed\SliceApp_0.1.1.0_x64.msix')
Copy-Item -LiteralPath (Join-Path $FeedDir 'SliceApp.0.appinstaller'), (Join-Path $FeedDir 'SliceApp.1.appinstaller') -Destination (Join-Path $Pkgs 'feed')
$sig = Get-AuthenticodeSignature -FilePath $OldMsix
Export-Certificate -Cert $sig.SignerCertificate -FilePath (Join-Path $Pkgs 'signer.cer') -Type CERT | Out-Null   # public certificate only
$wsb = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'clean-machine.wsb.tmpl'), $Utf8)
$wsb = $wsb.Replace('__HOST_HARNESS__', $Harness).Replace('__HOST_PACKAGES__', $Pkgs).Replace('__HOST_RECEIPTS__', $Rec).Replace('__NETWORKING__', 'Enable')
if ($wsb -match '__[A-Z_]+__') { throw 'unreplaced token' }
[void][xml]$wsb
$wsbPath = Join-Path $RunDir 'w08-recovery.wsb'
[IO.File]::WriteAllText($wsbPath, $wsb, $Utf8)
$hashes = [ordered]@{ run_id = $RunId; method = $Method; hold_minutes = $HoldMinutes; old_msix_sha256 = $ExpectOldSha256.ToLower(); new_msix_sha256 = $ExpectNewSha256.ToLower()
    guest_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Harness 'w08-recovery-guest.ps1')).Hash.ToLower(); staged_utc = (Get-Date).ToUniversalTime().ToString('o') }
[IO.File]::WriteAllText((Join-Path $RunDir 'run-inputs.json'), (($hashes | ConvertTo-Json) + "`r`n"), $Utf8)
$exe = Join-Path $env:SystemRoot 'System32\WindowsSandbox.exe'
$bgLog = Join-Path $RunDir 'sandbox-background.log'
$script:bgLast = ''
function Step-Background { [void][SbBack]::Tick(); if ([SbBack]::LastEvent -ne $script:bgLast) { $script:bgLast = [SbBack]::LastEvent; try { Add-Content -LiteralPath $bgLog -Value ((Get-Date -Format 'HH:mm:ss.fff') + ' ' + $script:bgLast + ' | pushes=' + [SbBack]::Pushes + ' push_failures=' + [SbBack]::PushFailures + ' restores=' + [SbBack]::Restores + ' restore_failures=' + [SbBack]::RestoreFailures) } catch { } } }
Step-Background   # baseline: remembers the window that is in front before the Sandbox starts
$p = Start-Process -FilePath $exe -ArgumentList ('"' + $wsbPath + '"') -PassThru
"launched $RunId method=$Method via WindowsSandbox.exe (launcher pid $($p.Id)) at $(Get-Date -Format o)"
$done = Join-Path $Rec 'DONE'
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
while (-not (Test-Path -LiteralPath $done) -and (Get-Date) -lt $deadline) { Step-Background; Start-Sleep -Milliseconds 150 }
if (-not (Test-Path -LiteralPath $done)) { "TIMEOUT: no DONE after $TimeoutMinutes min (sandbox left running; not killed)"; exit 4 }
"DONE seen at $(Get-Date -Format o)"
$gone = $false; $dl2 = (Get-Date).AddSeconds(150)
while ((Get-Date) -lt $dl2 -and -not $gone) { Step-Background; Start-Sleep -Milliseconds 150; $gone = (@(Get-Process | Where-Object { $_.ProcessName -match '^WindowsSandbox' }).Count -eq 0) }
"sandbox processes gone: $gone"
"sandbox-background: " + (Get-SandboxBackgroundSummary)
try { Add-Content -LiteralPath $bgLog -Value ((Get-Date -Format 'HH:mm:ss.fff') + ' summary: ' + (Get-SandboxBackgroundSummary)) } catch { }
Get-ChildItem -LiteralPath $Rec | Select-Object Name, Length | Format-Table -AutoSize | Out-String
exit 0
