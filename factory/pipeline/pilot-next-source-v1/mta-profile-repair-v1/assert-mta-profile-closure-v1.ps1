Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-BoundedJson([string]$Path) {
    $fi = [IO.FileInfo]$Path
    if (-not $fi.Exists -or (($fi.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw "JSON file missing or reparse: $Path" }
    if ($fi.Length -gt 2MB) { throw "JSON exceeds 2 MiB: $Path" }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}
function Get-StreamHash([string]$Path) {
    $fi = [IO.FileInfo]$Path
    if (-not $fi.Exists -or (($fi.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { throw "source missing or reparse: $Path" }
    $before = $fi.Length
    if ($before -gt 64MB) { throw "source exceeds 64 MiB: $Path" }
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $buf = New-Object byte[] (1MB); $total = 0L
        while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) {
            $sha.TransformBlock($buf, 0, $n, $buf, 0) | Out-Null
            $total += $n
            if ($total -gt 64MB) { throw "source grew over 64 MiB: $Path" }
        }
        $sha.TransformFinalBlock([byte[]]::new(0), 0, 0) | Out-Null
        $hex = ([BitConverter]::ToString($sha.Hash) -replace '-', '').ToLowerInvariant()
    } finally { $stream.Dispose(); $sha.Dispose() }
    $after = ([IO.FileInfo]$Path).Length
    if ($before -ne $after -or $before -ne $total) { throw "source changed while hashing: $Path" }
    return [pscustomobject]@{ bytes = [int64]$total; sha256 = $hex }
}
function Assert-MtaProfileClosure {
    param(
        [Parameter(Mandatory)][string]$ProducerRoot,
        [Parameter(Mandatory)][string]$IntegrationBindingsPath,
        [Parameter(Mandatory)][string]$SourceInputsPath,
        [Parameter(Mandatory)]$BindingDocument,
        [Parameter(Mandatory)]$SourceInputs,
        [Parameter(Mandatory)][ValidateSet('text','circle')][string]$Profile,
        [Parameter(Mandatory)][string]$ExpectedBindingKind,
        [Parameter(Mandatory)][string]$ExpectedPathFragment,
        [Parameter(Mandatory)][string]$ExpectedMtaWorkerHash
    )
    if ($BindingDocument.kind -cne $ExpectedBindingKind) { throw "binding kind mismatch" }
    $rows = @($BindingDocument.files)
    if ($rows.Count -lt 1 -or $rows.Count -gt 512) { throw "binding row count out of bounds" }
    $seen = @{}; $mta = $null; $total = 0L
    foreach ($row in $rows) {
        $rel = [string]$row.path
        if ([string]::IsNullOrWhiteSpace($rel) -or $rel.Contains('\') -or [IO.Path]::IsPathRooted($rel) -or $rel -match '(^|/)\.\.(/|$)' -or $seen.ContainsKey($rel)) { throw "unsafe or duplicate binding path: $rel" }
        $seen[$rel] = $true
        $full = Join-Path $ProducerRoot ($rel -replace '/', '\')
        $actual = Get-StreamHash $full
        $total += $actual.bytes
        if ($total -gt 256MB) { throw "binding closure exceeds 256 MiB" }
        if ([int64]$row.bytes -ne $actual.bytes -or ([string]$row.sha256).ToLowerInvariant() -cne $actual.sha256) { throw "binding row hash/bytes mismatch: $rel" }
        if ($rel -ceq 'dependencies/uia-worker/invoke-worker-mta.ps1') { $mta = $row }
    }
    if ($null -eq $mta -or ([string]$mta.sha256).ToLowerInvariant() -cne $ExpectedMtaWorkerHash.ToLowerInvariant()) { throw "MTA worker binding mismatch" }

    $bindingActual = Get-StreamHash $IntegrationBindingsPath
    if ([string]$SourceInputs.integrationBindingsHash -cne $bindingActual.sha256) { throw "source-inputs integration binding hash mismatch" }
    if ($null -eq $SourceInputs.integrationBindingsRef) { throw "source-inputs binding ref missing" }
    if ([int64]$SourceInputs.integrationBindingsRef.bytes -ne $bindingActual.bytes -or ([string]$SourceInputs.integrationBindingsRef.sha256).ToLowerInvariant() -cne ('sha256:' + $bindingActual.sha256)) { throw "source-inputs binding ref mismatch" }
    if (-not ([string]$SourceInputs.integrationBindingsRef.path -match '(?i)integration-bindings\.json$')) { throw "source-inputs binding path mismatch" }
    $profilePath = ([string]$SourceInputs.capturePlanPath) + ' ' + ([string]$SourceInputs.bindingRef.path)
    if ($profilePath.IndexOf($ExpectedPathFragment, [StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "profile path fragment mismatch" }
    $serialized = $SourceInputs | ConvertTo-Json -Depth 32 -Compress
    if ($serialized -match '(?i)count1-r10|count20-r10|r100') { throw "stale sequential profile token" }
    return [pscustomobject]@{ accepted = $true; profile = $Profile; rows = $rows.Count; bytes = $total; integrationBindingsSha256 = $bindingActual.sha256; mtaWorkerSha256 = [string]$mta.sha256 }
}
