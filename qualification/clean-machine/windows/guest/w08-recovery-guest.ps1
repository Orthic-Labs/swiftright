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
#   tier1-launch        W08 Tier 1: NO action of ours. Launch ONLY via explorer shell:AppsFolder and let App Installer (OnLaunch, ShowPrompt + UpdateBlocksActivation) finish or repair the update; feed serves 0.1.1.0.
#                       Any App Installer prompt is answered through UIA (its Update button) and recorded. Pass = within 60 s package Ok at 0.1.1.0, window appears, rows.json unchanged.
#   tier1-launch-old    as tier1-launch, with the feed switched back to the 0.1.0.0 .appinstaller (no newer version published)
#   tier2-repair        W08 Tier 2: the app registered the out-of-package repair guard (scheduled task <PFN>-Repair) on its first launch. After NeedsRemediation is induced we do
#                       NOTHING for up to 120 s (the guard acts on event 751), then launch via explorer shell:AppsFolder. Pass = package Ok, window appears, rows.json unchanged.
#   tier2-feed-down     as tier2-repair, with the feed server stopped at the cancel: the guard must fail EXPLICITLY (repair.log names the unreachable feed, task result 1) and leave
#                       the package untouched; the feed is then restored and the task started by hand to show the retry path recovers it.
#   tier2-uninstall     no induction: install, launch once (guard registered), Remove-AppxPackage, start the task (stand-in for the next logon trigger); the task and its folder must be gone.
#                       The tier2-* methods below all run the induction first and apply their condition AT the cancel (the guard acts within ~1 s of event 751). The repair is NEVER started by hand
#                       except where a method says so (tier2-uninstall stands in for a logon).
#   tier2-feed-down     (redefined) feed down at the cancel, feed back after 60 s; the guard's own retry (+2 min) must recover the package with NO manual task start
#   tier2-stale         feed switched back to the 0.1.0.0 .appinstaller at the cancel (no newer version published): recovery to 0.1.0.0 or an explicit refusal
#   tier2-wrongid       feed and msix files replaced by a package of a DIFFERENT identity at the cancel: the guard must refuse and install nothing; the feed is restored after 60 s and the retry recovers
#   tier2-corrupt       msix files replaced by truncated copies at the cancel: explicit failure, package untouched, retry; the feed is restored after 60 s and the retry recovers
#   tier2-mutex         a second run of the guard script is started while the task's run is in its settle window: it must log that another run is active and exit
#   tier2-killclient    AddPackageAsync runs in a child process that is killed at staging+delay instead of Cancel (does the deployment survive its client being killed?)
#   tier2-sched-blocked no induction (#47): task creation is denied BEFORE the first launch by an ACE on the Task Scheduler root folder's security descriptor
#                       (deny FW, the right Authenticated Users are granted, to Interactive users; the GPO `Prohibit New Task Creation` only governs the UI, measured 22 Oct: it does not stop
#                       Register-ScheduledTask), proved by a failing Register-ScheduledTask of our own; the app must still
#                       launch and work, the guard task must not exist, and the state is recorded (no crash, no half-written guard directory)
#   tier2-healthy       no induction: the guard must do nothing to a healthy package (same package full name, last-result healthy, no Add-AppxPackage logged)
#   tier2-task-deleted  no induction: the task is deleted; the next app launch must register it again; then with a fresh install-attempt marker the next launch must NOT (24 h backoff)
#   tier2-uninstall-retry  feed down so the first run fails and a retry is pending, then Remove-AppxPackage: the retry tick (no manual start) must clean up the task and folder
#   reset / platform-register   baselines: the guard task is removed before the induction's recovery step so the method is tested alone
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
$IsT2 = ($Method -like 'tier2-*')
$NoGuard = (-not $IsT2 -and $Method -ne 'settings-probe')   # baselines of the pre-guard recoveries run with the guard task removed
$Variant = ''
if ($Method -in 'tier2-feed-down', 'tier2-stale', 'tier2-wrongid', 'tier2-corrupt') { $Variant = $Method.Substring(6) }
if ($Method -in 'tier2-uninstall-retry', 'tier2-feed-down-long') { $Variant = 'feed-down' }
$BadThenRestore = ($Variant -in 'feed-down', 'wrongid', 'corrupt') -and $Method -ne 'tier2-feed-down-long'   # tier2-feed-down-long: the feed stays down (the worker keeps the state; see job-w08.ps1 keepState)
$PathInstall = ($Method -like '*-path')   # old version installed with Add-AppxPackage -Path (no App Installer association) and no feed served: the W08 offline scenario
$PkgName = 'OrthicLabs.SliceApp'
$OldVersion = '0.1.0.0'
$NewVersion = '0.1.1.0'
$LocalAppData = Join-Path $env:LOCALAPPDATA 'SliceApp'
$RowsPath = Join-Path $LocalAppData 'rows.json'
$LogPath = Join-Path $LocalAppData 'slice-app.log'
$Feed = 'C:\feed'
$FeedUrl = 'https://localhost:8443/sliceapp/SliceApp.appinstaller'
$ExtraDir = Join-Path $PackagesDir 'extra'
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
    # a killed feed server (tier2-feed-down stops it at the cancel) leaves its http.sys certificate bindings behind; serve-local-feed.ps1 would throw on `netsh http add sslcert`
    foreach ($ip in '127.0.0.1:8443', '[::1]:8443') { & netsh.exe http delete sslcert ipport=$ip 2>&1 | Out-Null }
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

