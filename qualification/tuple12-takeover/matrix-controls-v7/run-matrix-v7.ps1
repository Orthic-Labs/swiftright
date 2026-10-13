# Tuple12 candidate matrix runner v7. Requires admitted noactivate F1 smoke before any matrix task.
# It preserves every output/task, bounds each coordinator, uses targeted delivery, & aborts remaining cases on bounded failure.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$Driver,
  [Parameter(Mandatory)][string]$Worker,
  [Parameter(Mandatory)][string]$Coordinator,
  [Parameter(Mandatory)][string]$ExpectWorker,
  [Parameter(Mandatory)][string]$ExpectCoordinator,
  [Parameter(Mandatory)][string]$SmokeReceipt,
  [Parameter(Mandatory)][string]$ExpectExe,
  [Parameter(Mandatory)][string]$ExpectDll,
  [Parameter(Mandatory)][string]$ExpectDriver,
  [Parameter(Mandatory)][string]$OutRoot,
  [ValidateSet('F1','F6Reduced','Full')][string]$Mode = 'F1',
  [ValidateSet(20)][int]$Runs = 20,
  [ValidateRange(30,300)][int]$CoordinatorTimeoutSeconds = 300,
  [ValidateRange(1048576,67108864)][int64]$CoordinatorStreamCapBytes = 8388608,
  [ValidateRange(134217728,4294967296)][int64]$CoordinatorRssCapBytes = 2147483648,
  [string]$Lock = 'D:\Claude\desktop.lock'
)
$ErrorActionPreference = 'Stop'
$expectedExe = $ExpectExe.ToLowerInvariant(); $expectedDll = $ExpectDll.ToLowerInvariant(); $expectedDriver = $ExpectDriver.ToLowerInvariant(); $expectedWorker = $ExpectWorker.ToLowerInvariant(); $expectedCoordinator = $ExpectCoordinator.ToLowerInvariant()
foreach ($name in @('ExpectExe','ExpectDll','ExpectDriver','ExpectWorker','ExpectCoordinator')) {
  $value = Get-Variable -Name $name -ValueOnly
  if ($value -notmatch '^[0-9a-f]{64}$') { throw "$name is not SHA-256" }
}
function Full-Leaf([string]$path) {
  $item = Get-Item -LiteralPath $path -ErrorAction Stop
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "reparse-point input rejected: $path" }
  return $item.FullName
}
function Hash-Lower([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Read-BoundedText([string]$path, [Int64]$maxBytes = 8388608) {
  $item = Get-Item -LiteralPath $path -ErrorAction Stop
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "reparse-point text rejected: $path" }
  if ($item.Length -gt $maxBytes) { throw "text exceeds bounded read: $path" }
  return [IO.File]::ReadAllText($path)
}
function Write-Exclusive([string]$path, [string]$text) {
  if (Test-Path -LiteralPath $path) { throw "output exists: $path" }
  $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
  try { $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($text); $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}
function Assert-Receipt([string]$path, [bool]$smoke) {
  $r = Read-BoundedText $path | ConvertFrom-Json
  if ([string]$r.kind -notin @('sr0-tuple12-startupguard-matrix-worker-v3','sr0-tuple12-startupguard-matrix-worker-v4','sr0-tuple12-startupguard-matrix-worker-v5')) { throw "unexpected worker receipt kind: $path" }
  if ($r.status -ne 'passed' -or $r.workerExitCode -ne 0 -or $r.driverExitCode -ne 0 -or $r.childExitCode -ne 0) { throw "receipt is not admitted: $path" }
  if (-not $r.driverScript -or $r.driverScript.sha256.ToLowerInvariant() -cne $expectedDriver) { throw "driver receipt hash mismatch: $path" }
  if ($r.exe.sha256.ToLowerInvariant() -cne $expectedExe -or $r.renderer.sha256.ToLowerInvariant() -cne $expectedDll) { throw "artifact receipt hash mismatch: $path" }
  if (-not $r.driverKernel.terminal -or -not $r.childKernel.terminal -or -not $r.driverHandle.retained -or -not $r.childHandle.retained) { throw "kernel/handle proof missing: $path" }
  return $r
}
$baseFull = Full-Leaf $Base
$driverFull = Full-Leaf $Driver
$workerFull = Full-Leaf $Worker
$coordinatorFull = Full-Leaf $Coordinator
$smokeFull = Full-Leaf $SmokeReceipt
if ((Hash-Lower $driverFull) -cne $expectedDriver) { throw 'candidate driver hash mismatch' }
if ((Hash-Lower $workerFull) -cne $expectedWorker) { throw 'candidate worker source hash mismatch' }
if ((Hash-Lower $coordinatorFull) -cne $expectedCoordinator) { throw 'candidate coordinator source hash mismatch' }
$smoke = Assert-Receipt $smokeFull $true
$bin = Join-Path $baseFull 'scratch\out\Products\Release-windows-x86_64'
$exe = Join-Path $bin 'FreshOnBridge.exe'; $dll = Join-Path $bin 'swiftright_render.dll'
if ((Hash-Lower $exe) -cne $expectedExe -or (Hash-Lower $dll) -cne $expectedDll) { throw 'candidate artifact hash mismatch before matrix' }
if (Test-Path -LiteralPath $OutRoot) {
  if (-not (Get-Item -LiteralPath $OutRoot).PSIsContainer) { throw 'OutRoot exists and is not directory' }
  $existing = @(Get-ChildItem -LiteralPath $OutRoot -Force)
  if ($existing.Count -ne 0) { throw 'OutRoot must be fresh and empty' }
} else { [IO.Directory]::CreateDirectory($OutRoot) | Out-Null }
$configs = @(
  [pscustomobject]@{ Fixture='F1'; Variant='' }
)
if ($Mode -eq 'F6Reduced') {
  $configs = @(
    [pscustomobject]@{ Fixture='F6'; Variant='reduced' }
  )
}
if ($Mode -eq 'Full') {
  $configs = @(
    [pscustomobject]@{ Fixture='F1'; Variant='' }, [pscustomobject]@{ Fixture='F2'; Variant='' },
    [pscustomobject]@{ Fixture='F3'; Variant='list-0s' }, [pscustomobject]@{ Fixture='F3'; Variant='list-1s' },
    [pscustomobject]@{ Fixture='F3'; Variant='list-3s' }, [pscustomobject]@{ Fixture='F3'; Variant='vstack-1s' },
    [pscustomobject]@{ Fixture='F3'; Variant='vstack-3s' }, [pscustomobject]@{ Fixture='F3'; Variant='lazy-1s' },
    [pscustomobject]@{ Fixture='F3'; Variant='lazy-3s' }, [pscustomobject]@{ Fixture='F4'; Variant='' },
    [pscustomobject]@{ Fixture='F5'; Variant='' }, [pscustomobject]@{ Fixture='F6'; Variant='' },
    [pscustomobject]@{ Fixture='F6'; Variant='reduced' }, [pscustomobject]@{ Fixture='F7'; Variant='' },
    [pscustomobject]@{ Fixture='F8'; Variant='' }, [pscustomobject]@{ Fixture='F9'; Variant='' }
  )
}
$index = 0
$failedCount = 0
$abortRemaining = $false
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class Sr0MatrixRunnerV5Kernel {
  [DllImport("kernel32.dll", SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
}
'@
function Quote-Arg([string]$v) { return '"' + $v.Replace('"','\"') + '"' }
function Lock-Free([string]$path) {
  try {
    $text=[IO.File]::ReadAllText($path).Trim()
    if ($text -eq 'free') { return $true }
    try { $o=$text | ConvertFrom-Json; foreach ($k in @('state','status','value')) { if ($o.PSObject.Properties.Name -contains $k -and [string]$o.$k -eq 'free') { return $true } } } catch {}
  } catch { return $false }
  return $false
}
function Start-Coordinator([string[]]$arguments,[string]$stdoutPath,[string]$stderrPath) {
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=Join-Path $PSHOME 'powershell.exe'
  $psi.Arguments=(($arguments | ForEach-Object { Quote-Arg ([string]$_) }) -join ' ')
  $psi.WorkingDirectory=$baseFull; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
  $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true; $psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
  $proc=$null; $handle=[IntPtr]::Zero; $outStream=$null; $errStream=$null; $outTask=$null; $errTask=$null
  $outDone=$false; $errDone=$false; [uint32]$kernelExit=259; $terminal=$false
  $timedOut=$false; $outputExceeded=$false; $rssExceeded=$false; $terminateAttempted=$false; $terminateSucceeded=$false
  [int64]$peakRss=0; [int64]$rssSamples=0; $watch=$null
  try {
    $proc=[Diagnostics.Process]::Start($psi); if ($null -eq $proc) { throw 'coordinator did not start' }
    # Retain original coordinator handle before waiting; no post-hoc PID substitution.
    $handle=$proc.Handle
    $outStream=[IO.File]::Open($stdoutPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $errStream=[IO.File]::Open($stderrPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $outTask=$proc.StandardOutput.BaseStream.CopyToAsync($outStream)
    $errTask=$proc.StandardError.BaseStream.CopyToAsync($errStream)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $wait=258
    while ($true) {
      $wait=[Sr0MatrixRunnerV5Kernel]::WaitForSingleObject($handle,1000)
      try { $proc.Refresh(); $rss=[int64]$proc.WorkingSet64; $rssSamples++; if ($rss -gt $peakRss) { $peakRss=$rss } } catch {}
      try { if ((Get-Item -LiteralPath $stdoutPath).Length -gt $CoordinatorStreamCapBytes -or (Get-Item -LiteralPath $stderrPath).Length -gt $CoordinatorStreamCapBytes) { $outputExceeded=$true; break } } catch { $outputExceeded=$true; break }
      if ($peakRss -gt $CoordinatorRssCapBytes) { $rssExceeded=$true; break }
      if ($wait -eq 0) { break }
      if ($watch.Elapsed.TotalSeconds -ge $CoordinatorTimeoutSeconds) { $timedOut=$true; break }
    }
    if ($timedOut -or $outputExceeded -or $rssExceeded) {
      try { $terminateAttempted=$true; $proc.Kill(); $terminateSucceeded=$true } catch {}
      $wait=[Sr0MatrixRunnerV5Kernel]::WaitForSingleObject($handle,15000)
    }
    $ok=[Sr0MatrixRunnerV5Kernel]::GetExitCodeProcess($handle,[ref]$kernelExit)
    $terminal=($proc.HasExited -and $wait -eq 0 -and $ok -and $kernelExit -ne 259)
    $outDone=$outTask.Wait(30000); $errDone=$errTask.Wait(30000)
    if ((Get-Item -LiteralPath $stdoutPath).Length -gt $CoordinatorStreamCapBytes -or (Get-Item -LiteralPath $stderrPath).Length -gt $CoordinatorStreamCapBytes) { $outputExceeded=$true }
    $reportedExit=$null; if ($terminal) { $reportedExit=[int64]$kernelExit }
    return [ordered]@{ started=$true; handle=$handle.ToInt64(); terminal=$terminal; kernelExit=$reportedExit; streamsDrained=($outDone -and $errDone); timedOut=$timedOut; outputExceeded=$outputExceeded; rssExceeded=$rssExceeded; terminateAttempted=$terminateAttempted; terminateSucceeded=$terminateSucceeded; peakRssBytes=$peakRss; rssSamples=$rssSamples; deadlineSeconds=$CoordinatorTimeoutSeconds; streamCapBytes=$CoordinatorStreamCapBytes; rssCapBytes=$CoordinatorRssCapBytes }
  } finally {
    if ($outStream) { try { $outStream.Flush(); $outStream.Dispose() } catch {} }
    if ($errStream) { try { $errStream.Flush(); $errStream.Dispose() } catch {} }
    if ($proc) { try { $proc.Dispose() } catch {} }
  }
}
foreach ($cfg in $configs) {
  $slug = if ($cfg.Variant) { "$($cfg.Fixture)-$($cfg.Variant)" } else { $cfg.Fixture }
  for ($run = 1; $run -le $Runs; $run++) {
    $index++
    $caseRoot = Join-Path $OutRoot ("{0}-r{1}-{2}" -f $slug,$run,[guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $caseRoot) { throw "case output exists: $caseRoot" }
    [IO.Directory]::CreateDirectory($caseRoot) | Out-Null
    $stdoutPath=Join-Path $caseRoot 'coordinator.stdout.bin'; $stderrPath=Join-Path $caseRoot 'coordinator.stderr.bin'
    $coordOutputPath=Join-Path $caseRoot 'coordinator-output.txt'; $terminalPath=Join-Path $caseRoot 'matrix-run.json'
    $caseStatus='failed'; $failure=$null; $coordInfo=$null; $receiptPath=$null; $receiptError=$null; $coordExit=$null
    try {
      if (-not (Lock-Free $Lock)) { throw 'desktop lock is not free before case launch; preserving remaining cases' }
      $coordinatorArguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$coordinatorFull,'-Base',$baseFull,'-Worker',$workerFull,'-Driver',$driverFull,'-ExpectDriver',$expectedDriver,'-ExpectWorker',$expectedWorker,'-ExpectExe',$expectedExe,'-ExpectDll',$expectedDll,'-OutRoot',$caseRoot,'-Fixture',$cfg.Fixture,'-KeyMode','char','-Lock',$Lock)
      if ($cfg.Variant) { $coordinatorArguments += @('-Variant',$cfg.Variant) }
      $coordInfo=Start-Coordinator $coordinatorArguments $stdoutPath $stderrPath
      $coordExit=$coordInfo.kernelExit
      $receipts=@(Get-ChildItem -LiteralPath $caseRoot -Filter 'worker-*.json' -File -Recurse -ErrorAction SilentlyContinue)
      if ($receipts.Count -ne 1) { throw "expected one worker receipt for $slug run $run, got $($receipts.Count)" }
      $receiptPath=$receipts[0].FullName
      try { [void](Assert-Receipt $receiptPath $false) } catch { $receiptError=$_.Exception.Message; throw "worker receipt rejected: $receiptError" }
      if (-not $coordInfo.terminal) { throw 'coordinator kernel terminal proof missing' }
      if (-not $coordInfo.streamsDrained) { throw 'coordinator stream drain proof missing' }
      if ($coordInfo.timedOut -or $coordInfo.outputExceeded -or $coordInfo.rssExceeded) { throw 'coordinator bounded execution proof failed; preserving lock and aborting remaining cases' }
      if ($coordExit -ne 0) { throw "coordinator failed exit=$coordExit; raw streams preserved" }
      $caseStatus='passed'
    } catch { $failure=$_.Exception.Message; $failedCount++ }
    $terminal=[ordered]@{ kind='sr0-tuple12-matrix-run-v7'; index=$index; mode=$Mode; fixture=$cfg.Fixture; variant=$cfg.Variant; run=$run; runs=$Runs; status=$caseStatus; failure=$failure; abortRemaining=$abortRemaining; base=$baseFull; driver=$driverFull; driverSha256=$expectedDriver; worker=$workerFull; workerSha256=$expectedWorker; coordinator=$coordinatorFull; coordinatorSha256=$expectedCoordinator; exeSha256=$expectedExe; rendererSha256=$expectedDll; workerReceipt=$receiptPath; coordinatorExit=$coordExit; coordinatorKernel=$coordInfo; smokeReceipt=$smokeFull; targetedDelivery=$true; noActivate=$true; output=$caseRoot; rawStdout=$stdoutPath; rawStderr=$stderrPath }
    if ($null -ne $coordInfo -and ($coordInfo.timedOut -or $coordInfo.outputExceeded -or $coordInfo.rssExceeded)) { $abortRemaining = $true }
    Write-Exclusive $terminalPath (($terminal | ConvertTo-Json -Depth 12) + "`r`n")
    Write-Exclusive $coordOutputPath (([ordered]@{ status=$caseStatus; failure=$failure; coordinator=$coordInfo; workerReceipt=$receiptPath; rawStdout=$stdoutPath; rawStderr=$stderrPath } | ConvertTo-Json -Depth 12) + "`r`n")
    $linePrefix=if ($caseStatus -eq 'passed') { 'PASS' } else { 'FAIL' }
    Write-Output ($linePrefix + " $slug run=$run/$Runs output=$caseRoot")
    if ($caseStatus -ne 'passed') { $abortRemaining = $true }
    if ($abortRemaining) { break }
  }
  if ($abortRemaining) { break }
}
if ($failedCount -eq 0) {
  Write-Output ("MATRIX_PASS mode={0} configs={1} runs={2} total={3} smoke={4}" -f $Mode,$configs.Count,$Runs,$index,$smokeFull)
  exit 0
}
Write-Output ("MATRIX_FAIL mode={0} configs={1} runs={2} total={3} failures={4} smoke={5}; all case receipts preserved" -f $Mode,$configs.Count,$Runs,$index,$failedCount,$smokeFull)
exit 1
