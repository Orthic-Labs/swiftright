# Tuple12 F1 source-bound smoke worker. Runs inside one hidden interactive task; never deletes output or tasks.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$Driver,
  [Parameter(Mandatory)][string]$ExpectExe,
  [Parameter(Mandatory)][string]$ExpectDll,
  [Parameter(Mandatory)][string]$RunRoot,
  [Parameter(Mandatory)][string]$Receipt
)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Sr0SmokeKernel {
  public static class Native {
    [DllImport("kernel32.dll", SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr handle, out uint exitCode);
  }
}
'@
$expectedExe = $ExpectExe.ToLowerInvariant()
$expectedDll = $ExpectDll.ToLowerInvariant()
if ($expectedExe -notmatch '^[0-9a-f]{64}$' -or $expectedDll -notmatch '^[0-9a-f]{64}$') { throw 'expected artifact hash is not SHA-256' }
$bin = Join-Path $Base 'scratch\out\Products\Release-windows-x86_64'
$exe = Join-Path $bin 'FreshOnBridge.exe'
$dll = Join-Path $bin 'swiftright_render.dll'
$driverFull = [IO.Path]::GetFullPath($Driver)
$exeFull = [IO.Path]::GetFullPath($exe)
$trace = Join-Path $RunRoot 'driver-trace.txt'
$stdoutPath = Join-Path $RunRoot 'driver.stdout.bin'
$stderrPath = Join-Path $RunRoot 'driver.stderr.bin'
$workerPid = [Diagnostics.Process]::GetCurrentProcess().Id
$driverProc = $null
$childProc = $null
$driverHandle = [IntPtr]::Zero
$childHandle = [IntPtr]::Zero
$outStream = $null
$errStream = $null
$stdoutTask = $null
$stderrTask = $null
$workerCode = 1
$failure = $null
$proof = [ordered]@{
  kind = 'sr0-tuple12-startupguard-f1-worker-v1'
  status = 'failed'
  workerPid = $workerPid
  base = $Base
  driver = $driverFull
  expected = [ordered]@{ exe = $expectedExe; renderer = $expectedDll }
  runRoot = $RunRoot
  receipt = $Receipt
  nativeLaunches = 0
  lockActions = 0
}
function Quote-Arg([string]$v) { return '"' + $v.Replace('"', '\"') + '"' }
function Hash-Ref([string]$path) {
  $i = Get-Item -LiteralPath $path -ErrorAction Stop
  return [ordered]@{ path = $path; bytes = [int64]$i.Length; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
}
function Observe-FreshChild([int]$parentPid) {
  @(Get-CimInstance Win32_Process -Filter ("ParentProcessId={0}" -f $parentPid) -ErrorAction Stop |
    Where-Object { $_.Name -ieq 'FreshOnBridge.exe' })
}
function Kernel-Terminal([IntPtr]$handle) {
  if ($handle -eq [IntPtr]::Zero) { return [ordered]@{ terminal = $false; wait = 'invalid'; getExitCode = $false; exitCode = $null } }
  [uint32]$code = 259
  $wait = [Sr0SmokeKernel.Native]::WaitForSingleObject($handle, 0)
  $ok = [Sr0SmokeKernel.Native]::GetExitCodeProcess($handle, [ref]$code)
  return [ordered]@{ terminal = ($wait -eq 0 -and $ok -and $code -ne 259); wait = $wait; getExitCode = $ok; exitCode = [int64]$code }
}
try {
  foreach ($path in @($Base, $Driver, $exe, $dll)) { if (-not (Test-Path -LiteralPath $path)) { throw "missing pinned path: $path" } }
  if (Test-Path -LiteralPath $RunRoot) { throw "run namespace already exists: $RunRoot" }
  if (Test-Path -LiteralPath $Receipt) { throw "receipt already exists: $Receipt" }
  [IO.Directory]::CreateDirectory($RunRoot) | Out-Null
  [IO.Directory]::CreateDirectory((Split-Path -Parent $Receipt)) | Out-Null
  $driverRef = Hash-Ref $driverFull; $exeRef = Hash-Ref $exe; $dllRef = Hash-Ref $dll
  if ($exeRef.sha256 -cne $expectedExe) { throw 'FreshOnBridge hash mismatch' }
  if ($dllRef.sha256 -cne $expectedDll) { throw 'renderer hash mismatch' }
  $proof.driverScript = $driverRef; $proof.exe = $exeRef; $proof.renderer = $dllRef

  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = Join-Path $PSHOME 'powershell.exe'
  $psi.Arguments = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File {0} -Base {1} -Fixture F1 -Variant "" -Out {2} -KeyMode char -NoActivate' -f (Quote-Arg $driverFull), (Quote-Arg ([IO.Path]::GetFullPath($Base))), (Quote-Arg $trace))
  $psi.WorkingDirectory = $bin
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables['SR0S_DELIVERY'] = 'targeted'
  $driverProc = [Diagnostics.Process]::Start($psi)
  if ($null -eq $driverProc) { throw 'driver process did not start' }
  $proof.driverPid = $driverProc.Id
  # Retain driver kernel handle before any wait or refresh.
  $driverHandle = $driverProc.Handle
  $proof.driverHandle = [ordered]@{ value = $driverHandle.ToInt64(); retained = (-not $driverProc.SafeHandle.IsClosed) }
  $outStream = [IO.File]::Open($stdoutPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
  $errStream = [IO.File]::Open($stderrPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
  try {
    $stdoutTask = $driverProc.StandardOutput.BaseStream.CopyToAsync($outStream)
    $stderrTask = $driverProc.StandardError.BaseStream.CopyToAsync($errStream)
    $deadline = [DateTime]::UtcNow.AddMinutes(6)
    while (-not $driverProc.HasExited -and [DateTime]::UtcNow -lt $deadline) {
      $rows = @(Observe-FreshChild $driverProc.Id)
      if ($rows.Count -gt 1) { throw 'more than one FreshOnBridge child under driver' }
      if ($rows.Count -eq 1) {
        $row = $rows[0]
        $path = [IO.Path]::GetFullPath([string]$row.ExecutablePath)
        if ($path -cne $exeFull) { throw "FreshOnBridge child path mismatch: $path" }
        if ($null -eq $childProc) {
          $childProc = [Diagnostics.Process]::GetProcessById([int]$row.ProcessId)
          $childHandle = $childProc.Handle
          $proof.childPid = $childProc.Id
          $proof.childPath = $path
          $proof.childHandle = [ordered]@{ value = $childHandle.ToInt64(); retained = (-not $childProc.SafeHandle.IsClosed) }
          $proof.nativeLaunches = 1
        } elseif ($childProc.Id -ne [int]$row.ProcessId) { throw 'FreshOnBridge child PID changed' }
      }
      Start-Sleep -Milliseconds 200
    }
    if (-not $driverProc.HasExited) { throw 'driver timeout; process left for coordinator quiescence audit' }
    $driverProc.WaitForExit()
    $stdoutTask.GetAwaiter().GetResult(); $stderrTask.GetAwaiter().GetResult()
  } finally { $outStream.Dispose(); $errStream.Dispose() }
  $driverProc.Refresh()
  $proof.driverKernel = Kernel-Terminal $driverHandle
  if (-not $proof.driverKernel.terminal) { throw 'driver kernel handle is not terminal' }
  $proof.driverExitCode = [int]$proof.driverKernel.exitCode
  if ($null -eq $childProc) { throw 'exact FreshOnBridge child was never observed' }
  $childDeadline = [DateTime]::UtcNow.AddSeconds(30)
  while (-not $childProc.HasExited -and [DateTime]::UtcNow -lt $childDeadline) { Start-Sleep -Milliseconds 200; $childProc.Refresh() }
  if (-not $childProc.HasExited) { throw 'FreshOnBridge child remained running after driver exit' }
  $childProc.Refresh(); $proof.childKernel = Kernel-Terminal $childHandle
  if (-not $proof.childKernel.terminal) { throw 'FreshOnBridge kernel handle is not terminal' }
  $proof.childExitCode = [int]$proof.childKernel.exitCode
  if ($proof.driverExitCode -ne 0 -or $proof.childExitCode -ne 0) { throw "terminal exit failure driver=$($proof.driverExitCode) child=$($proof.childExitCode)" }
  if (-not (Test-Path -LiteralPath $trace -PathType Leaf)) { throw 'driver trace missing' }
  $traceText = [IO.File]::ReadAllText($trace)
  $guardAt = $traceText.IndexOf('SR0_NOACTIVATE guard=installed', [StringComparison]::OrdinalIgnoreCase)
  $readyAt = $traceText.IndexOf('SR0_RENDERER_READY file=created', [StringComparison]::OrdinalIgnoreCase)
  if ($guardAt -lt 0 -or $readyAt -le $guardAt) { throw 'no-activate guard marker missing or follows renderer-ready marker' }
  foreach ($needle in @('renderer_ready_event=True','SR0_RENDERER_READY file=created','record=renderer-ready','phase=first-ready','source=Bridge.onReady','WindowMetrics phase=startup','client_ok=True','same_process=True','focus[Row 5]=ok','focused_after_focus=[Row 5]','SELFTEST F1: PASS','driver_abort=none','driver_close_ready_file=True','close_window=WM_CLOSE posted=True','same_hwnd=True','same_handle=True','exit=0',("ARTIFACTS exe={0} renderer={1}" -f $expectedExe,$expectedDll))) {
    if ($traceText.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "required trace field missing: $needle" }
  }
  $proof.rawDriverStreams = [ordered]@{ stdout = Hash-Ref $stdoutPath; stderr = Hash-Ref $stderrPath }
  $proof.trace = Hash-Ref $trace
  $proof.outputs = @((Get-ChildItem -LiteralPath $RunRoot -File -Recurse | ForEach-Object { Hash-Ref $_.FullName }))
  $proof.status = 'passed'; $workerCode = 0
} catch { $failure = $_.Exception.Message; $proof.failure = $failure; $workerCode = 1 }
finally {
  if ($null -ne $outStream) { try { $outStream.Dispose() } catch {} }
  if ($null -ne $errStream) { try { $errStream.Dispose() } catch {} }
  if ($driverHandle -ne [IntPtr]::Zero) { try { $proof.driverKernel = Kernel-Terminal $driverHandle } catch { $proof.driverKernel = [ordered]@{ terminal = $false; error = $_.Exception.Message } } }
  if ($childHandle -ne [IntPtr]::Zero) { try { $proof.childKernel = Kernel-Terminal $childHandle } catch { $proof.childKernel = [ordered]@{ terminal = $false; error = $_.Exception.Message } } }
  if (Test-Path -LiteralPath $stdoutPath -PathType Leaf) { try { if ($null -eq $proof.rawDriverStreams) { $proof.rawDriverStreams = [ordered]@{} }; $proof.rawDriverStreams.stdout = Hash-Ref $stdoutPath } catch { $proof.rawDriverStreams = [ordered]@{ stdoutError = $_.Exception.Message } } }
  if (Test-Path -LiteralPath $stderrPath -PathType Leaf) { try { if ($null -eq $proof.rawDriverStreams) { $proof.rawDriverStreams = [ordered]@{} }; $proof.rawDriverStreams.stderr = Hash-Ref $stderrPath } catch { $proof.rawDriverStreams.stderrError = $_.Exception.Message } }
  if (Test-Path -LiteralPath $RunRoot -PathType Container) { try { $proof.outputs = @((Get-ChildItem -LiteralPath $RunRoot -File -Recurse | ForEach-Object { Hash-Ref $_.FullName })) } catch { $proof.outputsError = $_.Exception.Message } }
  if ($null -ne $driverProc) { try { $driverProc.Dispose() } catch {} }
  if ($null -ne $childProc) { try { $childProc.Dispose() } catch {} }
  $proof.workerExitCode = $workerCode
  $proof.at = [DateTimeOffset]::UtcNow.ToString('o')
  $json = $proof | ConvertTo-Json -Depth 12
  if (-not (Test-Path -LiteralPath $Receipt)) {
    $receiptStream = [IO.File]::Open($Receipt, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $receiptBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($json); $receiptStream.Write($receiptBytes,0,$receiptBytes.Length); $receiptStream.Flush($true) } finally { $receiptStream.Dispose() }
  }
}
if ($workerCode -ne 0) { throw $failure }
exit 0
