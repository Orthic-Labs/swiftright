# sandbox-run.ps1 - guest-side clean-machine harness for Windows Sandbox (SR0 R5). Prep only; not yet run.
#
# Runs inside the sandbox as WDAGUtilityAccount (an administrator in the sandbox), started by logon.cmd.
# Reads host-staged inputs from the read-only packages folder (manifest.json, old and new .msix, signer.cer).
# Writes one receipt per check to the writable receipts folder as it goes: <check_id>.json, then guest-run.json.
# guest-run.json is the guest's own run record. run-sandbox.ps1 verifies it and writes the authoritative run.json,
# which is what the package stage reads.
# Receipts follow ..\..\receipt.schema.json (sr0-a.package-receipt/v2).
#
# Rules:
#   * A check passes only when its own observations pass. Anything not implemented is recorded as fail with
#     reason "not-implemented" (never pass). Exceptions in a check are recorded as fail with the message.
#   * No check reads or writes outside this sandbox's user profile and the mapped folders.
#   * Windows PowerShell 5.1 compatible (the sandbox ships 5.1, not pwsh).
#   * Interactive app steps use UI Automation (UIA) inside the sandbox desktop. Nothing is sent to the host.
#
# Sandbox facts this relies on (Microsoft Learn, Use and configure Windows Sandbox, and the wsb CLI page):
#   Networking Disable removes the default route (W00 checks this); mapped folders must exist before logon;
#   LogonCommand runs as the container user, which should be an administrator.

