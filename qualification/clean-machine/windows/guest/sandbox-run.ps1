# sandbox-run.ps1 - guest-side clean-machine harness for Windows Sandbox (SR0 R5). Prep only; not yet run.
#
# Runs inside the sandbox as WDAGUtilityAccount (an administrator in the sandbox), started by logon.cmd.
# Reads host-staged inputs from the read-only packages folder (manifest.json, old and new .msix, signer.cer).
# Writes one receipt per check to the writable receipts folder as it goes: <check_id>.json, then run-summary.json.
# Receipts follow ..\..\receipt.schema.json (clean-machine-receipt/v1).
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
    'W11-legacy-data-physical-path'
)

$script:Results = New-Object System.Collections.ArrayList
$script:Pfn = $null
$script:AppId = $null
$script:DataSha = $null

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
    $envRec = Get-EnvironmentRecord
    $ids = @{}
    foreach ($k in $Artifacts.Keys) {
        # Only real digests go in artifact_ids (schema: sha256:<64 hex>). 'missing' stays in observed.
        if ([string]$Artifacts[$k] -match '^sha256:[0-9a-f]{64}$') { $ids[$k] = [string]$Artifacts[$k] }
    }
    $rec = [ordered]@{
        schema = 'clean-machine-receipt/v1'
        record = 'check'
        platform = 'windows'
        run_id = $script:RunId
        check_id = $CheckId
        check_name = $CheckName
        stage = 'package'
        status = $Status
        implemented = $Implemented
        reason = $(if ($Status -eq 'pass') { $null } else { $Reason })
        started_utc = $Started
        ended_utc = Get-UtcStamp
        exit_status = $ExitStatus
        observed = $Observed
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
            $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $pid0)
            $win = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
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
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessId)
    return [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
}

function Find-ByName {
    param($Root, [string]$Name, $ControlType)
    $c1 = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)
    $c2 = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $ControlType)
    $cond = New-Object System.Windows.Automation.AndCondition($c1, $c2)
    return @($Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond))
}

