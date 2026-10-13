# SR0 tuple12 v4 Windows owned-job controls. No GUI, lock, input, Git, or global kill.
[CmdletBinding()]
param(
  [ValidateSet('positive','spawned-descendant','timeout','output-cap','wrong-memory-flag','resume-before-assignment','drop-active-query')]
  [string]$Mode = 'positive',
  [Parameter(Mandatory=$true)][string]$OutRoot,
  [string]$ChildPath = "$env:WINDIR\System32\cmd.exe"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ChildPath -PathType Leaf)) { throw "child missing: $ChildPath" }
$outRootFull = [IO.Path]::GetFullPath($OutRoot)
if (-not (Test-Path -LiteralPath $outRootFull -PathType Container)) { [IO.Directory]::CreateDirectory($outRootFull) | Out-Null }
$outRootItem = Get-Item -LiteralPath $outRootFull -Force
if (($outRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "OutRoot may not be a reparse point: $outRootFull" }
if ($outRootFull -notmatch '(?i)[\\/]\.work([\\/]|$)') { throw "OutRoot must be under ignored .work: $outRootFull" }
$helperPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'shared\Sr0OwnedJobProcess.cs'))
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw "helper missing: $helperPath" }
Add-Type -Path $helperPath

$ownedRoot = Join-Path $outRootFull ('job-controls-' + $Mode + '-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($ownedRoot) | Out-Null
$stdoutPath = Join-Path $ownedRoot 'stdout.bin'; $stderrPath = Join-Path $ownedRoot 'stderr.bin'; $receiptPath = Join-Path $ownedRoot 'control-receipt.json'
[IO.File]::WriteAllBytes($stdoutPath, [byte[]]@()); [IO.File]::WriteAllBytes($stderrPath, [byte[]]@())
$job = [IntPtr]::Zero; $process = [IntPtr]::Zero; $thread = [IntPtr]::Zero; $stdoutRead = [IntPtr]::Zero; $stderrRead = [IntPtr]::Zero
$assigned = $false; $terminal = $false; $jobQuiescent = $false; $outcome = 'started'; $failureMessage = ''
$activeQueryAttempted = $false; $activeReadable = $false; [uint32]$active = 0
$cleanupWait = [uint32]258; $cleanupStdoutDrained = $false; $cleanupStderrDrained = $false; $cleanupActiveReadable = $false; [uint32]$cleanupActive = 1; $cleanupQuiescent = $false
$outPipe = $null; $errPipe = $null; $outFile = $null; $errFile = $null; $outTask = $null; $errTask = $null
$flags = [uint32]0; $childPid = 0; $timedOut = $false; $capHit = $false; $releaseAdmitted = $false; $expectedReject = $false; $expectedReason = ''

function Assert-ReleaseAdmission([bool]$KernelTerminal, [bool]$StdoutDrained, [bool]$StderrDrained, [bool]$ActiveReadable, [uint32]$ActiveProcesses) {
  if (-not $KernelTerminal -or -not $StdoutDrained -or -not $StderrDrained -or -not $ActiveReadable -or $ActiveProcesses -ne 0) {
    throw "release admission refused: terminal=$KernelTerminal stdoutDrained=$StdoutDrained stderrDrained=$StderrDrained activeReadable=$ActiveReadable activeProcesses=$ActiveProcesses"
  }
  return $true
}

try {
  $job = [Sr0OwnedJobProcess]::CreateJob()
  if ($job -eq [IntPtr]::Zero) { throw 'CreateJobObject failed' }
  $flagsForMode = [uint32]([Sr0OwnedJobProcess]::JobObjectLimitKillOnJobClose -bor [Sr0OwnedJobProcess]::JobObjectLimitJobMemory)
  if ($Mode -eq 'wrong-memory-flag') { $flagsForMode = [uint32]([Sr0OwnedJobProcess]::JobObjectLimitKillOnJobClose -bor [Sr0OwnedJobProcess]::JobObjectLimitProcessMemory) }
  if (-not [Sr0OwnedJobProcess]::ConfigureJobWithFlags($job, $flagsForMode, 1073741824)) { throw 'SetInformationJobObject failed' }
  [uint32]$flags = 0
  if (-not [Sr0OwnedJobProcess]::ReadJobFlags($job, [ref]$flags)) { throw 'job limits query failed' }
  if ($Mode -eq 'wrong-memory-flag') {
    if (($flags -band [uint32]0x100) -eq 0 -or ($flags -band [uint32]0x200) -ne 0) { throw "wrong-memory flag was not observed: $flags" }
  } elseif (($flags -band [uint32]0x2000) -eq 0 -or ($flags -band [uint32]0x200) -eq 0) { throw "required job flags missing: $flags" }
  $childArgs = switch ($Mode) {
    'positive' { '/d /c echo SR0_JOB_CONTROL_POSITIVE' }
    'wrong-memory-flag' { '/d /c echo SR0_JOB_CONTROL_MEMORY_FLAG' }
    'resume-before-assignment' { '/d /c echo SR0_JOB_CONTROL_ORDER' }
    'drop-active-query' { '/d /c echo SR0_JOB_CONTROL_ACTIVE_QUERY' }
    'spawned-descendant' { '/d /c start "" /b cmd.exe /d /c "ping.exe -n 6 127.0.0.1 >nul"' }
    'timeout' { '/d /c ping.exe -n 30 127.0.0.1 >nul' }
    'output-cap' { '/d /c for /L %i in (1,1,1000000) do @echo SR0_OUTPUT_%i' }
  }
  $commandLine = [Sr0OwnedJobProcess]::BuildCommandLine($ChildPath, $childArgs)
  [uint32]$childPid = 0
  if (-not [Sr0OwnedJobProcess]::CreateSuspended($ChildPath, $commandLine, $ownedRoot, [ref]$process, [ref]$thread, [ref]$stdoutRead, [ref]$stderrRead, [ref]$childPid)) { throw 'CreateProcess suspended failed' }
  if ($Mode -eq 'resume-before-assignment') {
    try { [Sr0OwnedJobProcess]::ResumeThread($thread, $process) | Out-Null; throw 'resume-before-assignment was accepted' }
    catch [InvalidOperationException] { throw "resume-before-assignment guard exercised: $($_.Exception.Message)" }
  }
  if (-not [Sr0OwnedJobProcess]::AssignProcessToJobObject($job, $process)) { throw 'job assignment failed' }
  $assigned = $true
  if ([Sr0OwnedJobProcess]::ResumeThread($thread, $process) -eq [uint32]0xffffffff) { throw 'resume failed' }
  $outPipe = New-Object IO.FileStream($stdoutRead, [IO.FileAccess]::Read, $false); $errPipe = New-Object IO.FileStream($stderrRead, [IO.FileAccess]::Read, $false)
  $outFile = [IO.File]::Open($stdoutPath, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read); $errFile = [IO.File]::Open($stderrPath, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read)
  $outTask = $outPipe.CopyToAsync($outFile); $errTask = $errPipe.CopyToAsync($errFile)
  $watch = [Diagnostics.Stopwatch]::StartNew(); $wait = [uint32]258
  while ($true) {
    $wait = [Sr0OwnedJobProcess]::WaitForSingleObject($process, 1000)
    if ($wait -eq [Sr0OwnedJobProcess]::WaitObject0) { $terminal = $true; break }
    if ((Get-Item -LiteralPath $stdoutPath).Length -gt 8388608 -or (Get-Item -LiteralPath $stderrPath).Length -gt 8388608) { $capHit = $true; break }
    if ($Mode -eq 'timeout' -and $watch.Elapsed.TotalSeconds -ge 1) { $timedOut = $true; break }
    if ($watch.Elapsed.TotalSeconds -ge 10) { $timedOut = $true; break }
  }
  if ($timedOut -or $capHit) {
    if (-not [Sr0OwnedJobProcess]::TerminateJobObject($job, 124)) { throw 'owned job termination failed' }
    $wait = [Sr0OwnedJobProcess]::WaitForSingleObject($process, 5000); $terminal = ($wait -eq [Sr0OwnedJobProcess]::WaitObject0)
  }
  $outDone = $outTask.Wait(10000); $errDone = $errTask.Wait(10000)
  if (-not $outDone -or -not $errDone) {
    [Sr0OwnedJobProcess]::TerminateJobObject($job, 124) | Out-Null
    $wait = [Sr0OwnedJobProcess]::WaitForSingleObject($process, 5000); $terminal = ($wait -eq [Sr0OwnedJobProcess]::WaitObject0)
    $outDone = $outTask.Wait(5000); $errDone = $errTask.Wait(5000)
  }
  if ($Mode -eq 'drop-active-query') {
    $releaseAdmitted = Assert-ReleaseAdmission $terminal $outDone $errDone $false 1
  } else {
    $activeQueryAttempted = $true
    $activeReadable = [Sr0OwnedJobProcess]::ReadActiveProcessCount($job, [ref]$active)
    if ($active -ne 0) {
      [Sr0OwnedJobProcess]::TerminateJobObject($job, 124) | Out-Null
      $wait = [Sr0OwnedJobProcess]::WaitForSingleObject($process, 5000)
      $terminal = ($wait -eq [Sr0OwnedJobProcess]::WaitObject0)
      for ($q = 0; $q -lt 40 -and $active -ne 0; $q++) { [Sr0OwnedJobProcess]::WaitForSingleObject($process, 250) | Out-Null; $activeReadable = [Sr0OwnedJobProcess]::ReadActiveProcessCount($job, [ref]$active) }
    }
    if ($active -ne 0) { throw "job still active after termination: $active" }
    $releaseAdmitted = Assert-ReleaseAdmission $terminal $outDone $errDone $activeReadable $active
    $code = [uint32]0
    if (-not [Sr0OwnedJobProcess]::GetExitCodeProcess($process, [ref]$code) -or $code -eq 259) { throw 'kernel exit proof failed' }
    $jobQuiescent = $true
  }
  $outcome = 'passed'
  if ($Mode -eq 'wrong-memory-flag') { 'job-control wrong-memory-flag: PASS actual per-process flag setup & flags query' }
  elseif ($Mode -eq 'spawned-descendant') { 'job-control spawned-descendant: PASS descendant pipes drained & active=0' }
  elseif ($Mode -eq 'timeout') { if (-not $timedOut) { throw 'timeout mode did not hit deadline' }; 'job-control timeout: PASS exact job terminated & drained' }
  elseif ($Mode -eq 'output-cap') { if (-not $capHit) { throw 'output-cap mode did not hit cap' }; 'job-control output-cap: PASS exact job terminated at 8MiB stream bound' }
  else { 'job-control positive: PASS suspended->assign->resume, flags, kernel exit, active=0' }
} catch {
  $failureMessage = $_.Exception.Message
  if (($Mode -eq 'resume-before-assignment' -and $failureMessage -like 'resume-before-assignment guard exercised:*') -or ($Mode -eq 'drop-active-query' -and $failureMessage -like 'release admission refused:*')) {
    $outcome = 'expected-rejected'; $expectedReject = $true; $expectedReason = $failureMessage
  } else { $outcome = 'failed'; throw }
} finally {
  if ($process -ne [IntPtr]::Zero -and -not $jobQuiescent) {
    if ($assigned -and $job -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::TerminateJobObject($job, 124) | Out-Null } else { [Sr0OwnedJobProcess]::TerminateProcess($process, 124) | Out-Null }
    $cleanupWait = [Sr0OwnedJobProcess]::WaitForSingleObject($process, 5000)
    $terminal = ($cleanupWait -eq [Sr0OwnedJobProcess]::WaitObject0)
    if ($outTask) { $cleanupStdoutDrained = $outTask.Wait(5000) } else { if ($stdoutRead -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::CloseHandle($stdoutRead) | Out-Null; $stdoutRead = [IntPtr]::Zero }; $cleanupStdoutDrained = $true }
    if ($errTask) { $cleanupStderrDrained = $errTask.Wait(5000) } else { if ($stderrRead -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::CloseHandle($stderrRead) | Out-Null; $stderrRead = [IntPtr]::Zero }; $cleanupStderrDrained = $true }
  }
  if ($process -ne [IntPtr]::Zero -and $job -ne [IntPtr]::Zero) {
    try { $cleanupActiveReadable = [Sr0OwnedJobProcess]::ReadActiveProcessCount($job, [ref]$cleanupActive) } catch { $cleanupActiveReadable = $false }
    $cleanupQuiescent = $jobQuiescent -or ($cleanupWait -eq [uint32]0 -and $cleanupStdoutDrained -and $cleanupStderrDrained -and $cleanupActiveReadable -and $cleanupActive -eq 0)
  } elseif ($process -eq [IntPtr]::Zero) { $cleanupQuiescent = $true }
  if ($outPipe) { $outPipe.Dispose() }; if ($errPipe) { $errPipe.Dispose() }; if ($outFile) { $outFile.Dispose() }; if ($errFile) { $errFile.Dispose() }
  if ($thread -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::CloseHandle($thread) | Out-Null }; if ($process -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::CloseHandle($process) | Out-Null }
  if ($stdoutRead -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::CloseHandle($stdoutRead) | Out-Null }; if ($stderrRead -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::CloseHandle($stderrRead) | Out-Null }; if ($job -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::CloseHandle($job) | Out-Null }
  $stdoutBytes = 0; $stderrBytes = 0; $stdoutHash = ''; $stderrHash = ''
  try { $stdoutBytes = (Get-Item -LiteralPath $stdoutPath -Force).Length; if ($stdoutBytes -le 8388608) { $stdoutHash = (Get-FileHash -LiteralPath $stdoutPath -Algorithm SHA256).Hash.ToLowerInvariant() } } catch {}
  try { $stderrBytes = (Get-Item -LiteralPath $stderrPath -Force).Length; if ($stderrBytes -le 8388608) { $stderrHash = (Get-FileHash -LiteralPath $stderrPath -Algorithm SHA256).Hash.ToLowerInvariant() } } catch {}
  $receipt = [ordered]@{ kind='sr0-tuple12-job-control-v2'; mode=$Mode; out_root=$outRootFull; owned_root=$ownedRoot; outcome=$outcome; failure=$failureMessage; child_path=$ChildPath; child_pid=$childPid; flags=$flags; assigned=$assigned; kernel_terminal=$terminal; timed_out=$timedOut; output_cap_hit=$capHit; active_query_attempted=$activeQueryAttempted; active_readable=$activeReadable; active_processes=$active; release_admitted=$releaseAdmitted; stdout_bytes=$stdoutBytes; stderr_bytes=$stderrBytes; stdout_sha256=$stdoutHash; stderr_sha256=$stderrHash; cleanup_wait=$cleanupWait; cleanup_streams_drained=($cleanupStdoutDrained -and $cleanupStderrDrained); cleanup_active_readable=$cleanupActiveReadable; cleanup_active_processes=$cleanupActive; cleanup_quiescent=$cleanupQuiescent }
  [IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
}
if ($expectedReject) {
  if (-not $cleanupQuiescent) { throw "expected rejection cleanup proof failed: $expectedReason" }
  "EXPECTED-REJECTED $Mode after owned cleanup: $expectedReason"
  exit 1
}
