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
  [string]$SwiftPath = 'C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe'
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
  return [IO.File]::ReadAllBytes($Path)
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
$stageFull = [IO.Path]::GetFullPath($StageRoot)
$sourceFull = [IO.Path]::GetFullPath($SourceRoot)
if (-not $sourceFull.StartsWith($stageFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'SourceRoot escaped StageRoot' }
$meta = Get-Content -LiteralPath $BuildMetadata -Raw | ConvertFrom-Json
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
Require-File $exe
Require-File $dll
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
$shimPath = "$shim;$oldPath"
$oldWrapper = $env:RUSTC_WRAPPER
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Sr0IncrementalKernelV2 {
  [StructLayout(LayoutKind.Sequential)] struct Basic { public long user; public long kernel; public uint min; public uint max; public uint active; public uint affinity; public uint priority; public uint scheduling; public uint flags; }
  [StructLayout(LayoutKind.Sequential)] struct Io { public ulong read; public ulong write; public ulong other; public ulong rbytes; public ulong wbytes; public ulong obytes; }
  [StructLayout(LayoutKind.Sequential)] struct Extended { public Basic basic; public Io io; public UIntPtr processMemory; public UIntPtr jobMemory; public UIntPtr peakProcess; public UIntPtr peakJob; }
  [DllImport("kernel32.dll", SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern IntPtr CreateJobObject(IntPtr attrs, string name);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int kind, ref Extended info, uint length);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool TerminateJobObject(IntPtr job, uint code);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
  public static bool ConfigureJob(IntPtr job, ulong memory) { var x = new Extended(); x.basic.flags = 0x2000u | 0x100u; x.processMemory = (UIntPtr)memory; return SetInformationJobObject(job, 9, ref x, (uint)Marshal.SizeOf(typeof(Extended))); }
}
'@
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
$swiftArgs = "build --jobs 1 -c release --product WorkloadWin --scratch-path `"$StageRoot\scratch`" -Xlinker `"/MANIFEST:EMBED`" -Xlinker `"$dep`""
$trials = @()
$rustTotal = 0
$sourceRestored = $false
try {
  $env:Path = $shimPath
  $env:RUSTC_WRAPPER = (Join-Path $shim 'rustc.cmd')
  for ($i = 1; $i -le $Edits; $i++) {
    Add-Marker $target $i $runId
    $stdoutPath = Join-Path $trialDir "edit-$i.stdout.txt"
    $stderrPath = Join-Path $trialDir "edit-$i.stderr.txt"
    Write-CreateNewText $stdoutPath ''
    Write-CreateNewText $stderrPath ''
    $shimCountBefore = Get-BoundedLineCount $shimLog
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $SwiftPath
    $psi.Arguments = $swiftArgs
    $psi.WorkingDirectory = $work
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['PATH'] = $shimPath
    $psi.EnvironmentVariables['RUSTC_WRAPPER'] = (Join-Path $shim 'rustc.cmd')
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $psi
    $jobHandle = [IntPtr]::Zero
    $outStream = $null; $errStream = $null; $outTask = $null; $errTask = $null
    $startUtc = [DateTimeOffset]::UtcNow.ToString('o')
    try {
      $jobHandle = [Sr0IncrementalKernelV2]::CreateJobObject([IntPtr]::Zero, $null)
      if ($jobHandle -eq [IntPtr]::Zero) { throw "job create failed edit $i" }
      if (-not [Sr0IncrementalKernelV2]::ConfigureJob($jobHandle, 1073741824)) { throw "job memory cap failed edit $i" }
      if (-not $proc.Start()) { throw "swift start failed edit $i" }
      $originalHandle = $proc.Handle
      if ($originalHandle -eq [IntPtr]::Zero) { throw "swift handle missing edit $i" }
      if (-not [Sr0IncrementalKernelV2]::AssignProcessToJobObject($jobHandle, $originalHandle)) { throw "job assignment failed edit $i" }
      $outStream = [IO.File]::Open($stdoutPath, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read)
      $errStream = [IO.File]::Open($stderrPath, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read)
      $outTask = $proc.StandardOutput.BaseStream.CopyToAsync($outStream)
      $errTask = $proc.StandardError.BaseStream.CopyToAsync($errStream)
      $watch = [Diagnostics.Stopwatch]::StartNew(); $kernelWait = 258; $timedOut = $false
      $outputExceeded = $false
      while ($true) {
        $kernelWait = [Sr0IncrementalKernelV2]::WaitForSingleObject($originalHandle, 1000)
        if ($kernelWait -eq 0) { break }
        if ((Get-Item -LiteralPath $stdoutPath).Length -gt 8388608 -or (Get-Item -LiteralPath $stderrPath).Length -gt 8388608) { $outputExceeded = $true; break }
        if ($watch.Elapsed.TotalSeconds -ge 900) { $timedOut = $true; break }
      }
      $terminatedForTimeout = $false
      $terminatedForOutputCap = $false
      if ($timedOut -or $outputExceeded) {
        if ($outputExceeded) { $terminatedForOutputCap = [Sr0IncrementalKernelV2]::TerminateJobObject($jobHandle, 125) }
        else { $terminatedForTimeout = [Sr0IncrementalKernelV2]::TerminateJobObject($jobHandle, 124) }
        $kernelWait = [Sr0IncrementalKernelV2]::WaitForSingleObject($originalHandle, 15000)
      }
      $kernelCode = [uint32]0
      $kernelRead = ($kernelWait -eq 0) -and [Sr0IncrementalKernelV2]::GetExitCodeProcess($originalHandle, [ref]$kernelCode)
      $dotnetExit = if ($kernelWait -eq 0) { $proc.ExitCode } else { -1 }
      $drained = $false
      if ($outTask -and $errTask) { $drained = $outTask.Wait(15000) -and $errTask.Wait(15000) }
      if (-not $drained) {
        [Sr0IncrementalKernelV2]::TerminateJobObject($jobHandle, 124) | Out-Null
        [Sr0IncrementalKernelV2]::WaitForSingleObject($originalHandle, 5000) | Out-Null
        $drained = $outTask.Wait(5000) -and $errTask.Wait(5000)
      }
      $shimCountAfter = Get-BoundedLineCount $shimLog
      $rustInvocations = $shimCountAfter - $shimCountBefore
      if ((Get-Item -LiteralPath $stdoutPath).Length -gt 8388608 -or (Get-Item -LiteralPath $stderrPath).Length -gt 8388608) { $outputExceeded = $true }
      if ($kernelWait -ne 0 -or -not $kernelRead -or $kernelCode -eq 259 -or $dotnetExit -ne 0 -or -not $drained -or $timedOut -or $outputExceeded) { throw "incremental edit $i terminal/timeout/drain/output proof failed" }
      $outTask.GetAwaiter().GetResult(); $errTask.GetAwaiter().GetResult()
      $postBuild = [ordered]@{}
      foreach ($path in $artifactPaths) { $postBuild[$path] = Hash-File $path; Restore-Bytes $path $artifactBytes[$path] }
      $restored = [ordered]@{}
      foreach ($path in $artifactPaths) { $restored[$path] = Hash-File $path }
      $rustTotal += $rustInvocations
      $trials += [ordered]@{ edit=$i; start_utc=$startUtc; process_id=$proc.Id; original_handle_retained=$true; job_handle_retained=$true; memory_cap_bytes=1073741824; kernel_wait=$kernelWait; kernel_exit_code=[uint64]$kernelCode; dotnet_exit_code=$dotnetExit; streams_drained=$drained; stdout_drained=$outTask.IsCompleted; stderr_drained=$errTask.IsCompleted; owned_process=$true; owned_descendants=$true; timeout=$timedOut; timeout_termination=$terminatedForTimeout; output_cap_exceeded=$outputExceeded; output_cap_termination=$terminatedForOutputCap; shim_line_count_before=$shimCountBefore; shim_line_count_after=$shimCountAfter; shim_line_count_total=$shimCountAfter; post_build_hashes=$postBuild; restored_hashes=$restored; rust_invocations=$rustInvocations }
    } finally {
      if ($jobHandle -ne [IntPtr]::Zero) { [Sr0IncrementalKernelV2]::CloseHandle($jobHandle) | Out-Null; $jobHandle = [IntPtr]::Zero }
      if ($outStream) { $outStream.Dispose() }
      if ($errStream) { $errStream.Dispose() }
      if ($proc) { $proc.Dispose() }
    }
    [GC]::Collect()
  }
} finally {
  $env:Path = $oldPath
  $env:RUSTC_WRAPPER = if ($null -eq $oldWrapper) { '' } else { $oldWrapper }
  Restore-Bytes $target $sourceBefore
  foreach ($path in $artifactPaths) { Restore-Bytes $path $artifactBytes[$path] }
  $sourceRestored = ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -eq $sourceBeforeHash)
}
if (-not $sourceRestored) { throw 'source restoration hash mismatch' }
$finalHashes = [ordered]@{}
foreach ($path in $artifactPaths) { $finalHashes[$path] = Hash-File $path }
$artifactIdentity = $true
foreach ($path in $artifactPaths) { if ($finalHashes[$path] -cne $artifactBefore[$path]) { $artifactIdentity = $false } }
if (-not $artifactIdentity) { throw 'final artifact identity mismatch' }
$shimLines = [IO.File]::ReadAllLines($shimLog)
$receipt = [ordered]@{
  kind='sr0-tuple12-ui-only-incremental-v2'; platform='windows'; stage_root=$stageFull; source_root=$sourceFull; run_id=$runId; edits=$Edits
  source_commit=[string]$meta.sourceCommit; source_manifest_sha256=[string]$meta.sourceManifestSha256; source_file_sha256=$sourceBeforeHash
  compiler_path=$SwiftPath; compiler_sha256=(Hash-File $SwiftPath); argv=$swiftArgs; working_directory=$work
  trials=$trials; rust_invocations_total=$rustTotal; shim_log=$shimLines; shim_log_line_count_total=(Get-BoundedLineCount $shimLog)
  hashes_before=$artifactBefore; hashes_after=$finalHashes; source_restored=$sourceRestored; hashes_identical=$artifactIdentity
  final_noop_identity_check=$false; artifact_restoration_only=$true; builds_ok=(@($trials | Where-Object { $_.dotnet_exit_code -ne 0 -or $_.kernel_wait -ne 0 -or -not $_.stdout_drained -or -not $_.stderr_drained -or $_.output_cap_exceeded }).Count -eq 0)
  owned_namespace=$true; desktop_lock_touched=$false; gui_launched=$false; native_input=$false
}
$out = Join-Path $StageRoot 'incremental.json'
if (Test-Path -LiteralPath $out) { throw "incremental receipt already exists: $out" }
Write-CreateNewText $out ($receipt | ConvertTo-Json -Depth 12)
if (-not $receipt.builds_ok -or $rustTotal -ne 0 -or -not $artifactIdentity) { throw 'incremental qualification failed' }
"incremental receipt=$out rust_invocations_total=$rustTotal hashes_identical=$artifactIdentity source_restored=$sourceRestored"
