[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$FreshPacketRoot,
  [Parameter(Mandatory = $true)][string]$SourcePackageRoot,
  [Parameter(Mandatory = $true)][string]$RuntimeSourceRoot,
  [Parameter(Mandatory = $true)][string]$BridgeSourceRoot,
  [Parameter(Mandatory = $true)][string]$CompilerPath,
  [Parameter(Mandatory = $true)][string]$RendererPath,
  [Parameter(Mandatory = $true)][string]$SwiftPath,
  [Parameter(Mandatory = $true)][string]$DestinationRoot,
  [Parameter(Mandatory = $true)][string]$SourceMapSha256
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Hash-File([string]$Path) {
  return ('sha256:' + (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant())
}
function Assert-Ref([string]$Label, [string]$Path, [string]$ExpectedHash, [Nullable[long]]$ExpectedBytes) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "MISSING $Label $Path" }
  $item = Get-Item -LiteralPath $Path
  $actualHash = Hash-File $Path
  if ($actualHash -ne $ExpectedHash) { throw "HASH_MISMATCH $Label expected=$ExpectedHash actual=$actualHash path=$Path" }
  if ($null -ne $ExpectedBytes -and $item.Length -ne [long]$ExpectedBytes) { throw "BYTES_MISMATCH $Label expected=$ExpectedBytes actual=$($item.Length) path=$Path" }
}
function Read-Json([string]$Path) {
  return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}
function Relative-Join([string]$Root, [string]$RelativePath) {
  return (Join-Path $Root ($RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar))
}

