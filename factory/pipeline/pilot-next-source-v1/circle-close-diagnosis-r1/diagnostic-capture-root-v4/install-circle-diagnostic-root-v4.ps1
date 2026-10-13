# Source-only installer for diagnostic Circle Count1 packet. No compile/native/lock/GUI action.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$PackageZip,
  [Parameter(Mandatory=$true)][string]$PackageZipSha256,
  [Parameter(Mandatory=$true)][string]$StageManifest,
  [Parameter(Mandatory=$true)][string]$StageManifestSha256,
  [Parameter(Mandatory=$true)][string]$SourceGraph,
  [Parameter(Mandatory=$true)][string]$SourceGraphSha256,
  [Parameter(Mandatory=$true)][string]$BuildScriptPath,
  [Parameter(Mandatory=$true)][string]$BuildScriptSha256,
  [Parameter(Mandatory=$true)][string]$HelperPath,
  [Parameter(Mandatory=$true)][string]$HelperSha256,
  [string]$StageRoot='D:\Claude\swiftright\factory\native\windows\.work\circle-close-r11-r4'
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$MaxJson=4194304;$MaxFile=67108864;$MaxArchive=67108864;$MaxTotal=268435456;$MaxFiles=256
function Assert-Regular([string]$Path,[long]$Limit=$MaxFile){
  $i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if($i.PSIsContainer -or (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0) -or $i.Length -gt $Limit){throw "bounded regular file required: $Path"}
  return $i
}
function Hash-Bounded([string]$Path,[long]$Limit=$MaxFile){
  $i=Assert-Regular $Path $Limit;$stream=[IO.FileStream]::new($i.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$sha=[Security.Cryptography.SHA256]::Create();$buf=New-Object byte[] 1048576;$n=[long]0
  try{while(($r=$stream.Read($buf,0,$buf.Length))-gt 0){$n+=$r;if($n -gt $Limit){throw "hash bound exceeded: $Path"};[void]$sha.TransformBlock($buf,0,$r,$null,0)};[void]$sha.TransformFinalBlock($buf,0,0);$hex=([BitConverter]::ToString($sha.Hash)).Replace('-','').ToLowerInvariant()}finally{$stream.Dispose();$sha.Dispose()}
  if($n -ne $i.Length -or (Get-Item -LiteralPath $Path -Force).Length -ne $i.Length){throw "file changed during hash: $Path"};return $hex
}
function Load-Json([string]$Path){[void](Assert-Regular $Path $MaxJson);Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json}
function Assert-Hash([string]$Path,[string]$Expected,[long]$Limit=$MaxFile){$want=$Expected.ToLowerInvariant().Replace('sha256:','');if((Hash-Bounded $Path $Limit)-cne $want){throw "hash mismatch: $Path"}}
function Safe-Relative([string]$Value){
  if([string]::IsNullOrWhiteSpace($Value) -or $Value.StartsWith('/') -or $Value.StartsWith('\') -or $Value -match '^[A-Za-z]:' -or $Value -match '(^|[/\\])\.\.([/\\]|$)'){throw "unsafe archive path: $Value"};return $Value.Replace('/','\')
}
function Assert-Zip([string]$Path){
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip=[IO.Compression.ZipFile]::OpenRead($Path);$seen=@{};$n=0;$total=[long]0
  try{foreach($entry in $zip.Entries){if([string]::IsNullOrEmpty($entry.Name)){continue};$name=$entry.FullName.Replace('/','\');if(-not $name.StartsWith('package\',[StringComparison]::Ordinal)){throw 'archive package root mismatch'};$rel=Safe-Relative $name.Substring(8);if($seen.ContainsKey($rel)){throw "archive duplicate: $rel"};$seen[$rel]=$true;if($entry.Length -gt $MaxFile){throw 'archive file bound exceeded'};$n++;$total+=$entry.Length;if($n -gt $MaxFiles -or $total -gt $MaxTotal){throw 'archive total bound exceeded'};if(($entry.ExternalAttributes -band 0x40000000)-ne 0){throw 'archive reparse entry forbidden'}}}finally{$zip.Dispose()};if($n -eq 0){throw 'empty archive'};return [ordered]@{files=$n;bytes=$total}
}
$zip=[IO.Path]::GetFullPath($PackageZip);$manifestPath=[IO.Path]::GetFullPath($StageManifest);$graphPath=[IO.Path]::GetFullPath($SourceGraph);$stage=[IO.Path]::GetFullPath($StageRoot)
if(Test-Path -LiteralPath $stage){throw "fresh stage required: $stage"}
Assert-Hash $zip $PackageZipSha256 $MaxArchive;Assert-Hash $manifestPath $StageManifestSha256 $MaxJson;Assert-Hash $graphPath $SourceGraphSha256 $MaxJson;Assert-Hash $BuildScriptPath $BuildScriptSha256;Assert-Hash $HelperPath $HelperSha256
$manifest=Load-Json $manifestPath;$graph=Load-Json $graphPath
if($manifest.kind -cne 'factory-circle-incremental-diagnostic-stage-v4' -or $manifest.status -cne 'SOURCE_ONLY'){throw 'stage manifest identity mismatch'}
if([string]$manifest.stageRoot -cne $StageRoot){throw 'stage root mismatch'}
if([string]$manifest.plan.sha256 -ne 'sha256:a47edfddc082d183dff2f6af9888725896bf859c5c2e60b1e12a8fb0d392f6f1'){throw 'plan seal mismatch'}
if([string]$manifest.receipt.sha256 -ne 'sha256:fcbcdfafd2358b34b2d9483d229ccc019a5bba7c6320569436b39702edbe2428'){throw 'receipt seal mismatch'}
if([string]$manifest.incrementalPlanKind -ne 'factory-circle-incremental-compile-plan-v1' -or [string]$manifest.incrementalReceiptKind -ne 'factory-circle-incremental-owned-compile-v1'){throw 'incremental kinds required'}
if(([string]$graph.cleanup.renderer.sha256).Replace('sha256:','') -ne 'cce603b0e2582b0be65b0ff78b5be17b540fb98efa237bb23de68d9f4a5a7e13' -or [string]$graph.cleanup.uia.sha256 -ne [string]$graph.cleanup.renderer.sha256){throw 'cleanup-v2 graph seal mismatch'}
$zipStats=Assert-Zip $zip
New-Item -ItemType Directory -Path $stage -Force:$false | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($zip,$stage)
$package=Join-Path $stage 'package';if(-not(Test-Path -LiteralPath $package -PathType Container)){throw 'package missing'}
foreach($row in @($manifest.files)){$rel=Safe-Relative ([string]$row.path);$file=Join-Path $package $rel;if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw "staged row missing: $rel"};Assert-Hash $file ([string]$row.sha256);if((Get-Item -LiteralPath $file).Length -ne [int64]$row.bytes){throw "staged byte mismatch: $rel"}}
$installedBuild=Join-Path $stage 'build-circle-diagnostic-root-v4.ps1';$installedHelper=Join-Path $stage 'Sr0OwnedJobProcess.cs';Copy-Item -LiteralPath $BuildScriptPath -Destination $installedBuild;Copy-Item -LiteralPath $HelperPath -Destination $installedHelper;Assert-Hash $installedBuild $BuildScriptSha256;Assert-Hash $installedHelper $HelperSha256
$receipt=[ordered]@{kind='factory-circle-incremental-diagnostic-stage-installed-v4';status='SOURCE_ONLY';stageRoot=$StageRoot;packageArchiveSha256=$PackageZipSha256.ToLowerInvariant();stageManifestSha256=$StageManifestSha256.ToLowerInvariant();sourceGraphSha256=$SourceGraphSha256.ToLowerInvariant();archiveFiles=$zipStats.files;archiveBytes=$zipStats.bytes;planSha256=$manifest.plan.sha256;receiptSha256=$manifest.receipt.sha256;incrementalPlanKind=$manifest.incrementalPlanKind;incrementalReceiptKind=$manifest.incrementalReceiptKind;candidate=$manifest.candidate;qualification='diagnostic-native-only-not-qualified';compilerActions=0;nativeActions=0;guiActions=0;lockActions=0}
$receipt | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $stage 'install-receipt.json') -Encoding UTF8
$receipt | ConvertTo-Json -Depth 16
