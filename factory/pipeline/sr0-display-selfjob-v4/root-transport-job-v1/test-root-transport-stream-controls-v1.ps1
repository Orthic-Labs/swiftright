param([Parameter(Mandatory = $true)][string]$WrapperPath)
$ErrorActionPreference = 'Stop'
$text = [IO.File]::ReadAllText([IO.Path]::GetFullPath($WrapperPath))
foreach ($needle in @(
    'RedirectStandardOutput', 'RedirectStandardError', 'StartBoundedDrain',
    'streamCapBytes=8388608', 'stdoutPath=', 'stderrPath=',
    'stdoutBytes=', 'stderrBytes=', 'stdoutSha256=', 'stderrSha256=',
    'streamsSealed=', 'outputCapExceeded=', 'childHandleAcquired=',
    'childTerminal=', 'childExitIdentity='
)) { if (-not $text.Contains($needle)) { throw "stream control needle missing: $needle" } }
foreach ($forbidden in @('ReadToEnd', 'ReadToEndAsync', 'StandardOutput.ReadToEnd', 'StandardError.ReadToEnd')) {
    if ($text.Contains($forbidden)) { throw "unbounded child output read present: $forbidden" }
}
$drainStart = $text.IndexOf('StartBoundedDrain', [StringComparison]::Ordinal)
$dispose = $text.IndexOf('$child.StandardOutput.Dispose()', [StringComparison]::Ordinal)
$proof = $text.IndexOf('Get-StreamProof', $dispose, [StringComparison]::Ordinal)
if ($drainStart -lt 0 -or $dispose -lt 0 -or $proof -lt 0 -or $dispose -ge $proof) { throw 'stream drain/close/hash ordering invalid' }
@{ kind = 'sr0-root-transport-stream-controls-v1'; status = 'passed-source-controls'; nativeActions = 0; streamCapBytes = 8388608; boundedReads = $true; closeBeforeHash = $true } | ConvertTo-Json -Compress
