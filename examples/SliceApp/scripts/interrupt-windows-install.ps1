# F6 (Windows): real interruptions of an MSIX update, for the Windows Sandbox guest only (never the Dell desktop).
#   interrupt-windows-install.ps1 -OldMsix <0.1.0.0.msix> -NewMsix <0.1.1.0.msix> -Mode KillDeployment|DeferInUse -DisposableGuest [-ResultJson <path>]
#
# Sources: Microsoft Learn, Add-AppxPackage (learn.microsoft.com/powershell/module/appx/add-appxpackage):
#   -DeferRegistrationWhenPackagesAreInUse "Specifies that the app won't register for a user if currently in use. The
#   app will update on the next launch." (example 2: register an update but not until the app has closed);
#   -Stage "Stages a package to the system without registering it"; "To update an already installed package, the new
#   package must have the same package family name."
# KillDeployment is a fault-injection technique, not a documented Microsoft procedure. Deployment runs in the AppX
# Deployment Service (AppXSvc), not in the PowerShell client, so killing the cmdlet's host would not interrupt it; the
# script stops AppXSvc while the update is in flight. The expected outcome is OBSERVED and recorded, not assumed:
# exactly one of 0.1.0.0 / 0.1.1.0 registered (never none, never both, no PartiallyStaged/needs-repair state), the
# registered one launches, and %LOCALAPPDATA%\SliceApp\rows.json is byte-identical to before.
#   KillDeployment  install the old package (which must NOT be registered yet, remove any other version first), start
#                   Add-AppxPackage for the new package, stop AppXSvc as soon as deployment events appear.
#                   The run is VALID only when the cmdlet job was still running at the stop AND it ended with an error.
#   DeferInUse      launch the old app, then Add-AppxPackage -DeferRegistrationWhenPackagesAreInUse for the new package:
#                   expect old still registered while running (the caller closes the app, relaunches, checks the new version).
# -ResultJson writes the observations as JSON (schema sr0-interrupt/v1) so a harness can assert on them; the script
# also prints them. Launch / rerun / data-readability steps stay with the caller (they need the desktop and UIA).
param(
    [Parameter(Mandatory)][string]$OldMsix, [Parameter(Mandatory)][string]$NewMsix,
    [Parameter(Mandatory)][ValidateSet('KillDeployment', 'DeferInUse')][string]$Mode,
    [string]$PackageName = 'OrthicLabs.SliceApp', [string]$ResultJson = '', [switch]$DisposableGuest
)
$ErrorActionPreference = 'Stop'
if (-not $DisposableGuest) { throw 'refusing to run: pass -DisposableGuest to confirm this is a throwaway Windows Sandbox guest' }
$rows = Join-Path $env:LOCALAPPDATA 'SliceApp\rows.json'
function State([string]$when) {
    $pk = @(Get-AppxPackage -Name $PackageName)
    $all = @(Get-AppxPackage -AllUsers -Name $PackageName -ErrorAction SilentlyContinue)
    $sha = $(if (Test-Path -LiteralPath $rows) { (Get-FileHash -LiteralPath $rows -Algorithm SHA256).Hash } else { 'absent' })
    $o = [ordered]@{
        when = $when
        registered_count = $pk.Count
        registered = @($pk | ForEach-Object { [ordered]@{ full_name = $_.PackageFullName; version = [string]$_.Version; status = [string]$_.Status } })
        all_users_count = $all.Count
        rows_sha256 = $sha
    }
    Write-Host "[$when] registered: $(if ($pk) { ($pk | ForEach-Object { "$($_.PackageFullName) status=$($_.Status)" }) -join '; ' } else { 'NONE' }); rows.json $sha"   # PATCH-6: Write-Host (a bare string polluted the return value, so `states` serialized as [string, object] pairs)
    return $o
}
$res = [ordered]@{ schema = 'sr0-interrupt/v1'; mode = $Mode; old_msix = $OldMsix; new_msix = $NewMsix; valid = $false; states = @() }
function Finish {
    if ($ResultJson) { [IO.File]::WriteAllText($ResultJson, ($res | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false))) }
}
if (@(Get-AppxPackage -Name $PackageName).Count -gt 0) { throw "$PackageName is already registered; remove it first (Remove-AppxPackage -PreserveApplicationData)" }
Add-AppxPackage -Path $OldMsix
$res.states += , (State 'old installed')
if ($Mode -eq 'DeferInUse') {
    $pkg = Get-AppxPackage -Name $PackageName
    $appId = [string](Get-AppxPackageManifest -Package $pkg.PackageFullName).Package.Applications.Application.Id
    Start-Process 'explorer.exe' ("shell:AppsFolder\$($pkg.PackageFamilyName)!$appId"); Start-Sleep -Seconds 6
    Add-AppxPackage -Path $NewMsix -DeferRegistrationWhenPackagesAreInUse
    $res.states += , (State 'after deferred add (app running)')
    $res.valid = $true
    Finish
    "close SliceApp, relaunch it, then run: Get-AppxPackage -Name $PackageName | Select Version"
    return
}
$errText = ''
$job = Start-Job { param($m) Add-AppxPackage -Path $m } -ArgumentList $NewMsix
$deadline = (Get-Date).AddSeconds(60)
$start = Get-Date
while ((Get-Date) -lt $deadline) {
    # PATCH-11b: the event-log query took longer than the whole (~1 s) deployment, so the interrupt never landed in flight. Trigger on the staging directory instead.
    $ev = @([IO.Directory]::GetDirectories('C:\Program Files\WindowsApps', ($PackageName + '_*')) | Where-Object { $_ -match '_0\.1\.1\.0_' })
    if ($ev.Count -gt 0) { break }
    if ($job.State -ne 'Running') { break }
    Start-Sleep -Milliseconds 20
}
$stoppedInFlight = ($job.State -eq 'Running')
if ($stoppedInFlight) {
    # PATCH-11: Stop-Service waits for the in-flight deployment (observed: job Completed, nothing interrupted). Kill the service host process instead (disposable guest only).
    $svcPid = [int](Get-CimInstance Win32_Service -Filter "Name='AppXSvc'").ProcessId
    $killed = $false
    if ($svcPid -gt 0) { & cmd.exe /c "taskkill.exe /F /PID $svcPid >nul 2>&1"; $killed = ($LASTEXITCODE -eq 0) }
    if ($killed) { "AppXSvc host process $svcPid killed mid-deployment" } else { Stop-Service -Name AppXSvc -Force; "AppXSvc stopped mid-deployment (host process is protected: taskkill failed)" }
} else { "deployment finished before the interrupt landed: result not valid, rerun" }
$null = Wait-Job $job -Timeout 120
try { Receive-Job $job -ErrorAction Stop | Out-Null } catch { $errText = $_.Exception.Message }
$jobState = [string]$job.State
Remove-Job $job -Force -ErrorAction SilentlyContinue
Start-Service -Name AppXSvc -ErrorAction SilentlyContinue
$res.states += , (State 'after interrupt')
$res.stopped_in_flight = $stoppedInFlight
$res.job_state = $jobState
$res.job_error = $errText
# Valid only if the stop landed mid-flight AND the cmdlet reported a failure (a clean success means it finished anyway).
$res.valid = ($stoppedInFlight -and $errText -ne '')
Finish
"valid=$($res.valid) job_state=$jobState error=[$errText]"
"launch check (caller): start SliceApp and confirm the window, then re-run Add-AppxPackage for $NewMsix and confirm the new version registers."
