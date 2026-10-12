# Source controls for strict-input-repair-v1; no process/native/compiler execution.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$MaterializerPath,
  [Parameter(Mandatory)][string]$AnalyzerPath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function ReadBounded([string]$Path){
  $i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  Require (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0) 'source reparse rejected'
  Require ($i.Length -le 2097152) 'source exceeds 2MiB'
  return [IO.File]::ReadAllText($i.FullName)
}
$materializer=ReadBounded $MaterializerPath;$analyzer=ReadBounded $AnalyzerPath
$materializerNeed=@(
  'RawRoot','BuildPath','IncrementalPath','OutputRoot','OutputPath',
  'MaxResultBytes=2097152','MaxStreamBytes=8388608','MaxCsvBytes=67108864',
  'MaxTraceBytes=33554432','MaxTotalBytes=134217728',
  'presentmon.console.txt','configuration=''release''','adapterDerived=$true',
  'rawPreserved=$true','qualificationHeld=$true','optionalHandleTailPreserved=$true',
  'pid_exit run=\S+ pid=\d+ handle=[1-9]\d+','Incremental/source manifest mismatch',
  'output root must be fresh','derived output exists'
)
foreach($n in $materializerNeed){Require $materializer.Contains($n) "materializer guard missing: $n"}
$analyzerNeed=@(
  'pid_exit run=(\S+) pid=(\d+)(?: handle=[1-9]\d*)? qpc_end=(\d+) exit=(-?\d+)',
  'presentmon.console.txt','incremental_check','build.json',
  'global_invalid.append'
)
foreach($n in $analyzerNeed){Require $analyzer.Contains($n) "analyzer guard missing: $n"}
$mutations=[ordered]@{
  'unbounded-result'=@{source=$materializer;needle='MaxResultBytes=2097152';replacement='MaxResultBytes=9223372036854775807'}
  'raw-overwrite'=@{source=$materializer;needle='rawPreserved=$true';replacement='rawPreserved=$false'}
  'release-identity'=@{source=$materializer;needle="configuration=''release''";replacement="configuration=''debug''"}
  'handle-tail'=@{source=$analyzer;needle='(?: handle=[1-9]\d*)?';replacement='(?: handle=[1-9]\d*)'}
}
$cases=[ordered]@{}
foreach($k in $mutations.Keys){$m=$mutations[$k];Require $m.source.Contains($m.needle) "mutation needle missing: $k";$changed=$m.source.Replace($m.needle,$m.replacement);Require ($changed -ne $m.source) "mutation had no effect: $k";$cases[$k]=[ordered]@{status='expected-rejected';changed=$true}}
$full=[IO.Path]::GetFullPath($OutputPath);$parent=Split-Path -Parent $full;if(-not(Test-Path -LiteralPath $parent -PathType Container)){[IO.Directory]::CreateDirectory($parent)|Out-Null};Require (-not(Test-Path -LiteralPath $full)) 'controls output must be fresh'
$receipt=[ordered]@{kind='sr0-display-strict-input-repair-v1-controls';status='passed';materializerPath=[IO.Path]::GetFullPath($MaterializerPath);analyzerPath=[IO.Path]::GetFullPath($AnalyzerPath);cases=$cases;nativeActions=0;compilerActions=0;qualificationClaimed=$false;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
[IO.File]::WriteAllText($full,($receipt|ConvertTo-Json -Depth 10)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)));exit 0

