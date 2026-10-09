# run-sandbox.ps1 - host-side launcher for the SR0 R5 Windows Sandbox clean-machine run. Prep only; not yet run.
#
# What it does (in order):
#   1. Reads identity, version and publisher from both .msix files (AppxManifest.xml inside the package).
#   2. Hashes both packages and exports the PUBLIC signer certificate (.cer; no private key) from the old package.
#   3. Stages <run>\staging\packages (manifest.json, old.msix, new.msix, signer.cer) and <run>\staging\harness (guest).
#   4. Writes <run>\clean-machine.wsb from clean-machine.wsb.tmpl with absolute, XML-escaped host paths.
#   5. Starts the sandbox. Uses the documented `wsb start --config` (Windows 11 24H2 and later) when `wsb` is on PATH,
#      otherwise WindowsSandbox.exe with the .wsb file (documented since Windows 10 build 18342).
#   6. Waits for <run>\receipts\guest-run.json (written last by the guest). Times out with a fail verdict.
#   7. Verifies every receipt against the host's own hashes and the guest harness hash, writes the authoritative
#      run record <run>\receipts\run.json (sr0-a.package-receipt/v2; the package stage reads it), then stops the
#      sandbox with `wsb stop --id` when an id is known.
#
# Verdict rule: pass only if the guest summary passed, every expected check has a receipt with status pass and
# implemented true, the receipt artifact hashes equal the host hashes, and the harness hash equals the staged guest.
# A check that is not implemented is a fail. A missing receipt is a fail.
#
# Usage (Windows host, PowerShell 5.1 or 7):
#   .\run-sandbox.ps1 -OldMsix D:\sr0\SliceApp_0.1.0.0_x64.msix -NewMsix D:\sr0\SliceApp_0.1.1.0_x64.msix
#   .\run-sandbox.ps1 ... -DryRun     # stage and write the .wsb only; does not start the sandbox
#
# Requirements on the host: Windows Sandbox feature enabled (restart after enabling). Nothing here changes Windows
# settings. Sandbox networking is disabled in the .wsb, so no network is needed.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OldMsix,
    [Parameter(Mandatory = $true)][string]$NewMsix,
    [string]$RunId = (Get-Date -Format 'yyyyMMddTHHmmss'),
    [string]$OutRoot = (Join-Path $PSScriptRoot 'runs'),
    [int]$TimeoutMinutes = 45,
    [switch]$DryRun
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$HostHarnessName = 'run-sandbox.ps1'

# Must match $ExpectedChecks in guest\sandbox-run.ps1.
$ExpectedChecks = @(
    'W00-environment', 'W01-artifacts-bound', 'W02-signer-trust', 'W03-install-old',
    'W04-launch-offline-old', 'W05-write-data', 'W06-upgrade-new', 'W07-corrupt-update-rejected',
    'W08-interrupted-update', 'W09-rollback-readable', 'W10-uninstall-keeps-data',
    'W11-legacy-data-physical-path'
)

$GuestDir = Join-Path $PSScriptRoot 'guest'
$TemplatePath = Join-Path $PSScriptRoot 'clean-machine.wsb.tmpl'
$RunDir = Join-Path $OutRoot $RunId
$StageDir = Join-Path $RunDir 'staging'
$PkgStage = Join-Path $StageDir 'packages'
$HarnessStage = Join-Path $StageDir 'harness'
$ReceiptsDir = Join-Path $RunDir 'receipts'
$VerdictPath = Join-Path $ReceiptsDir 'run.json'

function Get-Sha256Ref {
    param([string]$Path)
    return 'sha256:' + (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-UtcStamp { return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }

function Write-Utf8 {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8)
}

function Read-MsixIdentity {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $zip.GetEntry('AppxManifest.xml')
        if (-not $entry) { throw "AppxManifest.xml missing in $Path" }
        $sr = New-Object System.IO.StreamReader($entry.Open())
        try { [xml]$xml = $sr.ReadToEnd() } finally { $sr.Close() }
    }
    finally { $zip.Dispose() }
    $id = $xml.Package.Identity
    $app = $xml.Package.Applications.Application
    return @{
        identity_name = [string]$id.Name
        publisher = [string]$id.Publisher
        version = [string]$id.Version
        app_id = [string]$app.Id
    }
}

# ---------------------------------------------------------------- inputs

foreach ($p in @($OldMsix, $NewMsix, $TemplatePath)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "not found: $p" }
}
$OldMsix = (Resolve-Path -LiteralPath $OldMsix).Path
$NewMsix = (Resolve-Path -LiteralPath $NewMsix).Path

