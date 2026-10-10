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

$ExpectedChecks = @(
    'W00-environment', 'W01-artifacts-bound', 'W02-signer-trust', 'W03-install-old',
    'W04-launch-offline-old', 'W05-write-data', 'W06-upgrade-new', 'W07-corrupt-update-rejected',
    'W08-interrupted-update', 'W09-rollback-readable', 'W10-uninstall-keeps-data',
    'W11-legacy-data-physical-path', 'W12-appinstaller-update', 'W13-renderer-layout-installed',
    'W14-deferred-update-in-use'
)

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
    Start-Sleep -Seconds 1
    $rows = @(Find-RowFields -Root $Root)
    if ($rows.Count -eq 0) { throw 'no "Row" text fields found after insert' }
    # Insert above adds an EMPTY row (EditorModel.insertAbove); write into it so earlier markers are never overwritten.
    $target = $null
    foreach ($r in $rows) {
        $v = $r.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        if ([string]$v.Current.Value -eq '') { $target = $r; break }
    }
    if (-not $target) { throw 'no empty Row field after Insert above' }
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

# ---------------------------------------------------------------- start

if (-not (Test-Path -LiteralPath $ReceiptsDir)) { throw "receipts folder not mapped: $ReceiptsDir" }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$script:Manifest = $null
$manifestPath = Join-Path $PackagesDir 'manifest.json'
if (Test-Path -LiteralPath $manifestPath) {
    $script:Manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
}
$script:RunId = $(if ($script:Manifest) { [string]$script:Manifest.run_id } else { 'unknown-no-manifest' })
$script:RunStarted = Get-UtcStamp

# W00: environment. Offline must be real (no default route) and the logon must be elevated.
Invoke-Check -CheckId 'W00-environment' -CheckName 'Sandbox environment, elevation, offline' -Body {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $defaultRoutes = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue).Count
    $adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $observed = @{
        elevated = [string]$elevated
        default_routes = [string]$defaultRoutes
        adapters = ($adapters -join ',')
        manifest_present = [string]($null -ne $script:Manifest)
    }
    $pass = $elevated -and ($defaultRoutes -eq 0) -and ($null -ne $script:Manifest)
    @{ pass = $pass; reason = 'need elevated, no default route, and a manifest'; observed = $observed; artifacts = @{}; exit = $null }
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
    @{ pass = $pass; reason = 'window has no name'; observed = @{ renderer_module_loaded_from = $rmod; window_name = [string]$w.window_name; pid = [string]$w.pid; network_default_routes = [string](@(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue).Count) }; artifacts = @{}; exit = $null }
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
    # PATCH-4. Original ran with the NEW build installed and running: the refusal was 0x80073D02 (in use), not corruption, and its flipped byte sat in
    # _FoundationICU.dll, a payload file identical in old and new. An update over the old build reuses unchanged blocks from the installed copy (differential
    # update), so a flip there is never read. Now: app closed, OLD installed; (a, informational) flip inside the unchanged ICU entry; (b, the check) flip inside
    # SliceApp.exe, a file that differs old->new, must be refused for a non-in-use reason with OLD still registered; then the genuine NEW must apply.
    $m = $script:Manifest
    $old = Join-Path $PackagesDir $m.old.file
    $src = Join-Path $PackagesDir $m.new.file
    function Try-Tampered([string]$entry, [string]$tag) {
        [void](Stop-AppGracefully)
        [void](Remove-PkgKeepData)
        Add-AppxPackage -Path $old
        $o = Get-ZipEntryMidOffset -Path $src -EntryName $entry
        $bad = Join-Path $WorkDir ('tampered-' + $tag + '.msix')
        Copy-Item -LiteralPath $src -Destination $bad -Force
        $bytes = [System.IO.File]::ReadAllBytes($bad)
        $b0 = $bytes[$o.offset]
        $bytes[$o.offset] = $b0 -bxor 0x01
        [System.IO.File]::WriteAllBytes($bad, $bytes)
        $rej = $false; $msg = ''; $hr = ''
        try { Add-AppxPackage -Path $bad } catch { $rej = $true; $msg = $_.Exception.Message; $hr = ('0x{0:X8}' -f $_.Exception.HResult) }
        return @{ entry = $entry; offset = [string]$o.offset; byte_before = ('{0:x2}' -f $b0); byte_after = ('{0:x2}' -f $bytes[$o.offset]); rejected = $rej; error = $msg; hresult = $hr; version_after = (Get-VersionString); sha = (Get-Sha256Ref -Path $bad) }
    }
    $a = Try-Tampered -entry '_FoundationICU.dll' -tag 'unchanged-entry'
    $b = Try-Tampered -entry 'SliceApp.exe' -tag 'changed-entry'
    $verBefore = [string]$m.old.version
    $goodErr = ''
    try { Add-AppxPackage -Path $src } catch { $goodErr = $_.Exception.Message }
    $verFinal = Get-VersionString
    $inUse = ($b.error -match '0x80073D02')
    $observed = @{
        changed_entry = $b.entry; flipped_offset = $b.offset; byte_before = $b.byte_before; byte_after = $b.byte_after
        rejected = [string]$b.rejected; refusal_is_in_use = [string]$inUse; hresult = $b.hresult; error = $b.error
        version_before = $verBefore; version_after_tampered = $b.version_after
        genuine_update_error = $goodErr; version_after_genuine_update = $verFinal
        info_unchanged_entry = $a.entry; info_unchanged_rejected = [string]$a.rejected; info_unchanged_version_after = $a.version_after; info_unchanged_error = $a.error
    }
    $pass = $b.rejected -and (-not $inUse) -and ($b.version_after -eq $verBefore) -and ($goodErr -eq '') -and ($verFinal -eq [string]$m.new.version)
    @{ pass = $pass; reason = 'tampered changed-entry package accepted, refused only because the app was in use, installed version changed, or the genuine update failed'; observed = $observed; artifacts = @{ tampered_msix = $b.sha }; exit = $null }
}

