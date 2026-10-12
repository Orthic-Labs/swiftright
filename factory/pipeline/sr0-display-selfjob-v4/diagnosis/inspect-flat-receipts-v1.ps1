param(
    [Parameter(Mandatory = $true)][string[]]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$MaxFileBytes = 2MB
$MaxTotalBytes = 8MB
$MaxFiles = 32
$MaxFieldsPerFile = 24
$MaxFieldBytes = 256

function Escape-Json([string]$Value) {
    if ($null -eq $Value) { return 'null' }
    return '"' + ($Value.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')) + '"'
}

function Get-FlatFields([string]$Text) {
    $names = @(
        'kind', 'status', 'pid', 'path', 'startedAt', 'observedAt', 'finishedAt',
        'runID', 'runId', 'kernelWait', 'rawExit', 'dotnetExit', 'exitCode',
        'streamDrainComplete', 'streamsSealed', 'lockReleased', 'windowDeadline',
        'nativeDeadline', 'primaryError', 'error'
    )
    $namePattern = ($names | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $rx = [regex]::new(('"(?<name>' + $namePattern + ')"\s*:\s*(?:"(?<string>(?:\\.|[^"\\])*)"|(?<scalar>-?\d+|true|false|null))'), [Text.RegularExpressions.RegexOptions]::CultureInvariant)
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($m in $rx.Matches($Text)) {
        if ($rows.Count -ge $MaxFieldsPerFile) { break }
        $raw = if ($m.Groups['string'].Success) { $m.Groups['string'].Value } else { $m.Groups['scalar'].Value }
        if ($raw.Length -gt $MaxFieldBytes) { $raw = $raw.Substring(0, $MaxFieldBytes) }
        $rows.Add([ordered]@{ name = $m.Groups['name'].Value; raw = $raw })
    }
    return @($rows)
}

function Read-BoundedUtf8([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "regular non-reparse file required: $Path" }
    if ($item.Length -gt $MaxFileBytes) { throw "receipt exceeds 2MiB: $Path" }
    $bytes = [IO.File]::ReadAllBytes($item.FullName)
    if ($bytes.Length -gt $MaxFileBytes) { throw "receipt grew past bound: $Path" }
    return [Text.Encoding]::UTF8.GetString($bytes)
}

function Render-Row([object]$Row) {
    $fields = @($Row.fields | ForEach-Object { '{0}:{1}' -f (Escape-Json $_.name), (Escape-Json $_.raw) }) -join ','
    return ('{{"path":{0},"bytes":{1},"sha256":{2},"fields":{{{3}}}}}' -f (Escape-Json $Row.path), $Row.bytes, (Escape-Json $Row.sha256), $fields)
}

$rows = New-Object 'System.Collections.Generic.List[object]'
$total = [int64]0
$seen = @{}
if ($InputPath.Count -gt $MaxFiles) { throw 'receipt file count exceeds 32' }
foreach ($input in $InputPath) {
    $full = [IO.Path]::GetFullPath($input)
    if ($seen.ContainsKey($full)) { throw "duplicate input path: $full" }
    $seen[$full] = $true
    $item = Get-Item -LiteralPath $full -Force
    if ($item.Length -gt $MaxFileBytes) { throw "receipt exceeds 2MiB: $full" }
    $total += [int64]$item.Length
    if ($total -gt $MaxTotalBytes) { throw 'receipt aggregate exceeds 8MiB' }
    $text = Read-BoundedUtf8 $full
    $rows.Add([ordered]@{
        path = $full
        bytes = [int64]$item.Length
        sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
        fields = @(Get-FlatFields $text)
    })
}

$rendered = @($rows | ForEach-Object { Render-Row $_ }) -join ','
$json = '{"kind":"sr0-flat-receipt-inspection-v1","transportJobRequired":"sr0-root-transport-job-v1","recursiveJson":false,"dateTimeConversion":false,"totalBytes":' + $total + ',"files":[' + $rendered + ']}'
$parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'output parent must already exist' }
$tmp = ([IO.Path]::GetFullPath($OutputPath)) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
$bytesOut = [Text.Encoding]::UTF8.GetBytes($json + "`r`n")
try {
    $stream = [IO.File]::Open($tmp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytesOut, 0, $bytesOut.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    [IO.File]::Move($tmp, [IO.Path]::GetFullPath($OutputPath))
} catch {
    if (Test-Path -LiteralPath $tmp) { [IO.File]::Delete($tmp) }
    throw
}
