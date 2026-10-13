# Source-only stage installer. It performs no compiler, native, lock, or GUI action.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$PackageZip,
  [Parameter(Mandatory=$true)][string]$PackageZipSha256,
  [Parameter(Mandatory=$true)][string]$StageManifest,
  [Parameter(Mandatory=$true)][string]$StageManifestSha256,
  [Parameter(Mandatory=$true)][string]$BuildScriptPath,
  [Parameter(Mandatory=$true)][string]$BuildScriptSha256,
  [Parameter(Mandatory=$true)][string]$HelperPath,
  [Parameter(Mandatory=$true)][string]$HelperSha256,
  [string]$StageRoot='D:\Claude\swiftright\.factory-work\hosts\circle-close-r1'
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$MaxJson=4194304;$MaxFile=67108864;$MaxTotal=268435456;$MaxFiles=256
function Hash([string]$Path,[long]$Limit=$MaxFile) {
  $item=Get-Item -LiteralPath $Path -Force
  if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt $Limit){throw "bounded regular file required: $Path"}
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function LoadJson([string]$Path) {
  if((Get-Item -LiteralPath $Path -Force).Length -gt $MaxJson){throw "JSON bound exceeded: $Path"}
  Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}
function AssertHash([string]$Path,[string]$Expected,[long]$Limit=$MaxFile) {
  if((Hash $Path $Limit) -cne $Expected.Replace('sha256:','').ToLowerInvariant()){throw "hash mismatch: $Path"}
}
function SafeRel([string]$Value) {
  if([string]::IsNullOrWhiteSpace($Value) -or $Value.StartsWith('/') -or $Value.StartsWith('\') -or $Value -match '(^|/|\\)\.\.($|/|\\)' -or $Value -match '^[A-Za-z]:'){throw "unsafe archive path: $Value"}
  $Value.Replace('/','\')
}
function AssertArchive([string]$Path) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip=[IO.Compression.ZipFile]::OpenRead($Path);$seen=@{};$count=0;$total=[long]0
  try {
    foreach($entry in $zip.Entries) {
      if([string]::IsNullOrEmpty($entry.Name)){continue}
      $name=$entry.FullName.Replace('/','\');if(-not $name.StartsWith('package\',[StringComparison]::Ordinal)){throw 'archive root mismatch'}
      $rel=SafeRel $name.Substring(8);if($seen.ContainsKey($rel)){throw 'archive duplicate'};$seen[$rel]=$true
      if($entry.Length -gt $MaxFile){throw 'archive file bound exceeded'};$count++;$total+=$entry.Length
      if($count -gt $MaxFiles -or $total -gt $MaxTotal){throw 'archive total bound exceeded'}
      if(($entry.ExternalAttributes -band 0x40000000) -ne 0){throw 'archive reparse entry forbidden'}
    }
  } finally {$zip.Dispose()}
  if($count -lt 1){throw 'empty package archive'}
  [ordered]@{files=$count;bytes=$total}
}
$zip=[IO.Path]::GetFullPath($PackageZip);$manifestPath=[IO.Path]::GetFullPath($StageManifest);$stage=[IO.Path]::GetFullPath($StageRoot)
if(Test-Path -LiteralPath $stage){throw "fresh stage required: $stage"}
AssertHash $zip $PackageZipSha256 67108864
AssertHash $manifestPath $StageManifestSha256 $MaxJson
AssertHash $BuildScriptPath $BuildScriptSha256 $MaxFile
AssertHash $HelperPath $HelperSha256 $MaxFile
$manifest=LoadJson $manifestPath
if($manifest.kind -cne 'factory-circle-close-diagnostic-stage-v1' -or $manifest.status -cne 'SOURCE_ONLY'){throw 'stage manifest identity mismatch'}
if($manifest.stageRoot -cne $StageRoot){throw 'stage root mismatch'}
$archiveStats=AssertArchive $zip
if($manifest.packageArchive.sha256 -cne $PackageZipSha256.ToLowerInvariant()){throw 'manifest archive hash mismatch'}
New-Item -ItemType Directory -Path $stage -Force:$false|Out-Null
try {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::ExtractToDirectory($zip,$stage)
  $package=Join-Path $stage 'package'
  if(-not (Test-Path -LiteralPath $package -PathType Container)){throw 'package directory missing'}
  foreach($row in @($manifest.files)) {
    $rel=SafeRel ([string]$row.path);$file=Join-Path $package $rel
    if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw "staged file missing: $rel"}
    if((Get-Item -LiteralPath $file).Length -ne [int64]$row.bytes){throw "staged byte mismatch: $rel"}
    AssertHash $file ([string]$row.sha256) $MaxFile
  }
  $installedBuild=Join-Path $stage 'build-circle-close-diagnostic-v1.ps1';$installedHelper=Join-Path $stage 'Sr0OwnedJobProcess.cs'
  Copy-Item -LiteralPath $BuildScriptPath -Destination $installedBuild
  Copy-Item -LiteralPath $HelperPath -Destination $installedHelper
  AssertHash $installedBuild $BuildScriptSha256 $MaxFile;AssertHash $installedHelper $HelperSha256 $MaxFile
  $receipt=[ordered]@{kind='factory-circle-close-diagnostic-stage-installed-v1';status='SOURCE_ONLY';stageRoot=$StageRoot;archive=$PackageZipSha256.ToLowerInvariant();manifest=$StageManifestSha256.ToLowerInvariant();archiveFiles=$archiveStats.files;archiveBytes=$archiveStats.bytes;planSha256=([string]$manifest.plan.sha256);buildScriptSha256=$BuildScriptSha256.ToLowerInvariant();helperSha256=$HelperSha256.ToLowerInvariant();compilerActions=0;nativeActions=0;guiActions=0;lockActions=0}
  $receipt|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $stage 'install-receipt.json') -Encoding UTF8
  $receipt|ConvertTo-Json -Depth 12
} catch { throw }
