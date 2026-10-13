param(
 [Parameter(Mandatory=$true)][string]$StageRoot,
 [Parameter(Mandatory=$true)][string]$CoordinatorPath,
 [Parameter(Mandatory=$true)][string[]]$CallerPaths,
 [Parameter(Mandatory=$true)][string]$CleanupPath,
 [Parameter(Mandatory=$true)][string]$ExpectedCleanupHash
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
function Fail([string]$Message){throw ('factory-process-wait-v7: '+$Message)}
function Read-Bounded([string]$Path){
 $item=Get-Item -LiteralPath $Path -Force
 if($item.PSIsContainer -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0) -or $item.Length -gt 8388608){Fail ('unsafe source '+$Path)}
 return [IO.File]::ReadAllText($Path)
}
if(-not(Test-Path -LiteralPath $StageRoot -PathType Container)){Fail 'stage root missing'}
$cleanup=Read-Bounded $CleanupPath
if((Get-FileHash -LiteralPath $CleanupPath).Hash.ToLowerInvariant() -cne $ExpectedCleanupHash.ToLowerInvariant()){Fail 'cleanup hash drift'}
if($cleanup -notmatch "FactoryProcessWaitV6" -or $cleanup -notmatch "Add-Type"){Fail 'FactoryProcessWaitV6 definition missing'}
if($cleanup -match 'FactoryProcessWaitV5'){Fail 'stale V5 type in cleanup'}
. $CleanupPath
if(-not ('FactoryProcessWaitV6' -as [type])){Fail 'FactoryProcessWaitV6 was not loaded'}
$all=@($CoordinatorPath)+@($CallerPaths)
foreach($path in $all){
 $text=Read-Bounded $path
 if($text -match 'FactoryProcessWaitV5'){Fail ('stale V5 caller '+$path)}
 $idx=$text.IndexOf('[FactoryProcessWaitV6]',[StringComparison]::Ordinal)
 if($idx -ge 0){
  $cleanupIndex=$text.IndexOf('cleanup.ps1',[StringComparison]::Ordinal)
  if($cleanupIndex -lt 0 -or $cleanupIndex -gt $idx){Fail ('V6 caller loads cleanup after type use '+$path)}
 }
}
[ordered]@{kind='factory-process-wait-v7-controls';status='SOURCE_CONTROLS_PASS';type='FactoryProcessWaitV6';typeLoaded=$true;staleV5Rejected=$true;callers=@($all|ForEach-Object{[IO.Path]::GetFileName($_)});nativeActions=0;lockActions=0;compilerActions=0}|ConvertTo-Json -Depth 8
