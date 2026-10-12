# Source controls for immutable-input-cache-v1; root runs under supervise-job.
param(
    [Parameter(Mandatory=$true)][string]$ControlRoot,
    [Parameter(Mandatory=$true)][string]$ReparsePath,
    [Parameter(Mandatory=$true)][string]$CacheSource
)
$ErrorActionPreference='Stop'; . $CacheSource
$run = Join-Path $ControlRoot ('cache-control-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $run -Force | Out-Null
$input = Join-Path $run 'immutable-input.bin'; [IO.File]::WriteAllBytes($input, [Text.Encoding]::UTF8.GetBytes('immutable-source-v1'))
$expected = (Get-UncachedOutputHash $input).Hash
$bytes = (Get-Item -LiteralPath $input).Length
$results = [ordered]@{}

$cache = New-ImmutableInputCache @([pscustomobject]@{Path=$input;Sha256=$expected;Bytes=$bytes})
try {
    $results.baseline = ((Get-ImmutableInputHash $cache $input).Hash -ceq $expected)
    try { $writer=[IO.File]::Open($input,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None); $writer.Dispose(); throw 'write unexpectedly succeeded' }
    catch {
        $errorText = $_.Exception.Message
        if ($errorText -eq 'write unexpectedly succeeded') { throw }
        if ($_.Exception -is [IO.IOException] -or $_.Exception.InnerException -is [IO.IOException] -or $errorText -match 'sharing|denied|access') { $results.writeBlockedWhileLeased = $true }
        else { throw }
    }
} finally { Close-ImmutableInputCache $cache | Out-Null }

try { New-ImmutableInputCache @([pscustomobject]@{Path=$input;Sha256=('0'*64);Bytes=$bytes}) | Out-Null; throw 'wrong hash unexpectedly admitted' }
catch { $results.wrongHashRejected = $_.Exception.Message -match 'mismatch|changed' }

$output = Join-Path $run 'unlisted-output.bin'; [IO.File]::WriteAllText($output, 'one')
$one = (Get-UncachedOutputHash $output).Hash; [IO.File]::WriteAllText($output, 'two')
$two = (Get-UncachedOutputHash $output).Hash; $results.unlistedOutputRehashed = $one -cne $two

try { New-ImmutableInputCache @([pscustomobject]@{Path=$ReparsePath;Sha256=('0'*64);Bytes=0}) | Out-Null; throw 'reparse unexpectedly admitted' }
catch { $results.reparseRejected = $_.Exception.Message -match 'reparse|regular' }

if ($results.Values -contains $false) { throw 'immutable cache control failed' }
[ordered]@{kind='factory-immutable-input-cache-controls-v1';status='passed';controls=$results;nativeActions=0;compilerActions=0;lockActions=0}|ConvertTo-Json -Depth 8