$oldId = Read-MsixIdentity -Path $OldMsix
$newId = Read-MsixIdentity -Path $NewMsix
if ($oldId.identity_name -ne $newId.identity_name) { throw "identity differs: '$($oldId.identity_name)' vs '$($newId.identity_name)'" }
if ($oldId.publisher -ne $newId.publisher) { throw 'publisher differs between old and new packages' }

$oldSig = Get-AuthenticodeSignature -FilePath $OldMsix
$newSig = Get-AuthenticodeSignature -FilePath $NewMsix
if (-not $oldSig.SignerCertificate) { throw 'old package has no signer certificate' }
if (-not $newSig.SignerCertificate) { throw 'new package has no signer certificate' }
if ($oldSig.SignerCertificate.Thumbprint -ne $newSig.SignerCertificate.Thumbprint) { throw 'old and new packages are signed by different certificates' }

# ---------------------------------------------------------------- stage

New-Item -ItemType Directory -Force -Path $PkgStage, $HarnessStage, $ReceiptsDir | Out-Null
Copy-Item -LiteralPath $OldMsix -Destination (Join-Path $PkgStage 'old.msix') -Force
Copy-Item -LiteralPath $NewMsix -Destination (Join-Path $PkgStage 'new.msix') -Force
# Public certificate only. The sandbox has no trust; the guest imports this .cer into TrustedPeople (W02).
Export-Certificate -Cert $oldSig.SignerCertificate -FilePath (Join-Path $PkgStage 'signer.cer') -Type CERT | Out-Null
Copy-Item -Path (Join-Path $GuestDir '*') -Destination $HarnessStage -Force

$oldSha = Get-Sha256Ref -Path (Join-Path $PkgStage 'old.msix')
$newSha = Get-Sha256Ref -Path (Join-Path $PkgStage 'new.msix')
$cerSha = Get-Sha256Ref -Path (Join-Path $PkgStage 'signer.cer')
$guestHarnessSha = Get-Sha256Ref -Path (Join-Path $HarnessStage 'sandbox-run.ps1')

$manifest = [ordered]@{
    run_id = $RunId
    identity_name = $oldId.identity_name
    publisher = $oldId.publisher
    expected_schema = 1
    old = [ordered]@{ file = 'old.msix'; sha256 = $oldSha; version = $oldId.version }
    new = [ordered]@{ file = 'new.msix'; sha256 = $newSha; version = $newId.version }
    signer_cer = [ordered]@{
        file = 'signer.cer'; sha256 = $cerSha
        thumbprint = $oldSig.SignerCertificate.Thumbprint
        subject = [string]$oldSig.SignerCertificate.Subject
    }
}
Write-Utf8 -Path (Join-Path $PkgStage 'manifest.json') -Text ($manifest | ConvertTo-Json -Depth 6)

# ---------------------------------------------------------------- .wsb

function Get-XmlEscapedPath {
    param([string]$Path)
    return [System.Security.SecurityElement]::Escape((Resolve-Path -LiteralPath $Path).Path)
}

$wsbText = [System.IO.File]::ReadAllText($TemplatePath, $Utf8)
$wsbText = $wsbText.Replace('__HOST_HARNESS__', (Get-XmlEscapedPath -Path $HarnessStage))
$wsbText = $wsbText.Replace('__HOST_PACKAGES__', (Get-XmlEscapedPath -Path $PkgStage))
$wsbText = $wsbText.Replace('__HOST_RECEIPTS__', (Get-XmlEscapedPath -Path $ReceiptsDir))
if ($wsbText -match '__HOST_[A-Z]+__') { throw 'unreplaced token in .wsb' }
$wsbXml = [xml]$wsbText   # throws if the generated XML is malformed
if (-not $wsbXml.Configuration) { throw 'generated .wsb has no Configuration root' }
$wsbPath = Join-Path $RunDir 'clean-machine.wsb'
Write-Utf8 -Path $wsbPath -Text $wsbText

if ($DryRun) {
    Write-Output "dry run: staged $StageDir and wrote $wsbPath; sandbox not started."
    Write-Output ('old ' + $oldSha + ' ' + $oldId.version)
    Write-Output ('new ' + $newSha + ' ' + $newId.version)
    exit 0
}

# ---------------------------------------------------------------- launch

