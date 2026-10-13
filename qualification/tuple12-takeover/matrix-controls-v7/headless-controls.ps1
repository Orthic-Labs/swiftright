# Matrix v7 headless process controls. Root runs after parser review on Dell.
# Uses owned PowerShell children only; no GUI, lock, scheduled task, input, or cleanup deletion.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$OutRoot,
  [ValidateRange(1,30)][int]$TimeoutSeconds = 5
)
$ErrorActionPreference = 'Stop'
function Write-CreateNew([string]$Path, [string]$Text) {
  if (Test-Path -LiteralPath $Path) { throw "output exists: $Path" }
  $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
  $s = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
  try { $s.Write($bytes,0,$bytes.Length); $s.Flush($true) } finally { $s.Dispose() }
}
function Require-Fresh([string]$Path) {
  if (Test-Path -LiteralPath $Path) { throw "output namespace exists: $Path" }
  [IO.Directory]::CreateDirectory($Path) | Out-Null
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Sr0MatrixV7ControlKernel {
  [DllImport("kernel32.dll", SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
}
'@
function Invoke-OwnedChild([string]$Name, [string]$Command, [int]$DeadlineSeconds, [bool]$ExpectTimeout) {
  $root = Join-Path $OutRoot $Name
  Require-Fresh $root
  $stdoutPath = Join-Path $root 'stdout.bin'; $stderrPath = Join-Path $root 'stderr.bin'
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = Join-Path $PSHOME 'powershell.exe'
  $psi.Arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -Command ' + ('"' + $Command.Replace('"','\"') + '"')
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $proc = $null; $handle = [IntPtr]::Zero; $outStream = $null; $errStream = $null; $outTask = $null; $errTask = $null
  $terminal = $false; $timedOut = $false; $streamCap = $false; [uint32]$exitCode = 259; [int64]$peakRss = 0
  try {
    $proc = [Diagnostics.Process]::Start($psi); if ($null -eq $proc) { throw 'owned headless child did not start' }
    $handle = $proc.Handle
    $outStream = [IO.File]::Open($stdoutPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $errStream = [IO.File]::Open($stderrPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $outTask = $proc.StandardOutput.BaseStream.CopyToAsync($outStream); $errTask = $proc.StandardError.BaseStream.CopyToAsync($errStream)
    $watch = [Diagnostics.Stopwatch]::StartNew(); $wait = 258
    while ($true) {
      $wait = [Sr0MatrixV7ControlKernel]::WaitForSingleObject($handle,1000)
      try { $proc.Refresh(); if ([int64]$proc.WorkingSet64 -gt $peakRss) { $peakRss = [int64]$proc.WorkingSet64 } } catch {}
      if ((Get-Item -LiteralPath $stdoutPath).Length -gt 1048576 -or (Get-Item -LiteralPath $stderrPath).Length -gt 1048576) { $streamCap = $true; break }
      if ($wait -eq 0) { break }
      if ($watch.Elapsed.TotalSeconds -ge $DeadlineSeconds) { $timedOut = $true; break }
    }
    if ($timedOut -or $streamCap) { $proc.Kill(); $wait = [Sr0MatrixV7ControlKernel]::WaitForSingleObject($handle,5000) }
    $kernelReadable = [Sr0MatrixV7ControlKernel]::GetExitCodeProcess($handle,[ref]$exitCode)
    $terminal = ($wait -eq 0 -and $kernelReadable -and $exitCode -ne 259)
    $outDone = $outTask.Wait(5000)
    $errDone = $errTask.Wait(5000)
    $drained = $outDone -and $errDone
    $result = [ordered]@{ name=$Name; terminal=$terminal; timedOut=$timedOut; streamCap=$streamCap; kernelExit=[uint64]$exitCode; kernelReadable=$kernelReadable; streamsDrained=$drained; peakRssBytes=$peakRss; originalHandleRetained=($handle -ne [IntPtr]::Zero); expectedTimeout=$ExpectTimeout }
    if ($ExpectTimeout) { if (-not $timedOut -or -not $terminal -or -not $drained) { throw 'timeout fault control did not prove owned termination/drain' } }
    else { if ($timedOut -or $streamCap -or -not $terminal -or $exitCode -ne 0 -or -not $drained) { throw 'headless positive control failed' } }
    return $result
  } finally {
    if ($outStream) { $outStream.Dispose() }; if ($errStream) { $errStream.Dispose() }; if ($proc) { $proc.Dispose() }
  }
}
Require-Fresh $OutRoot
$results = @(
  (Invoke-OwnedChild 'positive' 'Write-Output matrix-v7-positive' 5 $false),
  (Invoke-OwnedChild 'timeout-fault' 'Start-Sleep -Seconds 30' $TimeoutSeconds $true)
)
$receipt = [ordered]@{ kind='sr0-tuple12-matrix-headless-controls-v1'; status='passed'; results=$results; gui=$false; desktopLock=$false; nativeInput=$false; deletion=$false }
Write-CreateNew (Join-Path $OutRoot 'controls.json') (($receipt | ConvertTo-Json -Depth 8) + "`r`n")
Write-Output (($receipt | ConvertTo-Json -Depth 8))
