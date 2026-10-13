[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if(-not(Test-Path -LiteralPath $Root -PathType Container)){throw 'V6 closure root missing'}
$required=@('capture-circle-diagnostic-single-v9.ps1')
$legacy='FactoryProcessWait'+'V5';$rows=@();$v6=0
foreach($name in $required){$p=Join-Path $Root ('overlay\root-v9\'+$name);if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ('V6 caller missing '+$name)};$text=Get-Content -LiteralPath $p -Raw;if($text -match $legacy){throw ('stale V5 caller '+$name)};if($text -notmatch 'FactoryProcessWaitV6'){throw ('V6 call missing '+$name)};$v6++;$rows+=[ordered]@{path=$p;waitType='FactoryProcessWaitV6'}}
$all=@(Get-ChildItem -LiteralPath $Root -Filter '*.ps1' -File -Recurse);foreach($p in $all){$text=Get-Content -LiteralPath $p.FullName -Raw;if($text -match $legacy){throw ('stale V5 process-wait type '+$p.FullName)}}
if($v6 -ne 1){throw 'expected admitted V6 capture caller'}
[ordered]@{kind='factory-circle-process-wait-v6-controls-v1';status='SOURCE_V6_WAIT_CONTROLS_PASS';callerCount=$v6;rows=$rows;nativeActions=0;compilerActions=0;lockActions=0}|ConvertTo-Json -Depth 8
