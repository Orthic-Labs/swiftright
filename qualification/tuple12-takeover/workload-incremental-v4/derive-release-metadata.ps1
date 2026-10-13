# Derive release build metadata from sealed tuple12 build receipt.
# Source-only candidate: no build, copy, signing, GUI, lock, or native action.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$StageRoot,
  [Parameter(Mandatory)][string]$Receipt,
  [Parameter(Mandatory)][string]$CompiledManifest,
  [string]$Out = ''
)
$ErrorActionPreference = 'Stop'
function Require-File([string]$Path, [Int64]$MaxBytes = 8388608) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "file missing: $Path" }
  $i = Get-Item -LiteralPath $Path
  if (($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "reparse file rejected: $Path" }
  if ($i.Length -gt $MaxBytes) { throw "file exceeds bounded read: $Path ($($i.Length) bytes)" }
}
function Write-CreateNewText([string]$Path, [string]$Text) {
  if (Test-Path -LiteralPath $Path) { throw "output already exists: $Path" }
  $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
  $s = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
  try { $s.Write($bytes, 0, $bytes.Length) } finally { $s.Dispose() }
}
Require-File $Receipt
Require-File $CompiledManifest
$r = Get-Content -LiteralPath $Receipt -Raw | ConvertFrom-Json
$m = Get-Content -LiteralPath $CompiledManifest -Raw | ConvertFrom-Json
if ([string]$r.kind -cne 'root-sr0-workload-windows-build-v1') { throw 'unexpected build receipt kind' }
if ([int]$r.exitCode -ne 0) { throw 'build receipt exitCode is not zero' }
if ([bool]$r.compilerKernelHandleRetained -ne $true) { throw 'compiler handle retention proof missing' }
if ([string]$r.sourceCommit -cne '0e201571e4320a3b6ccce14313fd2ad67e523904') { throw 'source commit mismatch' }
if ([string]$r.sourceManifestSha256 -cne '26705e8f1fdd0164a9963c9cb0f730fda2e313e5c07348097c8fe8ab3ef7e468') { throw 'source manifest mismatch' }
if ([int]$r.sourceFilesVerified -ne 54) { throw 'source file count is not 54' }
if ([string]$r.argv -notmatch 'build --jobs 1 -c release --product WorkloadWin') { throw 'receipt argv does not prove release build' }
if ([bool]$r.manifestOK -ne $true -or [int]$r.manifestVerifier.exitCode -ne 0) { throw 'embedded manifest proof missing' }
if ([int]$r.nativeLaunches -ne 0 -or [int]$r.lockActions -ne 0) { throw 'receipt includes native or lock action' }
if ([string]$r.qualification -cne 'hold-native') { throw 'receipt qualification state drift' }
if ([string]$m.sourceCommit -cne [string]$r.sourceCommit) { throw 'compiled manifest source commit does not join receipt' }
if ([string]$m.kind -cne 'root-sr0-workload-materialized-source-v1') { throw 'compiled manifest kind mismatch' }
if ([string]$m.planManifestSha256 -cne 'a780e651a1506fde772453548fd4defb4831731588c00e8772c224e47696cf28') { throw 'compiled manifest plan hash mismatch' }
if ($null -eq $m.files -or -not ($m.files -is [array])) { throw 'compiled manifest files must be an array' }
if (@($m.files).Count -ne 54) { throw 'compiled manifest files array count mismatch' }
$sourceFileCount = if ($m.sourceFiles -is [array]) { @($m.sourceFiles).Count } else { [int]$m.sourceFiles }
if ($sourceFileCount -ne 42) { throw 'compiled manifest source file count mismatch' }
if ([int]$m.patchesApplied -ne 3) { throw 'compiled manifest patch count mismatch' }
if ([string]$m.guardImport -cne 'SwiftRightBridge') { throw 'compiled manifest guard import mismatch' }
if ([string]$m.qualification -cne 'hold-build-native') { throw 'compiled manifest qualification state drift' }
foreach ($entry in @($m.files)) {
  if (-not $entry.path -or -not $entry.sha256 -or $null -eq $entry.bytes) { throw 'compiled manifest file entry is incomplete' }
  if ([int64]$entry.bytes -lt 0 -or ([string]$entry.sha256).Length -ne 64) { throw 'compiled manifest file entry is malformed' }
}
if ([string]$m.rendererSha256 -cne [string]$r.renderer.sha256) { throw 'compiled manifest renderer hash does not join receipt' }
$manifestHash = (Get-FileHash -LiteralPath $CompiledManifest -Algorithm SHA256).Hash.ToLowerInvariant()
if ($manifestHash -cne [string]$r.sourceManifestSha256) { throw 'compiled manifest bytes do not match receipt hash' }
foreach ($artifact in @($r.exe,$r.renderer)) {
  if (-not $artifact.path -or -not $artifact.sha256) { throw 'artifact path/hash missing from receipt' }
}
$OutPath = if ($Out) { $Out } else { Join-Path $StageRoot 'release-build-metadata.json' }
if (-not ([IO.Path]::GetFullPath($OutPath)).StartsWith([IO.Path]::GetFullPath($StageRoot) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'metadata output escaped StageRoot' }
$meta = [ordered]@{
  kind='sr0-tuple12-derived-release-build-metadata-v4'; configuration='release'; derivation='argv -c release from sealed root build receipt';
  receipt_path=[IO.Path]::GetFullPath($Receipt); receipt_sha256=(Get-FileHash -LiteralPath $Receipt -Algorithm SHA256).Hash.ToLowerInvariant();
  sourceCommit=[string]$r.sourceCommit; sourceManifestSha256=[string]$r.sourceManifestSha256; sourceFilesVerified=[int]$r.sourceFilesVerified;
  exe=[string]$r.exe.path; exe_sha256=[string]$r.exe.sha256; exe_bytes=[int64]$r.exe.bytes;
  dll=[string]$r.renderer.path; dll_sha256=[string]$r.renderer.sha256; dll_bytes=[int64]$r.renderer.bytes;
  compiled_manifest_path=[IO.Path]::GetFullPath($CompiledManifest); compiled_manifest_sha256=$manifestHash;
  swift_path=[string]$r.swift.path; swift_sha256=[string]$r.swift.sha256; compiler_handle_retained=$true; source_manifest_bytes=(Get-Item -LiteralPath $CompiledManifest).Length;
  original_build_argv=[string]$r.argv; working_directory=[string]$r.workingDirectory
}
Write-CreateNewText $OutPath ($meta | ConvertTo-Json -Depth 8)
"derived metadata=$OutPath receipt=$($meta.receipt_sha256) configuration=release sourceFilesVerified=54"
