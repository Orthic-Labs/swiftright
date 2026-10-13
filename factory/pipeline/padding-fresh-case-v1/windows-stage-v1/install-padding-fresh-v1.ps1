# Bounded source installer for fresh Padding Windows compile stage.
# Verifies ZIP/manifest/source bytes before extraction; performs no compiler,
# native window, lock, or remote action.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PackageZip,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ZipSha256,
    [Parameter(Mandatory=$true)][string]$ManifestPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$ManifestSha256,
    [Parameter(Mandatory=$true)][string]$BuildScript,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$BuildSha256,
    [Parameter(Mandatory=$true)][string]$HelperPath,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$HelperSha256,
    [Parameter(Mandatory=$true)][string]$StageRoot
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$MaxFiles = 256
$MaxFileBytes = [Int64]67108864
$MaxTotalBytes = [Int64]268435456
$MaxJsonBytes = [Int64]8388608
$ChunkBytes = 1048576

function Fail([string]$Message) { throw "PADDING_INSTALL_HOLD: $Message" }
function Full([string]$Path) { return [IO.Path]::GetFullPath($Path) }

function Assert-Regular([string]$Path, [string]$Label, [Int64]$Limit) {
    $item = Get-Item -LiteralPath $Path -Force
    if($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) { Fail "$Label must be regular non-reparse" }
    if([Int64]$item.Length -gt $Limit) { Fail "$Label exceeds byte bound" }
    return $item
}

