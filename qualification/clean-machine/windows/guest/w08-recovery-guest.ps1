# w08-recovery-guest.ps1 - Windows Sandbox guest (networking ENABLED), SR0 T12: recovery from `Modified, NeedsRemediation` on the FINAL packages.
# One method per fresh Sandbox (method.txt beside this script; optional line 2 = hold minutes for platform-register):
#   settings-repair     Settings > Apps > Installed apps > SliceApp > Advanced options > Repair, driven through UI Automation of the Settings app in this guest
#   platform-register   no action of ours: a launch attempt (and an optional hold) and the observed platform RegisterByPackageFullName operation, then status,
#                       relaunch, version and data afterwards
#   reset               Reset-AppxPackage
#   reinstall-same      Add-AppxPackage -Path <the same 0.1.0.0 MSIX> (same-version reinstall)
#   appinstaller-same   Add-AppxPackage -AppInstallerFile <feed that declares the installed 0.1.0.0>: no newer version available
#   settings-repair-same  as settings-repair, with the feed switched back to the 0.1.0.0 .appinstaller first (no newer version available to the Repair)
#   settings-repair-path  as settings-repair, but the old version is installed with Add-AppxPackage -Path (no App Installer association) and no feed is served (the W08 offline scenario)
#   settings-probe      development aid: no induction; dumps the Settings UI tree step by step (receipts settings-*.txt/jpg)
# Flow: trust the signer, serve the feed (as W12), install 0.1.0.0 through the feed, write a data marker through the UI, publish the 0.1.1.0 feed,
# induce NeedsRemediation by cancelling PackageManager.AddPackageAsync(0.1.1.0 msix) at staging+delay (retry delays until Status shows it), confirm the app
# does not launch, apply ONE recovery method, then record package status, relaunch (UIA window + log banner), version and data marker.
# Descended from the RightKit W08-recovery probe harness (RESULT-R5-W08-recovery.md); methods a..d of that probe were different questions.
[CmdletBinding()]
param(
    [string]$HarnessDir = $PSScriptRoot,
    [string]$PackagesDir = 'C:\Users\WDAGUtilityAccount\Desktop\clean-machine\packages',
    [string]$ReceiptsDir = 'C:\Users\WDAGUtilityAccount\Desktop\clean-machine\receipts',
    [int]$MaxAttempts = 40
)
$ErrorActionPreference = 'Continue'
if (-not $HarnessDir) { $HarnessDir = Split-Path -Parent $PSCommandPath }
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$MethodLines = @((Get-Content -LiteralPath (Join-Path $HarnessDir 'method.txt')) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
$Method = $MethodLines[0]
$HoldMinutes = $(if ($MethodLines.Count -gt 1) { [int]$MethodLines[1] } else { 0 })
$PathInstall = ($Method -like '*-path')   # old version installed with Add-AppxPackage -Path (no App Installer association) and no feed served: the W08 offline scenario
$PkgName = 'OrthicLabs.SliceApp'
$OldVersion = '0.1.0.0'
$NewVersion = '0.1.1.0'
$LocalAppData = Join-Path $env:LOCALAPPDATA 'SliceApp'
$RowsPath = Join-Path $LocalAppData 'rows.json'
$LogPath = Join-Path $LocalAppData 'slice-app.log'
$Feed = 'C:\feed'
$FeedUrl = 'https://localhost:8443/sliceapp/SliceApp.appinstaller'
$OldMsix = Join-Path $PackagesDir 'old.msix'
$NewMsix = Join-Path $PackagesDir 'new.msix'
$WorkDir = Join-Path $env:TEMP 'w08-recovery-work'
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$Marker = 'w08-recovery-' + $Method + '-marker'
$script:Pfn = ''
$script:AppId = 'App'
$script:MarkerSha = ''
$script:FeedProc = $null
$R = [ordered]@{ method = $Method; started_utc = (Get-Date).ToUniversalTime().ToString('o'); marker = $Marker; attempts = @(); induction = [ordered]@{}; pre_recovery = [ordered]@{}; recovery = [ordered]@{}; post = [ordered]@{}; errors = @() }

function Beat { try { [IO.File]::WriteAllText((Join-Path $WorkDir 'hb.txt'), (Get-Date).ToString('o')) } catch { } }
function L([string]$s) {
    $line = (Get-Date -Format 'HH:mm:ss.fff') + ' ' + $s
    try { [IO.File]::AppendAllText((Join-Path $ReceiptsDir 'log.txt'), $line + "`r`n", $Utf8) } catch { }
    Beat
}
function Save-Result { try { [IO.File]::WriteAllText((Join-Path $ReceiptsDir 'result.json'), ($R | ConvertTo-Json -Depth 8), $Utf8) } catch { L ('save-result failed: ' + $_.Exception.Message) } }

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

# ---------------------------------------------------------------- helpers
function Get-Pkgs { return @(Get-AppxPackage -Name $PkgName -ErrorAction SilentlyContinue) }
function Get-PkgText {
    $r = @(Get-Pkgs)
    if ($r.Count -eq 0) { return 'none' }
    return (($r | ForEach-Object { [string]$_.Version + ':' + [string]$_.Status }) -join ',')
}
function Get-PkgDetail {
    $r = @(Get-Pkgs)
    return @($r | ForEach-Object {
            [ordered]@{ version = [string]$_.Version; status = [string]$_.Status; full_name = [string]$_.PackageFullName; install_location = [string]$_.InstallLocation
                is_partially_staged = [string]$_.IsPartiallyStaged
                user_install_state = (@($_.PackageUserInformation | ForEach-Object { [string]$_.InstallState }) -join ',') }
        })
}
function Test-NeedsRemediation { foreach ($p in @(Get-Pkgs)) { if ([string]$p.Status -match 'NeedsRemediation') { return $true } }; return $false }
function Test-NewStaging { return (@([IO.Directory]::GetDirectories('C:\Program Files\WindowsApps', ($PkgName + '_' + $NewVersion + '_*'))).Count -gt 0) }
function Get-Sha([string]$Path) { if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash } else { return 'absent' } }
function Test-MarkerInFile {
    if (-not (Test-Path -LiteralPath $RowsPath -PathType Leaf)) { return $false }
    $t = [IO.File]::ReadAllText($RowsPath, [Text.Encoding]::UTF8)
    return $t.Contains($Marker)
}

