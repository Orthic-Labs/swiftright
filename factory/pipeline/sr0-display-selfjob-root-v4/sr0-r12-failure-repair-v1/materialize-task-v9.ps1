[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SourcePath,
  [Parameter(Mandatory)][string]$OutputPath,
  [int64]$MaxSourceBytes = 2097152
)
$ErrorActionPreference = 'Stop'
$source = Get-Item -LiteralPath $SourcePath -Force -ErrorAction Stop
if ($source.PSIsContainer -or ($source.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $source.Length -gt $MaxSourceBytes) { throw 'source task must be bounded regular file' }
if (Test-Path -LiteralPath $OutputPath) { throw "fresh output required: $OutputPath" }
$text = [IO.File]::ReadAllText($source.FullName)
$replacements = @(
  @('$lines.Add("worker run=$id pid=$($proc.Id) parent_pid=$PID full_path=$workerFullPath")', '$lines.Add("worker run=$id pid=$($proc.Id) parent_pid=$PID full_path=$workerFullPath")`r`n  Flush-Out'),
  @('$lines.Add("pid run=$id pid=$($proc.Id) handle=$workerHandle start_utc=$([DateTime]::UtcNow.ToString(''o'')) qpc_start=$qs")', '$lines.Add("pid run=$id pid=$($proc.Id) handle=$workerHandle start_utc=$([DateTime]::UtcNow.ToString(''o'')) qpc_start=$qs")`r`n  Flush-Out'),
  @('$lines.Add("pid_exit run=$id pid=$($proc.Id) handle=$workerHandle qpc_end=$qe exit=$exit kernel_terminal=$([int]$workerTerminal) kernel_exit_raw=$kernelCode kernel_exit=$kernelCodeSigned dotnet_exit=$dotnetExit")', '$lines.Add("pid_exit run=$id pid=$($proc.Id) handle=$workerHandle qpc_end=$qe exit=$exit kernel_terminal=$([int]$workerTerminal) kernel_exit_raw=$kernelCode kernel_exit=$kernelCodeSigned dotnet_exit=$dotnetExit")`r`n  Flush-Out'),
  @('$lines.Add("stream_drain_diagnostics run=$id process_wait=$([int]$drain.processWaitCompleted) process_terminal=$([int]$drain.processTerminal) stdout_fault=$([int]$drain.stdoutFaulted) stderr_fault=$([int]$drain.stderrFaulted) stdout_canceled=$([int]$drain.stdoutCanceled) stderr_canceled=$([int]$drain.stderrCanceled)")', '$lines.Add("stream_drain_diagnostics run=$id process_wait=$([int]$drain.processWaitCompleted) process_terminal=$([int]$drain.processTerminal) stdout_fault=$([int]$drain.stdoutFaulted) stderr_fault=$([int]$drain.stderrFaulted) stdout_canceled=$([int]$drain.stdoutCanceled) stderr_canceled=$([int]$drain.stderrCanceled)")`r`n  Flush-Out')
)
foreach ($pair in $replacements) {
  $needle = [string]$pair[0]
  if ([regex]::Matches($text,[regex]::Escape($needle)).Count -ne 1) { throw "expected one publication marker: $needle" }
  $text = $text.Replace($needle,[string]$pair[1])
}
$parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
$tmp = "$OutputPath.$PID.$([guid]::NewGuid().ToString('N')).tmp"
$s = [IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
try { $bytes = [Text.Encoding]::UTF8.GetBytes($text); $s.Write($bytes,0,$bytes.Length); $s.Flush($true) } finally { $s.Dispose() }
[IO.File]::Move($tmp,$OutputPath)
[ordered]@{status='materialized';source=$source.FullName;output=[IO.Path]::GetFullPath($OutputPath);bytes=$bytes.Length;publicationMarkers=4;qualificationClaim=$false} | ConvertTo-Json -Depth 8
