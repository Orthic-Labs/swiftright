# SR0 tuple12 Workload launcher envelope. Source-only candidate; root owns Windows execution.
# Holds desktop.lock through one hidden v3 orchestrator process, which owns interactive task, worker, sampler & PresentMon.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$ControlRoot,
  [Parameter(Mandatory)][string]$AnalysisRoot,
  [Parameter(Mandatory)][string]$OutRoot,
  [Parameter(Mandatory)][string]$ExpectExe,
  [Parameter(Mandatory)][string]$ExpectDll,
  [string]$Lock = 'D:\Claude\desktop.lock',
  [string]$Tag = ''
)
$ErrorActionPreference = 'Stop'
$expectedExe = $ExpectExe.ToLowerInvariant(); $expectedDll = $ExpectDll.ToLowerInvariant()
if ($expectedExe -notmatch '^[0-9a-f]{64}$' -or $expectedDll -notmatch '^[0-9a-f]{64}$') { throw 'expected artifact hash is not SHA-256' }
foreach ($path in @($Base,$ControlRoot,$AnalysisRoot)) { if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "required directory missing: $path" } }
if (-not (Test-Path -LiteralPath $Lock -PathType Leaf)) { throw "desktop lock missing: $Lock" }
if (-not $Tag) { $Tag = 'tuple12-r10-' + [guid]::NewGuid().ToString('N') }
if ($Tag -notmatch '^[A-Za-z0-9._-]+$') { throw 'tag contains unsafe characters' }
$runRoot = Join-Path $Base ("runs\" + $Tag)
$receipt = Join-Path $OutRoot ("receipts\workload-" + $Tag + '.json')
$stdoutPath = Join-Path $OutRoot ("streams\orchestrator-" + $Tag + '.stdout.bin')
$stderrPath = Join-Path $OutRoot ("streams\orchestrator-" + $Tag + '.stderr.bin')
$orchestrator = Join-Path $ControlRoot 'run-workload.ps1'
foreach ($path in @($orchestrator)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "pinned control missing: $path" } }
foreach ($path in @($runRoot,$receipt,$stdoutPath,$stderrPath)) { if (Test-Path -LiteralPath $path) { throw "fresh output already exists: $path" } }
[IO.Directory]::CreateDirectory($OutRoot) | Out-Null
[IO.Directory]::CreateDirectory((Split-Path -Parent $receipt)) | Out-Null
[IO.Directory]::CreateDirectory((Split-Path -Parent $stdoutPath)) | Out-Null