# ---- W08 Tier 2 guard evidence
function Get-GuardDir { return (Join-Path $env:LOCALAPPDATA 'SliceApp\repair') }
function Get-GuardState {
    $o = [ordered]@{ task_name = ($script:Pfn + '-Repair') }
    $t = $null
    try { $t = Get-ScheduledTask -TaskName ($script:Pfn + '-Repair') -ErrorAction Stop } catch { }
    $o.task_exists = [bool]$t
    if ($t) {
        $o.task_state = [string]$t.State
        try { $i = Get-ScheduledTaskInfo -TaskName ($script:Pfn + '-Repair'); $o.last_run = [string]$i.LastRunTime; $o.last_result = [int]$i.LastTaskResult } catch { }
        $o.triggers = @($t.Triggers | ForEach-Object { $_.CimClass.CimClassName + $(if ($_.Subscription) { ' ' + (([string]$_.Subscription) -replace '\s+', ' ') } else { '' }) })
        $o.action = [string]$t.Actions[0].Execute + ' ' + [string]$t.Actions[0].Arguments
        $o.run_as = [string]$t.Principal.UserId + ' ' + [string]$t.Principal.LogonType + ' ' + [string]$t.Principal.RunLevel
    }
    $d = Get-GuardDir
    $o.dir_exists = (Test-Path -LiteralPath $d)
    if ($o.dir_exists) {
        $o.files = @(Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name + ' ' + $_.Length })
        try { $o.guard_json = (Get-Content -LiteralPath (Join-Path $d 'guard.json') -Raw -ErrorAction Stop) -replace '\s+', ' ' } catch { $o.guard_json = 'unreadable' }
        try { $o.repair_log = @(Get-Content -LiteralPath (Join-Path $d 'repair.log') -ErrorAction Stop | ForEach-Object { [string]$_ }) } catch { $o.repair_log = @() }
        foreach ($f in 'last-result.json', 'retry.json', 'install-result.json', 'install-attempt.json') { try { $o[$f] = (Get-Content -LiteralPath (Join-Path $d $f) -Raw -ErrorAction Stop) -replace '\s+', ' ' } catch { $o[$f] = $null } }
    }
    return $o
}
function Wait-Guard([int]$Sec) {
    $dl = (Get-Date).AddSeconds($Sec)
    while ((Get-Date) -lt $dl) {
        $t = $null; try { $t = Get-ScheduledTask -TaskName ($script:Pfn + '-Repair') -ErrorAction Stop } catch { }
        if ($t -and (Test-Path -LiteralPath (Join-Path (Get-GuardDir) 'guard.json'))) { return $true }
        Beat; Start-Sleep -Milliseconds 500
    }
    return $false
}
function Get-GuardLogText { try { $fs = [IO.File]::Open((Join-Path (Get-GuardDir) 'repair.log'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite); try { return (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() } } catch { return '' } }
function Remove-GuardTask { foreach ($t in @(Get-ScheduledTask -TaskName ($script:Pfn + '-Repair') -ErrorAction SilentlyContinue)) { try { Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false -ErrorAction Stop } catch { L ('  guard task removal failed: ' + $_.Exception.Message) } } }
function Test-OtherAppInstalled { return (@(Get-AppxPackage -Name 'OrthicLabs.OtherApp' -ErrorAction SilentlyContinue).Count -gt 0) }
function Apply-Variant {
    # applied AT the cancel: the guard acts within ~1 s of event 751 and reads the feed after an 8 s settle
    switch ($Variant) {
        'feed-down' { if ($script:FeedProc) { try { Stop-Process -Id $script:FeedProc.Id -Force -ErrorAction Stop; return 'feed server stopped' } catch { return 'feed stop error: ' + $_.Exception.Message } } }
        'stale' { Set-Feed 0; return 'feed switched to the 0.1.0.0 .appinstaller' }
        'wrongid' {
            Copy-Item -LiteralPath (Join-Path $ExtraDir 'wrongid.msix') -Destination (Join-Path $Feed 'SliceApp_0.1.0.0_x64.msix') -Force
            Copy-Item -LiteralPath (Join-Path $ExtraDir 'wrongid.msix') -Destination (Join-Path $Feed 'SliceApp_0.1.1.0_x64.msix') -Force
            Copy-Item -LiteralPath (Join-Path $ExtraDir 'SliceApp.wrongid.appinstaller') -Destination (Join-Path $Feed 'SliceApp.appinstaller') -Force
            return 'feed declares OrthicLabs.OtherApp and both msix files are that package'
        }
        'corrupt' {
            Copy-Item -LiteralPath (Join-Path $ExtraDir 'corrupt-old.msix') -Destination (Join-Path $Feed 'SliceApp_0.1.0.0_x64.msix') -Force
            Copy-Item -LiteralPath (Join-Path $ExtraDir 'corrupt-new.msix') -Destination (Join-Path $Feed 'SliceApp_0.1.1.0_x64.msix') -Force
            return 'both msix files replaced by truncated copies'
        }
    }
    return ''
}
function Restore-Feed {
    if ($Variant -eq 'feed-down') { [void](Start-Feed); Set-Feed 1; return 'feed server restarted' }
    Get-ChildItem -LiteralPath (Join-Path $PackagesDir 'feed') -Filter '*.msix' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $Feed -Force }
    Set-Feed 1
    return 'feed files restored'
}
function Test-FeedUp { try { return ((Invoke-WebRequest -Uri $FeedUrl -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200) } catch { return $false } }

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
    if ($Variant -eq 'feed-down' -and -not (Test-FeedUp)) { [void](Start-Feed); $att.feed_restarted_for_attempt = $true }
    if ($Variant -in 'wrongid', 'corrupt' -and $script:MarkerSha) { [void](Restore-Feed) }   # a later attempt starts from the good feed
    $errArr = @(Install-OldViaFeed)
    $err = [string]$errArr[-1]
    $att.install_old_s = [math]::Round($tAll.Elapsed.TotalSeconds, 1)
    if (-not $err) { $att.appinstaller_assoc_after_install = Get-AppInstallerAssoc }
    if ($err) { $att.outcome = 'setup-failed'; $att.error = $err; return $att }
    # first attempt: write the data marker through the UI (rows.json is outside the package and survives remove/reinstall)
    if (-not $script:MarkerSha) {
        $w = Invoke-Launch 60 'marker-write'
        if (-not $w.launched) { $att.outcome = 'setup-failed'; $att.error = 'old build did not launch for the marker write'; $att.launch_detail = $w; try { $att.slice_log = @(Get-Content -LiteralPath $LogPath -ErrorAction Stop | Select-Object -Last 20 | ForEach-Object { [string]$_ }) } catch { $att.slice_log = @('no slice-app.log') }; $att.events_tail = @(Get-AppxEvents (Get-Date).AddMinutes(-2) 12); $att.pkg_now = Get-PkgDetail; return $att }
        $root = Find-AppWindow
        Write-MarkerRow -Root $root -Text $Marker
        $deadline = (Get-Date).AddSeconds(20); while ((Get-Date) -lt $deadline -and -not (Test-MarkerInFile)) { Start-Sleep -Milliseconds 500 }
        Stop-App | Out-Null
        if (-not (Test-MarkerInFile)) { $att.outcome = 'setup-failed'; $att.error = 'marker never reached rows.json'; return $att }
        $script:MarkerSha = Get-Sha $RowsPath
        $R.marker_sha_written = $script:MarkerSha
        L ('marker written, rows.json sha ' + $script:MarkerSha)
        if ($IsT2) {
            $gOk = Wait-Guard 90
            $R.guard_after_first_launch = Get-GuardState
            L ('guard registered by the first launch: ' + $gOk)
            if (-not $gOk) { $att.outcome = 'setup-failed'; $att.error = 'the first launch did not register the repair guard'; return $att }
        } elseif ($NoGuard) {
            $gOk = Wait-Guard 90
            Remove-GuardTask
            $R.guard_removed_for_baseline = [ordered]@{ guard_was_registered = $gOk; task_exists_now = [bool](Get-ScheduledTask -TaskName ($script:Pfn + '-Repair') -ErrorAction SilentlyContinue) }
            L ('baseline: guard task removed (it had been registered: ' + $gOk + ')')
        }
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
    $kill = ($Method -eq 'tier2-killclient'); $child = $null; $op = $null
    if ($kill) {
        $childCmd = "`$ErrorActionPreference='Stop'; [void][Windows.Management.Deployment.PackageManager, Windows.Management.Deployment, ContentType = WindowsRuntime]; `$pm = New-Object Windows.Management.Deployment.PackageManager; `$op = `$pm.AddPackageAsync((New-Object Uri('" + $uri.AbsoluteUri + "')), [Collections.Generic.IEnumerable[Uri]]`$null, [Windows.Management.Deployment.DeploymentOptions]::None); `$i = [Windows.Foundation.IAsyncInfo, Windows.Foundation, ContentType = WindowsRuntime]; while ([int]`$i.GetProperty('Status').GetValue(`$op) -eq 0) { Start-Sleep -Milliseconds 50 }"
        $child = Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCmd)))
        $att.child_pid = $child.Id
    } else { $op = $pm.AddPackageAsync($uri, [Collections.Generic.IEnumerable[Uri]]$null, [Windows.Management.Deployment.DeploymentOptions]::None) }
    $seen = $false; $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        if (Test-NewStaging) { $seen = $true; break }
        if ($kill) { if ($child.HasExited) { break } } elseif ([int]$asyncInfo.GetProperty('Status').GetValue($op) -ne 0) { break }
        Start-Sleep -Milliseconds 5
    }
    $att.trigger_seen = $seen
    $att.t_trigger_ms = [int]$watch.ElapsedMilliseconds
    if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
    if ($kill) {
        $stNow = $(if ($child.HasExited) { 9 } else { 0 })
        $att.op_status_at_cancel = $(if ($stNow -eq 0) { 'client running' } else { 'client already exited' })
        $att.t_cancel_ms = [int]$watch.ElapsedMilliseconds
        if ($stNow -eq 0) { try { Stop-Process -Id $child.Id -Force -ErrorAction Stop; $att.client_killed = $true } catch { $att.client_kill_error = $_.Exception.Message } }
    } else {
        $stNow = [int]$asyncInfo.GetProperty('Status').GetValue($op)
        $att.op_status_at_cancel = [string]$stNow   # 0 Started, 1 Completed, 2 Canceled, 3 Error
        $att.t_cancel_ms = [int]$watch.ElapsedMilliseconds
        if ($stNow -eq 0) { [void]$asyncInfo.GetMethod('Cancel').Invoke($op, $null) }
    }
    $att.cancel_utc = (Get-Date).ToUniversalTime().ToString('o'); $script:InducedAt = Get-Date
    if ($Variant) { $att.variant_at_cancel = Apply-Variant }
    if ($kill) { $att.op_status_after = 'n/a (client killed)'; $att.op_error_code = '' }
    else {
        $d2 = (Get-Date).AddSeconds(60)
        while ([int]$asyncInfo.GetProperty('Status').GetValue($op) -eq 0 -and (Get-Date) -lt $d2) { Start-Sleep -Milliseconds 50 }
        $att.op_status_after = [string][int]$asyncInfo.GetProperty('Status').GetValue($op)
        $att.op_error_code = [string]$asyncInfo.GetProperty('ErrorCode').GetValue($op)
    }
    # settle: stable for 6 s, max 40 s
    $last = ''; $stableSince = Get-Date; $sw2 = [Diagnostics.Stopwatch]::StartNew(); $timeline = @(); $sawNR = $false
    while ($sw2.Elapsed.TotalSeconds -lt 40) {
        $txt = (Get-PkgText) + ' | staging_new=' + (Test-NewStaging)
        if ($txt -match 'NeedsRemediation') { $sawNR = $true }
        if ($txt -ne $last) { $timeline += ('+' + [int]$watch.ElapsedMilliseconds + 'ms ' + $txt); $last = $txt; $stableSince = Get-Date }
        elseif (((Get-Date) - $stableSince).TotalSeconds -ge 6 -and $Method -ne 'tier2-mutex') { break }
        if ($Method -eq 'tier2-mutex' -and -not $att.second_run_started -and (Get-GuardLogText) -match 'NOT healthy') {
            # the task's run is in its 8 s settle window: start a second run of the very same script directly
            $att.second_run_started = $true; $att.second_run_utc = (Get-Date).ToUniversalTime().ToString('o')
            $p2 = Start-Process -FilePath 'powershell.exe' -PassThru -Wait -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path (Get-GuardDir) 'repair-guard.ps1'))
            $att.second_run_exit = [int]$p2.ExitCode
            $att.second_run_log_busy = ((Get-GuardLogText) -match 'another repair run is active')
        }
        if ($Method -eq 'tier2-mutex' -and $sw2.Elapsed.TotalSeconds -ge 25) { break }
        Start-Sleep -Milliseconds $(if ($Method -eq 'tier2-mutex') { 250 } else { 1000 })
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
    $ev751 = @($att.events | Where-Object { $_ -match ' id=751 ' }).Count -gt 0
    $att.saw_needs_remediation = $sawNR; $att.event_751 = $ev751
    $att.outcome = $(if ((Test-NeedsRemediation) -or ($IsT2 -and ($sawNR -or $ev751))) { 'NEEDS-REMEDIATION' }
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
    if ($Method -eq 'tier2-uninstall') {
        $u = $R.recovery
        $pe = @(Install-OldViaFeed); $pe = [string]$pe[-1]
        if ($pe) { throw $pe }
        try { $script:AppId = [string](Get-AppxPackageManifest -Package (Get-Pkgs)[0].PackageFullName).Package.Applications.Application.Id } catch { }
        $l = Invoke-Launch 60 'uninstall-first-launch'
        $u.first_launch = $l
        $u.guard_registered = Wait-Guard 90
        $u.guard_before = Get-GuardState
        L ('guard registered: ' + $u.guard_registered)
        Stop-App | Out-Null
        $u.rows_exists_before = (Test-Path -LiteralPath $RowsPath)
        $u.parent_dir_before = [bool](Test-Path -LiteralPath $LocalAppData)
        foreach ($p in @(Get-Pkgs)) { try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop } catch { $u.remove_error = $_.Exception.Message } }
        $u.package_after_remove = Get-PkgText
        $u.task_exists_right_after_remove = [bool](Get-ScheduledTask -TaskName ($script:Pfn + '-Repair') -ErrorAction SilentlyContinue)
        $swU = [Diagnostics.Stopwatch]::StartNew()
        Start-ScheduledTask -TaskName ($script:Pfn + '-Repair')   # stands in for the next logon trigger
        $gone = $false
        while ($swU.Elapsed.TotalSeconds -lt 90) { if (-not (Get-ScheduledTask -TaskName ($script:Pfn + '-Repair') -ErrorAction SilentlyContinue)) { $gone = $true; break }; Beat; Start-Sleep -Milliseconds 500 }
        $u.task_removed = $gone; $u.seconds_to_task_removed = [math]::Round($swU.Elapsed.TotalSeconds, 1)
        Start-Sleep -Seconds 2
        $u.guard_after = Get-GuardState
        $u.repair_dir_removed = -not (Test-Path -LiteralPath (Get-GuardDir))
        $u.parent_dir_kept = [bool](Test-Path -LiteralPath $LocalAppData)
        $u.rows_kept = (Test-Path -LiteralPath $RowsPath)
        try { $u.cleanup_note = @(Get-Content -LiteralPath (Join-Path $env:TEMP ($script:Pfn + '-repair-cleanup.log')) -ErrorAction Stop | ForEach-Object { [string]$_ }) } catch { $u.cleanup_note = @('none') }
        $u.pass = [bool]($u.guard_registered -and $u.task_removed -and $u.repair_dir_removed -and $u.parent_dir_kept -and $u.rows_kept)
        $u.result = 'task removed=' + $gone + ' repair dir removed=' + $u.repair_dir_removed + ' user data kept=' + $u.rows_kept
        L ('uninstall: ' + $u.result)
        Save-Result
        return
    }
    if ($Method -eq 'tier2-sched-blocked') {
        $b = $R.recovery
        $sched = New-Object -ComObject Schedule.Service; $sched.Connect(); $root = $sched.GetFolder('\')
        $b.root_sd_before = $root.GetSecurityDescriptor(4)   # DACL only
        try { [IO.File]::WriteAllText('C:\sbq\state\taskroot-dacl.txt', $b.root_sd_before) } catch { }
        try { $root.SetSecurityDescriptor(($b.root_sd_before -replace '^D:([A-Z]*)', 'D:$1(D;CI;FW;;;IU)'), 0); $b.policy_set = $true } catch { $b.policy_set = $false; $b.policy_error = $_.Exception.Message }
        $b.root_sd_blocked = $root.GetSecurityDescriptor(4)
        Start-Sleep -Seconds 2
        try {
            $act = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c exit'
            Register-ScheduledTask -TaskName 'W08-block-probe' -Action $act -ErrorAction Stop | Out-Null
            $b.block_effective = $false
            Unregister-ScheduledTask -TaskName 'W08-block-probe' -Confirm:$false -ErrorAction SilentlyContinue
        } catch { $b.block_effective = $true; $b.block_probe_error = $_.Exception.Message }
        L ('policy set: ' + $b.policy_set + '; block effective: ' + $b.block_effective)
        $pe = @(Install-OldViaFeed); $pe = [string]$pe[-1]
        if ($pe) { throw $pe }
        try { $script:AppId = [string](Get-AppxPackageManifest -Package (Get-Pkgs)[0].PackageFullName).Package.Applications.Application.Id } catch { }
        $b.first_launch = Invoke-Launch 60 'first-launch-sched-blocked'
        $b.guard_registered = Wait-Guard 60
        $b.guard_state = Get-GuardState
        $b.guard_dir_exists = [bool](Test-Path -LiteralPath (Get-GuardDir))
        try { $b.guard_dir_files = @(Get-ChildItem -LiteralPath (Get-GuardDir) -ErrorAction Stop | ForEach-Object { $_.Name }) } catch { $b.guard_dir_files = @() }
        $b.package = Get-PkgText
        $b.relaunch = Invoke-Launch 60 'relaunch-sched-blocked'
        Stop-App | Out-Null
        $b.rows_exists = (Test-Path -LiteralPath $RowsPath)
        try { $root.SetSecurityDescriptor($b.root_sd_before, 0); $b.policy_removed = ($root.GetSecurityDescriptor(4) -eq $b.root_sd_before) } catch { $b.policy_removed = $false; $b.restore_error = $_.Exception.Message }
        try { $b.guard_log = Get-GuardLogText } catch { }
        $b.pass = [bool]($b.block_effective -and $b.first_launch.launched -and $b.relaunch.launched -and -not $b.guard_registered)
        $b.result = 'block effective=' + $b.block_effective + ' app launched=' + $b.first_launch.launched + '/' + $b.relaunch.launched + ' guard registered=' + $b.guard_registered + ' guard dir files=' + (($b.guard_dir_files) -join ',')
        L ('result: ' + $b.result)
        Save-Result
        return
    }
    if ($Method -in 'tier2-healthy', 'tier2-task-deleted') {
        $h = $R.recovery
        $pe = @(Install-OldViaFeed); $pe = [string]$pe[-1]
        if ($pe) { throw $pe }
        try { $script:AppId = [string](Get-AppxPackageManifest -Package (Get-Pkgs)[0].PackageFullName).Package.Applications.Application.Id } catch { }
        $h.first_launch = Invoke-Launch 60 'first-launch'
        $h.guard_registered = Wait-Guard 90
        Stop-App | Out-Null
        L ('guard registered: ' + $h.guard_registered)
        $taskName = $script:Pfn + '-Repair'
        if ($Method -eq 'tier2-healthy') {
            $h.package_before = Get-PkgDetail
            $logLenBefore = (Get-GuardLogText).Length
            $t0 = Get-Date
            Start-ScheduledTask -TaskName $taskName
            $res = $null; $sw = [Diagnostics.Stopwatch]::StartNew()
            while ($sw.Elapsed.TotalSeconds -lt 90) {
                try { $res = Get-Content -LiteralPath (Join-Path (Get-GuardDir) 'last-result.json') -Raw -ErrorAction Stop | ConvertFrom-Json; if ($res -and ([datetime]$res.timeUtc).ToUniversalTime() -gt $t0.ToUniversalTime().AddSeconds(-1) -and [string]$res.mode -eq 'repair') { break } } catch { }
                $res = $null; Beat; Start-Sleep -Milliseconds 500
            }
            $h.last_result = $res
            $h.package_after = Get-PkgDetail
            $h.guard_log_new = (Get-GuardLogText).Substring([math]::Min($logLenBefore, (Get-GuardLogText).Length))
            $h.package_unchanged = ((($h.package_before | ForEach-Object { $_.full_name + $_.status }) -join ',') -eq (($h.package_after | ForEach-Object { $_.full_name + $_.status }) -join ','))
            $h.add_appx_logged = ($h.guard_log_new -match 'Add-AppxPackage')
            $h.pass = [bool]($res -and [string]$res.status -eq 'healthy' -and [int]$res.code -eq 0 -and $h.package_unchanged -and -not $h.add_appx_logged)
            $h.result = 'status=' + $(if ($res) { $res.status } else { 'none' }) + ' package unchanged=' + $h.package_unchanged + ' Add-AppxPackage logged=' + $h.add_appx_logged
        } else {
            $g = $h
            $g.guard_before = Get-GuardState
            Remove-GuardTask
            $g.task_deleted = -not [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $g.relaunch = Invoke-Launch 60 'relaunch-after-task-deleted'
            while ($sw.Elapsed.TotalSeconds -lt 90 -and -not (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) { Beat; Start-Sleep -Milliseconds 500 }
            $g.task_reregistered = [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
            $g.seconds_to_reregister = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            Stop-App | Out-Null
            # backoff: the installer failed less than 24 h ago (marker on disk): a launch must not spawn it again
            Start-Sleep -Seconds 5
            Remove-GuardTask
            $scriptBytes = [IO.File]::ReadAllBytes((Join-Path (Get-GuardDir) 'repair-guard.ps1')); if ($scriptBytes.Length -eq 0 -or $scriptBytes[-1] -ne 10) { $scriptBytes = $scriptBytes + [byte[]](10) }   # the app now writes the final LF; older builds did not
            $sha = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($scriptBytes)) -replace '-', '').ToLower()
            [IO.File]::WriteAllText((Join-Path (Get-GuardDir) 'install-attempt.json'), ('{"epoch":' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + ',"sha256":"' + $sha + '"}'), $Utf8)
            $g.marker_sha256 = $sha
            $g.relaunch_with_marker = Invoke-Launch 60 'relaunch-with-backoff-marker'
            Start-Sleep -Seconds 25
            $g.task_registered_with_marker = [bool](Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)
            $g.install_skipped_logged = ((Get-GuardLogText) -match 'install skipped')
            Stop-App | Out-Null
            $g.guard_after = Get-GuardState
            $g.pass = [bool]($g.task_deleted -and $g.task_reregistered -and -not $g.task_registered_with_marker -and $g.install_skipped_logged)
            $g.result = 'task deleted=' + $g.task_deleted + ' re-registered by the next launch=' + $g.task_reregistered + ' (' + $g.seconds_to_reregister + ' s); with a fresh attempt marker re-registered=' + $g.task_registered_with_marker + ' skip logged=' + $g.install_skipped_logged
        }
        L ('result: ' + $R.recovery.result)
        Save-Result
        return
    }
    $delays = @(240, 200, 280, 240, 220, 260, 230, 250, 210, 270, 245, 235, 225, 255, 215, 265, 205, 275)
    $delayFile = Join-Path $HarnessDir 'delays.txt'   # optional: fixed cancel offset(s), one integer ms per line
    if (Test-Path -LiteralPath $delayFile) { $delays = @((Get-Content -LiteralPath $delayFile) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | ForEach-Object { [int]$_ }); L ('cancel offsets from delays.txt: ' + ($delays -join ',')) }
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
        { $_ -in 'tier2-repair', 'tier2-feed-down', 'tier2-stale', 'tier2-wrongid', 'tier2-corrupt', 'tier2-mutex', 'tier2-killclient', 'tier2-feed-down-long' } {
            $rec.command = 'NO action of ours on the guard (never started by hand): wait for the repair guard task (' + $script:Pfn + '-Repair, event 751 / logon / its own retry), then launch via explorer shell:AppsFolder' + $(if ($Variant) { '; condition applied at the cancel: ' + $Variant } else { '' })
            L ('recovery: ' + $rec.command)
            $rec.manual_task_start = $false
            $rec.timeline = @(); $lastT = ''; $okAt = $null; $restored = $false; $okBeforeRestore = $false
            $limit = $(if ($BadThenRestore) { 480 } else { 120 })
            $t0 = $(if ($script:InducedAt) { $script:InducedAt } else { Get-Date })
            while (((Get-Date) - $t0).TotalSeconds -lt $limit) {
                $el = ((Get-Date) - $t0).TotalSeconds
                $t = Get-PkgText; if ($t -ne $lastT) { $rec.timeline += ('+' + [math]::Round($el, 1) + 's ' + $t); $lastT = $t }
                if ($t -match '^0\.1\.[01]\.0:Ok$') { $okAt = [math]::Round($el, 1); if ($BadThenRestore -and -not $restored) { $okBeforeRestore = $true }; break }
                if ($BadThenRestore -and -not $restored -and $el -ge 60) {
                    $rec.snapshot_before_restore = [ordered]@{ at_s = [math]::Round($el, 1); package = Get-PkgText; guard = Get-GuardState; other_app_installed = Test-OtherAppInstalled; rows_sha_equals_written = ((Get-Sha $RowsPath) -eq $script:MarkerSha) }
                    $rec.restore = Restore-Feed; $rec.restored_at_s = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1); $restored = $true
                    L ('feed restored at +' + $rec.restored_at_s + ' s (' + $rec.restore + '); package ' + (Get-PkgText))
                }
                Beat; Start-Sleep -Milliseconds 500
            }
            $rec.seconds_to_package_ok_from_cancel = $okAt
            $rec.guard_after = Get-GuardState
            $rec.other_app_installed_at_end = Test-OtherAppInstalled
            $rl = (@($rec.guard_after.repair_log) -join "`n")
            if ($BadThenRestore) {
                $snapLog = (@($rec.snapshot_before_restore.guard.repair_log) -join "`n")
                $rec.package_while_bad = $rec.snapshot_before_restore.package
                $rec.ok_before_restore = $okBeforeRestore
                $expectLog = switch ($Variant) { 'feed-down' { 'feed unreachable' } 'wrongid' { 'REFUSED' } 'corrupt' { 'corrupt|-AppInstallerFile failed' } }
                $rec.failed_explicitly = [bool](($snapLog -match $expectLog) -and ($snapLog -match 'FAILED') -and (-not $okBeforeRestore))
                $rec.retry_scheduled_logged = [bool]($snapLog -match 'retry 1 scheduled')
                $rec.recovered_by_retry = [bool]($okAt -and $restored)
                $rec.seconds_ok_after_restore = $(if ($okAt -and $restored) { [math]::Round($okAt - $rec.restored_at_s, 1) } else { $null })
                $rec.task_last_result = $rec.guard_after.last_result
                L ('bad-then-restore: package while bad ' + $rec.package_while_bad + '; explicit failure logged ' + $rec.failed_explicitly + '; recovered by the guard retry ' + $rec.recovered_by_retry + ' (' + $rec.seconds_ok_after_restore + ' s after the restore)')
            }
            if ($Method -eq 'tier2-mutex') { $rec.mutex_second_run_busy = [bool]($R.attempts[-1].second_run_log_busy); $rec.mutex_second_run_exit = $R.attempts[-1].second_run_exit }
            $rec.result = 'package ' + (Get-PkgText) + '; seconds to Ok from cancel ' + $okAt
        }
        'tier2-uninstall-retry' {
            $rec.command = 'feed down at the cancel -> first run fails and schedules a retry; then Remove-AppxPackage; the retry tick (NO manual start) must remove the task and the folder'
            L ('recovery: ' + $rec.command)
            $rec.manual_task_start = $false
            $sw = [Diagnostics.Stopwatch]::StartNew(); $rt = $null
            while ($sw.Elapsed.TotalSeconds -lt 120) { if (Test-Path -LiteralPath (Join-Path (Get-GuardDir) 'retry.json')) { break }; Beat; Start-Sleep -Milliseconds 500 }
            $rec.retry_json_seen_s = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            $rec.guard_before_remove = Get-GuardState
            foreach ($p in @(Get-Pkgs)) { try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop } catch { $rec.remove_error = $_.Exception.Message } }
            $rec.package_after_remove = Get-PkgText
            $rec.task_exists_right_after_remove = [bool](Get-ScheduledTask -TaskName ($script:Pfn + '-Repair') -ErrorAction SilentlyContinue)
            $swU = [Diagnostics.Stopwatch]::StartNew(); $gone = $false
            while ($swU.Elapsed.TotalSeconds -lt 420) { if (-not (Get-ScheduledTask -TaskName ($script:Pfn + '-Repair') -ErrorAction SilentlyContinue)) { $gone = $true; break }; Beat; Start-Sleep -Milliseconds 500 }
            $rec.task_removed = $gone; $rec.seconds_to_task_removed = [math]::Round($swU.Elapsed.TotalSeconds, 1)
            Start-Sleep -Seconds 2
            $rec.repair_dir_removed = -not (Test-Path -LiteralPath (Get-GuardDir))
            $rec.parent_dir_kept = [bool](Test-Path -LiteralPath $LocalAppData); $rec.rows_kept = (Test-Path -LiteralPath $RowsPath)
            try { $rec.cleanup_note = @(Get-Content -LiteralPath (Join-Path $env:TEMP ($script:Pfn + '-repair-cleanup.log')) -ErrorAction Stop | ForEach-Object { [string]$_ }) } catch { $rec.cleanup_note = @('none') }
            $rec.pass = [bool]($gone -and $rec.repair_dir_removed -and $rec.parent_dir_kept -and $rec.rows_kept)
            $rec.result = 'task removed by the retry tick=' + $gone + ' (' + $rec.seconds_to_task_removed + ' s after the remove) repair dir removed=' + $rec.repair_dir_removed + ' user data kept=' + $rec.rows_kept
        }
        { $_ -in 'tier1-launch', 'tier1-launch-old' } {
            if ($Method -eq 'tier1-launch-old') { Set-Feed 0; $rec.feed_switched_back_to_0_1_0_0 = $true }
            $rec.command = 'launch ONLY via explorer shell:AppsFolder\' + $script:Pfn + '!' + $script:AppId + '; no Add-AppxPackage, no Repair, no Reset; feed serves ' + $(if ($Method -eq 'tier1-launch-old') { '0.1.0.0 only' } else { '0.1.1.0' })
            L ('recovery: ' + $rec.command)
            $rec.timeline = @(); $rec.prompt_actions = @(); $rec.launch = [ordered]@{ launched = $false }
            $t0 = Get-Date; $swL = [Diagnostics.Stopwatch]::StartNew(); $lastT = ''; $okAt = $null; $winAt = $null; $clicked = @{}
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('shell:AppsFolder\' + $script:Pfn + '!' + $script:AppId) | Out-Null
            $limit = 150
            while ($swL.Elapsed.TotalSeconds -lt $limit) {
                $t = Get-PkgText; if ($t -ne $lastT) { $rec.timeline += ('+' + [math]::Round($swL.Elapsed.TotalSeconds, 1) + 's ' + $t); $lastT = $t }
                if (-not $okAt -and $t -match '^0\.1\.1\.0:Ok$' -and $Method -eq 'tier1-launch') { $okAt = [math]::Round($swL.Elapsed.TotalSeconds, 1) }
                if (-not $okAt -and $t -match '^0\.1\.0\.0:Ok$' -and $Method -eq 'tier1-launch-old') { $okAt = [math]::Round($swL.Elapsed.TotalSeconds, 1) }
                $procs = @(Get-AppProcs | Where-Object { $_.MainWindowHandle -ne 0 })
                if ($procs.Count -gt 0 -and (Find-AppWindow)) { if (-not $winAt) { $winAt = [math]::Round($swL.Elapsed.TotalSeconds, 1) }; if ($okAt) { break } }
                # App Installer prompt (ShowPrompt=true): answer it through UIA and record exactly what it showed
                try {
                    $AE = [System.Windows.Automation.AutomationElement]
                    foreach ($w in @($AE::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition))) {
                        $cn = [string]$w.Current.ClassName; $nm = [string]$w.Current.Name
                        if ($cn -in @('Shell_TrayWnd', 'Progman', 'Shell_SecondaryTrayWnd', 'WorkerW', 'Zed::Window')) { continue }
                        if ($nm -notmatch 'App Installer|SliceApp|Update' -and [string]$w.Current.ProcessId -eq '') { continue }
                        $btns = @(Find-ByName -Root $w -Name 'Update' -ControlType ([System.Windows.Automation.ControlType]::Button))
                        if ($btns.Count -eq 0) { $btns = @(Find-ByName -Root $w -Name 'Update now' -ControlType ([System.Windows.Automation.ControlType]::Button)) }
                        if ($btns.Count -gt 0 -and -not $clicked.ContainsKey($w.Current.ProcessId)) {
                            $rec.prompt_actions += ('+' + [math]::Round($swL.Elapsed.TotalSeconds, 1) + 's window class=' + $cn + ' name=[' + $nm + '] dump: ' + ((Dump-Window $w 30) -join ' | '))
                            Save-Shot ('tier1-prompt-' + [int]$swL.Elapsed.TotalSeconds)
                            $how = Invoke-Element $btns[0]; $clicked[$w.Current.ProcessId] = $true
                            $rec.prompt_actions += ('+' + [math]::Round($swL.Elapsed.TotalSeconds, 1) + 's clicked Update via ' + $how)
                        }
                    }
                } catch { $rec.prompt_actions += ('prompt scan error: ' + $_.Exception.Message) }
                Beat; Start-Sleep -Milliseconds 500
            }
            $rec.time_to_package_ok_s = $okAt; $rec.time_to_window_s = $winAt
            $rec.package_final = Get-PkgText
            $rec.update_prompt_shown = ($rec.prompt_actions.Count -gt 0)
            $rec.pass_within_60s = [bool]($okAt -and $okAt -le 60 -and $winAt -and $winAt -le 60)
            if (-not $okAt -or -not $winAt) { $rec.top_windows_at_end = @(Get-TopWindows | Where-Object { $_ -notmatch 'class=(Shell_TrayWnd|Progman|Shell_SecondaryTrayWnd|WorkerW) ' }); Save-Shot 'tier1-end' }
            $rec.result = 'package ok at ' + $okAt + ' s, window at ' + $winAt + ' s, final ' + (Get-PkgText) + ', prompt shown ' + $rec.update_prompt_shown
            Stop-App | Out-Null
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
    if ($Method -eq 'tier2-feed-down-long') {
        # long-run retry test: leave the package NeedsRemediation and the feed down; the guard walks its retry ladder on its own. No post-state launch.
        $R.long_run = [ordered]@{ started_utc = (Get-Date).ToUniversalTime().ToString('o'); package = Get-PkgText; feed_up = (Test-FeedUp); guard = Get-GuardState }
        L 'long-run: state left in place (feed down, package NeedsRemediation)'
        Save-Result
        return
    }

    # ---- post state
    Start-Sleep -Seconds 5
    $R.post = Post-State $Method
    if ($IsT2) { $R.guard_final = Get-GuardState }   # the task's triggers after the run: the retry trigger must be gone after a repair
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
