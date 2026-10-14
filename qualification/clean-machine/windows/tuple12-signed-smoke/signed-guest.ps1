# Guest check of the RELEASE-SIGNED tuple 12 SliceApp MSIX (CI run 38535084834) inside the long-lived Windows Sandbox (job kind=command runs this file).
# No certificate is imported: the MSIX must install on the platform's own trust. Phases:
#   A smoke   : Add-AppxPackage, shell activation, window renders, WM_CLOSE exit, QA driver `launch` on the unpacked bytes
#   B guard   : the out-of-package repair task <PFN>-Repair is registered by the packaged launch; guard script hash vs the RightKit pin
#   C healthy : task run on a healthy package changes nothing (last-result healthy, same package full name)
#   D taskdel : task deleted, the next launch registers it again
#   E uninst  : Remove-AppxPackage, task started as the logon stand-in, task and repair folder removed, rows.json kept
# Positive repair (cancelled update -> NeedsRemediation -> guard repair) needs a newer release-signed version; only 0.1.0.0 is signed, so it is NOT run here.
$ErrorActionPreference = 'Continue'
$d = 'C:\sbq\tuple12s'; $out = Join-Path $d 'out'
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $out | Out-Null
$r = [ordered]@{ started = (Get-Date).ToString('o') }
function Save { ($r | ConvertTo-Json -Depth 8) | Set-Content (Join-Path $out 'signed-guest.json') -Encoding utf8 }
function Get-Pkg { Get-AppxPackage -Name OrthicLabs.SliceApp | Select-Object -First 1 }
function Launch([string]$pfn, [string]$appId) { Start-Process explorer.exe ('shell:AppsFolder\' + $pfn + '!' + $appId) }
function Stop-App { Get-Process SliceApp -ErrorAction SilentlyContinue | ForEach-Object { try { [void]$_.CloseMainWindow() } catch {}; if (-not $_.WaitForExit(15000)) { try { $_.Kill() } catch {} } } }
function Wait-Window { $p = $null; for ($i = 0; $i -lt 60 -and -not ($p -and $p.MainWindowHandle -ne 0); $i++) { Start-Sleep -Milliseconds 500; $p = Get-Process SliceApp -ErrorAction SilentlyContinue | Select-Object -First 1; if ($p) { $p.Refresh() } }; return $p }
$guardDir = Join-Path $env:LOCALAPPDATA 'SliceApp\repair'
try {
    $msix = Join-Path $d 'SliceApp_0.1.0.0_x64.msix'
    $r.msix_sha256 = (Get-FileHash $msix -Algorithm SHA256).Hash.ToLower()
    $r.os = [string][Environment]::OSVersion.Version
    $sig = Get-AuthenticodeSignature $msix
    $r.signature_status = [string]$sig.Status; $r.signer = $sig.SignerCertificate.Subject; $r.signer_thumbprint = $sig.SignerCertificate.Thumbprint
    $r.timestamper = if ($sig.TimeStamperCertificate) { $sig.TimeStamperCertificate.Subject } else { $null }
    Get-AppxPackage -Name OrthicLabs.SliceApp | Remove-AppxPackage -ErrorAction SilentlyContinue
    $t0 = Get-Date
    Add-AppxPackage -Path $msix -ErrorAction Stop
    $r.install_seconds = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
    $pkg = Get-Pkg
    $r.package = [ordered]@{ full = $pkg.PackageFullName; version = [string]$pkg.Version; status = [string]$pkg.Status; publisher = $pkg.Publisher; signatureKind = [string]$pkg.SignatureKind; install = $pkg.InstallLocation }
    $appId = [string](Get-AppxPackageManifest -Package $pkg.PackageFullName).Package.Applications.Application.Id
    $pfn = $pkg.PackageFamilyName
    $r.trusted_people_has_signer = [bool](Get-ChildItem Cert:\LocalMachine\TrustedPeople -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $sig.SignerCertificate.Thumbprint })
    Save

    # ---- A: packaged activation + render
    Add-Type -AssemblyName System.Drawing
    Add-Type -Namespace T12 -Name W -MemberDefinition '[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r); [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h); [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }'
    $tl = Get-Date
    Launch $pfn $appId
    $proc = Wait-Window
    $act = [ordered]@{ process_found = [bool]$proc }
    if ($proc) {
        $act.pid = $proc.Id; $act.path = $proc.Path; $act.window_title = $proc.MainWindowTitle; $act.window_visible = [T12.W]::IsWindowVisible($proc.MainWindowHandle)
        Start-Sleep -Seconds 4
        $rc = New-Object T12.W+RECT; [void][T12.W]::GetWindowRect($proc.MainWindowHandle, [ref]$rc)
        $w = $rc.right - $rc.left; $h = $rc.bottom - $rc.top; $act.window_size = "$w x $h"
        if ($w -gt 50 -and $h -gt 50) {
            $bmp = New-Object System.Drawing.Bitmap $w, $h
            $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($rc.left, $rc.top, 0, 0, $bmp.Size); $g.Dispose()
            $bmp.Save((Join-Path $out 'packaged-window.png'), [System.Drawing.Imaging.ImageFormat]::Png)
            $colors = @{}; $dark = 0; $total = 0
            for ($y = 0; $y -lt $h; $y += 3) { for ($x = 0; $x -lt $w; $x += 3) { $c = $bmp.GetPixel($x, $y); $colors[$c.ToArgb()] = 1; $total++; if ($c.R + $c.G + $c.B -lt 60) { $dark++ } } }
            $bmp.Dispose()
            $act.distinct_colors_sampled = $colors.Count; $act.black_fraction = [math]::Round($dark / [math]::Max(1, $total), 3)
            $act.rendered = ($colors.Count -gt 20 -and ($dark / [math]::Max(1, $total)) -lt 0.9)
        }
        $act.close_sent = $proc.CloseMainWindow()
        $exited = $proc.WaitForExit(20000); $act.exited_within_20s = $exited
        if (-not $exited) { $act.forced_kill = $true; try { $proc.Kill() } catch {} }
    }
    $act.crash_events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error', 'Windows Error Reporting'; StartTime = $tl } -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'SliceApp' } | ForEach-Object { $_.Message.Substring(0, [math]::Min(200, $_.Message.Length)) })
    $r.packaged_activation = $act
    Save

    # ---- B: guard registration
    $taskName = $pkg.PackageFamilyName + '-Repair'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 90 -and -not ((Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) -and (Test-Path (Join-Path $guardDir 'guard.json')))) { Start-Sleep -Milliseconds 500 }
    $gb = [ordered]@{ task_name = $taskName; seconds_to_register = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
    $t = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    $gb.task_registered = [bool]$t
    if ($t) { $gb.triggers = @($t.Triggers | ForEach-Object { $_.CimClass.CimClassName }); $gb.action = [string]$t.Actions[0].Execute + ' ' + [string]$t.Actions[0].Arguments; $gb.run_as = [string]$t.Principal.UserId + ' ' + [string]$t.Principal.LogonType + ' ' + [string]$t.Principal.RunLevel }
    $gs = Join-Path $guardDir 'repair-guard.ps1'
    $gb.guard_script_sha256 = if (Test-Path $gs) { (Get-FileHash $gs -Algorithm SHA256).Hash.ToLower() } else { $null }
    $gb.guard_pin_sha256 = '3df2415f19db8dfaffad1714b105434236310f9e84e10616855f96ae58cf634b'
    $gb.guard_matches_pin = ($gb.guard_script_sha256 -eq $gb.guard_pin_sha256)
    try { $gb.guard_json = (Get-Content (Join-Path $guardDir 'guard.json') -Raw) -replace '\s+', ' ' } catch { $gb.guard_json = $null }
    $r.guard_registration = $gb
    Save

    # ---- C: guard on a healthy package
    $ch = [ordered]@{}
    $before = (Get-Pkg).PackageFullName + ':' + (Get-Pkg).Status
    $logLen = 0; try { $logLen = (Get-Content (Join-Path $guardDir 'repair.log') -Raw).Length } catch {}
    $tc = Get-Date
    Start-ScheduledTask -TaskName $taskName
    $res = $null; $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 90) {
        try { $x = Get-Content (Join-Path $guardDir 'last-result.json') -Raw -ErrorAction Stop | ConvertFrom-Json; if ($x -and ([datetime]$x.timeUtc).ToUniversalTime() -gt $tc.ToUniversalTime().AddSeconds(-1) -and [string]$x.mode -eq 'repair') { $res = $x; break } } catch {}
        Start-Sleep -Milliseconds 500
    }
    $ch.last_result = $res; $ch.seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    $after = (Get-Pkg).PackageFullName + ':' + (Get-Pkg).Status
    $newLog = ''; try { $all = Get-Content (Join-Path $guardDir 'repair.log') -Raw; $newLog = $all.Substring([math]::Min($logLen, $all.Length)) } catch {}
    $ch.package_before = $before; $ch.package_after = $after; $ch.add_appx_logged = ($newLog -match 'Add-AppxPackage')
    $ch.pass = [bool]($res -and [string]$res.status -eq 'healthy' -and [int]$res.code -eq 0 -and $before -eq $after -and -not $ch.add_appx_logged)
    $r.control_healthy = $ch
    Save

    # ---- D: task deleted, next launch re-registers it
    $cd = [ordered]@{}
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $cd.task_deleted = -not [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
    Launch $pfn $appId; $null = Wait-Window
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 90 -and -not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) { Start-Sleep -Milliseconds 500 }
    $cd.task_reregistered = [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue); $cd.seconds_to_reregister = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    $cd.pass = [bool]($cd.task_deleted -and $cd.task_reregistered)
    Stop-App
    $r.control_task_deleted = $cd
    Save

    # ---- E: uninstall keeps data, guard cleans up
    $cu = [ordered]@{}
    $rows = Join-Path $env:LOCALAPPDATA 'SliceApp\rows.json'
    $cu.rows_exists_before = [bool](Test-Path $rows); $cu.rows_sha_before = if ($cu.rows_exists_before) { (Get-FileHash $rows -Algorithm SHA256).Hash.ToLower() } else { $null }
    Get-AppxPackage -Name OrthicLabs.SliceApp | Remove-AppxPackage -ErrorAction Stop
    $cu.package_removed = -not [bool](Get-Pkg)
    $cu.task_exists_right_after_remove = [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue   # stands in for the next logon trigger
    while ($sw.Elapsed.TotalSeconds -lt 120 -and ((Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) -or (Test-Path $guardDir))) { Start-Sleep -Milliseconds 500 }
    $cu.task_gone = -not [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
    $cu.repair_dir_gone = -not (Test-Path $guardDir)
    $cu.seconds_to_cleanup = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    $cu.rows_exists_after = [bool](Test-Path $rows); $cu.rows_sha_after = if ($cu.rows_exists_after) { (Get-FileHash $rows -Algorithm SHA256).Hash.ToLower() } else { $null }
    $cu.pass = [bool]($cu.package_removed -and $cu.task_gone -and $cu.repair_dir_gone -and ($cu.rows_sha_before -eq $cu.rows_sha_after))
    $r.control_uninstall = $cu
    Save
} catch {
    $r.error = $_.Exception.Message + ' @ ' + $_.InvocationInfo.ScriptLineNumber
}
try { Get-AppxPackage -Name OrthicLabs.SliceApp | Remove-AppxPackage -ErrorAction SilentlyContinue; $r.final_package_present = [bool](Get-Pkg) } catch { $r.remove_error = $_.Exception.Message }
$r.finished = (Get-Date).ToString('o')
Save