$build = Get-Content -LiteralPath (Join-Path $Base 'build.json') -Raw | ConvertFrom-Json
if (-not $build.exe -or -not $build.exe_sha256 -or -not $build.dll_sha256) { throw 'build.json lacks sealed exe_sha256/dll_sha256 fields' }
if ([string]$build.exe_sha256 -cne $expectedExe -or [string]$build.dll_sha256 -cne $expectedDll) { throw 'build.json hash fields differ from expected artifacts' }
$bin = Split-Path ([string]$build.exe)
$exe = Join-Path $bin 'WorkloadWin.exe'; $dll = Join-Path $bin 'swiftright_render.dll'
foreach ($path in @($exe,$dll)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "artifact missing: $path" } }
if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedExe) { throw 'WorkloadWin.exe hash mismatch' }
if ((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expectedDll) { throw 'renderer hash mismatch' }

$label = 'SR0-T12-WL-' + $Tag
$lockOwner = "$label $([DateTimeOffset]::UtcNow.ToString('o'))"
$taskName = 'SR0BWorkload-' + $Tag
$lockHeld = $false; $lockReleased = $false; $releaseAllowed = $false; $releaseError = $null
$orchestratorProc = $null; $orchestratorHandle = [IntPtr]::Zero
$stdoutTask = $null; $stderrTask = $null; $outStream = $null; $errStream = $null
$orchestratorTerminal = $false; $streamsDrained = $false; $taskQuiescent = $false; $semanticPass = $false
$exitCode = $null; $failure = $null; $resultText = ''

Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class Sr0WorkloadKernel {
  [DllImport("kernel32.dll", SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
}
'@
function Quote-Arg([string]$v) { return '"' + $v.Replace('"','\"') + '"' }
function Lock-Text([IO.FileStream]$fs) { $fs.Position=0; $buf=New-Object byte[] ([int]$fs.Length); if ($buf.Length) { [void]$fs.Read($buf,0,$buf.Length) }; [Text.Encoding]::UTF8.GetString($buf).Trim() }
function Lock-IsFree([string]$text) {
  if ($text -eq 'free') { return $true }
  try { $o=$text|ConvertFrom-Json; foreach ($k in @('state','status','value')) { if ($o.PSObject.Properties.Name -contains $k -and [string]$o.$k -eq 'free') { return $true } } } catch {}
  return $false
}
function Try-Acquire-Lock {
  try {
    $fs=[IO.File]::Open($Lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
      if (-not (Lock-IsFree (Lock-Text $fs))) { return $false }
      $bytes=[Text.Encoding]::UTF8.GetBytes("$lockOwner`r`n"); $fs.SetLength(0); $fs.Position=0; $fs.Write($bytes,0,$bytes.Length); $fs.Flush($true); return $true
    } finally { $fs.Dispose() }
  } catch [IO.IOException] { return $false }
}
function Release-Lock {
  $fs=[IO.File]::Open($Lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  try {
    if ((Lock-Text $fs) -cne $lockOwner) { throw 'desktop lock ownership changed; preserving lock' }
    $bytes=[Text.Encoding]::UTF8.GetBytes("free`r`n"); $fs.SetLength(0); $fs.Position=0; $fs.Write($bytes,0,$bytes.Length); $fs.Flush($true)
  } finally { $fs.Dispose() }
}
function Kernel-Terminal([IntPtr]$handle,[Diagnostics.Process]$process,[ref]$code) {
  $code.Value=259
  try { $process.Refresh(); if (-not $process.HasExited) { return $false }; $wait=[Sr0WorkloadKernel]::WaitForSingleObject($handle,0); $ok=[Sr0WorkloadKernel]::GetExitCodeProcess($handle,[ref]$code.Value); return ($wait -eq 0 -and $ok -and $code.Value -ne 259) } catch { return $false }
}
function Write-CreateNew([string]$path,[string]$text) {
  $b=[Text.Encoding]::UTF8.GetBytes($text); $fs=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try { $fs.Write($b,0,$b.Length); $fs.Flush($true) } finally { $fs.Dispose() }
}
function Task-Quiescent {
  try { $t=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue; if ($null -eq $t) { return $true }; return ($t.State -notin @('Running','Queued')) } catch { return $false }
}

try {
  # Silent CAS loop is intentional: lock ownership remains until exact terminal/quiescent proof.
  while (-not (Try-Acquire-Lock)) { Start-Sleep -Seconds 20 }
  $lockHeld=$true
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=Join-Path $PSHOME 'powershell.exe'
  $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File {0} -Base {1} -ControlRoot {2} -AnalysisRoot {3} -NoActivate -LifecycleProof -Runs 3 -Warmup 10 -Measure 60 -Rows 200 -KeyRate 10 -Instr full -Tag {4} -ExpectDll {5}' -f (Quote-Arg $orchestrator),(Quote-Arg ([IO.Path]::GetFullPath($Base))),(Quote-Arg ([IO.Path]::GetFullPath($ControlRoot))),(Quote-Arg ([IO.Path]::GetFullPath($AnalysisRoot)),(Quote-Arg $Tag),(Quote-Arg $expectedDll)
  $psi.WorkingDirectory=$Base; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
  $orchestratorProc=[Diagnostics.Process]::Start($psi); if ($null -eq $orchestratorProc) { throw 'orchestrator did not start' }
  $orchestratorHandle=$orchestratorProc.Handle
  $outStream=[IO.File]::Open($stdoutPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  $errStream=[IO.File]::Open($stderrPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  $stdoutTask=$orchestratorProc.StandardOutput.BaseStream.CopyToAsync($outStream)
  $stderrTask=$orchestratorProc.StandardError.BaseStream.CopyToAsync($errStream)
  $deadline=[DateTime]::UtcNow.AddMinutes(8)
  while (-not $orchestratorProc.HasExited -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Seconds 2; $orchestratorProc.Refresh() }
  [uint32]$kernelExit=259
  $orchestratorTerminal=Kernel-Terminal $orchestratorHandle $orchestratorProc ([ref]$kernelExit)
  if ($orchestratorTerminal) { $exitCode=[int64]$kernelExit }
  $stdoutDone=$stdoutTask.Wait(15000); $stderrDone=$stderrTask.Wait(15000); $streamsDrained=$stdoutDone -and $stderrDone
  if ($outStream) { $outStream.Flush(); $outStream.Dispose(); $outStream=$null }; if ($errStream) { $errStream.Flush(); $errStream.Dispose(); $errStream=$null }
  $resultPath=Join-Path $runRoot 'result-workload.txt'
  if (Test-Path -LiteralPath $resultPath -PathType Leaf) { $resultText=[IO.File]::ReadAllText($resultPath) }
  $taskQuiescent=Task-Quiescent
  $orchestrationLog=Join-Path $runRoot 'orchestrator.log'
  $orchestrationText=if (Test-Path -LiteralPath $orchestrationLog -PathType Leaf) { [IO.File]::ReadAllText($orchestrationLog) } else { '' }
  $nestedHandleProof=($orchestrationText -match 'presentmon .*handle=' -and $resultText -match 'pid run=' -and $resultText -match 'sampler run=')
  $proof=($resultText -match 'finished=' -and $resultText -match 'worker_terminal=1' -and $resultText -match 'sampler_terminal=1' -and $resultText -match 'task_quiescent=1')
  $semanticPass=($orchestratorTerminal -and $exitCode -eq 0 -and $proof)
  $releaseAllowed=($orchestratorTerminal -and $streamsDrained -and $taskQuiescent -and $nestedHandleProof)
  if (-not $orchestratorTerminal) { $failure='orchestrator terminal proof missing' } elseif (-not $streamsDrained) { $failure='orchestrator stream drain failed' } elseif (-not $taskQuiescent) { $failure='scheduled workload task not quiescent' } elseif (-not $nestedHandleProof) { $failure='nested worker/sampler/PresentMon handle evidence missing' } elseif (-not $proof) { $failure='workload lifecycle receipt proof missing' }
} catch { $failure=$_.Exception.Message }
finally {
  if ($outStream) { try { $outStream.Dispose() } catch {} }; if ($errStream) { try { $errStream.Dispose() } catch {} }
  if ($lockHeld -and $releaseAllowed) { try { Release-Lock; $lockReleased=$true } catch { $releaseError=$_.Exception.Message } }
  $status=if ($lockReleased -and $semanticPass -and -not $releaseError) { 'passed' } else { 'failed' }
  $obj=[ordered]@{ kind='sr0-tuple12-workload-coordinator-v1'; status=$status; tag=$Tag; lockOwner=$lockOwner; lockReleased=$lockReleased; taskName=$taskName; runRoot=$runRoot; receipt=$receipt; orchestratorHandle=$orchestratorHandle.ToInt64(); orchestratorTerminal=$orchestratorTerminal; orchestratorExit=$exitCode; streamsDrained=$streamsDrained; taskQuiescent=$taskQuiescent; nestedHandleProof=$nestedHandleProof; lifecycleProof=$semanticPass; expectedExe=$expectedExe; expectedDll=$expectedDll; failure=$failure; releaseError=$releaseError; orchestratorStdout=$stdoutPath; orchestratorStderr=$stderrPath }
  try { Write-CreateNew $receipt (($obj|ConvertTo-Json -Depth 8) + "`r`n") } catch { $obj.receiptWriteError=$_.Exception.Message; Write-Output ($obj|ConvertTo-Json -Depth 8) }
  $obj|ConvertTo-Json -Depth 8|Write-Output
}
if ($semanticPass) { exit 0 } else { exit 1 }