[CmdletBinding()]
param(
    [string]$PackagesDir = 'C:\Users\WDAGUtilityAccount\Desktop\clean-machine\packages',
    [string]$ReceiptsDir = 'C:\Users\WDAGUtilityAccount\Desktop\clean-machine\receipts',
    [string]$WorkDir     = 'C:\Users\WDAGUtilityAccount\AppData\Local\Temp\clean-machine-work'
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$HarnessName = 'sandbox-run.ps1'
$HarnessPath = $PSCommandPath
$Utf8 = New-Object System.Text.UTF8Encoding($false)

# Declared order = run.py PACKAGE_CHECKS (qualification/test_run.py HarnessDriftTests compares this block).
$ExpectedChecks = @(
    'W00-environment', 'W01-artifacts-bound', 'W02-signer-trust', 'W03-install-old',
    'W04-launch-offline-old', 'W05-write-data', 'W06-upgrade-new', 'W07-corrupt-update-rejected',
    'W08-interrupted-update', 'W09-rollback-readable', 'W10-uninstall-keeps-data',
    'W11-legacy-data-physical-path', 'W12-appinstaller-update', 'W13-renderer-layout-installed',
    'W14-deferred-update-in-use'
)
# R5 final: two runs. 'offline' (Networking Disable) runs every check except W12; 'network' (Networking Enable) runs W00, W01 and W12 only,
# because the App Installer route needs a connected guest (Delivery Optimization stalls without a network profile) while the install,
# signer-trust and offline-launch checks must stay offline. The profile comes from manifest.json (run-sandbox.ps1 -RunProfile).
$ProfileChecks = @{
    offline = @($ExpectedChecks | Where-Object { $_ -ne 'W12-appinstaller-update' })
    network = @('W00-environment', 'W01-artifacts-bound', 'W12-appinstaller-update')
}
$RunChecks = $ProfileChecks['offline']
$script:Profile = 'offline'

$script:Results = New-Object System.Collections.ArrayList
$script:Pfn = $null
$script:AppId = $null
$script:DataSha = $null
$script:NewMarkerWritten = $false

# ---------------------------------------------------------------- helpers

function Get-UtcStamp { return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }

function Get-Sha256Ref {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 'missing' }
    return 'sha256:' + (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-EnvironmentRecord {
    $os = [System.Environment]::OSVersion.Version.ToString()
    $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $build = ''
    if ($cv) { $build = '{0}.{1} {2}' -f $cv.CurrentBuild, $cv.UBR, $cv.DisplayVersion }
    return @{
        host = $env:COMPUTERNAME
        os_version = ('Windows {0} build {1}' -f $os, $build)
        user = $env:USERNAME
    }
}

function Write-CheckReceipt {
    param(
        [string]$CheckId, [string]$CheckName, [string]$Started, [string]$Status,
        [bool]$Implemented, [string]$Reason, $ExitStatus, [hashtable]$Observed, [hashtable]$Artifacts
    )
    if (-not $Implemented) {
        $Status = 'fail'
        $Reason = 'not-implemented: ' + $Reason
    }
    if ($Status -ne 'pass' -and [string]::IsNullOrEmpty($Reason)) { $Reason = 'failed' }
    $envRec = Get-EnvironmentRecord
    $ids = @{}
    foreach ($k in $Artifacts.Keys) {
        # Only real digests go in artifact_ids (schema: sha256:<64 hex>). 'missing' stays in observed.
        if ([string]$Artifacts[$k] -match '^sha256:[0-9a-f]{64}$') { $ids[$k] = [string]$Artifacts[$k] }
    }
    $rec = [ordered]@{
        schema = 'sr0-a.package-receipt/v2'
        record = 'check'
        product = 'SliceApp'
        platform = 'windows-x64'
        run_id = $script:RunId
        check_id = $CheckId
        check_name = $CheckName
        implemented = $Implemented
        status = $Status
        reason = $(if ($Status -eq 'pass') { $null } else { $Reason })
        started_utc = $Started
        ended_utc = Get-UtcStamp
        exit_status = $ExitStatus
        observations = $Observed
        artifact_ids = $ids
        environment = $envRec
        harness = [ordered]@{ name = $HarnessName; sha256 = (Get-Sha256Ref -Path $HarnessPath) }
    }
    $json = $rec | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText((Join-Path $ReceiptsDir ($CheckId + '.json')), $json, $Utf8)
    [void]$script:Results.Add([pscustomobject]@{ check_id = $CheckId; status = $Status; implemented = $Implemented })
    Write-Output ("{0}: {1}{2}" -f $CheckId, $Status, $(if ($Status -ne 'pass') { ' (' + $Reason + ')' } else { '' }))
}

# Invoke-Check runs a body that returns @{ pass = $bool; reason = ''; observed = @{}; artifacts = @{}; exit = $null }.
function Invoke-Check {
    param([string]$CheckId, [string]$CheckName, [scriptblock]$Body, [bool]$Implemented = $true, [string]$NotImplementedReason = '')
    if ($RunChecks -notcontains $CheckId) { return }   # not part of this run's profile
    $started = Get-UtcStamp
    if (-not $Implemented) {
        Write-CheckReceipt -CheckId $CheckId -CheckName $CheckName -Started $started -Status 'fail' -Implemented $false `
            -Reason $NotImplementedReason -ExitStatus $null -Observed @{} -Artifacts @{}
        return
    }
    try {
        # Bodies return one hashtable; stray pipeline output from cmdlets is discarded here.
        $r = @(& $Body) | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1
        if (-not $r) { throw 'check body returned no result hashtable' }
        $pass = [bool]$r.pass
        $status = $(if ($pass) { 'pass' } else { 'fail' })
        $reason = $(if ($pass) { '' } else { [string]$r.reason })
        # PASS / FAIL / NOT-DEMONSTRABLE (the schema only has pass|fail, so NOT-DEMONSTRABLE is a fail receipt whose reason and
        # observations.verdict say the experiment could not be performed, not that the product failed).
        if (-not $r.observed) { $r.observed = @{} }
        $verdict = $(if ($pass) { 'PASS' } elseif ($r.ContainsKey('verdict') -and $r['verdict']) { [string]$r['verdict'] } else { 'FAIL' })
        $r.observed['verdict'] = $verdict
        if ($verdict -eq 'NOT-DEMONSTRABLE') { $reason = 'NOT-DEMONSTRABLE: ' + $reason }
        Write-CheckReceipt -CheckId $CheckId -CheckName $CheckName -Started $started -Status $status -Implemented $true `
            -Reason $reason -ExitStatus $r.exit -Observed $r.observed -Artifacts $r.artifacts
    }
    catch {
        Write-CheckReceipt -CheckId $CheckId -CheckName $CheckName -Started $started -Status 'fail' -Implemented $true `
            -Reason ('exception: ' + $_.Exception.Message) -ExitStatus $null -Observed @{ error_type = $_.Exception.GetType().FullName } -Artifacts @{}
    }
}

function Get-Pkg {
    if (-not $script:Manifest) { return $null }
    return Get-AppxPackage -Name $script:Manifest.identity_name -ErrorAction SilentlyContinue
}

function Get-DataCandidates {
    $list = @()
    $list += [pscustomobject]@{ kind = 'physical-localappdata'; path = (Join-Path $env:LOCALAPPDATA 'SliceApp\rows.json') }
    if ($script:Pfn) {
        $list += [pscustomobject]@{ kind = 'msix-localcache'; path = (Join-Path $env:LOCALAPPDATA ('Packages\' + $script:Pfn + '\LocalCache\Local\SliceApp\rows.json')) }
    }
    return $list
}

# Returns the data file location that exists (first match), its sha, and both candidate states for the receipt.
function Get-DataState {
    $state = @{}
    $found = $null
    foreach ($c in (Get-DataCandidates)) {
        $exists = Test-Path -LiteralPath $c.path -PathType Leaf
        $state[$c.kind + '_exists'] = [string]$exists
        if ($exists) {
            $state[$c.kind + '_sha'] = Get-Sha256Ref -Path $c.path
            if (-not $found) { $found = $c }
        }
    }
    return @{ found = $found; observed = $state }
}

function Get-RowsText {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Test-RowsSchema1 {
    param([string]$Path)
    $text = Get-RowsText -Path $Path
    if ($null -eq $text) { return $false }
    try { $doc = $text | ConvertFrom-Json } catch { return $false }
    return ($doc.schema -eq $script:Manifest.expected_schema)
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

# PATCH-1: the packaged app shows two top-level windows (Zed::Window and a ConsoleWindowClass console) and the elevated guest's UIA client
# reports ProcessId 0 for them, so the original ProcessId lookup never matches. Find the app window by class instead.
function Find-AppWindow {
    $AE = [System.Windows.Automation.AutomationElement]
    return $AE::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, (New-Object System.Windows.Automation.PropertyCondition($AE::ClassNameProperty, 'Zed::Window')))
}

function Start-AppAndFindWindow {
    param([int]$TimeoutSec = 30)
    $pkg = Get-Pkg
    if (-not $pkg) { throw 'package not installed; cannot launch' }
    $script:Pfn = $pkg.PackageFamilyName
    $manifest = Get-AppxPackageManifest -Package $pkg.PackageFullName
    $script:AppId = [string]$manifest.Package.Applications.Application.Id
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('shell:AppsFolder\' + $script:Pfn + '!' + $script:AppId) | Out-Null
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $exe = [System.IO.Path]::GetFileNameWithoutExtension($manifest.Package.Applications.Application.Executable)
    while ((Get-Date) -lt $deadline) {
        $procs = @(Get-Process -Name $exe -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 })
        if ($procs.Count -gt 0) {
            $pid0 = [int]$procs[0].Id
            $win = Find-AppWindow
            if ($win) {
                return @{ pid = $pid0; window_name = $win.Current.Name; exe = $exe }
            }
        }
        Start-Sleep -Milliseconds 500
    }
    throw ('no window for ' + $exe + ' within ' + $TimeoutSec + ' s')
}

function Get-AppProcesses {
    $exe = 'SliceApp'
    return @(Get-Process -Name $exe -ErrorAction SilentlyContinue)
}

function Stop-AppGracefully {
    foreach ($p in (Get-AppProcesses)) { [void]$p.CloseMainWindow() }
    Start-Sleep -Seconds 3
    foreach ($p in (Get-AppProcesses)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
    return (@(Get-AppProcesses).Count -eq 0)
}

# UIA helpers over the app window of the given process id.
function Get-AppRoot {
    param([int]$ProcessId)
    return (Find-AppWindow)   # PATCH-1
}

function Find-ByName {
    param($Root, [string]$Name, $ControlType)
    $c1 = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    $c2 = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ControlType)
    $cond = New-Object System.Windows.Automation.AndCondition($c1, $c2)
    return @($Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond))
}

# Inserts a row and writes the marker into the new (empty) row, through UIA ValuePattern (the app routes AX SetValue into editText).
# PATCH-5: Edit controls carry no Name; they are identified by AutomationId row/<guid>/field.
function Find-RowFields {
    param($Root)
    $c = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
    return @($Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $c) | Where-Object { $_.Current.AutomationId -like 'row/*/field' })
}

function Write-MarkerRow {
    param($Root, [string]$Marker)
    $btn = @(Find-ByName -Root $Root -Name 'Insert above' -ControlType ([System.Windows.Automation.ControlType]::Button))
    if ($btn.Count -eq 0) { throw 'button "Insert above" not found in UIA tree' }
    $inv = $btn[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $inv.Invoke()
    # Insert above adds an EMPTY row (EditorModel.insertAbove); write into it so earlier markers are never overwritten. The software-rendered guest
    # can take longer than a second to reflect the insert in the UIA tree, so poll for up to 15 s.
    $target = $null; $rows = @()
    $deadlineRow = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadlineRow -and -not $target) {
        Start-Sleep -Milliseconds 500
        $rows = @(Find-RowFields -Root $Root)
        foreach ($r in $rows) {
            $v = $r.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
            if ([string]$v.Current.Value -eq '') { $target = $r; break }
        }
    }
    if ($rows.Count -eq 0) { throw 'no "Row" text fields found after insert' }
    if (-not $target) { throw 'no empty Row field after Insert above (15 s)' }
    $vp = $target.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $vp.SetValue($Marker)
    return @{ row_fields = $rows.Count }
}

function Read-RowValues {
    param($Root)
    $rows = @(Find-RowFields -Root $Root)
    $vals = @()
    foreach ($r in $rows) {
        $vp = $r.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $vals += [string]$vp.Current.Value
    }
    return ,$vals
}

function Wait-ForMarkerInFile {
    param([string]$Marker, [int]$TimeoutSec = 15)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        foreach ($c in (Get-DataCandidates)) {
            $t = Get-RowsText -Path $c.path
            if ($t -and $t.Contains($Marker)) { return $c }
        }
        Start-Sleep -Milliseconds 500
    }
    return $null
}

function Read-ManifestPackage {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.GetEntry('AppxManifest.xml')
        if (-not $entry) { throw 'AppxManifest.xml not in package' }
        $sr = New-Object System.IO.StreamReader($entry.Open())
        try { [xml]$xml = $sr.ReadToEnd() } finally { $sr.Close() }
    }
    finally { $zip.Dispose() }
    return $xml
}


# ---- R5 additions: SliceApp scripts staged beside this harness (harness\SliceApp\scripts, harness\SliceApp\Windows)
$script:SliceDir = Join-Path $PSScriptRoot 'SliceApp'
$script:LocalAppData = Join-Path $env:LOCALAPPDATA 'SliceApp'

# Runs a child Windows PowerShell with the given arguments, returns @{ exit; out }.
function Invoke-ChildPs {
    param([string[]]$PsArgs)
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass @PsArgs 2>&1 | Out-String
    return @{ exit = $LASTEXITCODE; out = $out.Trim() }
}

# Offset of the middle of an entry's compressed data (ZipArchive + the private local-header offset; handles ZIP64).
function Get-ZipEntryMidOffset {
    param([string]$Path, [string]$EntryName)
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $za = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Read)
        $e = $za.GetEntry($EntryName)
        if (-not $e) { throw "entry not found: $EntryName" }
        $fi = $e.GetType().GetField('_offsetOfLocalHeader', [System.Reflection.BindingFlags]'NonPublic,Instance')
        if (-not $fi) { throw 'ZipArchiveEntry local-header offset field not found' }
        $lho = [long]$fi.GetValue($e)
        $csize = [long]$e.CompressedLength
        $za.Dispose()
    } finally { $fs.Dispose() }
    $fs2 = [System.IO.File]::OpenRead($Path)
    try { [void]$fs2.Seek($lho, 'Begin'); $h = New-Object byte[] 30; [void]$fs2.Read($h, 0, 30) } finally { $fs2.Dispose() }
    if ([BitConverter]::ToUInt32($h, 0) -ne 0x04034b50) { throw 'bad local header signature' }
    $start = $lho + 30 + [BitConverter]::ToUInt16($h, 26) + [BitConverter]::ToUInt16($h, 28)
    return @{ offset = [int]($start + [Math]::Floor($csize / 2)); data_start = $start; compressed_size = $csize }
}

function Get-ZipEntryChangedBlockOffset {
    # W07: offset of a byte inside a block of $EntryName whose AppxBlockMap hash differs between $Path (new) and $OldPath (installed).
    # An update reuses every block whose hash matches the installed copy, so only a flip inside a changed block is ever read.
    param([string]$Path, [string]$OldPath, [string]$EntryName)
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    function Read-Blocks([string]$msix) {
        $za = [System.IO.Compression.ZipFile]::OpenRead($msix)
        try { $sr = New-Object System.IO.StreamReader($za.GetEntry('AppxBlockMap.xml').Open()); [xml]$x = $sr.ReadToEnd(); $sr.Dispose() } finally { $za.Dispose() }
        $f = @($x.BlockMap.File | Where-Object { $_.Name -eq $EntryName })[0]
        if (-not $f) { throw "blockmap has no $EntryName in $msix" }
        $n = @($f.Block).Count
        $out = @()
        for ($i = 0; $i -lt $n; $i++) {
            $blk = @($f.Block)[$i]
            $size = $(if ($blk.Size) { [long]$blk.Size } elseif ($i -lt $n - 1) { 65536 } else { [long]$f.Size - 65536 * ($n - 1) })
            $out += @{ hash = [string]$blk.Hash; size = $size }
        }
        return $out
    }
    $new = Read-Blocks $Path; $old = Read-Blocks $OldPath
    $changed = @(); for ($i = 0; $i -lt $new.Count; $i++) { if ($i -ge $old.Count -or $new[$i].hash -ne $old[$i].hash) { $changed += $i } }
    if ($changed.Count -eq 0) { throw "no block of $EntryName differs between old and new" }
    $pick = $changed[[int][Math]::Floor($changed.Count / 2)]
    $mid = Get-ZipEntryMidOffset -Path $Path -EntryName $EntryName
    $before = 0L; for ($i = 0; $i -lt $pick; $i++) { $before += $new[$i].size }
    return @{ offset = [int]($mid.data_start + $before + [Math]::Floor($new[$pick].size / 2)); data_start = $mid.data_start; block = $pick; changed_blocks = ($changed -join ',') }
}

function Invoke-AppInstallerBounded {
    param([string]$Url, [int]$TimeoutSec)
    $outf = Join-Path $WorkDir ('ai-' + [guid]::NewGuid().ToString('N') + '.txt')
    $cmd = "`$r = ''; try { Add-AppxPackage -AppInstallerFile '" + $Url + "' -ErrorAction Stop; `$r = 'OK' } catch { `$r = 'FAILED: ' + `$_.Exception.Message }; Set-Content -LiteralPath '" + $outf + "' -Value `$r"
    $p = Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd)
    if ($p.WaitForExit($TimeoutSec * 1000)) {
        $r = ''
        if (Test-Path -LiteralPath $outf) { $r = (Get-Content -LiteralPath $outf -Raw).Trim() }
        return @{ timed_out = $false; result = $r }
    }
    try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
    return @{ timed_out = $true; result = ('no result within ' + $TimeoutSec + ' s') }
}

function Get-VersionString { $p = Get-Pkg; if ($p) { return [string]$p.Version } else { return 'none' } }

function Remove-PkgKeepData {
    $p = Get-Pkg
    if ($p) { Remove-AppxPackage -Package $p.PackageFullName }   # PATCH-2: no -PreserveApplicationData (dev-mode only, 0x80073CFA)
    return (-not (Get-Pkg))
}

function Get-RowsSha {
    $f = Join-Path $script:LocalAppData 'rows.json'
    if (Test-Path -LiteralPath $f -PathType Leaf) { return Get-Sha256Ref -Path $f } else { return 'absent' }
}

# True when no package-private copy of the data exists (virtualization must be off).
function Test-NoLocalCacheCopy {
    if (-not $script:Pfn) { return $false }
    $lc = Join-Path $env:LOCALAPPDATA ('Packages\' + $script:Pfn + '\LocalCache\Local\SliceApp')
    return (-not (Test-Path -LiteralPath $lc))
}

# Polls until Get-Pkg reports the wanted version; returns the last observed version.
function Wait-PkgVersion {
    param([string]$Version, [int]$TimeoutSec = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if ((Get-VersionString) -eq $Version) { return $Version }
        Start-Sleep -Seconds 2
    }
    return (Get-VersionString)
}

# W08 hold-open (opt-in: manifest hold_open_for_repair_minutes > 0; default 0 = nothing below runs). After the FIRST genuine interruption that leaves
# the package with a status other than Ok (NeedsRemediation), W08 keeps the guest up so a person can try Settings > Apps > Installed apps > SliceApp >
# Advanced options > Repair, and records the package state around it. It runs after the case's own launch attempt and BEFORE the case's second
# Add-AppxPackage, and nothing it records feeds the case verdict, so W08 judges exactly what it judges without it. Evidence (neither name matches the package
# stage's check-record pattern, so the runner ignores them): receipts\hold-open-W08.log (timestamped lines, readable on the host while the guest runs; the
# host relays them) and receipts\hold-open-W08-state.json (snapshots: package status/version, rows sha, launch + marker + log banner, AppXDeploymentServer
# events since the hold began). Creating receipts\hold-release.txt on the host ends the hold early.
function Add-HoldLog {
    param([string]$Text)
    $now = Get-Date
    $line = ($now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')) + ' (guest local ' + $now.ToString('HH:mm:ss') + ') ' + $Text
    [System.IO.File]::AppendAllText((Join-Path $ReceiptsDir 'hold-open-W08.log'), $line + [Environment]::NewLine, $Utf8)
    Write-Host $line
}

function Get-HoldSnapshot {
    param([string]$Label, [datetime]$Since, [bool]$TryLaunch)
    $m = $script:Manifest
    $s = [ordered]@{ label = $Label; utc = (Get-UtcStamp) }
    $pk = @(Get-AppxPackage -Name $m.identity_name -ErrorAction SilentlyContinue)
    $all = @(Get-AppxPackage -AllUsers -Name $m.identity_name -ErrorAction SilentlyContinue)
    $s['registered_count'] = $pk.Count
    $s['all_users_count'] = $all.Count
    $s['version'] = $(if ($pk.Count -eq 1) { [string]$pk[0].Version } else { 'none-or-many' })
    $s['status'] = $(if ($pk.Count -eq 1) { [string]$pk[0].Status } else { 'n/a' })
    $s['rows_sha'] = (Get-RowsSha)
    $s['launched'] = 'not-attempted'; $s['window_name'] = ''; $s['marker_shown'] = 'not-attempted'; $s['log_banner_for_pid'] = 'not-attempted'; $s['launch_error'] = ''
    if ($TryLaunch -and $pk.Count -eq 1) {
        try {
            $w = Start-AppAndFindWindow -TimeoutSec 40
            $s['launched'] = 'True'; $s['window_name'] = [string]$w.window_name
            try { $vals = Read-RowValues -Root (Get-AppRoot -ProcessId $w.pid); $s['marker_shown'] = [string]($vals -contains ('rightkit-check-' + $script:RunId)) } catch { $s['marker_shown'] = 'unreadable: ' + $_.Exception.Message }
            $pidNow = [string]$w.pid
            [void](Stop-AppGracefully)
            $logPath = Join-Path $script:LocalAppData 'slice-app.log'
            $logText = ''
            if (Test-Path -LiteralPath $logPath) {
                $lfs = [IO.File]::Open($logPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                try { $lsr = New-Object IO.StreamReader($lfs); $logText = $lsr.ReadToEnd() } finally { $lfs.Dispose() }
            }
            $s['log_banner_for_pid'] = [string]($logText -match ('slice-app: log opened \S+ pid=' + $pidNow + ' '))
        }
        catch { $s['launched'] = 'False'; $s['launch_error'] = $_.Exception.Message; [void](Stop-AppGracefully) }
    }
    $s['events'] = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-AppXDeploymentServer/Operational'; StartTime = $Since.AddSeconds(-1) } -ErrorAction SilentlyContinue |
        Sort-Object TimeCreated | Select-Object -First 200 | ForEach-Object {
            $msg = ([string]$_.Message) -replace '\s+', ' '
            ('{0:HH:mm:ss.fff} id={1} {2}: {3}' -f $_.TimeCreated, $_.Id, $_.LevelDisplayName, $msg.Substring(0, [Math]::Min(220, $msg.Length)))
        })
    return $s
}

function Invoke-RepairHoldOpen {
    param([string]$CaseId, [int]$Minutes)
    $m = $script:Manifest
    $release = Join-Path $ReceiptsDir 'hold-release.txt'
    Remove-Item -LiteralPath $release -ErrorAction SilentlyContinue
    $since = Get-Date
    $startedUtc = Get-UtcStamp
    $before = Get-HoldSnapshot -Label 'before' -Since $since -TryLaunch $false
    $snaps = New-Object System.Collections.ArrayList
    [void]$snaps.Add($before)
    Add-HoldLog ('awaiting manual Repair: case ' + $CaseId + ', package ' + $before['version'] + ' status "' + $before['status'] + '". Holding the guest up for ' + $Minutes + ' min. Try Settings > Apps > Installed apps > SliceApp > Advanced options > Repair. To end the hold early create ' + $release + ' on the host.')
    $deadline = $since.AddMinutes($Minutes)
    $lastKey = [string]$before['version'] + '|' + [string]$before['status']
    $changed = $false; $repairSeen = $false; $afterTaken = $false; $settleAt = $null; $endReason = 'timeout'
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $release) { $endReason = 'released'; Add-HoldLog 'hold-release.txt seen; ending the hold'; break }
        $pk = @(Get-AppxPackage -Name $m.identity_name -ErrorAction SilentlyContinue)
        $key = $(if ($pk.Count -eq 1) { [string]$pk[0].Version + '|' + [string]$pk[0].Status } else { 'none-or-many|n/a' })
        if ($key -ne $lastKey) {
            Add-HoldLog ('package state changed: ' + $key + ' (was ' + $lastKey + ')')
            $lastKey = $key; $changed = $true
            if ($pk.Count -eq 1 -and [string]$pk[0].Status -eq 'Ok' -and -not $repairSeen) { $repairSeen = $true; $settleAt = (Get-Date).AddSeconds(10) }
        }
        if ($repairSeen -and -not $afterTaken -and $settleAt -and (Get-Date) -ge $settleAt) {
            $afterTaken = $true
            Add-HoldLog 'status is Ok again after the hold began: capturing the state after the Repair (launch, rows, marker, events)'
            [void]$snaps.Add((Get-HoldSnapshot -Label 'after-repair' -Since $since -TryLaunch $true))
            Add-HoldLog 'state after the Repair captured; still holding until the window ends or hold-release.txt appears'
        }
        Start-Sleep -Seconds 3
    }
    Add-HoldLog ('hold ending (' + $endReason + '); capturing the end-of-hold state')
    $final = Get-HoldSnapshot -Label 'end-of-hold' -Since $since -TryLaunch $true
    [void]$snaps.Add($final)
    $endedUtc = Get-UtcStamp
    Add-HoldLog ('hold ended: package ' + $final['version'] + ' status "' + $final['status'] + '", launched=' + $final['launched'] + ', marker_shown=' + $final['marker_shown'] + ', rows_sha_equal_before=' + [string]($final['rows_sha'] -eq $before['rows_sha']))
    $doc = [ordered]@{ schema = 'sr0-hold-open/v1'; case = $CaseId; minutes = $Minutes; started_utc = $startedUtc; ended_utc = $endedUtc; end_reason = $endReason; snapshots = @($snaps) }
    [System.IO.File]::WriteAllText((Join-Path $ReceiptsDir 'hold-open-W08-state.json'), ($doc | ConvertTo-Json -Depth 6), $Utf8)
    return @{
        hold_open_case = $CaseId; hold_open_minutes = [string]$Minutes; hold_open_started_utc = $startedUtc; hold_open_ended_utc = $endedUtc; hold_open_end_reason = $endReason
        hold_open_status_before = [string]$before['status']; hold_open_status_end = [string]$final['status']; hold_open_version_end = [string]$final['version']
        hold_open_state_changed = [string]$changed; hold_open_status_ok_seen = [string]$repairSeen; hold_open_end_launched = [string]$final['launched']
        hold_open_end_marker_shown = [string]$final['marker_shown']; hold_open_end_rows_sha_equal_before = [string]($final['rows_sha'] -eq $before['rows_sha'])
        hold_open_events_count = [string]@($final['events']).Count
    }
}

# ---------------------------------------------------------------- start

if (-not (Test-Path -LiteralPath $ReceiptsDir)) { throw "receipts folder not mapped: $ReceiptsDir" }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$script:Manifest = $null
$manifestPath = Join-Path $PackagesDir 'manifest.json'
if (Test-Path -LiteralPath $manifestPath) {
    $script:Manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
}
$script:RunId = $(if ($script:Manifest) { [string]$script:Manifest.run_id } else { 'unknown-no-manifest' })
if ($script:Manifest -and $script:Manifest.PSObject.Properties['profile'] -and $ProfileChecks.ContainsKey([string]$script:Manifest.profile)) {
    $script:Profile = [string]$script:Manifest.profile
    $RunChecks = $ProfileChecks[$script:Profile]
}
# Opt-in W08 hold-open (see Invoke-RepairHoldOpen); absent or 0 means W08 runs exactly as before.
$script:HoldOpenMinutes = 0
$script:HoldOpenDone = $false
if ($script:Manifest -and $script:Manifest.PSObject.Properties['hold_open_for_repair_minutes']) { $script:HoldOpenMinutes = [int]$script:Manifest.hold_open_for_repair_minutes }
$script:RunStarted = Get-UtcStamp

# W00: environment. Offline must be real (no default route) and the logon must be elevated.
Invoke-Check -CheckId 'W00-environment' -CheckName 'Sandbox environment, elevation, offline' -Body {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $defaultRoutes = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue).Count
    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $observed = @{
        profile = $script:Profile
        elevated = [string]$elevated
        default_routes = [string]$defaultRoutes
        adapters = ($adapters -join ',')
        manifest_present = [string]($null -ne $script:Manifest)
    }
    # offline: no default route (Networking Disable is real). network: a default route exists (Networking Enable), needed by W12 only.
    $netOk = $(if ($script:Profile -eq 'network') { $defaultRoutes -gt 0 } else { $defaultRoutes -eq 0 })
    $pass = $elevated -and $netOk -and ($null -ne $script:Manifest)
    @{ pass = $pass; reason = ('need elevated, a manifest, and ' + $(if ($script:Profile -eq 'network') { 'a default route (profile network)' } else { 'no default route (profile offline)' })); observed = $observed; artifacts = @{}; exit = $null }
}

# W01: staged artifacts match the host-side hashes in the manifest.
Invoke-Check -CheckId 'W01-artifacts-bound' -CheckName 'Staged packages and signer match host manifest' -Body {
    $m = $script:Manifest
    $old = Join-Path $PackagesDir $m.old.file
    $new = Join-Path $PackagesDir $m.new.file
    $cer = Join-Path $PackagesDir $m.signer_cer.file
    $shaOld = Get-Sha256Ref -Path $old
    $shaNew = Get-Sha256Ref -Path $new
    $shaCer = Get-Sha256Ref -Path $cer
    $arts = @{ old_msix = $shaOld; new_msix = $shaNew; signer_cer = $shaCer }
    $pass = ($shaOld -eq $m.old.sha256) -and ($shaNew -eq $m.new.sha256) -and ($shaCer -eq $m.signer_cer.sha256)
    # Feed material and the staged SliceApp scripts / renderer pin must match their host hashes too.
    $badExtra = @()
    foreach ($e in @($m.extra)) { if ((Get-Sha256Ref -Path (Join-Path $PackagesDir $e.path)) -ne $e.sha256) { $badExtra += [string]$e.path } }
    foreach ($e in @($m.harness_files)) { if ((Get-Sha256Ref -Path (Join-Path $PSScriptRoot $e.path)) -ne $e.sha256) { $badExtra += [string]$e.path } }
    if ($badExtra.Count -gt 0) { $pass = $false }
    @{ pass = $pass; reason = ('hash differs from manifest' + $(if ($badExtra.Count -gt 0) { ': ' + ($badExtra -join ', ') } else { '' })); observed = @{ run_id = $m.run_id; extra_files_checked = [string](@($m.extra).Count + @($m.harness_files).Count) }; artifacts = $arts; exit = $null }
}

# W02: the signer must be trusted in the guest. The sandbox starts with no trust. Import only the public .cer.
Invoke-Check -CheckId 'W02-signer-trust' -CheckName 'Signer trusted in the guest (public certificate only)' -Body {
    $m = $script:Manifest
    $old = Join-Path $PackagesDir $m.old.file
    $sig = Get-AuthenticodeSignature -FilePath $old
    $statusBefore = [string]$sig.Status
    $imported = $false
    $tp = 'Cert:\LocalMachine\TrustedPeople'
    $thumb = [string]$m.signer_cer.thumbprint
    $inStore = @(Get-ChildItem -Path $tp -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $thumb }).Count -gt 0
    if (-not $inStore -and $statusBefore -ne 'Valid') {
        Import-Certificate -FilePath (Join-Path $PackagesDir $m.signer_cer.file) -CertStoreLocation $tp | Out-Null
        $imported = $true
        $inStore = @(Get-ChildItem -Path $tp | Where-Object { $_.Thumbprint -eq $thumb }).Count -gt 0
    }
    $subjectOk = ([string]$sig.SignerCertificate.Subject) -eq [string]$m.publisher
    $observed = @{
        signature_status_before = $statusBefore
        imported_public_cer = [string]$imported
        in_trusted_people = [string]$inStore
        signer_subject = [string]$sig.SignerCertificate.Subject
        manifest_publisher = [string]$m.publisher
    }
    $pass = ($statusBefore -eq 'Valid' -or $inStore) -and $subjectOk
    @{ pass = $pass; reason = 'signer not trusted or subject differs from manifest publisher'; observed = $observed; artifacts = @{ signer_cer = (Get-Sha256Ref -Path (Join-Path $PackagesDir $m.signer_cer.file)) }; exit = $null }
}

# W03: install the old package offline (no network in this sandbox).
Invoke-Check -CheckId 'W03-install-old' -CheckName 'Install old MSIX' -Body {
    $m = $script:Manifest
    $old = Join-Path $PackagesDir $m.old.file
    Add-AppxPackage -Path $old
    $pkg = Get-Pkg
    $script:Pfn = $(if ($pkg) { $pkg.PackageFamilyName } else { $null })
    $ver = $(if ($pkg) { [string]$pkg.Version } else { 'none' })
    $pass = ($ver -eq [string]$m.old.version)
    @{ pass = $pass; reason = ('installed version ' + $ver + ' != ' + $m.old.version); observed = @{ version = $ver; package_family = [string]$script:Pfn }; artifacts = @{ old_msix = (Get-Sha256Ref -Path $old) }; exit = 0 }
}


# W03b: installed renderer layout (F1) by Authenticode digest. RightKit signs every packaged PE, so the raw sha256
# differs per build; verify-package-layout.ps1 -Mode Installed compares the PE Authenticode digest to
# Windows\renderer-pin.json (final tuple renderer 4FB068F0...) and loads the renderer + its closure from the package
# under a scrubbed environment (PATH = System32, SWIFTRIGHT_RENDER_DLL unset). No app launch.
Invoke-Check -CheckId 'W13-renderer-layout-installed' -CheckName 'Installed renderer matches the pin (Authenticode digest) and loads from the package' -Body {
    # PATCH-3: -Mode Installed ends with LoadLibraryEx of the DLL from C:\Program Files\WindowsApps in a non-package process: error 5 even though the
    # ACL grants Users read/execute. Check the installed files statically (Authenticode digest vs pin, exe beside DLL, closure files); the packaged exe's
    # own load of the renderer is observed in W04 (loaded module path).
    $pkg0 = Get-Pkg
    $r = Invoke-ChildPs -PsArgs @('-File', (Join-Path $script:SliceDir 'scripts\verify-package-layout.ps1'), '-Mode', 'Stage', '-Root', $pkg0.InstallLocation)
    $pin = Get-Content -Raw -LiteralPath (Join-Path $script:SliceDir 'Windows\renderer-pin.json') | ConvertFrom-Json
    $pkg = Get-Pkg
    $dll = Join-Path $pkg.InstallLocation $pin.file
    $exe = Join-Path $pkg.InstallLocation 'SliceApp.exe'
    $observed = @{
        verify_exit = [string]$r.exit; verify_output = $r.out
        pin_sha256_unsigned = [string]$pin.sha256; pin_authenticode_sha256 = [string]$pin.authenticodeSha256
        packaged_dll_raw_sha256 = [string](Get-FileHash -Algorithm SHA256 -LiteralPath $dll).Hash
        dll_signature = [string](Get-AuthenticodeSignature -FilePath $dll).Status
        exe_signature = [string](Get-AuthenticodeSignature -FilePath $exe).Status
        install_location = [string]$pkg.InstallLocation
    }
    @{ pass = ($r.exit -eq 0); reason = 'verify-package-layout -Mode Installed failed; see verify_output'; observed = $observed; artifacts = @{}; exit = $r.exit }
}

# W04: launch the old build offline; the window must appear through UIA.
Invoke-Check -CheckId 'W04-launch-offline-old' -CheckName 'Launch old build offline; window via UIA' -Body {
    $w = Start-AppAndFindWindow -TimeoutSec 40
    $pass = ($w.window_name -ne '')
    $rmod = ''
    try { $rmod = (@((Get-Process -Id $w.pid).Modules | Where-Object { $_.ModuleName -like 'swiftright_render*' } | ForEach-Object { $_.FileName }) -join ';') } catch { $rmod = 'unreadable: ' + $_.Exception.Message }
    # R5 final (product fix P1): SliceApp.exe is a GUI-subsystem exe. (a) no console window is opened for it (top-level ConsoleWindowClass / Windows Terminal
    # host window whose title names SliceApp.exe; the harness's own console never carries that title); (b) with no standard handles the packaged launch logs
    # to %LOCALAPPDATA%\SliceApp\slice-app.log: the log must hold this process's banner (pid).
    $AE = [System.Windows.Automation.AutomationElement]
    $consoleWins = @($AE::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition) |
        Where-Object { ($_.Current.ClassName -in @('ConsoleWindowClass', 'CASCADIA_HOSTING_WINDOW_CLASS')) -and ($_.Current.Name -match 'SliceApp') })
    $logPath = Join-Path $script:LocalAppData 'slice-app.log'
    # The shipped build opens the log exclusively while it runs (CRT freopen; a shared-read variant is a follow-up, RESULT-R5.md), so close the app first and
    # read the log afterwards. The pid and exe path are read before the app exits.
    $exePath = ''
    try { $exePath = (Get-Process -Id $w.pid).MainModule.FileName } catch { $exePath = '' }
    $closedForLog = Stop-AppGracefully
    $logText = ''
    if (Test-Path -LiteralPath $logPath) {
        $lfs = [IO.File]::Open($logPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        try { $lsr = New-Object IO.StreamReader($lfs); $logText = $lsr.ReadToEnd() } finally { $lfs.Dispose() }
    }
    $bannerForPid = ($logText -match ('slice-app: log opened \S+ pid=' + $w.pid + ' '))
    $subsystem = ''
    try { $b = [IO.File]::ReadAllBytes($exePath); $subsystem = [string][BitConverter]::ToUInt16($b, [BitConverter]::ToInt32($b, 0x3c) + 24 + 68) } catch { $subsystem = 'unreadable: ' + $_.Exception.Message }
    $pass = $pass -and ($consoleWins.Count -eq 0) -and $bannerForPid -and ($subsystem -eq '2')
    @{ pass = $pass; reason = 'window has no name, a console window opened for SliceApp.exe, the packaged launch left no log banner for its pid, or the exe is not subsystem 2'; observed = @{ renderer_module_loaded_from = $rmod; window_name = [string]$w.window_name; pid = [string]$w.pid; network_default_routes = [string](@(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue).Count); console_windows_for_app = [string]$consoleWins.Count; console_window_titles = (($consoleWins | ForEach-Object { $_.Current.Name }) -join ';'); log_banner_for_pid = [string]$bannerForPid; app_closed_for_log_read = [string]$closedForLog; log_path = $logPath; log_tail = (($logText -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 3) -join ' | '); pe_subsystem = $subsystem }; artifacts = @{}; exit = $null }
}

# W05: write data through the UI and confirm it reaches rows.json at a physical path.
Invoke-Check -CheckId 'W05-write-data' -CheckName 'Write a row through UIA; data lands on disk' -Body {
    $marker = 'rightkit-check-' + $script:RunId
    $w = Start-AppAndFindWindow -TimeoutSec 40
    $root = Get-AppRoot -ProcessId $w.pid
    $wr = Write-MarkerRow -Root $root -Marker $marker
    $found = Wait-ForMarkerInFile -Marker $marker -TimeoutSec 20
    $st = Get-DataState
    $observed = @{ marker = $marker; row_fields = [string]$wr.row_fields }
    foreach ($k in $st.observed.Keys) { $observed[$k] = $st.observed[$k] }
    $observed['found_at'] = $(if ($found) { $found.kind } else { 'none' })
    $art = @{}
    if ($found) { $art['rows_json_fresh'] = Get-Sha256Ref -Path $found.path; $script:DataSha = $art['rows_json_fresh'] }
    $pass = [bool]$found
    @{ pass = $pass; reason = 'marker not found in any rows.json location within 20 s'; observed = $observed; artifacts = $art; exit = $null }
}

# W06: upgrade to the new MSIX; rows.json must not change on install; app relaunches and shows the marker.
Invoke-Check -CheckId 'W06-upgrade-new' -CheckName 'Upgrade to new MSIX keeps data and UI' -Body {
    $m = $script:Manifest
    $new = Join-Path $PackagesDir $m.new.file
    $closed = Stop-AppGracefully
    $before = $script:DataSha
    Add-AppxPackage -Path $new
    $pkg = Get-Pkg
    $ver = $(if ($pkg) { [string]$pkg.Version } else { 'none' })
    $st = Get-DataState
    $loc = $st.found
    $after = $(if ($loc) { Get-Sha256Ref -Path $loc.path } else { 'missing' })
    $w = Start-AppAndFindWindow -TimeoutSec 40
    $vals = Read-RowValues -Root (Get-AppRoot -ProcessId $w.pid)
    $marker = 'rightkit-check-' + $script:RunId
    $shown = ($vals -contains $marker)
    # The NEW build writes a row of its own, so W09 can prove the OLD build reads data written by the new one.
    $newMarker = 'rightkit-new-' + $script:RunId
    [void](Write-MarkerRow -Root (Get-AppRoot -ProcessId $w.pid) -Marker $newMarker)
    $newFound = Wait-ForMarkerInFile -Marker $newMarker -TimeoutSec 20
    $script:NewMarkerWritten = [bool]$newFound
    $observed = @{ new_build_marker_written = [string]$script:NewMarkerWritten; closed_before_install = [string]$closed; version = $ver; data_sha_before = [string]$before; data_sha_after_install = [string]$after; marker_shown = [string]$shown }
    $pass = ($ver -eq [string]$m.new.version) -and ($before -eq $after) -and $shown -and $script:NewMarkerWritten
    @{ pass = $pass; reason = 'version, data hash, or marker in UI differs'; observed = $observed; artifacts = @{ new_msix = (Get-Sha256Ref -Path $new) }; exit = 0 }
}

# W07: a corrupt update must be refused and the installed version must stay put.
Invoke-Check -CheckId 'W07-corrupt-update-rejected' -CheckName 'Tampered MSIX refused; installed version unchanged; valid update still applies' -Body {
    # PATCH-5 (19 Oct, tuple 12): the mid-file flip of PATCH-4 landed in SliceApp.exe block 30, identical in 0.1.0 and 0.1.1 (6 of 60 blocks differ), so the
    # update reused the installed block and never read the flip. The changed-entry flip now sits inside a block whose blockmap hash differs.
    # PATCH-4. Original ran with the NEW build installed and running: the refusal was 0x80073D02 (in use), not corruption, and its flipped byte sat in
    # _FoundationICU.dll, a payload file identical in old and new. An update over the old build reuses unchanged blocks from the installed copy (differential
    # update), so a flip there is never read. Now: app closed, OLD installed; (a, informational) flip inside the unchanged ICU entry; (b, the check) flip inside
    # SliceApp.exe, a file that differs old->new, must be refused for a non-in-use reason with OLD still registered; then the genuine NEW must apply.
    $m = $script:Manifest
    $old = Join-Path $PackagesDir $m.old.file
    $src = Join-Path $PackagesDir $m.new.file
    function Try-Tampered([string]$entry, [string]$tag, [switch]$ChangedBlock) {
        [void](Stop-AppGracefully)
        [void](Remove-PkgKeepData)
        Add-AppxPackage -Path $old
        $o = $(if ($ChangedBlock) { Get-ZipEntryChangedBlockOffset -Path $src -OldPath $old -EntryName $entry } else { Get-ZipEntryMidOffset -Path $src -EntryName $entry })
        $bad = Join-Path $WorkDir ('tampered-' + $tag + '.msix')
        Copy-Item -LiteralPath $src -Destination $bad -Force
        $bytes = [System.IO.File]::ReadAllBytes($bad)
        $b0 = $bytes[$o.offset]
        $bytes[$o.offset] = $b0 -bxor 0x01
        [System.IO.File]::WriteAllBytes($bad, $bytes)
        $rej = $false; $msg = ''; $hr = ''
        try { Add-AppxPackage -Path $bad } catch { $rej = $true; $msg = $_.Exception.Message; $hr = ('0x{0:X8}' -f $_.Exception.HResult) }
        return @{ entry = $entry; offset = [string]$o.offset; block = [string]$o.block; changed_blocks = [string]$o.changed_blocks; byte_before = ('{0:x2}' -f $b0); byte_after = ('{0:x2}' -f $bytes[$o.offset]); rejected = $rej; error = $msg; hresult = $hr; version_after = (Get-VersionString); sha = (Get-Sha256Ref -Path $bad) }
    }
    $a = Try-Tampered -entry '_FoundationICU.dll' -tag 'unchanged-entry'
    $b = Try-Tampered -entry 'SliceApp.exe' -tag 'changed-entry' -ChangedBlock
    $verBefore = [string]$m.old.version
    $goodErr = ''
    try { Add-AppxPackage -Path $src } catch { $goodErr = $_.Exception.Message }
    $verFinal = Get-VersionString
    $inUse = ($b.error -match '0x80073D02')
    $observed = @{
        changed_entry = $b.entry; flipped_offset = $b.offset; flipped_block = $b.block; changed_blocks = $b.changed_blocks; byte_before = $b.byte_before; byte_after = $b.byte_after
        rejected = [string]$b.rejected; refusal_is_in_use = [string]$inUse; hresult = $b.hresult; error = $b.error
        version_before = $verBefore; version_after_tampered = $b.version_after
        genuine_update_error = $goodErr; version_after_genuine_update = $verFinal
        info_unchanged_entry = $a.entry; info_unchanged_rejected = [string]$a.rejected; info_unchanged_version_after = $a.version_after; info_unchanged_error = $a.error
    }
    $pass = $b.rejected -and (-not $inUse) -and ($b.version_after -eq $verBefore) -and ($goodErr -eq '') -and ($verFinal -eq [string]$m.new.version)
    @{ pass = $pass; reason = 'tampered changed-entry package accepted, refused only because the app was in use, installed version changed, or the genuine update failed'; observed = $observed; artifacts = @{ tampered_msix = $b.sha }; exit = $null }
}

# W08: real interrupted update (Sandbox guest only; R5 final). The earlier AppXSvc kill is gone: the service host is protected and Stop-Service lets the
# deployment finish. Interruption now comes from the deployment CLIENT, at a measured point (scripts\interrupt-windows-install.ps1):
#   KillClient      Stop-Process -Force on the powershell.exe that runs `Add-AppxPackage <new>`, when the new version's staging directory appears;
#   CancelOperation the documented WinRT route: PackageManager.AddPackageAsync(<new>) cancelled with IAsyncInfo.Cancel() at the same point.
# Eleven cases (2 client kills, 9 cancels at different phases of the ~0.5 s deployment). An interruption is GENUINE when the client/operation was alive at the interrupt, the
# deployment was demonstrably under way, and the new version is not registered afterwards (if the service completed the update anyway, only the client was
# interrupted: `completed-anyway`). Every genuine interruption is then judged: exactly one version registered (the old one), data byte-identical, that
# build launches, and a second Add-AppxPackage registers the new version with status Ok (a non-Ok status right after the interrupt, e.g.
# NeedsRemediation, is recorded in status_not_ok_after_interrupt). Verdicts: PASS = at least one genuine interruption and every one judged ok;
# FAIL = a genuine interruption left a bad state; NOT-DEMONSTRABLE = no method ever interrupted the update (evidence: per-case timelines and
# deployment-service events in receipts\evidence-W08-*.json).
# No reboot, no service kill, no guest power loss (Sandbox state is discarded on close, so a power-off could not be inspected).
Invoke-Check -CheckId 'W08-interrupted-update' -CheckName 'Interrupted update (deployment client killed / operation cancelled mid-deployment): state, data, launch, recovery per interruption' -Body {
    $m = $script:Manifest
    $old = Join-Path $PackagesDir $m.old.file
    $new = Join-Path $PackagesDir $m.new.file
    $script08 = Join-Path $script:SliceDir 'scripts\interrupt-windows-install.ps1'
    [void](Stop-AppGracefully)
    $shaBefore = Get-RowsSha
    $cases = @(
        @{ mode = 'KillClient'; trigger = 'staging'; delay = 0 }, @{ mode = 'KillClient'; trigger = 'staging'; delay = 150 },
        @{ mode = 'CancelOperation'; trigger = 'staging'; delay = 0 }, @{ mode = 'CancelOperation'; trigger = 'staging'; delay = 160 },
        @{ mode = 'CancelOperation'; trigger = 'staging'; delay = 200 }, @{ mode = 'CancelOperation'; trigger = 'staging'; delay = 240 },
        @{ mode = 'CancelOperation'; trigger = 'staging'; delay = 280 }, @{ mode = 'CancelOperation'; trigger = 'staging'; delay = 300 },
        @{ mode = 'CancelOperation'; trigger = 'staging'; delay = 320 }, @{ mode = 'CancelOperation'; trigger = 'staging'; delay = 360 },
        @{ mode = 'CancelOperation'; trigger = 'start'; delay = 0 }
    )
    $obs = @{}; $lines = @(); $json = @()
    $genuineCount = 0; $genuineOk = 0; $killAnyway = 0; $statusNotOk = @(); $badCases = @()
    $i = 0
    foreach ($c in $cases) {
        $i++
        $cid = ('c' + $i + '-' + $c.mode + '-' + $c.trigger + '+' + $c.delay + 'ms')
        [void](Stop-AppGracefully)
        [void](Remove-PkgKeepData)
        $resFile = Join-Path $WorkDir ('interrupt-' + $cid + '.json')
        Remove-Item -LiteralPath $resFile -ErrorAction SilentlyContinue
        $r = Invoke-ChildPs -PsArgs @('-File', $script08, '-OldMsix', $old, '-NewMsix', $new, '-Mode', $c.mode, '-Trigger', $c.trigger, '-ExtraDelayMs', [string]$c.delay, '-ResultJson', $resFile, '-DisposableGuest')
        if (-not (Test-Path -LiteralPath $resFile)) { $lines += ($cid + ': script wrote no result: ' + $r.out); $badCases += $cid; continue }
        Copy-Item -LiteralPath $resFile -Destination (Join-Path $ReceiptsDir ('evidence-W08-' + $cid + '.json')) -Force
        $res = Get-Content -Raw -LiteralPath $resFile | ConvertFrom-Json
        $att = @($res.attempts)[0]
        $case = [ordered]@{ id = $cid; interrupted = [bool]$att.interrupted; client_alive = [bool]$att.client_alive_at_interrupt; outcome = [string]$att.outcome; registered_after = [string]$att.registered_after; failed_to_reach_state = [string]$att.failed_to_reach_state; t_trigger_ms = [int]$att.t_trigger_ms; t_interrupt_ms = [int]$att.t_interrupt_ms }
        if ($c.mode -eq 'KillClient' -and $att.client_alive_at_interrupt -and $att.outcome -eq 'completed-anyway') { $killAnyway++ }
        if ($att.interrupted) {
            $genuineCount++
            # Judge this interruption: live registration, data, launch of the registered build, then a second update.
            $pk = @(Get-AppxPackage -Name $m.identity_name -ErrorAction SilentlyContinue)
            $allUsers = @(Get-AppxPackage -AllUsers -Name $m.identity_name -ErrorAction SilentlyContinue)
            $oneRegistered = ($pk.Count -eq 1) -and ($allUsers.Count -le 1)
            $verAfter = $(if ($oneRegistered) { [string]$pk[0].Version } else { 'none-or-many' })
            $statusAfter = $(if ($oneRegistered) { [string]$pk[0].Status } else { 'n/a' })
            $shaAfterInterrupt = Get-RowsSha
            $launched = $false; $launchErr = ''
            if ($oneRegistered) {
                try { $w = Start-AppAndFindWindow -TimeoutSec 40; $launched = ($w.window_name -ne '') } catch { $launchErr = $_.Exception.Message }
                [void](Stop-AppGracefully)
            }
            if ($script:HoldOpenMinutes -gt 0 -and -not $script:HoldOpenDone -and $oneRegistered -and ($statusAfter -ne 'Ok')) {
                # Hold-open: only after the launch attempt above and before the second update, once per run, and never part of the verdict.
                $script:HoldOpenDone = $true
                $holdObs = @(Invoke-RepairHoldOpen -CaseId $cid -Minutes $script:HoldOpenMinutes) | Where-Object { $_ -is [hashtable] } | Select-Object -Last 1
                if ($holdObs) { foreach ($hk in $holdObs.Keys) { $obs[$hk] = $holdObs[$hk] } }
            }
            $rerunErr = ''
            try { Add-AppxPackage -Path $new -ErrorAction Stop } catch { $rerunErr = $_.Exception.Message }
            $verRerun = Get-VersionString
            $pk2 = @(Get-AppxPackage -Name $m.identity_name -ErrorAction SilentlyContinue)
            $statusRerun = $(if ($pk2.Count -eq 1) { [string]$pk2[0].Status } else { 'n/a' })
            $shaFinal = Get-RowsSha
            $ok = $oneRegistered -and ($verAfter -eq [string]$m.old.version) -and ($shaAfterInterrupt -eq $shaBefore) -and $launched -and ($rerunErr -eq '') -and ($verRerun -eq [string]$m.new.version) -and ($statusRerun -eq 'Ok') -and ($shaFinal -eq $shaBefore)
            if ($statusAfter -ne 'Ok') { $statusNotOk += ($cid + ':' + $statusAfter) }
            $case['one_registered'] = $oneRegistered; $case['version_after_interrupt'] = $verAfter; $case['status_after_interrupt'] = $statusAfter
            $case['data_intact'] = ($shaAfterInterrupt -eq $shaBefore); $case['launched'] = $launched; $case['launch_error'] = $launchErr
            $case['rerun_error'] = $rerunErr; $case['version_after_rerun'] = $verRerun; $case['status_after_rerun'] = $statusRerun; $case['data_intact_final'] = ($shaFinal -eq $shaBefore); $case['ok'] = $ok
            if ($ok) { $genuineOk++ } else { $badCases += $cid }
        }
        $json += $case
        $lines += ($cid + ': ' + $(if ($att.interrupted) { 'INTERRUPTED' } else { 'not interrupted' }) + ' outcome=' + $att.outcome + ' registered=' + $att.registered_after + $(if ($att.failed_to_reach_state) { ' failed-to-reach=' + $att.failed_to_reach_state } else { '' }) + $(if ($att.interrupted) { ' launched=' + $case['launched'] + ' rerun=' + $case['version_after_rerun'] + '/' + $case['status_after_rerun'] + ' ok=' + $case['ok'] } else { '' }))
    }
    $obs['rows_sha_before'] = $shaBefore
    $obs['cases'] = ($lines -join ' || ')
    $obs['cases_json'] = ($json | ConvertTo-Json -Depth 4 -Compress)
    $obs['genuine_interruptions'] = [string]$genuineCount
    $obs['genuine_interruptions_ok'] = [string]$genuineOk
    $obs['killclient_alive_then_completed_anyway'] = [string]$killAnyway
    $obs['status_not_ok_after_interrupt'] = ($statusNotOk -join ',')
    $obs['bad_cases'] = ($badCases -join ',')
    $obs['final_registered_version'] = Get-VersionString
    if ($genuineCount -eq 0) {
        return @{ pass = $false; verdict = 'NOT-DEMONSTRABLE'; reason = ('no method interrupted the update in flight (every attempt ended completed-anyway, or the trigger never landed): ' + ($lines -join ' || ')); observed = $obs; artifacts = @{ new_msix = (Get-Sha256Ref -Path $new) }; exit = $null }
    }
    $pass = ($badCases.Count -eq 0) -and ($genuineOk -eq $genuineCount)
    @{ pass = $pass; reason = ('an interruption left a bad state: ' + ($badCases -join ',') + ' (not exactly one old version registered, data changed, the build did not launch, or the second update did not register the new version with status Ok)'); observed = $obs; artifacts = @{ new_msix = (Get-Sha256Ref -Path $new) }; exit = $null }
}

# W08b: update while the app is running. Add-AppxPackage -DeferRegistrationWhenPackagesAreInUse must leave the old version
# registered while the app runs, and the update must apply on a later launch (Microsoft Learn, Add-AppxPackage).
Invoke-Check -CheckId 'W14-deferred-update-in-use' -CheckName 'Update deferred while the app runs; applies on next launch' -Body {
    $m = $script:Manifest
    $old = Join-Path $PackagesDir $m.old.file
    $new = Join-Path $PackagesDir $m.new.file
    [void](Stop-AppGracefully)
    [void](Remove-PkgKeepData)
    Add-AppxPackage -Path $old
    $shaBefore = Get-RowsSha
    $w = Start-AppAndFindWindow -TimeoutSec 40
    $addErr = ''
    try { Add-AppxPackage -Path $new -DeferRegistrationWhenPackagesAreInUse } catch { $addErr = $_.Exception.Message }
    $versionWhileRunning = Get-VersionString
    $stillRunning = (@(Get-AppProcesses).Count -gt 0)
    [void](Stop-AppGracefully)
    $w2 = Start-AppAndFindWindow -TimeoutSec 40
    $versionAfterRelaunch = Wait-PkgVersion -Version ([string]$m.new.version) -TimeoutSec 90
    [void](Stop-AppGracefully)
    $shaAfter = Get-RowsSha
    $observed = @{ add_error = $addErr; version_while_running = $versionWhileRunning; app_still_running = [string]$stillRunning; version_after_relaunch = $versionAfterRelaunch; rows_sha_before = $shaBefore; rows_sha_after = $shaAfter }
    $pass = ($addErr -eq '') -and ($versionWhileRunning -eq [string]$m.old.version) -and $stillRunning -and ($versionAfterRelaunch -eq [string]$m.new.version) -and ($shaBefore -eq $shaAfter)
    @{ pass = $pass; reason = 'update was not deferred while running, did not apply after relaunch, or data changed'; observed = $observed; artifacts = @{ new_msix = (Get-Sha256Ref -Path $new) }; exit = $null }
}


# W09: rollback. Remove the new package keeping data, install the old build, and check it reads the new data.
Invoke-Check -CheckId 'W09-rollback-readable' -CheckName 'Old build reads data written by new build' -Body {
    $m = $script:Manifest
    $old = Join-Path $PackagesDir $m.old.file
    [void](Stop-AppGracefully)
    $pkg = Get-Pkg
    if ($pkg) { Remove-AppxPackage -Package $pkg.PackageFullName }   # PATCH-2
    $st = Get-DataState
    $preserved = ($null -ne $st.found)
    Add-AppxPackage -Path $old
    $ver = [string](Get-Pkg).Version
    $w = Start-AppAndFindWindow -TimeoutSec 40
    $vals = Read-RowValues -Root (Get-AppRoot -ProcessId $w.pid)
    $marker = 'rightkit-check-' + $script:RunId
    $shown = ($vals -contains $marker) -and ($vals -contains ('rightkit-new-' + $script:RunId))
    $schemaOk = $false
    if ($st.found) { $schemaOk = Test-RowsSchema1 -Path $st.found.path }
    $observed = @{ data_preserved_on_remove = [string]$preserved; old_version = $ver; marker_shown_by_old = [string]$shown; schema_1_after_old_launch = [string]$schemaOk }
    foreach ($k in $st.observed.Keys) { $observed[$k] = $st.observed[$k] }
    $pass = $preserved -and ($ver -eq [string]$m.old.version) -and $shown -and $schemaOk
    @{ pass = $pass; reason = 'rollback: data not preserved, old version wrong, marker not shown, or schema differs'; observed = $observed; artifacts = @{}; exit = 0 }
}

# W10: uninstall keeps user data at the physical path; the data hash must match the rollback state.
Invoke-Check -CheckId 'W10-uninstall-keeps-data' -CheckName 'Uninstall keeps rows.json (preserve flag)' -Body {
    [void](Stop-AppGracefully)
    $before = Get-DataState
    $bsha = $(if ($before.found) { Get-Sha256Ref -Path $before.found.path } else { 'missing' })
    $pkg = Get-Pkg
    if ($pkg) { Remove-AppxPackage -Package $pkg.PackageFullName }   # PATCH-2
    $gone = -not (Get-Pkg)
    $after = Get-DataState
    $asha = $(if ($after.found) { Get-Sha256Ref -Path $after.found.path } else { 'missing' })
    $observed = @{ package_removed = [string]$gone; sha_before = [string]$bsha; sha_after = [string]$asha; preserve_flag = 'plain Remove-AppxPackage (physical-path data is not package data)' }
    foreach ($k in $after.observed.Keys) { $observed[$k] = $after.observed[$k] }
    $pass = $gone -and ($bsha -ne 'missing') -and ($bsha -eq $asha)
    @{ pass = $pass; reason = 'package not removed or rows.json missing or changed'; observed = $observed; artifacts = @{ rows_json = $asha }; exit = 0 }
}

# W11: virtualization / physical paths (F8) and legacy data. Fresh profile: the file the packaged app created (W05) sits at
# %LOCALAPPDATA%\SliceApp\rows.json and no copy exists under Packages\<PFN>\LocalCache\Local\SliceApp. Legacy: with the
# package removed, a rows.json written by a NON-package process (the W05 file with its marker rewritten) is pre-placed; the
# reinstalled package must read it from the physical path, write the next change back to the same file, and still create
# no LocalCache copy. The installed manifest must declare FileSystemWriteVirtualization=disabled and unvirtualizedResources.
Invoke-Check -CheckId 'W11-legacy-data-physical-path' -CheckName 'Physical data path (fresh + legacy); virtualization disabled' -Body {
    $m = $script:Manifest
    $old = Join-Path $PackagesDir $m.old.file
    [void](Stop-AppGracefully)
    $rowsPath = Join-Path $script:LocalAppData 'rows.json'
    $freshExists = Test-Path -LiteralPath $rowsPath -PathType Leaf
    # W10 left the package removed and rows.json in place: this is the fresh-profile file, hash it, then rewrite as legacy.
    $freshText = Get-RowsText -Path $rowsPath
    $marker = 'rightkit-check-' + $script:RunId
    $legacyMarker = 'legacy-' + $script:RunId
    if (-not $freshText -or -not $freshText.Contains($marker)) { throw 'W05 marker not in rows.json; cannot derive the legacy file' }
    Add-AppxPackage -Path $old
    $manifestText = Get-Content -Raw -LiteralPath (Join-Path (Get-Pkg).InstallLocation 'AppxManifest.xml')
    $virtOff = ($manifestText -match 'FileSystemWriteVirtualization>\s*disabled\s*<')
    $unvirt = ($manifestText -match 'unvirtualizedResources')
    $noCacheFresh = Test-NoLocalCacheCopy
    [void](Remove-PkgKeepData)
    $legacyText = $freshText.Replace($marker, $legacyMarker)
    [System.IO.File]::WriteAllText($rowsPath, $legacyText, $Utf8)
    $legacySha = Get-Sha256Ref -Path $rowsPath
    Add-AppxPackage -Path $old
    $w = Start-AppAndFindWindow -TimeoutSec 40
    $root = Get-AppRoot -ProcessId $w.pid
    $vals = Read-RowValues -Root $root
    $shown = ($vals -contains $legacyMarker)
    $edit = 'edit-after-legacy-' + $script:RunId
    [void](Write-MarkerRow -Root $root -Marker $edit)
    $landed = $null
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline -and -not $landed) {
        $t = Get-RowsText -Path $rowsPath
        if ($t -and $t.Contains($edit)) { $landed = $true }
        Start-Sleep -Milliseconds 500
    }
    [void](Stop-AppGracefully)
    $noCacheLegacy = Test-NoLocalCacheCopy
    $observed = @{
        fresh_file_existed_at_physical_path = [string]$freshExists
        manifest_filesystem_write_virtualization_disabled = [string]$virtOff
        manifest_unvirtualized_resources = [string]$unvirt
        no_localcache_copy_fresh = [string]$noCacheFresh
        legacy_file_sha = $legacySha; legacy_marker_shown_by_app = [string]$shown
        edit_landed_at_physical_path = [string]($null -ne $landed)
        no_localcache_copy_after_legacy = [string]$noCacheLegacy
        rows_sha_final = (Get-RowsSha)
    }
    $pass = $freshExists -and $virtOff -and $unvirt -and $noCacheFresh -and $shown -and ($null -ne $landed) -and $noCacheLegacy
    @{ pass = $pass; reason = 'physical-path, virtualization manifest, or legacy-read check failed'; observed = $observed; artifacts = @{ rows_json_legacy = $legacySha }; exit = $null }
}

