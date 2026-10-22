# job-w08.ps1 - kind=w08. args: {"method":"tier2-repair|tier2-feed-down|tier2-uninstall","runId":"..","delays":"240,360","maxAttempts":8,"action":"run|reset"}.
# Runs the EXISTING guest harness (qualification\clean-machine\windows\guest\w08-recovery-guest.ps1, synced unmodified to guest\w08\) inside this long-lived Sandbox.
# Only change: the harness ends with `Stop-Computer -Force` (it expects a one-shot Sandbox); the staged COPY has those calls replaced by a log line. The original is
# never edited; the patch is verified (no Stop-Computer left) and its hash recorded. The harness's watchdog is not staged (it also stops the computer); the worker's
# per-job timeout replaces it.
# W08 needs a CLEAN package state per run, so: Reset-W08State BEFORE (and after) every job, with a verification; if the state cannot be proven clean the job fails with
# needs_fresh_sandbox=true and does NOT run (the lead decides about a relaunch; nothing here relaunches the Sandbox).
param([Parameter(Mandatory)][string]$JobDir)
$ErrorActionPreference = 'Continue'
$Utf8 = New-Object Text.UTF8Encoding($false)
$job = Get-Content -LiteralPath "$JobDir\job.json" -Raw | ConvertFrom-Json
$A = $job.args
$action = $(if ($A.action) { [string]$A.action } else { 'run' })
$Method = [string]$A.method
$PkgName = 'OrthicLabs.SliceApp'
$W = 'C:\w08t2'
$res = [ordered]@{ kind = 'w08'; method = $Method; ok = $false; needs_fresh_sandbox = $false; clean_before = $null; clean_after = $null }

function Reset-W08State {
    # #47 tier2-sched-blocked sets a Task Scheduler creation policy; never leave it behind for the next job
    try { Remove-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Task Scheduler5.0" -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    $log = @()
    function Step([string]$m, [scriptblock]$b) { try { & $b; $script:log += ('ok   ' + $m) } catch { $script:log += ('FAIL ' + $m + ': ' + $_.Exception.Message) } }
    $script:log = @()
    Step 'stop feed servers' { Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'powershell' -and $_.CommandLine -match 'serve-local-feed' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } }
    Step 'stop app + settings' { Get-Process -Name SliceApp, SystemSettings -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500 }
    Step 'remove repair scheduled tasks' { Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'OrthicLabs*' -or $_.TaskName -like '*SliceApp*' } | ForEach-Object { Stop-ScheduledTask -InputObject $_ -ErrorAction SilentlyContinue; Unregister-ScheduledTask -InputObject $_ -Confirm:$false -ErrorAction SilentlyContinue } }
    Step 'remove package (all users, then current user)' {
        foreach ($p in @(Get-AppxPackage -Name 'OrthicLabs.OtherApp' -ErrorAction SilentlyContinue)) { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction SilentlyContinue }   # wrong-identity control, if it was ever installed
        foreach ($p in @(Get-AppxPackage -Name $PkgName -AllUsers -ErrorAction SilentlyContinue)) {
            try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop } catch { try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop } catch { throw ('remove ' + $p.PackageFullName + ': ' + $_.Exception.Message) } }
        }
    }
    Step 'remove signer + feed certificates' {
        foreach ($c in @(Get-ChildItem Cert:\LocalMachine\TrustedPeople -ErrorAction SilentlyContinue | Where-Object { $_.Subject -match 'Orthic|SliceApp|SwiftRight' -or $_.Thumbprint -eq $script:SignerThumb })) { Remove-Item -LiteralPath $c.PSPath -Force }
        foreach ($store in 'My', 'Root') { foreach ($c in @(Get-ChildItem "Cert:\LocalMachine\$store" -ErrorAction SilentlyContinue | Where-Object { $_.Subject -eq 'CN=localhost' })) { Remove-Item -LiteralPath $c.PSPath -Force } }
    }
    Step 'remove http sslcert bindings 8443' { foreach ($ip in '127.0.0.1:8443', '[::1]:8443') { & netsh.exe http delete sslcert ipport=$ip 2>&1 | Out-Null } }
    Step 'remove app data + feed + harness temp' {
        foreach ($d in (Join-Path $env:LOCALAPPDATA 'SliceApp'), 'C:\feed', (Join-Path $env:TEMP 'w08-recovery-work'), (Join-Path $env:TEMP 'serve-local-feed.log')) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction Stop } }
        Get-ChildItem -LiteralPath $env:TEMP -Filter '*-repair-cleanup.log' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    # ---- verify
    $v = [ordered]@{}
    $v.packages = @(Get-AppxPackage -Name $PkgName -AllUsers -ErrorAction SilentlyContinue | ForEach-Object { $_.PackageFullName + ':' + $_.Status })
    $v.tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'OrthicLabs*' -or $_.TaskName -like '*SliceApp*' } | ForEach-Object { $_.TaskName })
    $v.certs = @(Get-ChildItem Cert:\LocalMachine\TrustedPeople -ErrorAction SilentlyContinue | Where-Object { $_.Subject -match 'Orthic|SliceApp|SwiftRight' -or $_.Thumbprint -eq $script:SignerThumb } | ForEach-Object { $_.Thumbprint }) +
        @(Get-ChildItem Cert:\LocalMachine\My, Cert:\LocalMachine\Root -ErrorAction SilentlyContinue | Where-Object { $_.Subject -eq 'CN=localhost' } | ForEach-Object { 'localhost:' + $_.Thumbprint })
    $v.sslcert_8443 = [bool]((& netsh.exe http show sslcert 2>&1 | Out-String) -match ':8443')
    $v.app_data = [bool](Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'SliceApp'))
    $v.feed_dir = [bool](Test-Path -LiteralPath 'C:\feed')
    $v.processes = @(Get-Process -Name SliceApp -ErrorAction SilentlyContinue | ForEach-Object { 'SliceApp#' + $_.Id }) + @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'powershell' -and $_.CommandLine -match 'serve-local-feed' } | ForEach-Object { 'feed#' + $_.ProcessId })
    $clean = ($v.packages.Count -eq 0 -and $v.tasks.Count -eq 0 -and $v.certs.Count -eq 0 -and -not $v.sslcert_8443 -and -not $v.app_data -and -not $v.feed_dir -and $v.processes.Count -eq 0)
    return [ordered]@{ clean = $clean; verify = $v; steps = $script:log }
}

