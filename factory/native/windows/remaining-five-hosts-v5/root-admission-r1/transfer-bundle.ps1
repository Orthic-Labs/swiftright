# Copies the reviewed V5 source packet into its exact owned Windows paths.
# No compiler/native calls and no overwrite/delete behavior.
$ErrorActionPreference = 'Stop'
$workspace = 'D:\Claude\swiftright'
$expectedPacket = Join-Path $workspace 'factory\native\windows\remaining-five-hosts-v5'
$packet = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
if ($packet -cne [IO.Path]::GetFullPath($expectedPacket)) { throw 'Exact V5 packet root required' }
$manifestPath = Join-Path $PSScriptRoot 'transfer-bundle.json'
$manifestHash = 'f545b56726f3f79981809c7ca3833dfe1613d45c9746b211236a7cf2cc3a2664'
if ((Get-FileHash -LiteralPath $manifestPath).Hash.ToLowerInvariant() -cne $manifestHash) { throw 'Transfer bundle manifest drift' }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.kind -cne 'remaining-five-v5-root-transfer-bundle-r1' -or $manifest.sourceStageManifestSha256 -cne 'ef0853a00aca582f10f655b05946303190dfe608b76b01dc9810e2921de71950') { throw 'V5 source stage identity drift' }
$stageManifestPath = Join-Path $packet 'root-stage-manifest.json'
if ((Get-FileHash -LiteralPath $stageManifestPath).Hash.ToLowerInvariant() -cne $manifest.sourceStageManifestSha256) { throw 'V5 source stage manifest drift' }
$stage = Get-Content -LiteralPath $stageManifestPath -Raw | ConvertFrom-Json
if ($stage.kind -cne 'remaining-five-hosts-source-stage-v5' -or $stage.compilerRuns -ne 0 -or $stage.nativeRuns -ne 0 -or $stage.files.Count -ne $manifest.sourceStageFileCount) { throw 'V5 source-only stage boundary drift' }
$stageFiles = @{}
foreach ($entry in $stage.files) {
    $rel = [string]$entry.path
    if (-not $rel.StartsWith('factory/native/windows/remaining-five-hosts-v5/', [StringComparison]::Ordinal) -or $rel.Contains('..')) { throw 'Unsafe source stage path' }
    $source = Join-Path $workspace ($rel.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw ('Missing source-stage file: ' + $rel) }
    $item = Get-Item -LiteralPath $source
    if ($item.Length -ne $entry.bytes -or (Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant() -cne $entry.hash.Replace('sha256:', '')) { throw ('Source-stage byte drift: ' + $rel) }
    $stageFiles[$rel.Substring('factory/native/windows/remaining-five-hosts-v5/'.Length)] = $entry
}
$toolRoot = Join-Path $workspace '.factory-work\hosts\remaining-five-v5-admission-r1'
$labels = @('disabled', 'image', 'shapes.fill-stroke', 'text.bundled-font', 'toggle')
$packageTargets = @{}
foreach ($label in $labels) { $packageTargets[$label] = Join-Path $workspace ('.factory-work\hosts\' + $label + '\package') }
if ($manifest.targetToolRoot -cne $toolRoot) { throw 'Exact owned tool destination required' }
$manifestLabels = (($manifest.planSha256ByLabel.PSObject.Properties.Name | Sort-Object) -join ',')
$expectedLabels = (($labels | Sort-Object) -join ',')
if ($manifestLabels -cne $expectedLabels) { throw 'Exact five-plan inventory required' }
foreach ($label in $labels) {
    if ($manifest.targetPackages.$label -cne $packageTargets[$label]) { throw ('Exact owned package destination required: ' + $label) }
    $planPayload = @($manifest.payload | Where-Object { $_.destinationKind -ceq 'package' -and $_.label -ceq $label -and $_.destination -ceq 'plan.json' })
    if ($planPayload.Count -ne 1 -or $planPayload[0].sha256 -cne $manifest.planSha256ByLabel.$label) { throw ('Plan pin/payload mismatch: ' + $label) }
}
if ($manifest.executionBoundary.compilerInvocations -ne 0 -or $manifest.executionBoundary.nativeCalls -ne 0 -or $manifest.executionBoundary.overwrite -ne $false -or $manifest.executionBoundary.delete -ne $false) { throw 'Transfer boundary drift' }
if (Test-Path -LiteralPath $toolRoot) { throw 'Owned V5 admission staging path already exists; preserve and inspect it' }
foreach ($label in $labels) { if (Test-Path -LiteralPath $packageTargets[$label]) { throw ('Owned V5 package target already exists; preserve and inspect it: ' + $label) } }

# Validate the exact transfer inventory against the frozen source-stage inventory before writing.
$seen = @{}
foreach ($entry in $manifest.payload) {
    $srcRel = [string]$entry.source
    if ($seen.ContainsKey($srcRel)) { throw ('Duplicate payload source: ' + $srcRel) }
    $seen[$srcRel] = $true
    if ($srcRel -ceq 'root-stage-manifest.json') {
        $frozen = @{ hash = $manifest.sourceStageManifestSha256; bytes = $manifest.sourceStageManifestBytes }
    } else {
        if (-not $stageFiles.ContainsKey($srcRel)) { throw ('Payload is outside frozen source manifest: ' + $srcRel) }
        $frozen = $stageFiles[$srcRel]
    }
    if ($entry.sha256 -cne $frozen.hash.Replace('sha256:', '') -or $entry.bytes -ne $frozen.bytes) { throw ('Payload/source manifest disagreement: ' + $srcRel) }
    if ($entry.destinationKind -cne 'tool' -and $entry.destinationKind -cne 'package') { throw 'Unknown transfer destination kind' }
    if ($entry.destinationKind -ceq 'package' -and $labels -cnotcontains $entry.label) { throw 'Unknown package destination label' }
    if ($entry.destination -notmatch '^[A-Za-z0-9._/-]+$' -or $entry.destination.Contains('..')) { throw 'Unsafe destination path' }
}
foreach ($dependency in $manifest.externalDependencies) {
    if ($dependency.kind -ceq 'file') {
        if (-not (Test-Path -LiteralPath $dependency.path -PathType Leaf)) { throw ('Missing pinned external dependency: ' + $dependency.name) }
        $file = Get-Item -LiteralPath $dependency.path
        if (($null -ne $dependency.bytes -and $file.Length -ne $dependency.bytes) -or (Get-FileHash -LiteralPath $dependency.path).Hash.ToLowerInvariant() -cne $dependency.sha256) { throw ('External dependency drift: ' + $dependency.name) }
    } elseif ($dependency.kind -ceq 'source-tree') {
        if (-not (Test-Path -LiteralPath $dependency.path -PathType Container)) { throw ('Missing pinned external source tree: ' + $dependency.name) }
    } else { throw ('Unknown external dependency kind: ' + $dependency.name) }
}

New-Item -ItemType Directory -Path $toolRoot | Out-Null
foreach ($entry in $manifest.payload) {
    $source = Join-Path $packet ($entry.source.Replace('/', '\'))
    if ($entry.destinationKind -ceq 'tool') {
        $destRoot = $toolRoot
    } else {
        $destRoot = $packageTargets[$entry.label]
    }
    $dest = Join-Path $destRoot ($entry.destination.Replace('/', '\'))
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $dest
    if ((Get-Item -LiteralPath $dest).Length -ne $entry.bytes -or (Get-FileHash -LiteralPath $dest).Hash.ToLowerInvariant() -cne $entry.sha256) { throw ('Transferred byte verification failed: ' + $entry.source) }
}
foreach ($asset in $manifest.admissionAssets) {
    $source = Join-Path $PSScriptRoot ($asset.path.Replace('/', '\'))
    if ((Get-Item -LiteralPath $source).Length -ne $asset.bytes -or (Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant() -cne $asset.sha256) { throw ('Admission asset drift: ' + $asset.path) }
    $dest = Join-Path $toolRoot ('root-admission-r1\' + $asset.path.Replace('/', '\'))
    New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $dest
    if ((Get-FileHash -LiteralPath $dest).Hash.ToLowerInvariant() -cne $asset.sha256) { throw ('Admission asset transfer mismatch: ' + $asset.path) }
}
$admissionScript = Join-Path $PSScriptRoot 'admit-hosts.ps1'
$admissionScriptHash = '07c6cf0ed95602ed82ee11933395c0b94afd9e26509e93e1676914a3520f2c2c'
if ((Get-FileHash -LiteralPath $admissionScript).Hash.ToLowerInvariant() -cne $admissionScriptHash) { throw 'Admission script source drift' }
$admissionScriptDestination = Join-Path $toolRoot 'root-admission-r1\admit-hosts.ps1'
Copy-Item -LiteralPath $admissionScript -Destination $admissionScriptDestination
if ((Get-FileHash -LiteralPath $admissionScriptDestination).Hash.ToLowerInvariant() -cne $admissionScriptHash) { throw 'Admission script transfer mismatch' }
$transferScript = Join-Path $PSScriptRoot 'transfer-bundle.ps1'
$transferScriptHash = (Get-FileHash -LiteralPath $transferScript).Hash.ToLowerInvariant()
$transferScriptDestination = Join-Path $toolRoot 'root-admission-r1\transfer-bundle.ps1'
New-Item -ItemType Directory -Path (Split-Path -Parent $transferScriptDestination) -Force | Out-Null
Copy-Item -LiteralPath $transferScript -Destination $transferScriptDestination
if ((Get-FileHash -LiteralPath $transferScriptDestination).Hash.ToLowerInvariant() -cne $transferScriptHash) { throw 'Transfer script copy mismatch' }
$manifestDestination = Join-Path $toolRoot 'root-admission-r1\transfer-bundle.json'
New-Item -ItemType Directory -Path (Split-Path -Parent $manifestDestination) -Force | Out-Null
Copy-Item -LiteralPath $manifestPath -Destination $manifestDestination
if ((Get-FileHash -LiteralPath $manifestDestination).Hash.ToLowerInvariant() -cne $manifestHash) { throw 'Transferred bundle manifest mismatch' }
[ordered]@{
    kind = 'remaining-five-v5-headless-transfer-result-r1'
    transferManifestSha256 = $manifestHash
    transferScriptSha256 = $transferScriptHash
    sourceStageManifestSha256 = $manifest.sourceStageManifestSha256
    payloadFiles = $manifest.payload.Count
    externalDependencyRequirementsChecked = $manifest.externalDependencies.Count
    toolRoot = $toolRoot
    packageRoots = $packageTargets
    compilerInvocations = 0
    nativeCalls = 0
    overwritten = $false
    deleted = $false
} | ConvertTo-Json -Depth 8
