# F6 (Windows): real interruptions of an MSIX update, for the Windows Sandbox guest only (never the Dell desktop).
#   interrupt-windows-install.ps1 -OldMsix <0.1.0.0.msix> -NewMsix <0.1.1.0.msix> -Mode KillClient|CancelOperation|KillDeployment|DeferInUse -DisposableGuest [-ResultJson <path>] [-Trigger staging|start] [-ExtraDelayMs <n>]
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
#   KillClient      (R5 final) install the old package, run `Add-AppxPackage <new>` in its own powershell.exe (the deployment client) and
#                   Stop-Process -Force that client at a measured point (the new version's staging directory appears under
#                   C:\Program Files\WindowsApps, plus -ExtraDelayMs steps). Survives in the guest: no reboot, no service kill.
#   CancelOperation (R5 final) same trigger, but the update runs through the documented WinRT PackageManager.AddPackageAsync and the
#                   operation is cancelled with IAsyncInfo.Cancel() (Windows.Management.Deployment; the service rolls the deployment back).
#   Each invocation is ONE attempt and leaves the guest in the post-interrupt state for the caller to judge (live registration, data, launch,
#   rerun of the update). An attempt is genuine only when the client was alive (or the operation still Started) at the
#   interrupt AND the new version was NOT registered afterwards: if the deployment service finished the update anyway, the update was not
#   interrupted (only the client was) and the attempt is recorded as `completed-anyway`. Each attempt records a measured timeline
#   (ms since the client started: staging directory seen, interrupt issued, client exit) and a settle sequence of registered versions/status.
# -ResultJson writes the observations as JSON (schema sr0-interrupt/v1) so a harness can assert on them; the script
# also prints them. Launch / rerun / data-readability steps stay with the caller (they need the desktop and UIA).
param(
    [Parameter(Mandatory)][string]$OldMsix, [Parameter(Mandatory)][string]$NewMsix,
    [Parameter(Mandatory)][ValidateSet('KillClient', 'CancelOperation', 'KillDeployment', 'DeferInUse')][string]$Mode,
    [string]$PackageName = 'OrthicLabs.SliceApp', [string]$ResultJson = '', [switch]$DisposableGuest,
    # KillClient / CancelOperation: ONE attempt per invocation (the caller judges the post-interrupt state, launches the build, reruns the update, then calls again).
    # -Trigger staging: fire when the new version's staging directory appears under WindowsApps, plus -ExtraDelayMs. -Trigger start (CancelOperation only):
    # cancel right after AddPackageAsync returned the operation (the service has accepted the request).
    [ValidateSet('staging', 'start')][string]$Trigger = 'staging', [int]$ExtraDelayMs = 0, [int]$SettleSeconds = 25
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
if (@(Get-AppxPackage -Name $PackageName).Count -gt 0) { throw "$PackageName is already registered; remove it first (Remove-AppxPackage)" }

if ($Mode -eq 'KillClient' -or $Mode -eq 'CancelOperation') {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    function Get-MsixVersion([string]$Path) {
        $zip = [IO.Compression.ZipFile]::OpenRead($Path)
        try { $sr = New-Object IO.StreamReader($zip.GetEntry('AppxManifest.xml').Open()); try { [xml]$x = $sr.ReadToEnd() } finally { $sr.Close() } } finally { $zip.Dispose() }
        return [string]$x.Package.Identity.Version
    }
    $oldVersion = Get-MsixVersion $OldMsix
    $newVersion = Get-MsixVersion $NewMsix
    $res.old_version = $oldVersion; $res.new_version = $newVersion
    $res.attempts = @(); $res.genuine = $false; $res.genuine_attempt = -1
    function Get-Reg { return @(Get-AppxPackage -Name $PackageName | ForEach-Object { [ordered]@{ version = [string]$_.Version; status = [string]$_.Status; full_name = [string]$_.PackageFullName } }) }
    function Get-RegText { $r = @(Get-Reg); if ($r.Count -eq 0) { return 'none' } else { return (($r | ForEach-Object { $_.version + ':' + $_.status }) -join ',') } }
    function Test-NewStaging { return (@([IO.Directory]::GetDirectories('C:\Program Files\WindowsApps', ($PackageName + '_' + $newVersion + '_*'))).Count -gt 0) }
    function Get-RowsHash { if (Test-Path -LiteralPath $rows) { return (Get-FileHash -LiteralPath $rows -Algorithm SHA256).Hash } else { return 'absent' } }
    # KillClient only counts when the deployment is demonstrably under way (staging directory seen), so it has no 'start' trigger. CancelOperation
    # also allows an immediate cancel: the operation object exists, so the service has accepted the request.
    if ($Mode -eq 'KillClient' -and $Trigger -eq 'start') { throw "KillClient needs -Trigger staging (a client killed before the deployment began proves nothing)" }
    $attemptSpecs = @(, @($Trigger, $ExtraDelayMs))
    $idx = 0
    foreach ($spec in $attemptSpecs) {
        $idx++
        $trigger = [string]$spec[0]; $extra = [int]$spec[1]
        # Clean slate for this attempt: nothing registered, then the old package.
        foreach ($pk in @(Get-AppxPackage -Name $PackageName)) { Remove-AppxPackage -Package $pk.PackageFullName }
        Add-AppxPackage -Path $OldMsix
        $att = [ordered]@{ n = $idx; method = $Mode; trigger = $trigger; extra_delay_ms = $extra; registered_before = (Get-RegText); rows_sha_before = (Get-RowsHash); staging_new_before_start = (Test-NewStaging) }
        $evStart = Get-Date
        $clientOut = Join-Path $env:TEMP ('interrupt-client-' + [guid]::NewGuid().ToString('N') + '.txt')
        $proc = $null; $op = $null; $watch = [Diagnostics.Stopwatch]::StartNew()
        if ($Mode -eq 'KillClient') {
            $cmd = "`$r = ''; try { Add-AppxPackage -Path '$NewMsix' -ErrorAction Stop; `$r = 'DONE' } catch { `$r = 'FAILED: ' + `$_.Exception.Message }; Set-Content -LiteralPath '$clientOut' -Value `$r"
            $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
            $proc = Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc)
            $att.client_pid = $proc.Id
        } else {
            [void][Windows.Management.Deployment.PackageManager, Windows.Management.Deployment, ContentType = WindowsRuntime]
            [void][Windows.Foundation.IAsyncInfo, Windows.Foundation, ContentType = WindowsRuntime]
            $asyncInfo = [Windows.Foundation.IAsyncInfo]
            $pm = New-Object Windows.Management.Deployment.PackageManager
            $uri = New-Object Uri(('file:///' + ($NewMsix -replace '\\', '/')))
            $op = $pm.AddPackageAsync($uri, [Collections.Generic.IEnumerable[Uri]]$null, [Windows.Management.Deployment.DeploymentOptions]::None)
        }
        $att.t_started_ms = [int]$watch.ElapsedMilliseconds
        # Measured trigger.
        $seen = $false
        $deadline = (Get-Date).AddSeconds(90)
        while ((Get-Date) -lt $deadline) {
            if ($trigger -eq 'start') { $seen = $true; break }
            if (Test-NewStaging) { $seen = $true; break }
            if ($Mode -eq 'KillClient' -and $proc.HasExited) { break }
            if ($Mode -eq 'CancelOperation' -and [int]$asyncInfo.GetProperty('Status').GetValue($op) -ne 0) { break }
            Start-Sleep -Milliseconds 5
        }
        $att.trigger_seen = $seen
        $att.t_trigger_ms = [int]$watch.ElapsedMilliseconds
        if ($extra -gt 0) { Start-Sleep -Milliseconds $extra }
        # Interrupt.
        if ($Mode -eq 'KillClient') {
            $att.client_alive_at_interrupt = (-not $proc.HasExited)
            $att.t_interrupt_ms = [int]$watch.ElapsedMilliseconds
            if ($att.client_alive_at_interrupt) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; [void]$proc.WaitForExit(5000) }
            $att.client_exited_after = $proc.HasExited
            $att.t_client_gone_ms = [int]$watch.ElapsedMilliseconds
        } else {
            $stNow = [int]$asyncInfo.GetProperty('Status').GetValue($op)
            $att.op_status_at_interrupt = [string]$stNow   # AsyncStatus: 0 Started, 1 Completed, 2 Canceled, 3 Error
            $att.client_alive_at_interrupt = ($stNow -eq 0)
            $att.t_interrupt_ms = [int]$watch.ElapsedMilliseconds
            if ($att.client_alive_at_interrupt) { [void]$asyncInfo.GetMethod('Cancel').Invoke($op, $null) }
            $d2 = (Get-Date).AddSeconds(60)
            while ([int]$asyncInfo.GetProperty('Status').GetValue($op) -eq 0 -and (Get-Date) -lt $d2) { Start-Sleep -Milliseconds 50 }
            $att.op_status_after = [string][int]$asyncInfo.GetProperty('Status').GetValue($op)
            $att.op_error_code = [string]$asyncInfo.GetProperty('ErrorCode').GetValue($op)
            $att.t_client_gone_ms = [int]$watch.ElapsedMilliseconds
        }
        # Settle: sample registered versions every second until unchanged for 6 s (max $SettleSeconds), then read the final state.
        $timeline = New-Object System.Collections.ArrayList
        $lastText = ''; $stableSince = Get-Date; $sw2 = [Diagnostics.Stopwatch]::StartNew()
        while ($sw2.Elapsed.TotalSeconds -lt $SettleSeconds) {
            $txt = (Get-RegText) + ' | staging_new=' + (Test-NewStaging)
            if ($txt -ne $lastText) { [void]$timeline.Add(('+{0}ms {1}' -f [int]($watch.ElapsedMilliseconds), $txt)); $lastText = $txt; $stableSince = Get-Date }
            elseif (((Get-Date) - $stableSince).TotalSeconds -ge 6) { break }
            Start-Sleep -Seconds 1
        }
        $att.settle_timeline = @($timeline)
        $reg = @(Get-Reg)
        $att.registered_after = (Get-RegText)
        $att.registered_count = $reg.Count
        $att.all_users_count = @(Get-AppxPackage -AllUsers -Name $PackageName -ErrorAction SilentlyContinue).Count
        $att.staging_new_after = (Test-NewStaging)
        $att.rows_sha_after = (Get-RowsHash)
        if ($Mode -eq 'KillClient') { $att.client_output = $(if (Test-Path -LiteralPath $clientOut) { (Get-Content -LiteralPath $clientOut -Raw).Trim() } else { '(none: client killed before it finished)' }) }
        $newRegistered = [bool]($reg | Where-Object { $_.version -eq $newVersion })
        $oldRegistered = [bool]($reg | Where-Object { $_.version -eq $oldVersion })
        $att.new_registered_after = $newRegistered
        # Genuine = the client/operation was alive at the interrupt, the deployment was demonstrably under way (staging directory seen; for CancelOperation the
        # operation object itself proves the request was accepted), and the new version is NOT registered afterwards.
        $underway = [bool]$att.trigger_seen -or ($Mode -eq 'CancelOperation')
        $att.deployment_underway = $underway
        $att.interrupted = ([bool]$att.client_alive_at_interrupt) -and $underway -and (-not $newRegistered)
        $att.outcome = $(if ($newRegistered -and $reg.Count -eq 1 -and $reg[0].status -eq 'Ok') { 'completed-anyway' }
            elseif ($oldRegistered -and $reg.Count -eq 1 -and $reg[0].status -eq 'Ok') { 'old-registered-ok' }
            else { 'inconsistent' })
        # Deployment-service events for this attempt (post hoc, not on the critical path): id and level plus a short message.
        try {
            $att.appx_events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-AppXDeploymentServer/Operational'; StartTime = $evStart.AddSeconds(-1) } -ErrorAction Stop |
                    Sort-Object TimeCreated | Select-Object -First 40 | ForEach-Object {
                    $msg = ($_.Message -replace '\s+', ' ')
                    ('{0:HH:mm:ss.fff} id={1} {2}: {3}' -f $_.TimeCreated, $_.Id, $_.LevelDisplayName, $msg.Substring(0, [Math]::Min(160, $msg.Length)))
                })
        } catch { $att.appx_events = @('unreadable: ' + $_.Exception.Message) }
        # The deployment state the interrupt hit, from the service's own performance-summary event ("Failed to reach state Staged ...").
        $att.failed_to_reach_state = ''
        foreach ($e in @($att.appx_events)) { if ($e -match 'Failed to reach state (\w+)') { $att.failed_to_reach_state = $Matches[1]; break } }
        $res.attempts += , $att
        Write-Host ("attempt $idx [$Mode/$trigger+${extra}ms]: alive_at_interrupt=$($att.client_alive_at_interrupt) interrupted=$($att.interrupted) outcome=$($att.outcome) registered=$($att.registered_after)")
        # A genuine interruption leaves a state the caller must judge: stop here and keep it (old registered, or whatever the interrupt left).
        if ($att.interrupted) { $res.genuine = $true; $res.genuine_attempt = $idx }
    }
    $res.valid = $res.genuine
    Finish
    "genuine=$($res.genuine) attempts=$($res.attempts.Count) genuine_attempt=$($res.genuine_attempt)"
    return
}

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
