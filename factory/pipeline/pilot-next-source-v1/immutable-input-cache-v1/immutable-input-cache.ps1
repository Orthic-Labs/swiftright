# Immutable measured-input cache proposal; source-only until root stages it.
# Never overrides Get-FileHash. Outputs & unlisted paths stay uncached.
Set-StrictMode -Version Latest

$script:ImmutableInputCacheMaxHandles = 512
$script:ImmutableInputCacheMaxBytes = [int64]1GB
$script:ImmutableInputCacheMaxFileBytes = [int64]64MB
$script:ImmutableInputCacheChunkBytes = 131072

function ConvertTo-CacheHash([string]$Hash) {
    if ([string]::IsNullOrWhiteSpace($Hash)) { throw 'cache hash required' }
    $value = $Hash.Trim().ToLowerInvariant().Replace('sha256:', '')
    if ($value -notmatch '^[0-9a-f]{64}$') { throw 'cache SHA256 required' }
    return $value
}

function Assert-CachePathNoReparse([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if ($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw 'cache input must be regular non-reparse file'
    }
    $parent = $item.Directory
    while ($null -ne $parent) {
        $parentItem = Get-Item -LiteralPath $parent.FullName -Force -ErrorAction Stop
        if (($parentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'cache path component is reparse point'
        }
        $parent = $parent.Parent
    }
    return $item
}

function Read-CacheStreamHash([IO.FileStream]$Stream) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $buffer = New-Object byte[] $script:ImmutableInputCacheChunkBytes
        while (($count = $Stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $sha.TransformBlock($buffer, 0, $count, $buffer, 0) | Out-Null
        }
        $sha.TransformFinalBlock([byte[]]::new(0), 0, 0) | Out-Null
        return ([BitConverter]::ToString($sha.Hash)).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}

function Open-ImmutableInputLease([string]$Path, [string]$ExpectedSha256, [int64]$ExpectedBytes) {
    $item = Assert-CachePathNoReparse $Path
    if ($ExpectedBytes -lt 0 -or $item.Length -ne $ExpectedBytes) { throw 'cache input byte count mismatch' }
    $expected = ConvertTo-CacheHash $ExpectedSha256
    $stream = [IO.FileStream]::new($item.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read,
        [IO.FileShare]::Read, $script:ImmutableInputCacheChunkBytes, [IO.FileOptions]::SequentialScan)
    try {
        $before = $stream.Length
        $stream.Position = 0
        $actual = Read-CacheStreamHash $stream
        if ($before -ne $stream.Length -or $stream.Length -ne $ExpectedBytes -or $actual -cne $expected) {
            throw 'immutable input changed or hash mismatched'
        }
        return [pscustomobject]@{
            Path = $item.FullName
            Bytes = [int64]$stream.Length
            Sha256 = $actual
            Stream = $stream
            Lease = 'FileShare.Read'
        }
    } catch { $stream.Dispose(); throw }
}

function New-ImmutableInputCache([object[]]$Whitelist) {
    if ($null -eq $Whitelist -or $Whitelist.Count -eq 0) { throw 'nonempty immutable whitelist required' }
    if ($Whitelist.Count -gt $script:ImmutableInputCacheMaxHandles) { throw 'immutable handle limit exceeded' }
    $cache = [pscustomobject]@{ Kind = 'factory-immutable-input-cache-v1'; Leases = @{}; TotalBytes = [int64]0; Closed = $false }
    try {
        foreach ($row in $Whitelist) {
            if ($null -eq $row.Path -or $null -eq $row.Sha256 -or $null -eq $row.Bytes) { throw 'whitelist path/hash/bytes required' }
            $item = Assert-CachePathNoReparse ([string]$row.Path)
            $key = $item.FullName.ToLowerInvariant()
            if ($cache.Leases.ContainsKey($key)) { throw 'duplicate immutable whitelist path' }
            if ([int64]$row.Bytes -gt $script:ImmutableInputCacheMaxFileBytes -or [int64]$row.Bytes -gt $script:ImmutableInputCacheMaxBytes -or $cache.TotalBytes + [int64]$row.Bytes -gt $script:ImmutableInputCacheMaxBytes) { throw 'immutable byte budget exceeded' }
            $lease = Open-ImmutableInputLease $item.FullName ([string]$row.Sha256) ([int64]$row.Bytes)
            $cache.Leases[$key] = $lease
            $cache.TotalBytes += $lease.Bytes
        }
        return $cache
    } catch {
        Close-ImmutableInputCache $cache | Out-Null
        throw
    }
}

function Get-ImmutableInputHash([object]$Cache, [string]$Path) {
    if ($null -eq $Cache -or $Cache.Closed) { throw 'immutable cache is closed' }
    $key = ([IO.Path]::GetFullPath($Path)).ToLowerInvariant()
    if (-not $Cache.Leases.ContainsKey($key)) { throw 'path is not in immutable whitelist' }
    $lease = $Cache.Leases[$key]
    [pscustomobject]@{ Algorithm = 'SHA256'; Hash = $lease.Sha256; Path = $lease.Path; Bytes = $lease.Bytes; Cached = $true }
}

function Get-UncachedOutputHash([string]$Path) {
    # Explicit helper keeps Get-FileHash-compatible fields while forcing a fresh read.
    $item = Assert-CachePathNoReparse $Path
    $stream = [IO.FileStream]::new($item.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read,
        [IO.FileShare]::Read, $script:ImmutableInputCacheChunkBytes, [IO.FileOptions]::SequentialScan)
    try {
        $hash = Read-CacheStreamHash $stream
        [pscustomobject]@{ Algorithm = 'SHA256'; Hash = $hash; Path = $item.FullName; Bytes = $item.Length; Cached = $false }
    } finally { $stream.Dispose() }
}

function Close-ImmutableInputCache([object]$Cache) {
    if ($null -eq $Cache -or $Cache.Closed) { return [pscustomobject]@{ Closed = $true; LeasesClosed = 0 } }
    $closed = 0
    foreach ($lease in @($Cache.Leases.Values)) {
        try { $lease.Stream.Dispose(); $closed++ } catch { }
    }
    $Cache.Leases.Clear(); $Cache.Closed = $true
    [pscustomobject]@{ Kind = 'factory-immutable-input-cache-close-v1'; Closed = $true; LeasesClosed = $closed; TotalBytes = $Cache.TotalBytes }
}
