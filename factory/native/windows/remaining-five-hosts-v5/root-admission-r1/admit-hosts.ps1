# Sequential headless controls + complete builder preflight for five frozen V5 packages.
# This script never invokes Swift, launches FactoryProbe, opens windows, or cleans remote paths.
$ErrorActionPreference = 'Stop'
$workspace = 'D:\Claude\swiftright'
$toolRoot = Join-Path $workspace '.factory-work\hosts\remaining-five-v5-admission-r1'
$expectedToolRoot = [IO.Path]::GetFullPath($toolRoot)
if ([IO.Path]::GetFullPath($PSScriptRoot) -cne [IO.Path]::GetFullPath((Join-Path $expectedToolRoot 'root-admission-r1'))) { throw 'Exact transferred V5 admission tools path required' }
$manifestPath = Join-Path $PSScriptRoot 'transfer-bundle.json'
$manifestHash = 'f545b56726f3f79981809c7ca3833dfe1613d45c9746b211236a7cf2cc3a2664'
if ((Get-FileHash -LiteralPath $manifestPath).Hash.ToLowerInvariant() -cne $manifestHash) { throw 'Transfer bundle manifest drift' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.kind -cne 'remaining-five-v5-root-transfer-bundle-r1' -or $manifest.sourceStageManifestSha256 -cne 'ef0853a00aca582f10f655b05946303190dfe608b76b01dc9810e2921de71950') { throw 'Frozen V5 source stage identity drift' }
$startedAt = [DateTimeOffset]::UtcNow.ToString('o')
$labels = @('disabled', 'image', 'shapes.fill-stroke', 'text.bundled-font', 'toggle')
$expectedLabels = (($labels | Sort-Object) -join ',')
if ((($manifest.planSha256ByLabel.PSObject.Properties.Name | Sort-Object) -join ',') -cne $expectedLabels) { throw 'Exact five-plan manifest inventory required' }
$expectedPackageBase = Join-Path $workspace '.factory-work\hosts'
foreach ($hostLabel in $labels) {
    $package = Join-Path $expectedPackageBase ($hostLabel + '\package')
    if ($manifest.targetPackages.$hostLabel -cne $package) { throw ('Package target drift: ' + $hostLabel) }
    $planRow = @($manifest.payload | Where-Object { $_.destinationKind -ceq 'package' -and $_.label -ceq $hostLabel -and $_.destination -ceq 'plan.json' })
    if ($planRow.Count -ne 1 -or $planRow[0].sha256 -cne $manifest.planSha256ByLabel.$hostLabel) { throw ('Package plan pin drift: ' + $hostLabel) }
}
$stageManifest = Join-Path $toolRoot 'root-stage-manifest.json'
if ((Get-FileHash -LiteralPath $stageManifest).Hash.ToLowerInvariant() -cne $manifest.sourceStageManifestSha256) { throw 'Transferred source stage manifest drift' }
foreach ($entry in $manifest.payload) {
    if ($entry.destinationKind -ceq 'tool') { $destRoot = $toolRoot }
    elseif ($entry.destinationKind -ceq 'package' -and $labels -ccontains $entry.label) { $destRoot = Join-Path $workspace ('.factory-work\hosts\' + $entry.label + '\package') }
    else { throw 'Unknown transfer payload destination' }
    $path = Join-Path $destRoot ($entry.destination.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw ('Transferred payload file missing: ' + $entry.destination) }
    $item = Get-Item -LiteralPath $path
    if ($item.Length -ne $entry.bytes -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $entry.sha256) { throw ('Transferred payload byte drift: ' + $entry.destination) }
}
foreach ($dependency in $manifest.externalDependencies) {
    if ($dependency.kind -ceq 'file') {
        if (-not (Test-Path -LiteralPath $dependency.path -PathType Leaf) -or (Get-FileHash -LiteralPath $dependency.path).Hash.ToLowerInvariant() -cne $dependency.sha256) { throw ('External dependency drift: ' + $dependency.name) }
    } elseif ($dependency.kind -ceq 'source-tree') {
        if (-not (Test-Path -LiteralPath $dependency.path -PathType Container)) { throw ('External source tree missing: ' + $dependency.name) }
    } else { throw 'Unknown external dependency kind' }
}
$outputRoot = Join-Path $toolRoot 'root-admission-r1\results'
if (Test-Path -LiteralPath $outputRoot) { throw 'Admission results path already exists; preserve and inspect it' }
New-Item -ItemType Directory -Path $outputRoot | Out-Null

function Invoke-RecordedScript([string]$Name, [string]$Path, [hashtable]$Parameters = @{}) {
    $log = Join-Path $outputRoot ($Name + '.log')
    try {
        $null = & $Path @Parameters *> $log
    } catch {
        [IO.File]::AppendAllText($log, [Environment]::NewLine + 'FAILED: ' + [string]$_ + [Environment]::NewLine)
        throw ('Control failed: ' + $Name)
    }
    return [ordered]@{
        name = $Name
        path = $Path
        log = $log
        sha256 = (Get-FileHash -LiteralPath $Path).Hash.ToLowerInvariant()
        logSha256 = (Get-FileHash -LiteralPath $log).Hash.ToLowerInvariant()
        passed = $true
        swiftCompilerInvocations = 0
        nativeCalls = 0
    }
}

$controls = @()
$v3 = Join-Path $toolRoot 'reviewed-v3-controls'
$controls += Invoke-RecordedScript 'v5-stream-source-parse' (Join-Path $toolRoot 'parse-stream-controls.ps1') @{ Output = (Join-Path $outputRoot 'stream-parse-controls.json') }
$controls += Invoke-RecordedScript 'v5-stream-kernel-controls' (Join-Path $toolRoot 'run-stream-controls.ps1')
$controls += Invoke-RecordedScript 'v5-stream-production-admission' (Join-Path $toolRoot 'test-stream-admission.ps1') @{ OutputRoot = (Join-Path $outputRoot 'stream-admission-faults') }
$controls += Invoke-RecordedScript 'v3-source-scope' (Join-Path $v3 'test-producer-source-scope.ps1') @{ OutputRoot = (Join-Path $outputRoot 'v3-source-scope') }
$controls += Invoke-RecordedScript 'v3-json-array-decoder' (Join-Path $v3 'test-json-array-shape.ps1') @{ OutputRoot = (Join-Path $outputRoot 'v3-json-array') }
$controls += Invoke-RecordedScript 'v5-pure-production-controls' (Join-Path $toolRoot 'run-controls.ps1')

$builder = Join-Path $toolRoot 'build-hosts-v2.ps1'
$preflights = @()
foreach ($hostLabel in $labels) {
    $package = Join-Path $workspace ('.factory-work\hosts\' + $hostLabel + '\package')
    $log = Join-Path $outputRoot ('preflight-' + $hostLabel + '.log')
    try {
        $raw = (& $builder -Package $package -PreflightOnly 2>&1 | Out-String)
        [IO.File]::WriteAllText($log, $raw)
    } catch {
        [IO.File]::AppendAllText($log, [Environment]::NewLine + 'FAILED: ' + [string]$_ + [Environment]::NewLine)
        throw ('Full builder preflight failed: ' + $hostLabel)
    }
    $result = $raw | ConvertFrom-Json
    $planPath = Join-Path $package 'plan.json'
    $planHash = (Get-FileHash -LiteralPath $planPath).Hash.ToLowerInvariant()
    if ($result.kind -cne 'full-remaining-five-builder-preflight-v5' -or $result.planSha256 -cne $planHash -or $result.package -cne $package -or $result.compilerStarted -isnot [bool] -or $result.compilerStarted -or $result.nativeActions -ne 0 -or $result.outputCreated -isnot [bool] -or $result.outputCreated -or $result.qualification -cne 'hold') { throw ('Preflight result boundary invalid: ' + $hostLabel) }
    $preflights += [ordered]@{
        label = $hostLabel
        planSha256 = $planHash
        resultSha256 = (Get-FileHash -LiteralPath $log).Hash.ToLowerInvariant()
        compilerStarted = $false
        nativeActions = 0
        outputCreated = $false
        qualification = 'hold'
    }
}

$result = [ordered]@{
    kind = 'remaining-five-v5-headless-admission-r1'
    transferManifestSha256 = $manifestHash
    sourceStageManifestSha256 = $manifest.sourceStageManifestSha256
    startedAt = $startedAt
    finishedAt = [DateTimeOffset]::UtcNow.ToString('o')
    controls = $controls
    preflights = $preflights
    swiftCompilerInvocations = 0
    nativeCalls = 0
    nativeParity = 'hold'
    frozenTupleBound = $false
    executionEligible = $false
    nextAction = 'Root may review receipts and then invoke serialized per-host builds separately.'
}
$resultPath = Join-Path $outputRoot 'admission-result.json'
$result | ConvertTo-Json -Depth 12 | Set-Content -Encoding UTF8 -LiteralPath $resultPath
Get-Content -LiteralPath $resultPath -Raw
