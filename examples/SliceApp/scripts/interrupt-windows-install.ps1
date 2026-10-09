# F6 (Windows): real interruptions of an MSIX update, for the Windows Sandbox guest only (never the Dell desktop).
#   interrupt-windows-install.ps1 -OldMsix <0.1.0.0.msix> -NewMsix <0.1.1.0.msix> -Mode KillDeployment|DeferInUse -DisposableGuest
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
#   KillDeployment  start Add-AppxPackage for the new package, stop AppXSvc as soon as deployment events appear.
#   DeferInUse      launch the old app, then Add-AppxPackage -DeferRegistrationWhenPackagesAreInUse for the new package:
#                   expect old still registered while running; close the app, relaunch, expect the new version.
param(
    [Parameter(Mandatory)][string]$OldMsix, [Parameter(Mandatory)][string]$NewMsix,
    [Parameter(Mandatory)][ValidateSet('KillDeployment', 'DeferInUse')][string]$Mode,
    [string]$PackageName = 'OrthicLabs.SliceApp', [switch]$DisposableGuest
)
$ErrorActionPreference = 'Stop'
if (-not $DisposableGuest) { throw 'refusing to run: pass -DisposableGuest to confirm this is a throwaway Windows Sandbox guest' }
$rows = Join-Path $env:LOCALAPPDATA 'SliceApp\rows.json'
function State([string]$when) {
    $pk = @(Get-AppxPackage -Name $PackageName)
    "[$when] registered: $(if ($pk) { ($pk | ForEach-Object { "$($_.PackageFullName) status=$($_.Status)" }) -join '; ' } else { 'NONE' })"
    if (Test-Path -LiteralPath $rows) { "[$when] rows.json sha256=$((Get-FileHash -LiteralPath $rows -Algorithm SHA256).Hash)" } else { "[$when] rows.json absent" }
}
Add-AppxPackage -Path $OldMsix
State 'old installed'
if ($Mode -eq 'DeferInUse') {
    $pfn = (Get-AppxPackage -Name $PackageName).PackageFamilyName
    Start-Process "shell:AppsFolder\$pfn!App"; Start-Sleep -Seconds 5
    Add-AppxPackage -Path $NewMsix -DeferRegistrationWhenPackagesAreInUse
    State 'after deferred add (app running)'
    "close SliceApp, relaunch it, then run: Get-AppxPackage -Name $PackageName | Select Version"
    return
}
$job = Start-Job { param($m) Add-AppxPackage -Path $m } -ArgumentList $NewMsix
$deadline = (Get-Date).AddSeconds(60)
$start = Get-Date
while ((Get-Date) -lt $deadline) {
    $ev = Get-WinEvent -LogName 'Microsoft-Windows-AppXDeploymentServer/Operational' -MaxEvents 20 -ErrorAction SilentlyContinue | Where-Object { $_.TimeCreated -ge $start }
    if ($ev) { break }
    if ($job.State -ne 'Running') { break }
    Start-Sleep -Milliseconds 20
}
if ($job.State -eq 'Running') { Stop-Service -Name AppXSvc -Force; "AppXSvc stopped mid-deployment" } else { "deployment finished before the interrupt landed: result not valid, rerun with a larger package" }
$null = Wait-Job $job -Timeout 120; Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
Start-Service -Name AppXSvc -ErrorAction SilentlyContinue
State 'after interrupt'
"launch check (Sandbox desktop): start SliceApp from the Start menu and confirm the window; then re-run Add-AppxPackage for $NewMsix and confirm 0.1.1.0 registers."