function Invoke-Bounded([string]$Script, [int]$TimeoutSec) {
    $outf = Join-Path $WorkDir ('b-' + [guid]::NewGuid().ToString('N') + '.txt')
    $cmd = @"
`$ErrorActionPreference = 'Stop'
`$r = ''
try { $Script; `$r = 'OK' } catch { `$r = 'FAILED: ' + `$_.Exception.Message + ' | id=' + `$_.FullyQualifiedErrorId }
Set-Content -LiteralPath '$outf' -Value `$r
"@
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc)
    while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt $TimeoutSec) { Beat; Start-Sleep -Milliseconds 500 }
    if ($p.HasExited) {
        $t = ''
        if (Test-Path -LiteralPath $outf) { $t = (Get-Content -LiteralPath $outf -Raw).Trim() }
        return [ordered]@{ timed_out = $false; result = $t; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
    }
    try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
    return [ordered]@{ timed_out = $true; result = ('no result within ' + $TimeoutSec + ' s'); seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1) }
}

function Save-Shot([string]$Name) {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
        $bmp.Save((Join-Path $ReceiptsDir ($Name + '.jpg')), [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $g.Dispose(); $bmp.Dispose()
        L ('screenshot ' + $Name + '.jpg ' + $b.Width + 'x' + $b.Height)
    } catch { L ('screenshot ' + $Name + ' failed: ' + $_.Exception.Message) }
}

function Get-TopWindows {
    $AE = [System.Windows.Automation.AutomationElement]
    $all = @($AE::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition))
    return @($all | ForEach-Object { 'class=' + $_.Current.ClassName + ' name=[' + $_.Current.Name + '] pid=' + $_.Current.ProcessId })
}
function Dump-Window($win, [int]$Max = 80) {
    $out = @()
    try {
        $kids = @($win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))
        foreach ($k in ($kids | Select-Object -First $Max)) { $out += ($k.Current.ControlType.ProgrammaticName + ' name=[' + $k.Current.Name + '] id=[' + $k.Current.AutomationId + ']') }
    } catch { $out += ('dump failed: ' + $_.Exception.Message) }
    return $out
}

# ---- app launch / UIA (copied from the R5 guest harness)
function Find-AppWindow {
    $AE = [System.Windows.Automation.AutomationElement]
    return $AE::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, (New-Object System.Windows.Automation.PropertyCondition($AE::ClassNameProperty, 'Zed::Window')))
}
function Get-AppProcs { return @(Get-Process -Name 'SliceApp' -ErrorAction SilentlyContinue) }
function Stop-App {
    foreach ($p in (Get-AppProcs)) { [void]$p.CloseMainWindow() }
    Start-Sleep -Seconds 3
    foreach ($p in (Get-AppProcs)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
    return (@(Get-AppProcs).Count -eq 0)
}
function Invoke-Launch([int]$TimeoutSec, [string]$Tag) {
    $o = [ordered]@{ tag = $Tag; launched = $false; pid = 0; window_name = ''; exe_path = ''; running_version = ''; seconds = 0; processes_without_window = 0; top_windows = @() }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    if (-not $script:Pfn) { $o.error = 'no package family name known'; return $o }
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('shell:AppsFolder\' + $script:Pfn + '!' + $script:AppId) | Out-Null
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $procs = @(Get-AppProcs | Where-Object { $_.MainWindowHandle -ne 0 })
        if ($procs.Count -gt 0) {
            $win = Find-AppWindow
            if ($win) {
                $o.launched = $true; $o.pid = [int]$procs[0].Id; $o.window_name = [string]$win.Current.Name
                try { $o.exe_path = [string](Get-Process -Id $o.pid).MainModule.FileName } catch { $o.exe_path = '' }
                $m = [regex]::Match($o.exe_path, 'SliceApp_(\d+\.\d+\.\d+\.\d+)_')
                if ($m.Success) { $o.running_version = $m.Groups[1].Value }
                break
            }
        }
        Beat
        Start-Sleep -Milliseconds 500
    }
    $o.seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    $o.processes_without_window = @(Get-AppProcs | Where-Object { $_.MainWindowHandle -eq 0 }).Count
    $o.top_windows = @(Get-TopWindows | Where-Object { $_ -notmatch 'class=(Shell_TrayWnd|Progman|Shell_SecondaryTrayWnd|WorkerW) ' })
    if (-not $o.launched) {
        # what the OS shows instead (e.g. a "Can't open this app" dialog): dump the text of every non-shell top-level window
        $dumps = @()
        $AE = [System.Windows.Automation.AutomationElement]
        foreach ($w in @($AE::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition))) {
            if ($w.Current.ClassName -in @('Shell_TrayWnd', 'Progman', 'Shell_SecondaryTrayWnd', 'WorkerW')) { continue }
            $dumps += ('WINDOW class=' + $w.Current.ClassName + ' name=[' + $w.Current.Name + ']')
            $dumps += (Dump-Window $w 25)
        }
        $o.window_dumps = $dumps
    }
    return $o
}
function Find-ByName($Root, [string]$Name, $ControlType) {
    $c1 = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    $c2 = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ControlType)
    return @($Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.AndCondition($c1, $c2))))
}
function Find-RowFields($Root) {
    $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
    return @($Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c) | Where-Object { $_.Current.AutomationId -like 'row/*/field' })
}
function Write-MarkerRow($Root, [string]$Text) {
    $btn = @(Find-ByName -Root $Root -Name 'Insert above' -ControlType ([System.Windows.Automation.ControlType]::Button))
    if ($btn.Count -eq 0) { throw 'button "Insert above" not found in UIA tree' }
    $btn[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    $target = $null; $rows = @()
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline -and -not $target) {
        Start-Sleep -Milliseconds 500
        $rows = @(Find-RowFields -Root $Root)
        foreach ($r in $rows) { if ([string]$r.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value -eq '') { $target = $r; break } }
    }
    if (-not $target) { throw 'no empty Row field after Insert above (15 s)' }
    $target.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Text)
}
function Read-RowValues($Root) {
    $vals = @()
    foreach ($r in @(Find-RowFields -Root $Root)) { $vals += [string]$r.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value }
    return , $vals
}

# ---- feed
function Set-Feed([int]$n) { if (-not (Test-Path -LiteralPath $Feed)) { return }; Copy-Item -LiteralPath (Join-Path $PackagesDir ('feed\SliceApp.' + $n + '.appinstaller')) -Destination (Join-Path $Feed 'SliceApp.appinstaller') -Force }
function Start-Feed {
    if (Test-Path -LiteralPath $Feed) { Remove-Item -LiteralPath $Feed -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Feed | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $PackagesDir 'feed') -Filter '*.msix' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $Feed -Force }
    Set-Feed 0
    $script:FeedProc = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $HarnessDir 'serve-local-feed.ps1'), '-Dir', $Feed, '-DisposableGuest')
    L ('feed server pid ' + $script:FeedProc.Id)
    $up = $false; $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline -and -not $up) {
        try { $up = ((Invoke-WebRequest -Uri $FeedUrl -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200) } catch { Start-Sleep -Seconds 2 }
    }
    return $up
}
function Get-FeedTail([int]$n = 15) {
    # [string] cast: Get-Content decorates each line with PSPath/PSDrive/PSProvider note properties; ConvertTo-Json -Depth 8 then walks the provider graph and never returns
    try { return @(Get-Content -LiteralPath (Join-Path $env:TEMP 'serve-local-feed.log') -ErrorAction Stop | Select-Object -Last $n | ForEach-Object { [string]$_ }) } catch { return @('no feed log') }
}
function Get-FeedRequestCount { try { return @(Get-Content -LiteralPath (Join-Path $env:TEMP 'serve-local-feed.log') -ErrorAction Stop | Where-Object { $_ -match ' START ' }).Count } catch { return 0 } }

function Get-AppInstallerAssoc {
    # Package.GetAppInstallerInfo(): the .appinstaller URI the registered package is associated with (null when installed by path)
    try {
        [void][Windows.Management.Deployment.PackageManager, Windows.Management.Deployment, ContentType = WindowsRuntime]
        $pm = New-Object Windows.Management.Deployment.PackageManager
        $pk = @($pm.FindPackagesForUser('', $script:Pfn))
        if ($pk.Count -eq 0) { return 'no package' }
        $out = @()
        foreach ($x in $pk) {
            $ai = $x.GetAppInstallerInfo()
            $out += ([string]$x.Id.Version.Major + '.' + [string]$x.Id.Version.Minor + '.' + [string]$x.Id.Version.Build + '.' + [string]$x.Id.Version.Revision + ' -> ' + $(if ($ai) { [string]$ai.Uri } else { 'null (not associated)' }))
        }
        return ($out -join '; ')
    } catch { return 'unreadable: ' + $_.Exception.Message }
}
function Get-AppxEvents([datetime]$Since, [int]$Max = 60) {
    try {
        return @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-AppXDeploymentServer/Operational'; StartTime = $Since.AddSeconds(-1) } -ErrorAction Stop |
                Sort-Object TimeCreated | Select-Object -First $Max | ForEach-Object {
                $msg = ($_.Message -replace '\s+', ' ')
                ('{0:HH:mm:ss.fff} id={1} {2}: {3}' -f $_.TimeCreated, $_.Id, $_.LevelDisplayName, $msg.Substring(0, [Math]::Min(200, $msg.Length)))
            })
    } catch { return @('events unreadable: ' + $_.Exception.Message) }
}

# ---------------------------------------------------------------- induction
function Install-OldViaFeed {
    Stop-App | Out-Null
    foreach ($p in @(Get-Pkgs)) {
        try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop } catch { L ('  Remove-AppxPackage failed: ' + $_.Exception.Message) }
    }
    if (@(Get-Pkgs).Count -gt 0) { return 'old package still registered after remove: ' + (Get-PkgText) }
    Set-Feed 0
    $ai = $(if ($PathInstall) { Invoke-Bounded ("Add-AppxPackage -Path '" + $OldMsix + "'") 150 } else { Invoke-Bounded ("Add-AppxPackage -AppInstallerFile '" + $FeedUrl + "'") 150 })
    if ($ai.timed_out -or $ai.result -ne 'OK') { return 'feed install failed: ' + $ai.result }
    $pk = @(Get-Pkgs)
    if ($pk.Count -ne 1 -or [string]$pk[0].Version -ne $OldVersion -or [string]$pk[0].Status -ne 'Ok') { return 'unexpected state after feed install: ' + (Get-PkgText) }
    $script:Pfn = [string]$pk[0].PackageFamilyName
    return ''
}

function Invoke-CancelAttempt([int]$n, [int]$DelayMs) {
    $att = [ordered]@{ n = $n; delay_ms = $DelayMs; started = (Get-Date -Format 'HH:mm:ss') }
    $tAll = [Diagnostics.Stopwatch]::StartNew()
    $errArr = @(Install-OldViaFeed)
    $err = [string]$errArr[-1]
    $att.install_old_s = [math]::Round($tAll.Elapsed.TotalSeconds, 1)
    if (-not $err) { $att.appinstaller_assoc_after_install = Get-AppInstallerAssoc }
    if ($err) { $att.outcome = 'setup-failed'; $att.error = $err; return $att }
    # first attempt: write the data marker through the UI (rows.json is outside the package and survives remove/reinstall)
    if (-not $script:MarkerSha) {
        $w = Invoke-Launch 60 'marker-write'
        if (-not $w.launched) { $att.outcome = 'setup-failed'; $att.error = 'old build did not launch for the marker write'; return $att }
        $root = Find-AppWindow
        Write-MarkerRow -Root $root -Text $Marker
        $deadline = (Get-Date).AddSeconds(20); while ((Get-Date) -lt $deadline -and -not (Test-MarkerInFile)) { Start-Sleep -Milliseconds 500 }
        Stop-App | Out-Null
        if (-not (Test-MarkerInFile)) { $att.outcome = 'setup-failed'; $att.error = 'marker never reached rows.json'; return $att }
        $script:MarkerSha = Get-Sha $RowsPath
        $R.marker_sha_written = $script:MarkerSha
        L ('marker written, rows.json sha ' + $script:MarkerSha)
    }
    Set-Feed 1   # the update is published
    $att.rows_sha_before = Get-Sha $RowsPath
    $att.registered_before = Get-PkgText
    # clear a stale new-version staging dir, if any
    $dl = (Get-Date).AddSeconds(10); while ((Test-NewStaging) -and (Get-Date) -lt $dl) { Start-Sleep -Milliseconds 500 }
    $att.staging_new_before_start = Test-NewStaging
    $evStart = Get-Date
    [void][Windows.Management.Deployment.PackageManager, Windows.Management.Deployment, ContentType = WindowsRuntime]
    [void][Windows.Foundation.IAsyncInfo, Windows.Foundation, ContentType = WindowsRuntime]
    $asyncInfo = [Windows.Foundation.IAsyncInfo]
    $pm = New-Object Windows.Management.Deployment.PackageManager
    $uri = New-Object Uri(('file:///' + ($NewMsix -replace '\\', '/')))
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $op = $pm.AddPackageAsync($uri, [Collections.Generic.IEnumerable[Uri]]$null, [Windows.Management.Deployment.DeploymentOptions]::None)
    $seen = $false; $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        if (Test-NewStaging) { $seen = $true; break }
        if ([int]$asyncInfo.GetProperty('Status').GetValue($op) -ne 0) { break }
        Start-Sleep -Milliseconds 5
    }
    $att.trigger_seen = $seen
    $att.t_trigger_ms = [int]$watch.ElapsedMilliseconds
    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
    $stNow = [int]$asyncInfo.GetProperty('Status').GetValue($op)
    $att.op_status_at_cancel = [string]$stNow   # 0 Started, 1 Completed, 2 Canceled, 3 Error
    $att.t_cancel_ms = [int]$watch.ElapsedMilliseconds
    if ($stNow -eq 0) { [void]$asyncInfo.GetMethod('Cancel').Invoke($op, $null) }
    $d2 = (Get-Date).AddSeconds(60)
    while ([int]$asyncInfo.GetProperty('Status').GetValue($op) -eq 0 -and (Get-Date) -lt $d2) { Start-Sleep -Milliseconds 50 }
    $att.op_status_after = [string][int]$asyncInfo.GetProperty('Status').GetValue($op)
    $att.op_error_code = [string]$asyncInfo.GetProperty('ErrorCode').GetValue($op)
    # settle: stable for 6 s, max 40 s
    $last = ''; $stableSince = Get-Date; $sw2 = [Diagnostics.Stopwatch]::StartNew(); $timeline = @()
    while ($sw2.Elapsed.TotalSeconds -lt 40) {
        $txt = (Get-PkgText) + ' | staging_new=' + (Test-NewStaging)
        if ($txt -ne $last) { $timeline += ('+' + [int]$watch.ElapsedMilliseconds + 'ms ' + $txt); $last = $txt; $stableSince = Get-Date }
        elseif (((Get-Date) - $stableSince).TotalSeconds -ge 6) { break }
        Start-Sleep -Seconds 1
    }
    $att.timeline = $timeline
    $att.registered_after = Get-PkgText
    $att.detail_after = Get-PkgDetail
    $att.rows_sha_after = Get-Sha $RowsPath
    $att.events = Get-AppxEvents $evStart
    $att.failed_to_reach_state = ''
    foreach ($e in @($att.events)) { if ($e -match 'Failed to reach state (\w+)') { $att.failed_to_reach_state = $Matches[1]; break } }
    $reg = @(Get-Pkgs)
    $newReg = [bool]($reg | Where-Object { [string]$_.Version -eq $NewVersion })
    $att.outcome = $(if (Test-NeedsRemediation) { 'NEEDS-REMEDIATION' }
        elseif ($newReg -and $reg.Count -eq 1 -and [string]$reg[0].Status -eq 'Ok') { 'completed-anyway' }
        elseif ($reg.Count -eq 1 -and [string]$reg[0].Version -eq $OldVersion -and [string]$reg[0].Status -eq 'Ok') { 'old-ok' }
        else { 'other' })
    $att.total_s = [math]::Round($tAll.Elapsed.TotalSeconds, 1)
    return $att
}

function Probe-Launch([string]$Tag, [int]$TimeoutSec) {
    $feedBefore = Get-FeedRequestCount
    $o = Invoke-Launch $TimeoutSec $Tag
    $o.package_after = Get-PkgText
    $o.feed_requests_during = (Get-FeedRequestCount) - $feedBefore
    return $o
}

function Post-State([string]$Tag) {
    $p = [ordered]@{ tag = $Tag }
    $p.package = Get-PkgText
    $p.package_detail = Get-PkgDetail
    $p.appinstaller_assoc = Get-AppInstallerAssoc
    $p.needs_remediation = Test-NeedsRemediation
    $p.marker_in_file_before_launch = Test-MarkerInFile
    $p.rows_sha_before_launch = Get-Sha $RowsPath
    $p.rows_sha_equals_written = ($p.rows_sha_before_launch -eq $script:MarkerSha)
    if (@(Get-Pkgs).Count -gt 0) {
        $logBefore = ''
        if (Test-Path -LiteralPath $LogPath) { try { $logBefore = (Get-Content -LiteralPath $LogPath -Raw -ErrorAction Stop) } catch { } }
        $l = Invoke-Launch 60 ($Tag + '-launch')
        $p.launch = $l
        if ($l.launched) {
            try { $root = Find-AppWindow; $vals = Read-RowValues -Root $root; $p.marker_row_shown_in_ui = [bool]($vals -contains $Marker); $p.ui_row_count = $vals.Count } catch { $p.ui_error = $_.Exception.Message }
            $p.closed_for_log_read = Stop-App
            $logText = ''
            if (Test-Path -LiteralPath $LogPath) {
                try { $fs = [IO.File]::Open($LogPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite); try { $sr = New-Object IO.StreamReader($fs); $logText = $sr.ReadToEnd() } finally { $fs.Dispose() } } catch { $logText = 'unreadable: ' + $_.Exception.Message }
            }
            $p.log_banner_for_pid = ($logText -match ('slice-app: log opened \S+ pid=' + $l.pid + ' '))
            $p.log_tail = (($logText -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 3) -join ' | ')
        }
    } else { $p.launch = [ordered]@{ launched = $false; error = 'no package registered' } }
    $p.marker_in_file_after = Test-MarkerInFile
    $p.rows_sha_after = Get-Sha $RowsPath
    $p.rows_sha_equals_written_after = ($p.rows_sha_after -eq $script:MarkerSha)
    return $p
}


# ---------------------------------------------------------------- Settings (UI Automation, inside this disposable guest only)
function Get-SettingsWindow {
    $AE = [System.Windows.Automation.AutomationElement]
    foreach ($w in @($AE::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition))) {
        $n = [string]$w.Current.Name
        if ($n -eq 'Settings' -or ($w.Current.ClassName -eq 'ApplicationFrameWindow' -and $n -match 'Settings')) { return $w }
    }
    return $null
}
function Wait-SettingsWindow([int]$Sec) {
    $dl = (Get-Date).AddSeconds($Sec)
    while ((Get-Date) -lt $dl) { $w = Get-SettingsWindow; if ($w) { return $w }; Beat; Start-Sleep -Milliseconds 500 }
    return $null
}
function Get-AllElements($Root) {
    try { return @($Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) } catch { return @() }
}
function Dump-Settings([string]$Tag) {
    # every named element of the Settings window: control type, name, automation id; written to receipts\settings-<Tag>.txt and returned (first 60) for the result
    $w = Get-SettingsWindow
    $o = @()
    if ($w) {
        foreach ($e in (Get-AllElements $w)) {
            try {
                $n = [string]$e.Current.Name
                $id = [string]$e.Current.AutomationId
                if ($n -or $id) { $o += ($e.Current.ControlType.ProgrammaticName -replace '^ControlType\.', '') + ' name=[' + $n + '] id=[' + $id + '] enabled=' + $e.Current.IsEnabled + $(if ($e.Current.IsOffscreen) { ' offscreen' } else { '' }) }
            } catch { }
        }
    } else { $o = @('no Settings window') }
    try { [IO.File]::WriteAllLines((Join-Path $ReceiptsDir ('settings-' + $Tag + '.txt')), [string[]]$o, $Utf8) } catch { }
    Save-Shot ('settings-' + $Tag)
    L ('settings dump ' + $Tag + ': ' + $o.Count + ' named elements')
    return , @($o | Select-Object -First 60)
}
function Find-SettingsElement([string]$NameRegex, [string]$TypeName = '') {
    $w = Get-SettingsWindow
    if (-not $w) { return $null }
    foreach ($e in (Get-AllElements $w)) {
        try {
            if ([string]$e.Current.Name -match $NameRegex) {
                if (-not $TypeName -or ($e.Current.ControlType.ProgrammaticName -replace '^ControlType\.', '') -eq $TypeName) { return $e }
            }
        } catch { }
    }
    return $null
}
function Wait-SettingsElement([string]$NameRegex, [string]$TypeName, [int]$Sec) {
    $dl = (Get-Date).AddSeconds($Sec)
    while ((Get-Date) -lt $dl) { $e = Find-SettingsElement $NameRegex $TypeName; if ($e) { return $e }; Beat; Start-Sleep -Milliseconds 700 }
    return $null
}
function Invoke-Element($e) {
    # UIA only: Invoke, else SelectionItem.Select, else ExpandCollapse.Expand; returns the pattern used. An off-screen element is scrolled into view first.
    $p = $null
    try {
        if ($e.Current.IsOffscreen) {
            if ($e.TryGetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern, [ref]$p)) { $p.ScrollIntoView() } else { $e.SetFocus() }
            Start-Sleep -Milliseconds 800
        }
    } catch { L ('  scroll-into-view failed: ' + $_.Exception.Message) }
    $p = $null
    if ($e.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$p)) { $p.Invoke(); return 'Invoke' }
    if ($e.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$p)) { $p.Select(); return 'SelectionItem.Select' }
    if ($e.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$p)) { $p.Expand(); return 'ExpandCollapse.Expand' }
    return 'none'
}
function Stop-Settings { foreach ($p in @(Get-Process -Name 'SystemSettings' -ErrorAction SilentlyContinue)) { try { Stop-Process -Id $p.Id -Force } catch { } } }

# Opens the SliceApp Advanced options page in Settings (URI forms first, then Installed apps > search > "..." > Advanced options) and returns a record of what happened.
function Open-AdvancedOptions($rec) {
    $steps = @()
    $found = $null
    $uris = @('ms-settings:appsfeatures-app', ('ms-settings:appsfeatures-app?PackageFamilyName=' + $script:Pfn), ('ms-settings:appsfeatures-app?' + $script:Pfn))   # the parentheses matter: the comma binds tighter than +
    $i = 0
    foreach ($u in $uris) {
        $i++
        Stop-Settings; Start-Sleep -Seconds 1
        try { Start-Process $u; $steps += ('uri ' + $u + ' started') } catch { $steps += ('uri ' + $u + ' threw: ' + $_.Exception.Message); continue }
        $w = Wait-SettingsWindow 25
        Start-Sleep -Seconds 3
        $d = Dump-Settings ('uri' + $i)
        $rb = Find-SettingsElement '^Repair$' 'Button'
        $steps += ('uri ' + $u + ' -> Settings window=' + [bool]$w + ' Repair button=' + [bool]$rb)
        $rec[('uri_' + $i + '_dump')] = $d
        if ($rb) { $found = $rb; $rec.route = 'uri: ' + $u; break }
    }
    if (-not $found) {
        Stop-Settings; Start-Sleep -Seconds 1
        Start-Process 'ms-settings:appsfeatures'
        $w = Wait-SettingsWindow 30
        Start-Sleep -Seconds 3
        $rec.installed_apps_dump = Dump-Settings 'installed-apps'
        $steps += ('ms-settings:appsfeatures Settings window=' + [bool]$w)
        $edit = Wait-SettingsElement 'Search apps|Search' 'Edit' 20
        if ($edit) {
            try { $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('SliceApp'); $steps += 'search box set to SliceApp' } catch { $steps += ('search set failed: ' + $_.Exception.Message) }
            Start-Sleep -Seconds 3
        } else { $steps += 'no search box found' }
        $rec.after_search_dump = Dump-Settings 'after-search'
        $more = Find-SettingsElement 'More options.*SliceApp|SliceApp.*More options' 'Button'
        if (-not $more) { $more = Find-SettingsElement 'More options|^\.\.\.$' 'Button' }
        if ($more) {
            $steps += ('more-options button [' + $more.Current.Name + '] via ' + (Invoke-Element $more))
            Start-Sleep -Seconds 2
            $rec.menu_dump = Dump-Settings 'more-options-menu'
            $adv = Wait-SettingsElement '^Advanced options$' '' 10
            if ($adv) {
                $steps += ('Advanced options [' + $adv.Current.ControlType.ProgrammaticName + '] via ' + (Invoke-Element $adv))
                Start-Sleep -Seconds 3
                $rec.advanced_dump = Dump-Settings 'advanced-options'
                $found = Wait-SettingsElement '^Repair$' 'Button' 15
                if ($found) { $rec.route = 'Installed apps > search > More options > Advanced options' }
            } else { $steps += 'no Advanced options item in the menu' }
        } else { $steps += 'no More options button for the SliceApp row' }
    }
    $rec.steps = $steps
    return $found
}

# ---------------------------------------------------------------- main
# watchdog: separate process; if no heartbeat for 360 s it captures evidence, writes DONE and stops the guest
$wd = Join-Path $HarnessDir 'w08-recovery-watchdog.ps1'
if (Test-Path -LiteralPath $wd) { Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $wd, '-ReceiptsDir', $ReceiptsDir, '-Hb', (Join-Path $WorkDir 'hb.txt')) | Out-Null }
try {
    L ('w08-recovery guest start, method ' + $Method + ', host ' + $env:COMPUTERNAME + ', os ' + [Environment]::OSVersion.Version)
    $R.default_routes = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue).Count
    L ('default routes: ' + $R.default_routes)
    # signer trust (public .cer only, as W02)
    $cer = Join-Path $PackagesDir 'signer.cer'
    Import-Certificate -FilePath $cer -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null
    L 'signer imported to TrustedPeople'
    if ($PathInstall) { L 'path-install mode: no feed server (old version installed with Add-AppxPackage -Path)' }
    elseif (-not (Start-Feed)) { throw 'local feed did not come up' }
    else { L 'feed up (0.1.0.0 feed)' }
    if ($Method -eq 'settings-probe') {
        $pe = @(Install-OldViaFeed); $pe = [string]$pe[-1]
        if ($pe) { throw $pe }
        $R.recovery.package = Get-PkgText
        $R.recovery.probe = [ordered]@{}
        try { $script:AppId = [string](Get-AppxPackageManifest -Package (Get-Pkgs)[0].PackageFullName).Package.Applications.Application.Id } catch { }
        $rb = Open-AdvancedOptions $R.recovery
        $R.recovery.repair_button_found = [bool]$rb
        Stop-Settings
        Save-Result
        return
    }
    $delays = @(240, 200, 280, 240, 220, 260, 230, 250, 210, 270, 245, 235, 225, 255, 215, 265, 205, 275)
    $success = $false
    for ($n = 1; $n -le $MaxAttempts; $n++) {
        $d = $delays[($n - 1) % $delays.Count]
        L ('attempt ' + $n + ' delay +' + $d + ' ms')
        $att = $null
        try { $att = Invoke-CancelAttempt $n $d } catch { $att = [ordered]@{ n = $n; delay_ms = $d; outcome = 'exception'; error = $_.Exception.Message } }
        $R.attempts += , $att
        L ('  -> ' + $att.outcome + ' registered=' + $att.registered_after + ' op_after=' + $att.op_status_after + ' failed_state=' + $att.failed_to_reach_state + ' ' + $att.error)
        Save-Result
        if ($att.outcome -eq 'NEEDS-REMEDIATION') { $success = $true; break }
    }
    $R.induction.success = $success
    $R.induction.attempts_total = $R.attempts.Count
    $R.induction.genuine_cancels = @($R.attempts | Where-Object { $_.outcome -in @('old-ok', 'NEEDS-REMEDIATION', 'other') }).Count
    $R.induction.completed_anyway = @($R.attempts | Where-Object { $_.outcome -eq 'completed-anyway' }).Count
    $R.induction.setup_failed = @($R.attempts | Where-Object { $_.outcome -in @('setup-failed', 'exception') }).Count
    if ($success) {
        $R.induction.winning_delay_ms = $R.attempts[-1].delay_ms
        $R.induction.winning_failed_state = $R.attempts[-1].failed_to_reach_state
    }
    Save-Result
    if (-not $success) { throw 'induction did not reach NeedsRemediation' }

    # ---- confirm NeedsRemediation and that the app does not launch
    $pre = $R.pre_recovery
    $pre.package = Get-PkgText
    $pre.package_detail = Get-PkgDetail
    $pre.all_users = @(Get-AppxPackage -AllUsers -Name $PkgName -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.Version + ':' + [string]$_.Status })
    $pre.rows_sha = Get-Sha $RowsPath
    $pre.appinstaller_assoc = Get-AppInstallerAssoc
    L ('appinstaller association after induction: ' + $pre.appinstaller_assoc + ' | after install of the winning attempt: ' + $R.attempts[-1].appinstaller_assoc_after_install)
    $pre.marker_in_file = Test-MarkerInFile
    $pre.rows_sha_equals_written = ($pre.rows_sha -eq $script:MarkerSha)
    try { $pre.app_id = [string](Get-AppxPackageManifest -Package (Get-Pkgs)[0].PackageFullName).Package.Applications.Application.Id; if ($pre.app_id) { $script:AppId = $pre.app_id } } catch { $pre.app_id_error = $_.Exception.Message }
    $winBase = @(Get-TopWindows)
    $evPre = Get-Date
    if ($Method -eq 'platform-register') {
        # the launch attempts ARE the experiment for this method: first attempt now (as the R5-08 case did), hold, second attempt in the method
        $pl = Probe-Launch 'confirm-no-launch' 45
        $pre.launch_probe = $pl
        Save-Shot 'pre-recovery-launch'
        $pre.package_after_launch_probe = Get-PkgText
        $pre.app_launches = [bool]$pl.launched
        $pre.launch_probe_events = @(Get-AppxEvents $evPre 80 | Where-Object { $_ -match 'Register|Repair|AddFromAppInstaller|Add operation|Remove operation|Started deployment' } | Select-Object -First 25)
        L ('pre-recovery: package=' + $pre.package + ' launched=' + $pl.launched + ' after the probe: ' + $pre.package_after_launch_probe + ' windows=' + (($pl.top_windows) -join ' ; '))
        Stop-App | Out-Null
        if ($pl.launched) { L 'WARNING: app launched while NeedsRemediation was recorded' }
    } else {
        # No launch attempt before the method: in R5-08 a launch attempt was followed by a platform repair, and in this harness's reinstall-same-1 run a launch attempt
        # was followed by an App Installer update to 0.1.1.0 (feed requests during the probe), so a probe would change the state under test. The state is read from the package manager.
        $pre.launch_probe_skipped = 'no launch attempt before the method (a launch attempt can itself trigger recovery)'
        L ('pre-recovery: package=' + $pre.package + ' (no launch attempt before the method)')
    }
    $pre.package_at_method_start = Get-PkgText
    $pre.needs_remediation_at_method_start = [bool](Test-NeedsRemediation)
    if (-not $pre.needs_remediation_at_method_start) { L ('WARNING: package is no longer NeedsRemediation at the start of the method: ' + $pre.package_at_method_start + ' (the run does not test the method)') }
    Save-Result

    # ---- recovery method
    $rec = $R.recovery
    $evStart = $(if ($Method -eq 'platform-register') { $evPre } else { Get-Date })
    $feedBefore = Get-FeedRequestCount
    $sw = [Diagnostics.Stopwatch]::StartNew()
    switch ($Method) {
        { $_ -in 'settings-repair', 'settings-repair-same', 'settings-repair-path' } {
            if ($Method -eq 'settings-repair-same') { Set-Feed 0; $rec.feed_switched_back_to_0_1_0_0 = $true }   # no newer version available when Repair runs
            $rec.command = 'Settings > Apps > Installed apps > SliceApp > Advanced options > Repair, through UIA of the Settings app (no pointer or keyboard injection)' + $(if ($Method -eq 'settings-repair-same') { '; the feed serves the 0.1.0.0 .appinstaller (no newer version)' } elseif ($PathInstall) { '; old version installed with Add-AppxPackage -Path, no feed served' } else { '; the feed serves the 0.1.1.0 .appinstaller' })
            L ('recovery: ' + $rec.command)
            $rec.package_before_repair = Get-PkgText
            $rb = Open-AdvancedOptions $rec
            if (-not $rb) { $rec.result = 'Repair button not reachable'; $rec.repair_clicked = $false }
            else {
                $rec.repair_button_enabled = [bool]$rb.Current.IsEnabled
                $rec.repair_button_id = [string]$rb.Current.AutomationId
                $rec.repair_button_offscreen_before = [bool]$rb.Current.IsOffscreen
                $rec.dump_before_click = Dump-Settings 'before-repair'
                try { $rec.repair_invoke = (Invoke-Element $rb); $rec.repair_clicked = $true } catch { $rec.repair_clicked = $false; $rec.repair_error = $_.Exception.Message }
                L ('Repair clicked: ' + $rec.repair_clicked)
                $timeline = @(); $last = ''; $dl = (Get-Date).AddSeconds(120)
                while ((Get-Date) -lt $dl) {
                    $t = (Get-PkgText); if ($t -ne $last) { $timeline += ((Get-Date -Format 'HH:mm:ss') + ' ' + $t); $last = $t }
                    Start-Sleep -Seconds 3
                    if ($timeline.Count -gt 1 -and ((Get-Date) - $dl).TotalSeconds -lt -90 -and $t -match ':Ok$') { break }
                }
                $rec.package_timeline = $timeline
                $rec.dump_after_click = Dump-Settings 'after-repair'
                $rec.result = 'Repair clicked; package now ' + (Get-PkgText)
            }
            Stop-Settings
        }
        'platform-register' {
            $rec.command = 'no action of ours: hold ' + $HoldMinutes + ' min (if > 0), then a launch attempt (explorer shell:AppsFolder), then watch the AppX deployment log for the platform RegisterByPackageFullName operation'
            L ('recovery: ' + $rec.command)
            $rec.timeline = @()
            $regSeen = $false
            if ($HoldMinutes -gt 0) {
                $hd = (Get-Date).AddMinutes($HoldMinutes); $lastT = ''
                while ((Get-Date) -lt $hd -and -not $regSeen) {
                    $t = Get-PkgText; if ($t -ne $lastT) { $rec.timeline += ((Get-Date -Format 'HH:mm:ss') + ' hold: ' + $t); $lastT = $t }
                    if (@(Get-AppxEvents $evStart 200 | Where-Object { $_ -match 'RegisterByPackageFullName' }).Count -gt 0) { $regSeen = $true }
                    Beat; Start-Sleep -Seconds 5
                }
                $rec.hold_register_seen = $regSeen
                L ('hold ended; platform register seen during the hold: ' + $regSeen)
            }
            $rec.launch_attempt = Invoke-Launch 45 'platform-launch-attempt'
            $rec.package_after_launch_attempt = Get-PkgText
            $dl = (Get-Date).AddSeconds(150); $lastT = ''
            while ((Get-Date) -lt $dl) {
                $t = Get-PkgText; if ($t -ne $lastT) { $rec.timeline += ((Get-Date -Format 'HH:mm:ss') + ' after launch: ' + $t); $lastT = $t }
                if (@(Get-AppxEvents $evStart 200 | Where-Object { $_ -match 'RegisterByPackageFullName' }).Count -gt 0) { $regSeen = $true }
                if ($regSeen -and $t -match ':Ok$') { break }
                Beat; Start-Sleep -Seconds 3
            }
            $rec.platform_register_seen = $regSeen
            $rec.register_events = @(Get-AppxEvents $evStart 200 | Where-Object { $_ -match 'Register' } | Select-Object -First 25)
            Stop-App | Out-Null
            $rec.result = 'platform register seen=' + $regSeen + '; package now ' + (Get-PkgText)
        }
        'reset' {
            $rec.command = 'Get-AppxPackage ' + $PkgName + ' | Reset-AppxPackage'
            L ('recovery: ' + $rec.command)
            $rec.private_data_before = @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA ('Packages\' + $script:Pfn)) -Recurse -File -ErrorAction SilentlyContinue).Count
            $x = Invoke-Bounded ("Get-AppxPackage -Name '" + $PkgName + "' | Reset-AppxPackage") 240
            $rec.result = $x.result; $rec.timed_out = $x.timed_out
            $rec.private_data_after = @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA ('Packages\' + $script:Pfn)) -Recurse -File -ErrorAction SilentlyContinue).Count
        }
        'reinstall-same' {
            $rec.command = "Add-AppxPackage -Path '" + $OldMsix + "'  (the same 0.1.0.0 MSIX that is registered NeedsRemediation)"
            L ('recovery: ' + $rec.command)
            $rec.msix_sha256 = Get-Sha $OldMsix
            $x = Invoke-Bounded ("Add-AppxPackage -Path '" + $OldMsix + "'") 240
            $rec.result = $x.result; $rec.timed_out = $x.timed_out
        }
        'appinstaller-same' {
            Set-Feed 0   # the feed declares the installed 0.1.0.0: no newer version is available
            $rec.command = "Add-AppxPackage -AppInstallerFile '" + $FeedUrl + "'  (feed switched back to the 0.1.0.0 .appinstaller; no newer version)"
            L ('recovery: ' + $rec.command)
            $x = Invoke-Bounded ("Add-AppxPackage -AppInstallerFile '" + $FeedUrl + "'") 240
            $rec.result = $x.result; $rec.timed_out = $x.timed_out
        }
        default { $rec.result = 'unknown method ' + $Method }
    }
    $rec.seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    $rec.feed_requests_during = (Get-FeedRequestCount) - $feedBefore
    $rec.appx_events = Get-AppxEvents $evStart 30
    L ('recovery result: ' + $rec.result + ' package now ' + (Get-PkgText))
    Save-Result

    # ---- post state
    Start-Sleep -Seconds 5
    $R.post = Post-State $Method
    L ('post: package=' + $R.post.package + ' launched=' + $R.post.launch.launched + ' version=' + $R.post.launch.running_version + ' banner=' + $R.post.log_banner_for_pid + ' marker_in_file=' + $R.post.marker_in_file_after + ' marker_ui=' + $R.post.marker_row_shown_in_ui)
    Save-Shot 'post'
    L 'post screenshot done'
    $R.feed_log_tail = Get-FeedTail 30
    L 'feed tail read'
} catch {
    $R.errors += ($_.Exception.Message + ' @ ' + $_.InvocationInfo.ScriptLineNumber)
    L ('EXCEPTION: ' + $_.Exception.Message + ' @ line ' + $_.InvocationInfo.ScriptLineNumber)
}
finally {
    L 'finally: begin'
    $R.ended_utc = (Get-Date).ToUniversalTime().ToString('o')
    Save-Result
    L 'finally: result saved'
    try { Copy-Item -LiteralPath (Join-Path $env:TEMP 'serve-local-feed.log') -Destination (Join-Path $ReceiptsDir 'serve-local-feed.log') -Force } catch { }
    try { if (Test-Path -LiteralPath $LogPath) { Copy-Item -LiteralPath $LogPath -Destination (Join-Path $ReceiptsDir 'slice-app.log') -Force } } catch { }
    try { if (Test-Path -LiteralPath $RowsPath) { Copy-Item -LiteralPath $RowsPath -Destination (Join-Path $ReceiptsDir 'rows.json') -Force } } catch { }
    L 'finally: logs copied'
    Set-Content -LiteralPath (Join-Path $ReceiptsDir 'DONE') -Value 'done'
    L 'finally: DONE written, stopping computer'
    Start-Sleep -Seconds 8
    Stop-Computer -Force
}