# Writes the marker into the last editable row, through UIA ValuePattern (the app routes AX SetValue into editText).
function Write-MarkerRow {
    param($Root, [string]$Marker)
    $btn = @(Find-ByName -Root $Root -Name 'Insert above' -ControlType ([System.Windows.Automation.ControlType]::Button))
    if ($btn.Count -eq 0) { throw 'button "Insert above" not found in UIA tree' }
    $inv = $btn[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $inv.Invoke()
    Start-Sleep -Seconds 1
    $rows = @(Find-ByName -Root $Root -Name 'Row' -ControlType ([System.Windows.Automation.ControlType]::Edit))
    if ($rows.Count -eq 0) { throw 'no "Row" text fields found after insert' }
    $target = $rows[$rows.Count - 1]
    $vp = $target.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $vp.SetValue($Marker)
    return @{ row_fields = $rows.Count }
}

function Read-RowValues {
    param($Root)
    $rows = @(Find-ByName -Root $Root -Name 'Row' -ControlType ([System.Windows.Automation.ControlType]::Edit))
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

# ---------------------------------------------------------------- start

if (-not (Test-Path -LiteralPath $ReceiptsDir)) { throw "receipts folder not mapped: $ReceiptsDir" }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

$script:Manifest = $null
$manifestPath = Join-Path $PackagesDir 'manifest.json'
if (Test-Path -LiteralPath $manifestPath) {
    $script:Manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
}
$script:RunId = $(if ($script:Manifest) { [string]$script:Manifest.run_id } else { 'unknown-no-manifest' })

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
    @{ pass = $pass; reason = 'hash differs from manifest'; observed = @{ run_id = $m.run_id }; artifacts = $arts; exit = $null }
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

# W04: launch the old build offline; the window must appear through UIA.
Invoke-Check -CheckId 'W04-launch-offline-old' -CheckName 'Launch old build offline; window via UIA' -Body {
    $w = Start-AppAndFindWindow -TimeoutSec 40
    $pass = ($w.window_name -ne '')
    @{ pass = $pass; reason = 'window has no name'; observed = @{ window_name = [string]$w.window_name; pid = [string]$w.pid; network_default_routes = [string](@(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue).Count) }; artifacts = @{}; exit = $null }
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
    $observed = @{ closed_before_install = [string]$closed; version = $ver; data_sha_before = [string]$before; data_sha_after_install = [string]$after; marker_shown = [string]$shown }
    $pass = ($ver -eq [string]$m.new.version) -and ($before -eq $after) -and $shown
    @{ pass = $pass; reason = 'version, data hash, or marker in UI differs'; observed = $observed; artifacts = @{ new_msix = (Get-Sha256Ref -Path $new) }; exit = 0 }
}

# W07: a corrupt update must be refused and the installed version must stay put.
Invoke-Check -CheckId 'W07-corrupt-update-rejected' -CheckName 'Tampered MSIX refused; installed version unchanged' -Body {
    $m = $script:Manifest
    $src = Join-Path $PackagesDir $m.new.file
    $bad = Join-Path $WorkDir 'tampered.msix'
    Copy-Item -LiteralPath $src -Destination $bad -Force
    $bytes = [System.IO.File]::ReadAllBytes($bad)
    $off = [int]([math]::Floor($bytes.Length / 2))
    $oldByte = $bytes[$off]
    $bytes[$off] = $bytes[$off] -bxor 0x01
    [System.IO.File]::WriteAllBytes($bad, $bytes)
    $verBefore = [string](Get-Pkg).Version
    $rejected = $false
    $msg = ''
    $hresult = ''
    try { Add-AppxPackage -Path $bad } catch { $rejected = $true; $msg = $_.Exception.Message; $hresult = ('0x{0:X8}' -f $_.Exception.HResult) }
    $verAfter = [string](Get-Pkg).Version
    $observed = @{ flipped_offset = [string]$off; byte_before = ('{0:x2}' -f $oldByte); byte_after = ('{0:x2}' -f $bytes[$off]); rejected = [string]$rejected; hresult = $hresult; error = $msg; version_before = $verBefore; version_after = $verAfter }
    $pass = $rejected -and ($verBefore -eq $verAfter)
    @{ pass = $pass; reason = 'tampered package was accepted or installed version changed'; observed = $observed; artifacts = @{ tampered_msix = (Get-Sha256Ref -Path $bad) }; exit = $null }
}

# W08: interrupted update. Procedure not defined yet (close plan F6). Always FAILS until implemented.
Invoke-Check -CheckId 'W08-interrupted-update' -CheckName 'Interrupted update at install/copy/swap boundaries' -Implemented $false `
    -NotImplementedReason 'procedure not defined; see docs/sr0-close-plan.md F6 and mac-clean-checklist.md (shared procedure)'

# W09: rollback. Remove the new package keeping data, install the old build, and check it reads the new data.
Invoke-Check -CheckId 'W09-rollback-readable' -CheckName 'Old build reads data written by new build' -Body {
    $m = $script:Manifest
    $old = Join-Path $PackagesDir $m.old.file
    [void](Stop-AppGracefully)
    $pkg = Get-Pkg
    if ($pkg) { Remove-AppxPackage -Package $pkg.PackageFullName -PreserveApplicationData }
    $st = Get-DataState
    $preserved = ($null -ne $st.found)
    Add-AppxPackage -Path $old
    $ver = [string](Get-Pkg).Version
    $w = Start-AppAndFindWindow -TimeoutSec 40
    $vals = Read-RowValues -Root (Get-AppRoot -ProcessId $w.pid)
    $marker = 'rightkit-check-' + $script:RunId
    $shown = ($vals -contains $marker)
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
    if ($pkg) { Remove-AppxPackage -Package $pkg.PackageFullName -PreserveApplicationData }
    $gone = -not (Get-Pkg)
    $after = Get-DataState
    $asha = $(if ($after.found) { Get-Sha256Ref -Path $after.found.path } else { 'missing' })
    $observed = @{ package_removed = [string]$gone; sha_before = [string]$bsha; sha_after = [string]$asha; preserve_flag = 'Remove-AppxPackage -PreserveApplicationData' }
    foreach ($k in $after.observed.Keys) { $observed[$k] = $after.observed[$k] }
    $pass = $gone -and ($bsha -ne 'missing') -and ($bsha -eq $asha)
    @{ pass = $pass; reason = 'package not removed or rows.json missing or changed'; observed = $observed; artifacts = @{ rows_json = $asha }; exit = 0 }
}

# W11: legacy (pre-existing, not written by this package) data must be read from the physical path.
Invoke-Check -CheckId 'W11-legacy-data-physical-path' -CheckName 'Legacy data read at physical path after install' -Implemented $false `
    -NotImplementedReason 'legacy data fixture not defined; see docs/sr0-close-plan.md F6'

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
    schema = 'clean-machine-receipt/v1'
    record = 'run'
    platform = 'windows'
    run_id = $script:RunId
    status = $(if ($ok) { 'pass' } else { 'fail' })
    expected_checks = $ExpectedChecks
    checks = $checks
    started_utc = Get-UtcStamp
    ended_utc = Get-UtcStamp
    reason = $reason
    artifact_ids = @{}
    harness = [ordered]@{ name = $HarnessName; sha256 = (Get-Sha256Ref -Path $HarnessPath) }
}
[System.IO.File]::WriteAllText((Join-Path $ReceiptsDir 'run-summary.json'), ($summary | ConvertTo-Json -Depth 8), $Utf8)
Write-Output ('run ' + $script:RunId + ': ' + $summary.status + $(if ($reason) { ' (' + $reason + ')' } else { '' }))
