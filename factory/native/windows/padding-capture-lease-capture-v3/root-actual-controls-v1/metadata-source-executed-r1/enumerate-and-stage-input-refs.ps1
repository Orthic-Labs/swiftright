<#
Enumerates every hash/byte/path reference recursively from actual Count1 adapter
inputs, verifies source files, and creates one fresh non-overwriting Dell result
transport. No Python, compiler, native window, GUI, remote, lock, or cleanup action.
#>
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$AdapterInputsPath,
 [Parameter(Mandatory=$true)][string]$RepoRoot,
 [Parameter(Mandatory=$true)][string]$TransportRoot,
 [Parameter(Mandatory=$true)][string]$ManifestPath
)
$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $AdapterInputsPath -PathType Leaf)){throw 'Adapter inputs missing'}
if(Test-Path -LiteralPath $TransportRoot){throw 'Fresh transport root required; refusing overwrite'}
# Manifest must be emitted inside same fresh transport root; this prevents an
# external path from being overwritten or smuggled into the archive.
$transportFull=[System.IO.Path]::GetFullPath($TransportRoot).TrimEnd([char[]]'\/')
$manifestFull=[System.IO.Path]::GetFullPath($ManifestPath)
$transportPrefix=$transportFull+[System.IO.Path]::DirectorySeparatorChar
if(-not $manifestFull.StartsWith($transportPrefix,[System.StringComparison]::OrdinalIgnoreCase)){throw 'ManifestPath must be beneath fresh TransportRoot'}
$inputHash=(Get-FileHash -LiteralPath $AdapterInputsPath -Algorithm SHA256).Hash.ToLowerInvariant()
$inputBytes=(Get-Item -LiteralPath $AdapterInputsPath).Length
$adapterDocument=Get-Content -Raw -LiteralPath $AdapterInputsPath|ConvertFrom-Json
$refs=@{}
function Visit([object]$Value,[string]$Location){
 if($null -eq $Value){return}
 if($Value -is [string] -or $Value -is [int] -or $Value -is [long] -or $Value -is [bool]){return}
 if($Value -is [System.Array]){foreach($item in $Value){Visit $item $Location};return}
 $props=@($Value.PSObject.Properties)
 $pathProp=$Value.PSObject.Properties['path'];$hashProp=$Value.PSObject.Properties['sha256'];$bytesProp=$Value.PSObject.Properties['bytes']
 if($null -ne $pathProp -and $null -ne $hashProp -and $null -ne $bytesProp){
  $path=[string]$pathProp.Value;$sha=[string]$hashProp.Value
  $parts=$path.Split('/')
  if([string]::IsNullOrWhiteSpace($path) -or $path -match '^[A-Za-z]:' -or $path -match '^[\\/]' -or $path.Contains('\') -or $path.Contains(':') -or $path.Contains('//') -or $parts -contains '' -or $parts -contains '.' -or $parts -contains '..'){
   throw ('Adapter ref must be normalized repo-relative archive path: '+$path)
  }
  if($sha -notmatch '^sha256:[0-9a-f]{64}$'){throw ('Adapter ref hash invalid: '+$path)}
  if($bytesProp.Value -isnot [int] -and $bytesProp.Value -isnot [long]){throw ('Adapter ref byte count invalid: '+$path)}
  if($refs.ContainsKey($path)){
   $old=$refs[$path];if($old.sha256 -cne $sha -or [int64]$old.bytes -ne [int64]$bytesProp.Value){throw ('Conflicting duplicate adapter ref: '+$path)}
  } else {$refs[$path]=[pscustomobject]@{path=$path;sha256=$sha;bytes=[int64]$bytesProp.Value;locations=@($Location)}}
 }
 foreach($prop in $props){Visit $prop.Value ($Location+'.'+$prop.Name)}
}
Visit $adapterDocument '$'
if($refs.Count -lt 1){throw 'No transitive adapter refs found'}
# Validate complete source closure before creating any transport file.
$validated=[System.Collections.Generic.List[object]]::new()
$archiveRoot=Join-Path $TransportRoot 'archive'
$archiveFull=[System.IO.Path]::GetFullPath($archiveRoot).TrimEnd([char[]]'\/')
$archivePrefix=$archiveFull+[System.IO.Path]::DirectorySeparatorChar
foreach($path in ($refs.Keys|Sort-Object)){
 $ref=$refs[$path];$source=Join-Path $RepoRoot ($path -replace '/','\')
 if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw ('Adapter ref source missing: '+$path)}
 $actual=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant();$size=(Get-Item -LiteralPath $source).Length
 if($actual -cne $ref.sha256.Replace('sha256:','') -or [int64]$size -ne [int64]$ref.bytes){throw ('Adapter ref hash/bytes drift: '+$path)}
 $dest=Join-Path $archiveRoot ($path -replace '/','\')
 $destFull=[System.IO.Path]::GetFullPath($dest)
 if(-not $destFull.StartsWith($archivePrefix,[System.StringComparison]::OrdinalIgnoreCase)){throw ('Adapter destination escaped fresh transport root: '+$path)}
 $validated.Add([pscustomobject]@{path=$path;ref=$ref;source=$source;destination=$destFull})
}
New-Item -ItemType Directory -Force -Path $archiveRoot | Out-Null
Copy-Item -LiteralPath $AdapterInputsPath -Destination (Join-Path $TransportRoot 'inputs.json')
$rows=[System.Collections.Generic.List[object]]::new()
foreach($item in $validated){
 New-Item -ItemType Directory -Force -Path (Split-Path -Parent $item.destination) | Out-Null
 Copy-Item -LiteralPath $item.source -Destination $item.destination
 $ref=$item.ref
 $rows.Add([ordered]@{path=$item.path;sha256=$ref.sha256;bytes=[int64]$ref.bytes;locations=$ref.locations})
}
$manifest=[ordered]@{kind='factory-count1-dynamic-adapter-input-transport-v1';version='0.1';status='source-only-dell-transport';adapterInputs=[ordered]@{path='inputs.json';sha256=('sha256:'+$inputHash);bytes=[int64]$inputBytes};referenceCount=$rows.Count;references=@($rows);macStaticRefsDoNotQualify=$true;nativeWindowActions=0;compilerActions=0;qualification='hold'}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $manifestFull) | Out-Null
$manifest|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $manifestFull -Encoding UTF8
$zip=Join-Path $TransportRoot 'adapter-count1-dynamic-transport.zip'
Compress-Archive -LiteralPath (Join-Path $TransportRoot 'inputs.json'),(Join-Path $TransportRoot 'archive'),$manifestFull -DestinationPath $zip -CompressionLevel Optimal
[ordered]@{kind=$manifest.kind;referenceCount=$rows.Count;inputsSha256=$manifest.adapterInputs.sha256;zipPath=$zip;zipSha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant();nativeWindowActions=0}|ConvertTo-Json