# W12: real App Installer route over a local https feed served INSIDE the guest (loopback; the .wsb has networking disabled,
# loopback is used on purpose and W12 records whether it works). Feed files come from RightKit's generator on the host side
# (scripts\make-local-appinstaller.mjs), staged as packages\feed\. Steps: install via the feed (0.1.0.0), swap the feed for
# 0.1.1.0, relaunch (OnLaunch, HoursBetweenUpdateChecks=0), expect 0.1.1.0 to register with rows.json unchanged. Negative:
# a feed whose MainPackage Publisher differs from the package must fail to install.
Invoke-Check -CheckId 'W12-appinstaller-update' -CheckName 'App Installer feed install + OnLaunch update; mismatched feed rejected' -Body {
    $m = $script:Manifest
    $feedSrc = Join-Path $PackagesDir 'feed'
    $feed = 'C:\feed'
    [void](Stop-AppGracefully)
    [void](Remove-PkgKeepData)
    if (Test-Path -LiteralPath $feed) { Remove-Item -LiteralPath $feed -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $feed | Out-Null
    Get-ChildItem -LiteralPath $feedSrc -Filter '*.msix' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $feed -Force }
    Copy-Item -LiteralPath (Join-Path $feedSrc 'SliceApp.0.appinstaller') -Destination (Join-Path $feed 'SliceApp.appinstaller') -Force
    $server = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $script:SliceDir 'scripts\serve-local-feed.ps1'), '-Dir', $feed, '-DisposableGuest')
    $url = 'https://localhost:8443/sliceapp/SliceApp.appinstaller'
    try {
        $up = $false
        $deadline = (Get-Date).AddSeconds(40)
        while ((Get-Date) -lt $deadline -and -not $up) {
            try { $up = ((Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200) } catch { Start-Sleep -Seconds 2 }
        }
        if (-not $up) { throw 'local feed did not come up (loopback https unreachable in the guest)' }
        # Negative first (clean slate): publisher mismatch.
        $bad = (Get-Content -Raw -LiteralPath (Join-Path $feed 'SliceApp.appinstaller')) -replace 'Publisher="CN=Damned Ventures LLC', 'Publisher="CN=Not The Signer'
        [System.IO.File]::WriteAllText((Join-Path $feed 'SliceApp.appinstaller'), $bad, $Utf8)
        $negRejected = $false; $negMsg = ''
        $ni = Invoke-AppInstallerBounded -Url $url -TimeoutSec 90
        if ($ni.timed_out) { $negMsg = 'negative feed install did not return within 90 s' } elseif ($ni.result -ne 'OK') { $negRejected = $true; $negMsg = $ni.result }
        $negNotInstalled = (-not (Get-Pkg))
        # Positive: the 0.1.0.0 feed.
        Copy-Item -LiteralPath (Join-Path $feedSrc 'SliceApp.0.appinstaller') -Destination (Join-Path $feed 'SliceApp.appinstaller') -Force
        $installErr = ''
        $installTimedOut = $false
        $ai = Invoke-AppInstallerBounded -Url $url -TimeoutSec 120
        if ($ai.timed_out) { $installTimedOut = $true; $installErr = 'Add-AppxPackage -AppInstallerFile did not return within 120 s' } elseif ($ai.result -ne 'OK') { $installErr = $ai.result }
        if ($installTimedOut -or $installErr) {
            $feedLog = ''
            try { $feedLog = ((Get-Content -LiteralPath (Join-Path $env:TEMP 'serve-local-feed.log') -ErrorAction Stop | Select-Object -Last 12) -join ' | ') } catch { $feedLog = 'no feed log' }
            return @{ pass = $false; reason = ('App Installer feed install failed: ' + $installErr); observed = @{ feed_url = $url; negative_publisher_mismatch_rejected = [string]$negRejected; negative_error = $negMsg; negative_left_nothing_installed = [string]$negNotInstalled; install_timed_out = [string]$installTimedOut; install_error = $installErr; installed_version_after = (Get-VersionString); feed_server_log_tail = $feedLog }; artifacts = @{}; exit = $null }
        }
        $v0 = Get-VersionString
        if ($v0 -ne [string]$m.old.version) {
            $feedLog2 = ''
            try { $feedLog2 = ((Get-Content -LiteralPath (Join-Path $env:TEMP 'serve-local-feed.log') -ErrorAction Stop | Select-Object -Last 12) -join ' | ') } catch { $feedLog2 = 'no feed log' }
            return @{ pass = $false; reason = ('App Installer install returned without registering the package (version ' + $v0 + ')'); observed = @{ feed_url = $url; negative_publisher_mismatch_rejected = [string]$negRejected; negative_error = $negMsg; negative_left_nothing_installed = [string]$negNotInstalled; install_result = [string]$ai.result; version_after_feed_install = $v0; feed_server_log_tail = $feedLog2 }; artifacts = @{}; exit = $null }
        }
        $w = Start-AppAndFindWindow -TimeoutSec 40
        $shaBefore = Get-RowsSha
        [void](Stop-AppGracefully)
        # Publish the update and relaunch (OnLaunch check); the update may apply on this or the next launch.
        Copy-Item -LiteralPath (Join-Path $feedSrc 'SliceApp.1.appinstaller') -Destination (Join-Path $feed 'SliceApp.appinstaller') -Force
        $v1 = Get-VersionString
        for ($i = 0; $i -lt 3 -and $v1 -ne [string]$m.new.version; $i++) {
            $w = Start-AppAndFindWindow -TimeoutSec 40
            $v1 = Wait-PkgVersion -Version ([string]$m.new.version) -TimeoutSec 45
            [void](Stop-AppGracefully)
            if ($v1 -ne [string]$m.new.version) { Start-Sleep -Seconds 5; $v1 = Get-VersionString }
        }
        $shaAfter = Get-RowsSha
        $observed = @{
            feed_url = $url; negative_publisher_mismatch_rejected = [string]$negRejected; negative_error = $negMsg
            negative_left_nothing_installed = [string]$negNotInstalled; install_error = $installErr
            version_after_feed_install = $v0; version_after_update_feed = $v1; rows_sha_before = $shaBefore; rows_sha_after = $shaAfter
        }
        $pass = $negRejected -and $negNotInstalled -and ($installErr -eq '') -and ($v0 -eq [string]$m.old.version) -and ($v1 -eq [string]$m.new.version) -and ($shaBefore -eq $shaAfter)
        @{ pass = $pass; reason = 'feed install/update did not reach the new version, data changed, or the mismatched feed was accepted'; observed = $observed; artifacts = @{}; exit = $null }
    }
    finally {
        if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
    }
}