$sandboxId = $null
$launchedWith = $null
$wsbCmd = Get-Command wsb -ErrorAction SilentlyContinue
if ($wsbCmd) {
    $configOneLine = ($wsbText -replace "`r?`n", '') -replace '>\s+<', '><'
    $out = (& wsb start --config $configOneLine 2>&1) | Out-String
    if ($LASTEXITCODE -ne 0) { throw "wsb start failed (exit $LASTEXITCODE): $out" }
    $m = [regex]::Match($out, '[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}')
    if ($m.Success) { $sandboxId = $m.Value }
    $launchedWith = 'wsb start --config'
}
else {
    $exe = Join-Path $env:SystemRoot 'System32\WindowsSandbox.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw 'Windows Sandbox is not installed or not enabled on this host' }
    Start-Process -FilePath $exe -ArgumentList ('"' + $wsbPath + '"') | Out-Null
    $launchedWith = 'WindowsSandbox.exe <wsb>'
}
Write-Output "launched via $launchedWith (sandbox id: $(if ($sandboxId) { $sandboxId } else { 'unknown' }))"

# ---------------------------------------------------------------- wait, verify, stop

$startedUtc = Get-UtcStamp
$summaryPath = Join-Path $ReceiptsDir 'guest-run.json'
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
try {
    while (-not (Test-Path -LiteralPath $summaryPath) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 15
    }
    $timedOut = -not (Test-Path -LiteralPath $summaryPath)

    $guest = $null
    if (-not $timedOut) { $guest = Get-Content -Raw -LiteralPath $summaryPath | ConvertFrom-Json }

    $reasons = @()
    if ($timedOut) { $reasons += "timeout: no guest-run.json after $TimeoutMinutes min" }
    if ($guest) {
        if ([string]$guest.run_id -ne $RunId) { $reasons += 'guest run_id differs from host run_id' }
        if (($guest.expected_checks -join ',') -ne ($ExpectedChecks -join ',')) { $reasons += 'guest expected_checks differ from host list' }
        if ($guest.harness.sha256 -ne $guestHarnessSha) { $reasons += 'guest harness hash differs from staged harness' }
        if ($guest.status -ne 'pass') { $reasons += 'guest summary status is ' + $guest.status }
    }

    $rows = @()
    foreach ($id in $ExpectedChecks) {
        $path = Join-Path $ReceiptsDir ($id + '.json')
        if (-not (Test-Path -LiteralPath $path)) {
            $rows += [ordered]@{ check_id = $id; status = 'fail'; implemented = $false }
            $reasons += "missing receipt: $id"
            continue
        }
        $r = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
        $rowOk = ($r.status -eq 'pass') -and ($r.implemented -eq $true) -and ($r.run_id -eq $RunId) -and ($r.platform -eq 'windows-x64')
        if ($r.artifact_ids) {
            $expect = @{ old_msix = $oldSha; new_msix = $newSha; signer_cer = $cerSha }
            foreach ($k in $expect.Keys) {
                $have = $r.artifact_ids.PSObject.Properties[$k]
                if ($have -and $have.Value -ne $expect[$k]) { $rowOk = $false; $reasons += "$id artifact $k differs from host hash" }
            }
        }
        if ($r.harness.sha256 -ne $guestHarnessSha) { $rowOk = $false; $reasons += "$id harness hash differs" }
        if ($r.status -ne 'pass' -or $r.implemented -ne $true) { $reasons += "$id not passing: $($r.reason)" }
        $rows += [ordered]@{ check_id = $id; status = $(if ($rowOk) { 'pass' } else { 'fail' }); implemented = [bool]$r.implemented }
    }

    $ok = ($reasons.Count -eq 0) -and -not $timedOut
    $verdict = [ordered]@{
        schema = 'sr0-a.package-receipt/v2'
        record = 'run'
        product = 'SliceApp'
        platform = 'windows-x64'
        run_id = $RunId
        status = $(if ($ok) { 'pass' } else { 'fail' })
        expected_checks = $ExpectedChecks
        checks = $rows
        started_utc = $startedUtc
        ended_utc = Get-UtcStamp
        reason = $(if ($ok) { $null } else { ($reasons | Select-Object -Unique) -join '; ' })
        artifact_ids = [ordered]@{ old_msix = $oldSha; new_msix = $newSha; signer_cer = $cerSha }
        harness = [ordered]@{ name = $HostHarnessName; sha256 = (Get-Sha256Ref -Path $PSCommandPath) }
    }
    Write-Utf8 -Path $VerdictPath -Text ($verdict | ConvertTo-Json -Depth 6)
    Write-Output ('host verdict ' + $RunId + ': ' + $verdict.status + $(if ($verdict.reason) { ' (' + $verdict.reason + ')' } else { '' }))
}
finally {
    if ($sandboxId) {
        & wsb stop --id $sandboxId | Out-Null
    }
}

if ($verdict.status -ne 'pass') { exit 1 }
exit 0