function Stream-Hash([string]$Path, [string]$Label, [Int64]$Limit) {
    $item = Assert-Regular $Path $Label $Limit
    $initial = [Int64]$item.Length
    $stream = $null
    $sha = [Security.Cryptography.SHA256]::Create()
    $total = [Int64]0
    try {
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $buffer = New-Object byte[] $ChunkBytes
        while(($count = $stream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $sha.TransformBlock($buffer,0,$count,$buffer,0) | Out-Null
            $total += $count
            if($total -gt $Limit) { Fail "$Label grew beyond bound" }
        }
        $sha.TransformFinalBlock([byte[]]::new(0),0,0) | Out-Null
        $digest = ([BitConverter]::ToString($sha.Hash) -replace '-','').ToLowerInvariant()
    } finally {
        if($stream) { $stream.Dispose() }
        $sha.Dispose()
    }
    if($total -ne $initial) { Fail "$Label changed during read" }
    return [ordered]@{ sha256=$digest; bytes=$total }
}

function Read-BoundedJson([string]$Path, [string]$Label) {
    $item = Assert-Regular $Path $Label $MaxJsonBytes
    $stream = $null
    $memory = [IO.MemoryStream]::new()
    $total = [Int64]0
    try {
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $buffer = New-Object byte[] $ChunkBytes
        while(($count = $stream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $total += $count
            if($total -gt $MaxJsonBytes) { Fail "$Label grew beyond JSON bound" }
            $memory.Write($buffer,0,$count)
        }
    } finally { if($stream) { $stream.Dispose() } }
    if($total -ne [Int64]$item.Length) { Fail "$Label changed during read" }
    $raw = $memory.ToArray(); $memory.Dispose()
    return ([Text.Encoding]::UTF8.GetString($raw).TrimStart([char]0xFEFF) | ConvertFrom-Json)
}

function Safe-Entry([string]$Name) {
    if([string]::IsNullOrWhiteSpace($Name) -or $Name.Contains('\') -or $Name.StartsWith('/') -or $Name.Contains(':')) { Fail "unsafe ZIP path: $Name" }
    $parts = $Name.Split('/')
    foreach($part in $parts) { if($part -eq '' -or $part -eq '.' -or $part -eq '..') { Fail "unsafe ZIP path: $Name" } }
    return ($parts -join '/')
}

function Hash-Entry([IO.Compression.ZipArchiveEntry]$Entry, [Int64]$Limit) {
    $input = $null; $sha = [Security.Cryptography.SHA256]::Create(); $total = [Int64]0
    try {
        $input = $Entry.Open()
        $buffer = New-Object byte[] $ChunkBytes
        while(($count = $input.Read($buffer,0,$buffer.Length)) -gt 0) {
            $sha.TransformBlock($buffer,0,$count,$buffer,0) | Out-Null
            $total += $count
            if($total -gt $Limit) { Fail "ZIP entry exceeds byte bound" }
        }
        $sha.TransformFinalBlock([byte[]]::new(0),0,0) | Out-Null
        return [ordered]@{ sha256=([BitConverter]::ToString($sha.Hash) -replace '-','').ToLowerInvariant(); bytes=$total }
    } finally {
        if($input) { $input.Dispose() }; $sha.Dispose()
    }
}

$zip = Full $PackageZip; $manifestFile = Full $ManifestPath; $build = Full $BuildScript; $helper = Full $HelperPath; $stage = Full $StageRoot
$expectedStage = Full 'D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3'
if($stage -cne $expectedStage) { Fail "StageRoot must be fresh r3 path: $expectedStage" }
if(Test-Path -LiteralPath $stage) { Fail "fresh StageRoot already exists" }
$zipInfo = Assert-Regular $zip 'PackageZip' $MaxTotalBytes
$manifestInfo = Assert-Regular $manifestFile 'ManifestPath' $MaxJsonBytes
$buildInfo = Assert-Regular $build 'BuildScript' $MaxFileBytes
$helperInfo = Assert-Regular $helper 'HelperPath' $MaxFileBytes
$zipDigest = Stream-Hash $zip 'PackageZip' $MaxTotalBytes
if($zipDigest.sha256 -cne $ZipSha256.ToLowerInvariant()) { Fail 'PackageZip SHA256 mismatch' }
$manifestDigest = Stream-Hash $manifestFile 'ManifestPath' $MaxJsonBytes
if($manifestDigest.sha256 -cne $ManifestSha256.ToLowerInvariant()) { Fail 'ManifestPath SHA256 mismatch' }
$buildDigest = Stream-Hash $build 'BuildScript' $MaxFileBytes
if($buildDigest.sha256 -cne $BuildSha256.ToLowerInvariant()) { Fail 'BuildScript SHA256 mismatch' }
$helperDigest = Stream-Hash $helper 'HelperPath' $MaxFileBytes
if($helperDigest.sha256 -cne $HelperSha256.ToLowerInvariant()) { Fail 'HelperPath SHA256 mismatch' }
$manifest = Read-BoundedJson $manifestFile 'stage manifest'
if($null -eq $manifest.files -or @($manifest.files).Count -gt $MaxFiles) { Fail 'manifest file count exceeds bound' }
$rows = @{}
$manifestTotal = [Int64]0
foreach($row in @($manifest.files)) {
    $relative = Safe-Entry ([string]$row.path)
    if($rows.ContainsKey($relative)) { Fail "duplicate manifest path: $relative" }
    $rows[$relative] = $row
    $bytes = [Int64]$row.bytes
    if($bytes -lt 0 -or $bytes -gt $MaxFileBytes) { Fail "manifest file bound: $relative" }
    if(([string]$row.sha256) -notmatch '^[0-9a-fA-F]{64}$') { Fail "manifest SHA256 malformed: $relative" }
    $manifestTotal += $bytes
    if($manifestTotal -gt $MaxTotalBytes) { Fail 'manifest total exceeds bound' }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = $null
try {
    $archive = [IO.Compression.ZipFile]::OpenRead($zip)
    $seen = @{}
    $zipFiles = 0; $zipTotal = [Int64]0
    foreach($entry in $archive.Entries) {
        $relative = Safe-Entry $entry.FullName
        if($entry.FullName.EndsWith('/')) { Fail "ZIP directory entry is not whitelisted: $relative" }
        if($seen.ContainsKey($relative)) { Fail "duplicate ZIP entry: $relative" }
        $seen[$relative] = $true; $zipFiles++
        if(-not $rows.ContainsKey($relative)) { Fail "ZIP entry absent from manifest: $relative" }
        $row = $rows[$relative]
        if([Int64]$entry.Length -ne [Int64]$row.bytes) { Fail "ZIP byte drift: $relative" }
        $entryHash = Hash-Entry $entry $MaxFileBytes
        $zipTotal += [Int64]$entry.Length
        if($entryHash.sha256 -cne ([string]$row.sha256).ToLowerInvariant()) { Fail "ZIP hash drift: $relative" }
        if($zipTotal -gt $MaxTotalBytes) { Fail 'ZIP total exceeds bound' }
    }
    if($zipFiles -ne $rows.Count) { Fail 'ZIP/manifest file set mismatch' }
} finally { if($archive) { $archive.Dispose() } }

New-Item -ItemType Directory -Path $stage -Force:$false | Out-Null
$packageDestination = Join-Path $stage 'package'; New-Item -ItemType Directory -Path $packageDestination -Force:$false | Out-Null
Expand-Archive -LiteralPath $zip -DestinationPath $packageDestination
$extracted = @{}
$extractedTotal = [Int64]0
foreach($item in @(Get-ChildItem -LiteralPath $packageDestination -Force -File -Recurse)) {
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Fail "extracted reparse file: $($item.FullName)" }
    $relative = $item.FullName.Substring($packageDestination.Length).TrimStart('\','/')
    $relative = $relative.Replace('\','/')
    $relative = Safe-Entry $relative
    if($extracted.ContainsKey($relative) -or -not $rows.ContainsKey($relative)) { Fail "extracted file absent from manifest: $relative" }
    $measured = Stream-Hash $item.FullName "extracted $relative" $MaxFileBytes
    $row = $rows[$relative]
    if($measured.bytes -ne [Int64]$row.bytes -or $measured.sha256 -cne ([string]$row.sha256).ToLowerInvariant()) { Fail "extracted file drift: $relative" }
    $extracted[$relative] = $true
    $extractedTotal += $measured.bytes
}
if($extracted.Count -ne $rows.Count -or $extractedTotal -ne $zipTotal) { Fail 'extracted package/manifest set mismatch' }
$manifestDestination = Join-Path $stage 'inputs\stage-manifest.json'; $helperDestination = Join-Path $stage 'inputs\Sr0OwnedJobProcess.cs'; $buildDestination = Join-Path $stage 'build-padding-fresh-v1.ps1'
New-Item -ItemType Directory -Path (Split-Path -Parent $manifestDestination) -Force:$false | Out-Null
Copy-Item -LiteralPath $manifestFile -Destination $manifestDestination -Force:$false
Copy-Item -LiteralPath $helper -Destination $helperDestination -Force:$false
Copy-Item -LiteralPath $build -Destination $buildDestination -Force:$false
$stageReceipt = [ordered]@{schema='factory-padding-fresh-windows-stage-install-v1';status='source-installed';nativeActions=0;compilerActions=0;lockActions=0;remoteActions=0;stageRoot=$stage;packageZipSha256=$zipDigest.sha256;manifestSha256=$manifestDigest.sha256;buildSha256=$buildDigest.sha256;helperSha256=$helperDigest.sha256;packageFiles=$zipFiles;packageBytes=$zipTotal;helperPath='inputs/Sr0OwnedJobProcess.cs';buildScript='build-padding-fresh-v1.ps1'}
$stageReceipt | ConvertTo-Json -Depth 12