# W08: real interrupted update (Sandbox guest only). Fault injection: AppXSvc is stopped while Add-AppxPackage deploys the
# new package (scripts\interrupt-windows-install.ps1 -Mode KillDeployment). Valid only if the stop landed mid-flight and the
# cmdlet failed. Pass = exactly one version registered with status Ok (no none/both/partial), data byte-identical, the
# registered build launches, and a rerun of the update registers the new version. Not a Microsoft-documented procedure.
Invoke-Check -CheckId 'W08-interrupted-update' -CheckName 'Interrupted update (AppXSvc stopped mid-deployment): consistent state, data intact, recovery' -Body {
    $m = $script:Manifest
    $old = Join-Path $PackagesDir $m.old.file
    $new = Join-Path $PackagesDir $m.new.file
    [void](Stop-AppGracefully)
    $shaBefore = Get-RowsSha
    $removed = Remove-PkgKeepData
    $resFile = Join-Path $WorkDir 'interrupt-kill.json'
    Remove-Item -LiteralPath $resFile -ErrorAction SilentlyContinue
    $r = Invoke-ChildPs -PsArgs @('-File', (Join-Path $script:SliceDir 'scripts\interrupt-windows-install.ps1'), '-OldMsix', $old, '-NewMsix', $new, '-Mode', 'KillDeployment', '-ResultJson', $resFile, '-DisposableGuest')
    if (-not (Test-Path -LiteralPath $resFile)) { throw ('interrupt script wrote no result: ' + $r.out) }
    $res = Get-Content -Raw -LiteralPath $resFile | ConvertFrom-Json
    $after = $res.states | Where-Object { $_.when -eq 'after interrupt' } | Select-Object -Last 1
    $oneRegistered = ($after.registered_count -eq 1) -and ($after.all_users_count -le 1)
    $statusOk = $oneRegistered -and ([string]$after.registered[0].status -eq 'Ok')
    $versionAfter = $(if ($oneRegistered) { [string]$after.registered[0].version } else { 'none-or-many' })
    $oneOfTwo = ($versionAfter -eq [string]$m.old.version) -or ($versionAfter -eq [string]$m.new.version)
    $shaAfterInterrupt = Get-RowsSha
    # The registered build must launch.
    $launched = $false; $launchErr = ''
    if ($oneRegistered) {
        try { $w = Start-AppAndFindWindow -TimeoutSec 40; $launched = ($w.window_name -ne '') } catch { $launchErr = $_.Exception.Message }
        [void](Stop-AppGracefully)
    }
    # Recovery: rerun the update; the new version must register.
    $rerunErr = ''
    try { Add-AppxPackage -Path $new } catch { $rerunErr = $_.Exception.Message }
    $versionRerun = Get-VersionString
    $shaFinal = Get-RowsSha
    $observed = @{
        removed_before = [string]$removed; interrupt_valid = [string]$res.valid; stopped_in_flight = [string]$res.stopped_in_flight
        job_state = [string]$res.job_state; job_error = [string]$res.job_error
        registered_count_after_interrupt = [string]$after.registered_count; all_users_count_after_interrupt = [string]$after.all_users_count
        status_after_interrupt = $(if ($oneRegistered) { [string]$after.registered[0].status } else { 'n/a' })
        version_after_interrupt = $versionAfter
        rows_sha_before = $shaBefore; rows_sha_after_interrupt = $shaAfterInterrupt; rows_sha_after_rerun = $shaFinal
        launched_after_interrupt = [string]$launched; launch_error = $launchErr
        rerun_error = $rerunErr; version_after_rerun = $versionRerun; script_output = $r.out
    }
    $pass = [bool]$res.valid -and $oneRegistered -and $statusOk -and $oneOfTwo -and ($shaBefore -eq $shaAfterInterrupt) -and $launched -and ($versionRerun -eq [string]$m.new.version)
    @{ pass = $pass; reason = 'run invalid (not interrupted in flight), inconsistent registration, data changed, build did not launch, or rerun did not register the new version'; observed = $observed; artifacts = @{ new_msix = (Get-Sha256Ref -Path $new) }; exit = $r.exit }
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
$missing = @($ExpectedChecks | Where-Object { $id = $_; -not ($script:Results | Where-Object { $_.check_id -eq $id }) })
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
    expected_checks = $ExpectedChecks
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