$mapPath = Join-Path $FreshPacketRoot 'source-bound-windows-r11-v2.json'
Assert-Ref 'source map' $mapPath $SourceMapSha256 $null
$map = Read-Json $mapPath
if ($map.schema -ne 'factory-windows-r11-fresh-compile-source-map-v1') { throw 'SOURCE_MAP_SCHEMA_MISMATCH' }
if ($SourcePackageRoot.TrimEnd('\') -ne $map.hostSource.sourceRoot.TrimEnd('\')) { throw 'HOST_SOURCE_ROOT_MISMATCH' }
if ($RuntimeSourceRoot.TrimEnd('\') -ne $map.runtimeSource.sourceRoot.TrimEnd('\')) { throw 'RUNTIME_SOURCE_ROOT_MISMATCH' }
if ($BridgeSourceRoot.TrimEnd('\') -ne $map.bridgeSource.sourceRoot.TrimEnd('\')) { throw 'BRIDGE_SOURCE_ROOT_MISMATCH' }
if ($CompilerPath -ne $map.toolchain.compilerPath) { throw 'COMPILER_PATH_MISMATCH' }
if ($RendererPath -ne $map.toolchain.rendererPath) { throw 'RENDERER_PATH_MISMATCH' }
if ($map.build.reuseExecutable -ne $false -or $map.build.freshExecutableRequired -ne $true) { throw 'SOURCE_MAP_REUSE_POLICY_MISMATCH' }

$freshCase = Join-Path $FreshPacketRoot $map.freshBinding.caseFile.path
$freshTuple = Join-Path $FreshPacketRoot $map.freshBinding.tupleFile.path
$freshManifest = Join-Path $FreshPacketRoot $map.freshBinding.freshWitnessManifest.path
$freshSource = Join-Path $FreshPacketRoot $map.freshBinding.freshWitnessSource.path
Assert-Ref 'fresh case' $freshCase $map.freshBinding.caseFile.sha256 $map.freshBinding.caseFile.bytes
Assert-Ref 'fresh tuple' $freshTuple $map.freshBinding.tupleFile.sha256 $map.freshBinding.tupleFile.bytes
Assert-Ref 'fresh witness manifest' $freshManifest $map.freshBinding.freshWitnessManifest.sha256 $map.freshBinding.freshWitnessManifest.bytes
Assert-Ref 'fresh witness source' $freshSource $map.freshBinding.freshWitnessSource.sha256 $map.freshBinding.freshWitnessSource.bytes
$freshCaseDoc = Read-Json $freshCase
$freshManifestDoc = Read-Json $freshManifest
if ($freshCaseDoc.id -ne $map.freshBinding.case.id -or $freshManifestDoc.case.id -ne $map.freshBinding.case.id) { throw 'FRESH_CASE_ID_MISMATCH' }
if ($freshManifestDoc.case.hash -ne $map.freshBinding.case.hash) { throw 'FRESH_MANIFEST_CASE_HASH_MISMATCH' }
if ($freshManifestDoc.sourceHash -ne $map.freshBinding.freshWitnessSource.sha256) { throw 'FRESH_MANIFEST_SOURCE_HASH_MISMATCH' }

foreach ($row in @($map.hostSource.rows)) {
  Assert-Ref ('host source ' + $row.relativePath) (Relative-Join $SourcePackageRoot $row.relativePath) $row.sha256 $row.bytes
}
foreach ($row in @($map.runtimeSource.rows)) {
  Assert-Ref ('runtime source ' + $row.relativePath) (Relative-Join $RuntimeSourceRoot $row.relativePath) $row.sha256 $null
}
foreach ($row in @($map.bridgeSource.rows)) {
  Assert-Ref ('bridge source ' + $row.relativePath) (Relative-Join $BridgeSourceRoot $row.relativePath) $row.sha256 $null
}
Assert-Ref 'compiler' $CompilerPath $map.toolchain.compilerHash $null
Assert-Ref 'renderer' $RendererPath $map.toolchain.rendererHash $null

$swiftSourceRows = @($map.hostSource.rows | Where-Object { $_.relativePath -like '*.swift' })
$forbiddenSourceTokens = @('84951ddf8b3ff3239a497d8a8bbe525a9e09b5d7354f2d2ac994cf8e740bbc3d', 'swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258', 'swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9')
foreach ($row in $swiftSourceRows) {
  $path = Relative-Join $SourcePackageRoot $row.relativePath
  $text = Get-Content -LiteralPath $path -Raw
  foreach ($token in $forbiddenSourceTokens) {
    if ($text.Contains($token)) { throw "FORBIDDEN_CASE_TOKEN_IN_COMPILED_SOURCE $token $path" }
  }
}

if (Test-Path -LiteralPath $DestinationRoot) { throw "DESTINATION_MUST_BE_FRESH $DestinationRoot" }
New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null
foreach ($row in @($map.hostSource.rows)) {
  $source = Relative-Join $SourcePackageRoot $row.relativePath
  $target = Join-Path $DestinationRoot ($row.relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
  $parent = Split-Path -Parent $target
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  Copy-Item -LiteralPath $source -Destination $target
}
$stagedWitness = Join-Path $DestinationRoot 'Sources/FactoryProbe/Witness.swift'
$stagedManifest = Join-Path $DestinationRoot 'witness.manifest.json'
Copy-Item -LiteralPath $freshSource -Destination $stagedWitness
Copy-Item -LiteralPath $freshManifest -Destination $stagedManifest
foreach ($row in @($map.hostSource.rows)) {
  $path = Join-Path $DestinationRoot ($row.relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
  Assert-Ref ('staged host source ' + $row.relativePath) $path $row.sha256 $row.bytes
}
Assert-Ref 'staged fresh witness manifest' $stagedManifest $map.freshBinding.freshWitnessManifest.sha256 $map.freshBinding.freshWitnessManifest.bytes

$scratch = Join-Path $DestinationRoot $map.build.scratchRelativePath
$swiftArgs = @('build', '--package-path', $DestinationRoot, '--scratch-path', $scratch, '-c', 'release', '-Xlinker', '/MANIFEST:EMBED', '-Xlinker', '/SUBSYSTEM:WINDOWS', '-Xlinker', '/ENTRY:mainCRTStartup')
$psi = [Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $SwiftPath
$psi.WorkingDirectory = $DestinationRoot
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.Arguments = (($swiftArgs | ForEach-Object { '"' + ([string]$_).Replace('"', '\"') + '"' }) -join ' ')
$proc = [Diagnostics.Process]::new()
$proc.StartInfo = $psi
$proc.PriorityClass = [Diagnostics.ProcessPriorityClass]::BelowNormal
if (-not $proc.Start()) { throw 'SWIFT_PROCESS_START_FAILED' }
$stdoutTask = $proc.StandardOutput.ReadToEndAsync()
$stderrTask = $proc.StandardError.ReadToEndAsync()
$proc.WaitForExit()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()
if ($stdout) { Write-Output $stdout }
if ($stderr) { Write-Error $stderr }
if ($proc.ExitCode -ne 0) { throw "SWIFT_BUILD_FAILED exit=$($proc.ExitCode)" }
$expectedExe = Join-Path $scratch 'out/Products/Release-windows-x86_64/FactoryProbe.exe'
if (-not (Test-Path -LiteralPath $expectedExe -PathType Leaf)) { throw "FRESH_EXECUTABLE_OUTPUT_MISSING $expectedExe" }
$exe = Get-Item -LiteralPath $expectedExe
$receipt = [ordered]@{
  schema = 'factory-windows-r11-fresh-compile-receipt-v1'
  status = 'compiled-source-bound-candidate-only'
  candidateOnly = $true
  case = $map.freshBinding.case
  tupleID = $map.freshBinding.tuple.id
  sourceMap = @{ path = $mapPath; sha256 = Hash-File $mapPath; bytes = (Get-Item -LiteralPath $mapPath).Length }
  executable = @{ path = $exe.FullName; sha256 = Hash-File $exe.FullName; bytes = $exe.Length }
  compiler = @{ path = $CompilerPath; sha256 = Hash-File $CompilerPath; bytes = (Get-Item -LiteralPath $CompilerPath).Length }
  runtimeSourceCommit = $map.runtimeSource.sourceCommit
  runtimeSourceTreeHash = $map.runtimeSource.sourceTreeHash
  rendererHash = $map.toolchain.rendererHash
  sourceHash = $map.freshBinding.freshWitnessSource.sha256
  argv = ($swiftArgs -join ' ')
  effects = @{ compilerActions = 1; nativeWindowActions = 0; lockActions = 0; remoteActions = 0 }
}
$receiptPath = Join-Path $DestinationRoot 'build-r11-fresh-receipt.json'
$receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding UTF8
Write-Output ($receipt | ConvertTo-Json -Depth 8)