# ---------------------------------------------------------------- run summary

$checks = @($script:Results | ForEach-Object { @{ check_id = $_.check_id; status = $_.status; implemented = $_.implemented } })
$missing = @($RunChecks | Where-Object { $id = $_; -not ($script:Results | Where-Object { $_.check_id -eq $id }) })
$notPassing = @($script:Results | Where-Object { $_.status -ne 'pass' -or -not $_.implemented } | ForEach-Object { $_.check_id })
$ok = ($missing.Count -eq 0) -and ($notPassing.Count -eq 0)
$reason = $null
if (-not $ok) {
    $parts = @()
    if ($missing.Count -gt 0) { $parts += ('missing receipts: ' + ($missing -join ', ')) }
    if ($notPassing.Count -gt 0) { $parts += ('not passing: ' + ($notPassing -join ', ')) }
    $reason = ($parts -join '; ')
}
$summary = [ordered]@{
    schema = 'sr0-a.package-receipt/v2'
    record = 'run'
    product = 'SliceApp'
    platform = 'windows-x64'
    run_id = $script:RunId
    status = $(if ($ok) { 'pass' } else { 'fail' })
    expected_checks = $RunChecks
    checks = $checks
    started_utc = $script:RunStarted
    ended_utc = Get-UtcStamp
    reason = $reason
    artifact_ids = @{}
    harness = [ordered]@{ name = $HarnessName; sha256 = (Get-Sha256Ref -Path $HarnessPath) }
}
[System.IO.File]::WriteAllText((Join-Path $ReceiptsDir 'guest-run.json'), ($summary | ConvertTo-Json -Depth 8), $Utf8)
Write-Output ('run ' + $script:RunId + ': ' + $summary.status + $(if ($reason) { ' (' + $reason + ')' } else { '' }))
# No `wsb` CLI on this host (Windows Sandbox started through WindowsSandbox.exe has no id to stop), so the guest ends itself
# once the receipts are flushed to the mapped folder; the host verdict only needs the files.
Start-Sleep -Seconds 10
Stop-Computer -Force