function Save([string]$Why) {
    $res.reason = $Why
    [IO.File]::WriteAllText("$JobDir\result.json", (ConvertTo-Json -InputObject $res -Depth 10), $Utf8)
}

# A long-run retry test (keepState) leaves the package NeedsRemediation with the feed down on purpose; any other w08 / w08-reset job would destroy it (Reset-W08State runs before and after every job).
$LongRunLock = 'C:\sbq\state\longrun-active.json'
if ((Test-Path -LiteralPath $LongRunLock) -and -not $A.breakLongRun) { $res.refused = $true; $res.error = 'refused: the W08 long-run retry test is active (' + $LongRunLock + '); pass breakLongRun only when the test is finished or abandoned'; Save 'refused'; exit 0 }
try {
    # signer thumbprint (public cert out of the old package's signature) so the cleanup can remove exactly that cert
    $pkgSub = $(if ($A.pkgDir) { [string]$A.pkgDir } else { 'pkgs' })
    $oldMsix = Join-Path $W "$pkgSub\old.msix"; $newMsix = Join-Path $W "$pkgSub\new.msix"
    $sig = Get-AuthenticodeSignature -FilePath $oldMsix
    $script:SignerThumb = [string]$sig.SignerCertificate.Thumbprint
    $res.signer_thumbprint = $script:SignerThumb

    $rb = Reset-W08State
    $res.clean_before = $rb
    $proceed = $true
    if (-not $rb.clean) { $res.needs_fresh_sandbox = $true; $res.error = 'state not clean before the run; refusing to run (a truly fresh Sandbox is needed; lead decides)'; $proceed = $false }
    elseif ($action -eq 'reset') { $res.ok = $true; $proceed = $false }
    if ($proceed) {

    # ---- hashes of the packages (compare to the expected values when given)
    $res.old_sha256 = (Get-FileHash -LiteralPath $oldMsix -Algorithm SHA256).Hash.ToLower(); $res.new_sha256 = (Get-FileHash -LiteralPath $newMsix -Algorithm SHA256).Hash.ToLower()
    if ($A.expectOldSha256 -and $res.old_sha256 -ne ([string]$A.expectOldSha256).ToLower()) { throw 'old.msix sha256 mismatch' }
    if ($A.expectNewSha256 -and $res.new_sha256 -ne ([string]$A.expectNewSha256).ToLower()) { throw 'new.msix sha256 mismatch' }

    # ---- stage harness + packages like run-w08-recovery.ps1 does (same layout the guest script expects)
    $stage = 'C:\w08work\' + (Split-Path -Leaf $JobDir)
    $harness = "$stage\harness"; $pk = "$stage\packages"; $rec = "$JobDir\receipts"
    New-Item -ItemType Directory -Force -Path $harness, $pk, "$pk\feed", $rec | Out-Null
    $src = Get-Content -LiteralPath 'C:\sbq\guest\w08\w08-recovery-guest.ps1' -Raw
    $patched = [regex]::Replace($src, 'Stop-Computer\s+-Force', "L 'guest shutdown suppressed by the long-lived worker'")
    if ($patched -match 'Stop-Computer') { throw 'patch failed: Stop-Computer still present' }
    $res.guest_sha256_original = (Get-FileHash -LiteralPath 'C:\sbq\guest\w08\w08-recovery-guest.ps1' -Algorithm SHA256).Hash.ToLower()
    $res.stop_computer_calls_patched = ([regex]::Matches($src, 'Stop-Computer\s+-Force')).Count
    [IO.File]::WriteAllText("$harness\w08-recovery-guest.ps1", $patched, $Utf8)
    Copy-Item -LiteralPath 'C:\sbq\guest\w08\serve-local-feed.ps1' -Destination $harness
    [IO.File]::WriteAllText("$harness\method.txt", ($Method + "`r`n"), $Utf8)
    if ($A.delays) { [IO.File]::WriteAllText("$harness\delays.txt", ((([string]$A.delays -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join "`r`n") + "`r`n", $Utf8) }
    Copy-Item -LiteralPath $oldMsix -Destination "$pk\old.msix"; Copy-Item -LiteralPath $newMsix -Destination "$pk\new.msix"
    Copy-Item -LiteralPath $oldMsix -Destination "$pk\feed\SliceApp_0.1.0.0_x64.msix"; Copy-Item -LiteralPath $newMsix -Destination "$pk\feed\SliceApp_0.1.1.0_x64.msix"
    Copy-Item -LiteralPath "$W\feedin\SliceApp.0.appinstaller", "$W\feedin\SliceApp.1.appinstaller" -Destination "$pk\feed"
    if (Test-Path -LiteralPath "$W\$pkgSub\extra") { Copy-Item -LiteralPath "$W\$pkgSub\extra" -Destination "$pk\extra" -Recurse }   # negative-control inputs (wrong identity, truncated packages)
    Export-Certificate -Cert $sig.SignerCertificate -FilePath "$pk\signer.cer" -Type CERT | Out-Null   # public certificate only

    # ---- run the harness (interactive session of the Sandbox; UIA needs it). The worker's job timeout bounds it.
    $t0 = Get-Date
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$harness\w08-recovery-guest.ps1" -HarnessDir $harness -PackagesDir $pk -ReceiptsDir $rec -MaxAttempts $(if ($A.maxAttempts) { [int]$A.maxAttempts } else { 8 }) *>&1 | Out-File -LiteralPath "$JobDir\harness-console.txt" -Encoding utf8
    $res.harness_exit = $LASTEXITCODE
    $res.harness_seconds = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    $hr = $null
    try { $hr = Get-Content -LiteralPath "$rec\result.json" -Raw | ConvertFrom-Json } catch { $res.error = 'no harness result.json' }
    if ($hr) {
        $res.harness_errors = @($hr.errors)
        $res.induction = $hr.induction
        $res.pre_recovery_package = $hr.pre_recovery.package
        $res.recovery = $hr.recovery
        $res.post = $hr.post
        $res.ok = [bool](@($hr.errors).Count -eq 0)
        $rc = $hr.recovery
        $recovered = [bool]($hr.post.package -match ':Ok' -and $hr.post.launch.launched -and $hr.post.marker_in_file_after)
        switch ($Method) {
            'tier2-repair' { $res.pass = $recovered }
            'tier2-killclient' { $res.pass = $recovered }
            'tier2-stale' { $res.pass = $recovered }
            'tier2-mutex' { $res.pass = [bool]($recovered -and $rc.mutex_second_run_busy) }
            { $_ -in 'tier2-feed-down', 'tier2-wrongid', 'tier2-corrupt' } { $res.pass = [bool]($recovered -and $rc.failed_explicitly -and $rc.recovered_by_retry -and -not $rc.other_app_installed_at_end -and $rc.snapshot_before_restore.rows_sha_equals_written) }
            { $_ -in 'tier2-uninstall', 'tier2-uninstall-retry', 'tier2-healthy', 'tier2-task-deleted', 'tier2-sched-blocked' } { $res.pass = [bool]$rc.pass }
            'tier2-feed-down-long' { $res.pass = [bool]($hr.long_run -and $hr.long_run.package -match 'NeedsRemediation' -and -not $hr.long_run.feed_up) }
        }
    }
    }
} catch { $res.error = $_.Exception.Message; $res.ok = $false }
finally {
    if ($A.keepState -and $res.pass) { try { [IO.File]::WriteAllText($LongRunLock, (ConvertTo-Json @{ started_utc = (Get-Date).ToUniversalTime().ToString('o'); job = (Split-Path -Leaf $JobDir); note = 'W08 long-run retry test: do not run w08 / w08-reset; see qualification/clean-machine/windows/w08-tier2-signed-20261014-0.2.156/longrun' }), $Utf8) } catch { } }
    if ($A.keepState) { $res.clean_after = @{ clean = $null; kept = 'keepState: the W08 package state is left in place on purpose (long-run retry test); the next w08 / w08-reset job destroys it' } }
    else {
    try { $ra = Reset-W08State; $res.clean_after = $ra } catch { $res.clean_after = @{ clean = $false; error = $_.Exception.Message } }
    if ($res.clean_after -and -not $res.clean_after.clean) { $res.needs_fresh_sandbox = $true }
    }
    Save 'finished'
}
exit 0
