# SR0 tuple12 UI-only incremental build adapter.
# Source-only candidate: root runs on Dell after parser review. No desktop lock, GUI, task, or native input.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$StageRoot,
  [Parameter(Mandatory)][string]$SourceRoot,
  [Parameter(Mandatory)][string]$BuildMetadata,
  [string]$CompiledManifest = '',
  [int]$Edits = 3,
  [string[]]$EngineArtifacts = @(),
  [string]$SwiftPath = 'C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe',
  [string]$CompilerBin = 'C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin',
  [string]$RuntimeBin = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin'
)
$ErrorActionPreference = 'Stop'
if ($Edits -ne 3) { throw 'tuple12 requires exactly three UI-only edits' }
function Require-Directory([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "directory missing: $Path" }
  $item = Get-Item -LiteralPath $Path
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "reparse directory rejected: $Path" }
}
function Require-File([string]$Path, [Int64]$MaxBytes = 8388608) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "file missing: $Path" }
  $item = Get-Item -LiteralPath $Path
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "reparse file rejected: $Path" }
  if ($item.Length -gt $MaxBytes) { throw "file exceeds bounded read: $Path ($($item.Length) bytes)" }
}
function New-OwnedDirectory([string]$Path) {
  if (Test-Path -LiteralPath $Path) { throw "output already exists: $Path" }
  [IO.Directory]::CreateDirectory($Path) | Out-Null
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "output directory create failed: $Path" }
}
function Write-CreateNewBytes([string]$Path, [byte[]]$Bytes) {
  $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try { $stream.Write($Bytes, 0, $Bytes.Length) } finally { $stream.Dispose() }
}
function Write-CreateNewText([string]$Path, [string]$Text) {
  $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
  Write-CreateNewBytes $Path $bytes
}
function Hash-File([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Read-BoundedBytes([string]$Path, [Int64]$MaxBytes) {
  $item = Get-Item -LiteralPath $Path
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "reparse file rejected: $Path" }
  if ($item.Length -gt $MaxBytes) { throw "file exceeds bounded read: $Path ($($item.Length) bytes)" }
  return ,([IO.File]::ReadAllBytes($Path))
}
function Get-BoundedLineCount([string]$Path, [Int64]$MaxBytes = 1048576) {
  $item = Get-Item -LiteralPath $Path
  if ($item.Length -gt $MaxBytes) { throw "log exceeds bounded size: $Path ($($item.Length) bytes)" }
  return [IO.File]::ReadAllLines($Path).Length
}
function Restore-Bytes([string]$Path, [byte[]]$Bytes) {
  $stream = [IO.File]::Open($Path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read)
  try { $stream.SetLength(0); $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush() } finally { $stream.Dispose() }
}
function Add-Marker([string]$Path, [int]$Number, [string]$RunId) {
  $line = "`r`n// SR0 tuple12 UI-only edit $Number $RunId`r`n"
  [IO.File]::AppendAllText($Path, $line, [Text.Encoding]::UTF8)
}
Require-Directory $StageRoot
Require-Directory $SourceRoot
Require-File $BuildMetadata
if (-not $CompiledManifest) { $CompiledManifest = Join-Path $StageRoot 'compiled-source-manifest.json' }
Require-File $CompiledManifest
Require-File $SwiftPath 33554432
Require-Directory $CompilerBin
Require-Directory $RuntimeBin
$runtimeCoreDll = Join-Path $RuntimeBin 'swiftCore.dll'
Require-File $runtimeCoreDll 33554432
$stageFull = [IO.Path]::GetFullPath($StageRoot)
$sourceFull = [IO.Path]::GetFullPath($SourceRoot)
if (-not $sourceFull.StartsWith($stageFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'SourceRoot escaped StageRoot' }
$meta = Get-Content -LiteralPath $BuildMetadata -Raw | ConvertFrom-Json
if ([string]$meta.kind -cne 'sr0-tuple12-derived-release-build-metadata-v6') { throw 'BuildMetadata kind mismatch' }
if ([string]$meta.configuration -cne 'release') { throw 'BuildMetadata configuration must be derived release' }
if ([string]$meta.sourceCommit -cne '0e201571e4320a3b6ccce14313fd2ad67e523904') { throw 'source commit mismatch' }
if ([string]$meta.sourceManifestSha256 -cne '26705e8f1fdd0164a9963c9cb0f730fda2e313e5c07348097c8fe8ab3ef7e468') { throw '54-file source manifest mismatch' }
if ([string]$meta.exe_sha256 -cne '7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c') { throw 'WorkloadWin metadata hash mismatch' }
if ([string]$meta.dll_sha256 -cne '7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2') { throw 'renderer metadata hash mismatch' }
if ($meta.swift_path -and [IO.Path]::GetFullPath($SwiftPath) -ine [IO.Path]::GetFullPath([string]$meta.swift_path)) { throw 'Swift compiler path differs from sealed receipt' }
if ($meta.swift_sha256 -and (Get-FileHash -LiteralPath $SwiftPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne ([string]$meta.swift_sha256).ToLowerInvariant()) { throw 'Swift compiler hash differs from sealed receipt' }
$compiled = Get-Content -LiteralPath $CompiledManifest -Raw | ConvertFrom-Json
if ([string]$compiled.kind -cne 'root-sr0-workload-materialized-source-v1') { throw 'compiled manifest kind mismatch' }
if ([string]$compiled.sourceCommit -cne [string]$meta.sourceCommit) { throw 'compiled manifest source commit mismatch' }
if ($null -eq $compiled.files -or -not ($compiled.files -is [array]) -or @($compiled.files).Count -ne 54) { throw 'compiled manifest files array mismatch' }
$compiledSourceFileCount = if ($compiled.sourceFiles -is [array]) { @($compiled.sourceFiles).Count } else { [int]$compiled.sourceFiles }
if ($compiledSourceFileCount -ne 42) { throw 'compiled manifest source file count mismatch' }
$compiledHash = Hash-File $CompiledManifest
if ([string]$meta.compiled_manifest_sha256 -and $compiledHash -cne ([string]$meta.compiled_manifest_sha256).ToLowerInvariant()) { throw 'compiled manifest hash differs from sealed metadata' }
foreach ($entry in @($compiled.files)) {
  if (-not $entry.path -or -not $entry.sha256 -or $null -eq $entry.bytes) { throw 'compiled manifest entry incomplete' }
  $entryPath = [IO.Path]::GetFullPath((Join-Path $sourceFull ([string]$entry.path)))
  if (-not $entryPath.StartsWith($sourceFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "compiled manifest path escaped SourceRoot: $entryPath" }
  Require-File $entryPath 1048576
  $entryItem = Get-Item -LiteralPath $entryPath
  if ([int64]$entry.bytes -ne $entryItem.Length -or (Hash-File $entryPath) -cne ([string]$entry.sha256).ToLowerInvariant()) { throw "compiled manifest source mismatch: $entryPath" }
}
$exe = [string]$meta.exe
$dll = [string]$meta.dll
# Renderer is 11.89 MiB in sealed receipt; bound both artifacts at 32 MiB.
Require-File $exe 33554432
Require-File $dll 33554432
$work = Join-Path $sourceFull 'probes\sr0-b\workload'
$target = Join-Path $work 'Sources\WorkloadCore\WorkloadScreen.swift'
Require-File $target 1048576
$targetFull = [IO.Path]::GetFullPath($target)
if (-not $targetFull.StartsWith($sourceFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'edit target escaped SourceRoot' }
$artifactPaths = @($exe, $dll) + @($EngineArtifacts)
$artifactPaths = @($artifactPaths | ForEach-Object { [IO.Path]::GetFullPath([string]$_) })
foreach ($path in $artifactPaths) {
  if (-not $path.StartsWith($stageFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "artifact escaped StageRoot: $path" }
  Require-File $path 33554432
}
if ((@($artifactPaths | ForEach-Object { (Get-Item -LiteralPath $_).Length } | Measure-Object -Sum).Sum) -gt 134217728) { throw 'artifact bytes exceed bounded total' }
$sourceBefore = Read-BoundedBytes $target 1048576
$sourceBeforeHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
$artifactBefore = [ordered]@{}
$artifactBytes = @{}
foreach ($path in $artifactPaths) { $artifactBefore[$path] = Hash-File $path; $artifactBytes[$path] = Read-BoundedBytes $path 33554432 }
foreach ($pair in @(
  @('WorkloadWin.exe', [string]$meta.exe_sha256),
  @('swiftright_render.dll', [string]$meta.dll_sha256)
)) { $pairPath = if ($pair[0] -eq 'WorkloadWin.exe') { $exe } else { $dll }; $actual = Hash-File $pairPath; if ($actual -cne $pair[1]) { throw "$($pair[0]) pre-hash mismatch" } }
$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + ([Guid]::NewGuid().ToString('N'))
$incrementalRoot = Join-Path $StageRoot 'incremental-runs'
if (Test-Path -LiteralPath $incrementalRoot) { Require-Directory $incrementalRoot } else { New-OwnedDirectory $incrementalRoot }
$runRoot = Join-Path $incrementalRoot $runId
New-OwnedDirectory $runRoot
$shim = Join-Path $runRoot 'shim'
New-OwnedDirectory $shim
$shimLog = Join-Path $shim 'shim.log'
Write-CreateNewText $shimLog ''
foreach ($name in @('cargo','rustc','rustup','rightkit','rustdoc','cargo-clippy')) {
  $script = "@echo off`r`necho %DATE% %TIME% $name %*>>`"$shimLog`"`r`nexit /b 97`r`n"
  Write-CreateNewText (Join-Path $shim "$name.cmd") $script
}
$trialDir = Join-Path $runRoot 'trials'
New-OwnedDirectory $trialDir
$oldPath = $env:Path
$shimPath = "$shim;$CompilerBin;$RuntimeBin;$oldPath"
$oldWrapper = $env:RUSTC_WRAPPER
$helperPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\workload-incremental-v6\shared\Sr0OwnedJobProcess.cs'))
Require-File $helperPath 1048576
Add-Type -Path $helperPath
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
$swiftArgs = "build --jobs 1 -c release --product WorkloadWin --scratch-path `"$StageRoot\scratch`" -Xlinker `"/MANIFEST:EMBED`" -Xlinker `"$dep`""
$swiftCommandLine = [Sr0OwnedJobProcess]::BuildCommandLine($SwiftPath, $swiftArgs)
$trials = @()
$rustTotal = 0
$sourceRestored = $false
$allJobsQuiescent = $true
$heldMutation = $false
$heldReceiptPath = $null
try {
  $env:Path = $shimPath
  $env:RUSTC_WRAPPER = (Join-Path $shim 'rustc.cmd')
  for ($i = 1; $i -le $Edits; $i++) {
    Add-Marker $target $i $runId
    $heldMutation = $true
    $stdoutPath = Join-Path $trialDir "edit-$i.stdout.txt"
    $stderrPath = Join-Path $trialDir "edit-$i.stderr.txt"
    Write-CreateNewText $stdoutPath ''
    Write-CreateNewText $stderrPath ''
    $shimCountBefore = Get-BoundedLineCount $shimLog
    $jobHandle = [IntPtr]::Zero
    $jobAssigned = $false
    $jobHandleRetained = $false
    $kernelTerminal = $false
    $jobQuiescent = $false
    $streamsDrained = $false
    $outDone = $false; $errDone = $false
    [uint32]$kernelWait = 258; [uint32]$kernelCode = 259; $kernelRead = $false; [int64]$dotnetExit = -1
    [uint32]$jobActive = 1; $jobActiveReadable = $false
    $cleanupWait = [uint32]258; [uint32]$cleanupActive = 1; $cleanupReadable = $false; $cleanupStreamsDrained = $false
    $timedOut = $false; $outputExceeded = $false; $terminatedForTimeout = $false; $terminatedForOutputCap = $false
    $trialFailure = $null; $originalHandleRetained = $false; $failureReceiptPath = Join-Path $trialDir "edit-$i.failure.json"
    $originalHandle = [IntPtr]::Zero; $threadHandle = [IntPtr]::Zero; $stdoutReadHandle = [IntPtr]::Zero; $stderrReadHandle = [IntPtr]::Zero; [uint32]$processId = 0
    $outPipe = $null; $errPipe = $null; $outStream = $null; $errStream = $null; $outTask = $null; $errTask = $null; $streamsSealed = $false
    $startUtc = [DateTimeOffset]::UtcNow.ToString('o')
    try {
      $jobHandle = [Sr0OwnedJobProcess]::CreateJob()
      if ($jobHandle -eq [IntPtr]::Zero) { throw "job create failed edit $i" }
      $jobHandleRetained = $true
      if (-not [Sr0OwnedJobProcess]::ConfigureJob($jobHandle, 1073741824)) { throw "job memory cap failed edit $i" }
      $env:Path = $shimPath; $env:RUSTC_WRAPPER = (Join-Path $shim 'rustc.cmd')
      if (-not [Sr0OwnedJobProcess]::CreateSuspended($SwiftPath, $swiftCommandLine, $work, [ref]$originalHandle, [ref]$threadHandle, [ref]$stdoutReadHandle, [ref]$stderrReadHandle, [ref]$processId)) { throw "swift suspended start failed edit $i" }
      if ($originalHandle -eq [IntPtr]::Zero -or $threadHandle -eq [IntPtr]::Zero) { throw "swift handle missing edit $i" }
      $originalHandleRetained = $true; $jobHandleRetained = $jobHandle -ne [IntPtr]::Zero
      # Start both bounded pipe readers while child is suspended, before job assignment/resume.
      # Explicit CloseHandle below owns native pipe handles; streams must not double-close them.
      $outPipe = New-Object IO.FileStream($stdoutReadHandle,[IO.FileAccess]::Read,$false)
      $errPipe = New-Object IO.FileStream($stderrReadHandle,[IO.FileAccess]::Read,$false)
      $outStream = [IO.File]::Open($stdoutPath, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read)
      $errStream = [IO.File]::Open($stderrPath, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read)
      $outTask = $outPipe.CopyToAsync($outStream)
      $errTask = $errPipe.CopyToAsync($errStream)
      if (-not [Sr0OwnedJobProcess]::AssignProcessToJobObject($jobHandle, $originalHandle)) { throw "job assignment before resume failed edit $i" }
      $jobAssigned = $true
      if ([Sr0OwnedJobProcess]::ResumeThread($threadHandle, $originalHandle) -eq [uint32]::MaxValue) { throw "swift resume failed edit $i" }
      $watch = [Diagnostics.Stopwatch]::StartNew(); $kernelWait = 258; $timedOut = $false
      $outputExceeded = $false
      while ($true) {
        $kernelWait = [Sr0OwnedJobProcess]::WaitForSingleObject($originalHandle, 1000)
        if ($kernelWait -eq 0) { break }
        if ((Get-Item -LiteralPath $stdoutPath).Length -gt 8388608 -or (Get-Item -LiteralPath $stderrPath).Length -gt 8388608) { $outputExceeded = $true; break }
        if ($watch.Elapsed.TotalSeconds -ge 900) { $timedOut = $true; break }
      }
      $terminatedForTimeout = $false
      $terminatedForOutputCap = $false
      if ($timedOut -or $outputExceeded) {
        if ($outputExceeded) { $terminatedForOutputCap = [Sr0OwnedJobProcess]::TerminateJobObject($jobHandle, 125) }
        else { $terminatedForTimeout = [Sr0OwnedJobProcess]::TerminateJobObject($jobHandle, 124) }
        $kernelWait = [Sr0OwnedJobProcess]::WaitForSingleObject($originalHandle, 15000)
      }
      $kernelCode = [uint32]0
      $kernelRead = ($kernelWait -eq 0) -and [Sr0OwnedJobProcess]::GetExitCodeProcess($originalHandle, [ref]$kernelCode)
      $kernelTerminal = ($kernelWait -eq [Sr0OwnedJobProcess]::WaitObject0)
      $dotnetExit = if ($kernelWait -eq 0) { [int64]$kernelCode } else { -1 }
      $drained = $false
      if ($outTask -and $errTask) {
        $outDone = $outTask.Wait(15000)
        $errDone = $errTask.Wait(15000)
        $drained = $outDone -and $errDone
      }
      if (-not $drained) {
        [Sr0OwnedJobProcess]::TerminateJobObject($jobHandle, 124) | Out-Null
        [Sr0OwnedJobProcess]::WaitForSingleObject($originalHandle, 5000) | Out-Null
        $outDone = $outTask.Wait(5000)
        $errDone = $errTask.Wait(5000)
        $drained = $outDone -and $errDone
      }
      $jobActive = [uint32]0
      $jobActiveReadable = [Sr0OwnedJobProcess]::ReadActiveProcessCount($jobHandle, [ref]$jobActive)
      if (-not $jobActiveReadable -or $jobActive -ne 0) {
        [Sr0OwnedJobProcess]::TerminateJobObject($jobHandle, 124) | Out-Null
        [Sr0OwnedJobProcess]::WaitForSingleObject($originalHandle, 5000) | Out-Null
        $outDone = $outTask.Wait(5000)
        $errDone = $errTask.Wait(5000)
        $drained = $outDone -and $errDone
        # Kill-on-close is not the proof: poll job accounting until active count is zero.
        $jobActiveReadable = $false; $jobActive = [uint32]1
        for ($q = 0; $q -lt 60; $q++) {
          $jobActive = [uint32]0
          $jobActiveReadable = [Sr0OwnedJobProcess]::ReadActiveProcessCount($jobHandle, [ref]$jobActive)
          if ($jobActiveReadable -and $jobActive -eq 0) { break }
          [Sr0OwnedJobProcess]::WaitForSingleObject($originalHandle, 250) | Out-Null
        }
      }
      $shimCountAfter = Get-BoundedLineCount $shimLog
      $rustInvocations = $shimCountAfter - $shimCountBefore
      if ((Get-Item -LiteralPath $stdoutPath).Length -gt 8388608 -or (Get-Item -LiteralPath $stderrPath).Length -gt 8388608) { $outputExceeded = $true }
      if ($kernelWait -ne 0 -or -not $kernelRead -or $kernelCode -eq 259 -or $dotnetExit -ne 0 -or -not $drained -or $timedOut -or $outputExceeded -or -not $jobActiveReadable -or $jobActive -ne 0) { throw "incremental edit $i terminal/timeout/drain/output/job-quiescence proof failed" }
      # Seal pipe writers before any file metadata/hash read. Windows sharing
      # rejects Get-FileHash while CopyToAsync still owns writer handles.
      $outTask.GetAwaiter().GetResult(); $errTask.GetAwaiter().GetResult()
      if ($outStream) { $outStream.Flush(); $outStream.Dispose(); $outStream = $null }
      if ($errStream) { $errStream.Flush(); $errStream.Dispose(); $errStream = $null }
      $streamsSealed = $true
      $streamsDrained = $true
      $jobQuiescent = $kernelTerminal -and $streamsDrained -and $jobActiveReadable -and ($jobActive -eq 0)
      $stdoutItem = Get-Item -LiteralPath $stdoutPath -Force
      $stderrItem = Get-Item -LiteralPath $stderrPath -Force
      if ($stdoutItem.Length -gt 8388608 -or $stderrItem.Length -gt 8388608) { throw "stream exceeded bounded receipt size edit $i" }
      $stdoutHash = Hash-File $stdoutPath
      $stderrHash = Hash-File $stderrPath
      $postBuild = [ordered]@{}
      foreach ($path in $artifactPaths) { $postBuild[$path] = Hash-File $path; Restore-Bytes $path $artifactBytes[$path] }
      $restored = [ordered]@{}
      foreach ($path in $artifactPaths) { $restored[$path] = Hash-File $path }
      $rustTotal += $rustInvocations
      $trials += [ordered]@{ edit=$i; start_utc=$startUtc; process_id=$processId; original_handle_retained=$true; job_handle_retained=$true; memory_cap_bytes=1073741824; memory_limit_kind='job-memory'; kernel_wait=$kernelWait; kernel_exit_code=[uint64]$kernelCode; dotnet_exit_code=$dotnetExit; streams_drained=$drained; streams_sealed=$streamsSealed; seal_order='await-copy-tasks,flush,dispose,then-size-hash'; stdout_drained=$outTask.IsCompleted; stderr_drained=$errTask.IsCompleted; stdout_bytes=$stdoutItem.Length; stderr_bytes=$stderrItem.Length; stdout_sha256=$stdoutHash; stderr_sha256=$stderrHash; owned_process=$true; owned_descendants=($jobActiveReadable -and $jobActive -eq 0); job_active_processes=$jobActive; job_active_readable=$jobActiveReadable; timeout=$timedOut; timeout_termination=$terminatedForTimeout; output_cap_exceeded=$outputExceeded; output_cap_termination=$terminatedForOutputCap; shim_line_count_before=$shimCountBefore; shim_line_count_after=$shimCountAfter; shim_line_count_total=$shimCountAfter; post_build_hashes=$postBuild; restored_hashes=$restored; rust_invocations=$rustInvocations }
    } catch {
      $trialFailure = $_.Exception.Message
    } finally {
      if ($originalHandle -eq [IntPtr]::Zero) { $jobQuiescent = $true }
      if ($originalHandle -ne [IntPtr]::Zero -and -not $jobQuiescent) {
        if ($jobAssigned -and $jobHandle -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::TerminateJobObject($jobHandle, 124) | Out-Null }
        else { [Sr0OwnedJobProcess]::TerminateProcess($originalHandle, 124) | Out-Null }
        $cleanupWait = [Sr0OwnedJobProcess]::WaitForSingleObject($originalHandle, 5000)
        $kernelTerminal = ($cleanupWait -eq [Sr0OwnedJobProcess]::WaitObject0)
        $outDone = if ($outTask) { $outTask.Wait(5000) } else { $false }
        $errDone = if ($errTask) { $errTask.Wait(5000) } else { $false }
        $streamsDrained = $outDone -and $errDone
        $cleanupStreamsDrained = $streamsDrained
        $cleanupActive = [uint32]1
        $cleanupReadable = $false
        for ($q = 0; $q -lt 60; $q++) {
          if ($jobHandle -eq [IntPtr]::Zero) { $cleanupReadable = $true; $cleanupActive = 0; break }
          $cleanupActive = [uint32]0
          $cleanupReadable = [Sr0OwnedJobProcess]::ReadActiveProcessCount($jobHandle, [ref]$cleanupActive)
          if ($cleanupReadable -and $cleanupActive -eq 0) { break }
          [Threading.Thread]::Sleep(250)
        }
        $jobQuiescent = $kernelTerminal -and $streamsDrained -and $cleanupReadable -and ($cleanupActive -eq 0)
      }
      if ($originalHandle -ne [IntPtr]::Zero -and $jobHandle -ne [IntPtr]::Zero) { $jobActiveReadable = $cleanupReadable; $jobActive = $cleanupActive }
      if (-not $jobQuiescent) { $allJobsQuiescent = $false }
      if ($outPipe) { $outPipe.Dispose() }
      if ($errPipe) { $errPipe.Dispose() }
      if ($threadHandle -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::CloseHandle($threadHandle) | Out-Null; $threadHandle = [IntPtr]::Zero }
      if ($originalHandle -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::CloseHandle($originalHandle) | Out-Null; $originalHandle = [IntPtr]::Zero }
      if ($stdoutReadHandle -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::CloseHandle($stdoutReadHandle) | Out-Null; $stdoutReadHandle = [IntPtr]::Zero }
      if ($stderrReadHandle -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::CloseHandle($stderrReadHandle) | Out-Null; $stderrReadHandle = [IntPtr]::Zero }
      if ($jobHandle -ne [IntPtr]::Zero) { [Sr0OwnedJobProcess]::CloseHandle($jobHandle) | Out-Null; $jobHandle = [IntPtr]::Zero }
      if ($outStream) { $outStream.Dispose() }
      if ($errStream) { $errStream.Dispose() }
    }
    if ($null -ne $trialFailure) {
      $failureReceipt = [ordered]@{
        kind='sr0-tuple12-ui-only-incremental-v9-edit-failure'; edit=$i; run_id=$runId; failure=$trialFailure
        compiler_path=$SwiftPath; compiler_bin=$CompilerBin; runtime_bin=$RuntimeBin; path_prefix=@($shim,$CompilerBin,$RuntimeBin); runtime_core_dll=$runtimeCoreDll; runtime_core_dll_sha256=(Hash-File $runtimeCoreDll); runtime_path_prefix_source='sealed source build prepends compiler bin & Swift Runtimes 6.4.0 usr bin'
        original_handle_retained=$originalHandleRetained; job_handle_retained=$jobHandleRetained; assigned=$jobAssigned
        kernel_wait=$kernelWait; kernel_terminal=$kernelTerminal; kernel_exit_read=$kernelRead; kernel_exit_code=[uint64]$kernelCode; dotnet_exit_code=$dotnetExit
        timed_out=$timedOut; output_cap_exceeded=$outputExceeded; timeout_termination=$terminatedForTimeout; output_cap_termination=$terminatedForOutputCap
        stdout_drained=($outDone -and $outTask -and $outTask.IsCompleted); stderr_drained=($errDone -and $errTask -and $errTask.IsCompleted); streams_drained=$streamsDrained; streams_sealed=$streamsSealed; seal_order='await-copy-tasks,flush,dispose,then-size-hash'
        active_query_readable=$jobActiveReadable; active_processes=$jobActive; cleanup_wait=$cleanupWait; cleanup_streams_drained=$cleanupStreamsDrained; cleanup_active_readable=$cleanupReadable; cleanup_active_processes=$cleanupActive; cleanup_quiescent=$jobQuiescent
        mutation_held=$true; restoration_attempted=$false; restoration_allowed=$false; receipt_truth='failure-preserved-before-throw'
      }
      Write-CreateNewText $failureReceiptPath ($failureReceipt | ConvertTo-Json -Depth 12)
      throw $trialFailure
    }
    [GC]::Collect()
  }
} finally {
  $env:Path = $oldPath
  $env:RUSTC_WRAPPER = if ($null -eq $oldWrapper) { '' } else { $oldWrapper }
  if ($allJobsQuiescent) {
    try {
      Restore-Bytes $target $sourceBefore
      foreach ($path in $artifactPaths) { Restore-Bytes $path $artifactBytes[$path] }
      $sourceRestored = ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -eq $sourceBeforeHash)
      $heldMutation = -not $sourceRestored
      if (-not $sourceRestored) { $allJobsQuiescent = $false }
    } catch {
      $allJobsQuiescent = $false
      $heldMutation = $true
    }
  }
  if (-not $allJobsQuiescent) {
    # Held mutation is deliberate evidence when exact owned job quiescence was
    # not proved; never restore bytes while a child can still observe them.
    $heldReceiptPath = Join-Path $runRoot 'held-mutation-receipt.json'
    $heldReceipt = [ordered]@{
      kind='sr0-tuple12-ui-only-incremental-v9-held-mutation'; run_id=$runId
      source_root=$sourceFull; stage_root=$stageFull; edits_completed=@($trials).Count
      source_restored=$false; hashes_identical=$false; artifact_restoration_only=$true
      restoration_allowed=$false; job_quiescence_proved=$false
      reason='owned process kernel terminal, active=0, & stream drain or restoration proof incomplete'
    }
    Write-CreateNewText $heldReceiptPath ($heldReceipt | ConvertTo-Json -Depth 8)
  }
}
if (-not $sourceRestored) { throw 'source restoration hash mismatch' }
$finalHashes = [ordered]@{}
foreach ($path in $artifactPaths) { $finalHashes[$path] = Hash-File $path }
$artifactIdentity = $true
foreach ($path in $artifactPaths) { if ($finalHashes[$path] -cne $artifactBefore[$path]) { $artifactIdentity = $false } }
if (-not $artifactIdentity) { throw 'final artifact identity mismatch' }
$shimLines = [IO.File]::ReadAllLines($shimLog)
$receipt = [ordered]@{
  kind='sr0-tuple12-ui-only-incremental-v9'; platform='windows'; stage_root=$stageFull; source_root=$sourceFull; run_id=$runId; edits=$Edits
  source_commit=[string]$meta.sourceCommit; source_manifest_sha256=[string]$meta.sourceManifestSha256; source_file_sha256=$sourceBeforeHash
  compiler_path=$SwiftPath; compiler_sha256=(Hash-File $SwiftPath); compiler_bin=$CompilerBin; runtime_bin=$RuntimeBin; path_prefix=@($shim,$CompilerBin,$RuntimeBin); runtime_core_dll=$runtimeCoreDll; runtime_core_dll_sha256=(Hash-File $runtimeCoreDll); runtime_path_prefix_source='sealed source build prepends compiler bin & Swift Runtimes 6.4.0 usr bin'; argv=$swiftCommandLine; arguments=$swiftArgs; working_directory=$work
  trials=$trials; rust_invocations_total=$rustTotal; shim_log=$shimLines; shim_log_line_count_total=(Get-BoundedLineCount $shimLog); stream_seal_contract='each trial records streams_sealed=true only after await, flush, dispose, & before size/hash'
  hashes_before=$artifactBefore; hashes_after=$finalHashes; source_restored=$sourceRestored; hashes_identical=$artifactIdentity
  final_noop_identity_check=$false; artifact_restoration_only=$true; job_quiescence_required=$true; all_jobs_quiescent=$allJobsQuiescent; builds_ok=(@($trials | Where-Object { $_.dotnet_exit_code -ne 0 -or $_.kernel_wait -ne 0 -or -not $_.stdout_drained -or -not $_.stderr_drained -or $_.output_cap_exceeded -or -not $_.job_active_readable -or $_.job_active_processes -ne 0 }).Count -eq 0)
  owned_namespace=$true; desktop_lock_touched=$false; gui_launched=$false; native_input=$false
}
$out = Join-Path $StageRoot 'incremental.json'
if (Test-Path -LiteralPath $out) { throw "incremental receipt already exists: $out" }
Write-CreateNewText $out ($receipt | ConvertTo-Json -Depth 12)
if (-not $receipt.builds_ok -or $rustTotal -ne 0 -or -not $artifactIdentity) { throw 'incremental qualification failed' }
"incremental receipt=$out rust_invocations_total=$rustTotal hashes_identical=$artifactIdentity source_restored=$sourceRestored"
