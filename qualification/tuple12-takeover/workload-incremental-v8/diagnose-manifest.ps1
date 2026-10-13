# SR0 bounded SwiftPM manifest diagnostic. Source-only candidate; root runs on Windows.
# It probes SwiftPM under same explicit compiler/runtime PATH prefix as sealed source build.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$PackagePath,
  [Parameter(Mandatory)][string]$SwiftPath,
  [Parameter(Mandatory)][string]$OutRoot,
  [string]$CompilerBin = 'C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin',
  [string]$RuntimeBin = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin',
  [ValidateRange(10,300)][int]$DeadlineSeconds = 120,
  [ValidateRange(1048576,67108864)][int64]$StreamCapBytes = 8388608
)
$ErrorActionPreference = 'Stop'

function Need-Directory([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "directory missing: $Path" }
  $item = Get-Item -LiteralPath $Path
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "reparse directory rejected: $Path" }
}
function Need-File([string]$Path, [int64]$MaxBytes = 33554432) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "file missing: $Path" }
  $item = Get-Item -LiteralPath $Path
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "reparse file rejected: $Path" }
  if ($item.Length -gt $MaxBytes) { throw "file exceeds bound: $Path" }
}
function New-Text([string]$Path, [string]$Text) {
  $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
  $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
  try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}
function Close-Owned([pscustomobject]$State) {
  if ($null -eq $State) { return }
  foreach ($stream in @($State.OutPipe, $State.ErrPipe, $State.OutFile, $State.ErrFile)) {
    if ($null -ne $stream) { try { $stream.Dispose() } catch {} }
  }
  foreach ($handle in @($State.Thread, $State.Process, $State.StdoutRead, $State.StderrRead, $State.Job)) {
    if ($handle -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::CloseHandle($handle) | Out-Null }
  }
}

