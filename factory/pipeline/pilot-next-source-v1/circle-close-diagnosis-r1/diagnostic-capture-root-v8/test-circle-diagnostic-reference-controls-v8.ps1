[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$PackageRoot,
  [Parameter(Mandatory=$true)][string]$OverlayRoot,
  [Parameter(Mandatory=$true)][string]$AdmissionRoot,
  [Parameter(Mandatory=$true)][string]$SourceInputsPath,
  [Parameter(Mandatory=$true)][string]$ConfigPath
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$MaxJson=4194304;$MaxFile=67108864
function Full([string]$p){[IO.Path]::GetFullPath($p)}
function Regular([string]$p,[long]$limit=$MaxFile){
  $i=Get-Item -LiteralPath $p -Force -ErrorAction Stop
  if($i.PSIsContainer -or (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0) -or $i.Length -gt $limit){throw "unsafe typed reference: $p"}
  $i
}
function Hash([string]$p,[long]$limit=$MaxFile){
  $i=Regular $p $limit
  $h=(Get-FileHash -LiteralPath $i.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  $j=Get-Item -LiteralPath $p -Force
  if($j.Length -ne $i.Length){throw "typed reference changed: $p"};$h
}
function Expected([object]$r){([string]$r.sha256).ToLowerInvariant().Replace('sha256:','')}
function LocalRef([object]$r,[string]$name,[string]$root){
  if($null -eq $r -or [string]::IsNullOrWhiteSpace([string]$r.path)){throw "$name reference missing"}
  $full=Full ([string]$r.path);$base=(Full $root).TrimEnd('\')+'\'
  if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw "$name escapes installed package"}
  $i=Regular $full; $want=Expected $r
  if($want -notmatch '^[0-9a-f]{64}$'){throw "$name hash malformed"}
  if((Hash $full) -cne $want){throw "$name hash drift"}
  if($i.Length -ne [int64]$r.bytes){throw "$name byte drift"}
  $full
}
function LocalPath([string]$path,[string]$want,[string]$name,[string]$root){
  if([string]::IsNullOrWhiteSpace($path)){throw "$name path missing"}
  $full=Full $path;$base=(Full $root).TrimEnd('\')+'\'
  if(-not $full.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)){throw "$name path escapes installed package"}
  $i=Regular $full
  if([string]$want -notmatch '^[0-9a-f]{64}$' -or (Hash $full) -cne ([string]$want).ToLowerInvariant().Replace('sha256:','')){throw "$name hash drift"}
  $full
}
function Relative([string]$v){
  if([string]::IsNullOrWhiteSpace($v) -or [IO.Path]::IsPathRooted($v) -or $v -match '(^|[/\\])\.\.([/\\]|$)' -or $v -match '(^|[/\\])\.$'){throw "unsafe source binding path: $v"}
  $v.Replace('/','\')
}
$package=Full $PackageRoot;$overlay=Full $OverlayRoot;$admission=Full $AdmissionRoot
$cfg=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$si=Get-Content -LiteralPath $SourceInputsPath -Raw | ConvertFrom-Json
$checked=0
if((Full $cfg.package) -cne $package){throw 'config package root mismatch'}
if((Full $cfg.overlayRoot) -cne $overlay){throw 'config overlay root mismatch'}
if((Full $cfg.admissionRoot) -cne $admission){throw 'config admission root mismatch'}
$siFile=Regular $SourceInputsPath $MaxJson
if((Hash $SourceInputsPath $MaxJson) -cne ([string]$cfg.sourceInputsHash).ToLowerInvariant().Replace('sha256:','')){throw 'source-inputs config hash drift'}
$typed=@('tupleRef','bindingRef','contextRef','caseRef','recipeRef','manifestRef','serializerRef','integrationBindingsRef','buildPreflightRef','capturePlanRef')
foreach($n in $typed){if($null -ne $si.$n){[void](LocalRef $si.$n $n $package);$checked++}}
if($null -ne $si.serializerPath){[void](LocalPath ([string]$si.serializerPath) ([string]$si.serializerControlSha256) 'serializerPath' $package);$checked++}
if($null -ne $si.buildPreflightPath){[void](LocalPath ([string]$si.buildPreflightPath) ([string]$si.buildPreflightHash) 'buildPreflightPath' $package);$checked++}
if($null -ne $si.capturePlanPath){[void](LocalPath ([string]$si.capturePlanPath) ([string]$si.capturePlanHash) 'capturePlanPath' $package);$checked++}
if($null -ne $si.uiaWorkerPath){[void](LocalPath ([string]$si.uiaWorkerPath) ([string]$si.uiaWorkerHash) 'uiaWorkerPath' $package);$checked++}
foreach($row in @($cfg.sourceBindings)){
  $rel=Relative ([string]$row.path);$full=Join-Path $overlay $rel;$i=Regular $full
  $want=([string]$row.sha256).ToLowerInvariant().Replace('sha256:','')
  if($want -notmatch '^[0-9a-f]{64}$' -or (Hash $full) -cne $want -or $i.Length -ne [int64]$row.bytes){throw "overlay source binding drift: $rel"};$checked++
}
$guard=Full ([string]$cfg.integrationGuardPath)
if(-not $guard.StartsWith(($overlay.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'integration guard outside installed overlay'}
if((Hash $guard) -cne ([string]$cfg.integrationGuardHash).ToLowerInvariant().Replace('sha256:','')){throw 'integration guard hash drift'};$checked++
[ordered]@{kind='factory-circle-diagnostic-typed-reference-controls-v8';status='SOURCE_TYPED_REFERENCE_CONTROLS_PASS';checked=$checked;package=$package;overlay=$overlay;admission=$admission;nativeActions=0;compilerActions=0;lockActions=0}|ConvertTo-Json -Depth 8