Need-Directory $PackagePath
Need-File $SwiftPath 33554432
Need-Directory $CompilerBin
Need-Directory $RuntimeBin
$manifest = Join-Path $PackagePath 'Package.swift'
Need-File $manifest 1048576
$out = [IO.Path]::GetFullPath($OutRoot)
if (Test-Path -LiteralPath $out) {
  if (@(Get-ChildItem -LiteralPath $out -Force).Count -ne 0) { throw 'OutRoot must be fresh' }
} else { [IO.Directory]::CreateDirectory($out) | Out-Null }
$outItem = Get-Item -LiteralPath $out
if (($outItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'OutRoot reparse point rejected' }

$helper = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\workload-incremental-v6\shared\Sr0OwnedJobProcess.cs'))
Need-File $helper 1048576
Add-Type -Path $helper

$oldPath = [Environment]::GetEnvironmentVariable('Path')
$oldWrapper = [Environment]::GetEnvironmentVariable('RUSTC_WRAPPER')
$env:Path = "$CompilerBin;$RuntimeBin;$oldPath"
$environmentNames = @('PATH','SDKROOT','DEVELOPER_DIR','SWIFT_EXEC','SWIFT_DRIVER_SWIFT_FRONTEND','VCToolsInstallDir','WindowsSdkDir','UniversalCRTSdkDir','INCLUDE','LIB','LIBPATH','RUSTC_WRAPPER')
$environment = [ordered]@{ compilerBin=$CompilerBin; runtimeBin=$RuntimeBin; swiftPath=$SwiftPath; packagePath=$PackagePath }
foreach ($name in $environmentNames) {
  $value = [Environment]::GetEnvironmentVariable($name)
  $environment[$name] = if ($null -eq $value) { $null } else { [string]$value }
  if ($name -in @('SDKROOT','DEVELOPER_DIR','VCToolsInstallDir','WindowsSdkDir','UniversalCRTSdkDir','SWIFT_EXEC','SWIFT_DRIVER_SWIFT_FRONTEND') -and $value) {
    $environment["${name}_exists"] = (Test-Path -LiteralPath $value -PathType Leaf) -or (Test-Path -LiteralPath $value -PathType Container)
  }
}
New-Text (Join-Path $out 'environment.json') (($environment | ConvertTo-Json -Depth 8) + "`r`n")

function Probe([string]$Name, [string]$Arguments) {
  $stdout = Join-Path $out "$Name.stdout.bin"; $stderr = Join-Path $out "$Name.stderr.bin"; $receiptPath = Join-Path $out "$Name.receipt.json"
  $job = [IntPtr]::Zero; $process = [IntPtr]::Zero; $thread = [IntPtr]::Zero; $stdoutRead = [IntPtr]::Zero; $stderrRead = [IntPtr]::Zero; [uint32]$childPid = 0
  $assigned = $false; $terminal = $false; $timedOut = $false; $outputExceeded = $false; $kernelRead = $false
  [uint32]$kernelWait = [Sr0OwnedJobProcess]::WaitTimeout; [uint32]$exitCode = 259; $activeReadable = $false; [uint32]$activeProcesses = 1
  $stdoutDrained = $false; $stderrDrained = $false; $outPipe = $null; $errPipe = $null; $outFile = $null; $errFile = $null; $outTask = $null; $errTask = $null; $failure = $null; $cleanupZero = $false
  try {
    $job = [Sr0OwnedJobProcess]::CreateJob()
    if ($job -eq [IntPtr]::Zero) { throw 'CreateJobObject failed' }
    if (-not [Sr0OwnedJobProcess]::ConfigureJob($job, 1073741824)) { throw '1GiB job memory configuration failed' }
    $commandLine = [Sr0OwnedJobProcess]::BuildCommandLine($SwiftPath, $Arguments)
    if (-not [Sr0OwnedJobProcess]::CreateSuspended($SwiftPath, $commandLine, $PackagePath, [ref]$process, [ref]$thread, [ref]$stdoutRead, [ref]$stderrRead, [ref]$childPid)) { throw 'CreateProcess suspended failed' }
    $outPipe = New-Object IO.FileStream($stdoutRead, [IO.FileAccess]::Read, $false); $errPipe = New-Object IO.FileStream($stderrRead, [IO.FileAccess]::Read, $false)
    $outFile = [IO.File]::Open($stdout, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read); $errFile = [IO.File]::Open($stderr, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $outTask = $outPipe.CopyToAsync($outFile); $errTask = $errPipe.CopyToAsync($errFile)
    if (-not [Sr0OwnedJobProcess]::AssignProcessToJobObject($job, $process)) { throw 'AssignProcessToJobObject failed' }
    $assigned = $true
    if ([Sr0OwnedJobProcess]::ResumeThread($thread, $process) -eq [uint32]::MaxValue) { throw 'ResumeThread failed' }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
      $kernelWait = [Sr0OwnedJobProcess]::WaitForSingleObject($process, 1000)
      if ($kernelWait -eq [Sr0OwnedJobProcess]::WaitObject0) { $terminal = $true; break }
      if ((Get-Item -LiteralPath $stdout).Length -gt $StreamCapBytes -or (Get-Item -LiteralPath $stderr).Length -gt $StreamCapBytes) { $outputExceeded = $true; break }
      if ($watch.Elapsed.TotalSeconds -ge $DeadlineSeconds) { $timedOut = $true; break }
    }
    if ($timedOut -or $outputExceeded) {
      [Sr0OwnedJobProcess]::TerminateJobObject($job, 124) | Out-Null; $kernelWait = [Sr0OwnedJobProcess]::WaitForSingleObject($process, 15000); $terminal = $kernelWait -eq [Sr0OwnedJobProcess]::WaitObject0
    }
    $kernelRead = $terminal -and [Sr0OwnedJobProcess]::GetExitCodeProcess($process, [ref]$exitCode)
    $stdoutDrained = $outTask.Wait(15000); $stderrDrained = $errTask.Wait(15000)
    if (-not ($stdoutDrained -and $stderrDrained)) {
      [Sr0OwnedJobProcess]::TerminateJobObject($job, 124) | Out-Null; [Sr0OwnedJobProcess]::WaitForSingleObject($process, 5000) | Out-Null; $stdoutDrained = $outTask.Wait(5000); $stderrDrained = $errTask.Wait(5000)
    }
    foreach ($path in @($stdout, $stderr)) { if ((Get-Item -LiteralPath $path).Length -gt $StreamCapBytes) { $outputExceeded = $true } }
    $activeReadable = [Sr0OwnedJobProcess]::ReadActiveProcessCount($job, [ref]$activeProcesses)
    if (-not $activeReadable -or $activeProcesses -ne 0) {
      [Sr0OwnedJobProcess]::TerminateJobObject($job, 124) | Out-Null; [Sr0OwnedJobProcess]::WaitForSingleObject($process, 5000) | Out-Null
      for ($i = 0; $i -lt 60 -and $activeProcesses -ne 0; $i++) { $activeReadable = [Sr0OwnedJobProcess]::ReadActiveProcessCount($job, [ref]$activeProcesses); if ($activeReadable -and $activeProcesses -eq 0) { break }; [Sr0OwnedJobProcess]::WaitForSingleObject($process, 250) | Out-Null }
    }
    $cleanupZero = $terminal -and $kernelRead -and ($exitCode -ne 259) -and $stdoutDrained -and $stderrDrained -and $activeReadable -and ($activeProcesses -eq 0) -and (-not $outputExceeded)
  } catch { $failure = $_.Exception.Message }
  finally {
    if ($process -ne [IntPtr]::Zero -and -not $terminal) {
      if ($assigned) { [Sr0OwnedJobProcess]::TerminateJobObject($job, 124) | Out-Null } else { [Sr0OwnedJobProcess]::TerminateProcess($process, 124) | Out-Null }
      $kernelWait = [Sr0OwnedJobProcess]::WaitForSingleObject($process, 5000); $terminal = $kernelWait -eq [Sr0OwnedJobProcess]::WaitObject0
    }
    if ($null -ne $outTask) { try { $stdoutDrained = $outTask.Wait(5000) } catch {} }; if ($null -ne $errTask) { try { $stderrDrained = $errTask.Wait(5000) } catch {} }
    $receipt = [ordered]@{ kind='sr0-tuple12-manifest-probe'; probe=$Name; args=$Arguments; processId=$childPid; assigned=$assigned; originalHandleRetained=($process -ne [IntPtr]::Zero); jobHandleRetained=($job -ne [IntPtr]::Zero); kernelWait=$kernelWait; terminal=$terminal; kernelExitCode=[uint64]$exitCode; kernelExitRead=$kernelRead; timedOut=$timedOut; outputExceeded=$outputExceeded; stdoutBytes=if(Test-Path -LiteralPath $stdout){(Get-Item -LiteralPath $stdout).Length}else{$null}; stderrBytes=if(Test-Path -LiteralPath $stderr){(Get-Item -LiteralPath $stderr).Length}else{$null}; stdoutDrained=$stdoutDrained; stderrDrained=$stderrDrained; activeReadable=$activeReadable; activeProcesses=$activeProcesses; cleanupZero=$cleanupZero; failure=$failure }
    New-Text $receiptPath (($receipt | ConvertTo-Json -Depth 10) + "`r`n")
    Close-Owned ([pscustomobject]@{ Job=$job; Process=$process; Thread=$thread; StdoutRead=$stdoutRead; StderrRead=$stderrRead; OutPipe=$outPipe; ErrPipe=$errPipe; OutFile=$outFile; ErrFile=$errFile })
  }
  return $receipt
}

try {
  $probes = @([ordered]@{ name='dump-package'; args="package dump-package --package-path $([Sr0OwnedJobProcess]::QuoteWindowsArgument($PackagePath))" }, [ordered]@{ name='show-dependencies'; args="package show-dependencies --format json --package-path $([Sr0OwnedJobProcess]::QuoteWindowsArgument($PackagePath))" })
  $results = @(); foreach ($probe in $probes) { $results += Probe $probe.name $probe.args }
  $summary = [ordered]@{ kind='sr0-tuple12-workload-incremental-v8-manifest-diagnostic'; packagePath=$PackagePath; swiftPath=$SwiftPath; compilerBin=$CompilerBin; runtimeBin=$RuntimeBin; manifest=$manifest; helper=$helper; environment='environment.json'; probes=$results; allQuiescent=(@($results | Where-Object { -not $_.cleanupZero }).Count -eq 0); noMutation=$true }
  New-Text (Join-Path $out 'manifest-diagnostic.json') (($summary | ConvertTo-Json -Depth 12) + "`r`n"); $summary | ConvertTo-Json -Depth 12
  if (-not $summary.allQuiescent) { exit 1 }; exit 0
} finally { $env:Path = $oldPath; $env:RUSTC_WRAPPER = $oldWrapper }
