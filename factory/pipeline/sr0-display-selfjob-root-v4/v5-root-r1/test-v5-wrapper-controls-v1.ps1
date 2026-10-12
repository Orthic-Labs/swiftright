# Source controls for v5 worker/scheduler compatibility. Root executes on Windows; no child is launched here.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$WorkerPath,
  [Parameter(Mandatory)][string]$SchedulePath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Read-Bounded([string]$Path){$i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;Require (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0) "reparse source: $Path";Require ($i.Length -le 2097152) "source exceeds bound: $Path";return [IO.File]::ReadAllText($i.FullName)}
$worker=Read-Bounded $WorkerPath;$schedule=Read-Bounded $SchedulePath
foreach($pair in @(@($worker,'sr0-display-selfjob-v5-one-shot'),@($worker,"finalReceipt.kind -eq 'sr0-display-collector-v5'"),@($worker,'captureComplete'),@($worker,'qualificationHeld'),@($worker,"status -eq 'qualification-held'"),@($worker,"coordReceipt.kind -eq 'sr0-display-coordinator-v5'"),@($worker,'parentCertificatePresent'),@($schedule,'schema=''sr0-display-selfjob-v5-one-shot''')){Require ($pair[0].Contains([string]$pair[1])) "v5 wrapper guard missing: $($pair[1])"}
$cases=[ordered]@{}
$mutations=[ordered]@{
  'collector-kind'=@{source=$worker;needle="finalReceipt.kind -eq 'sr0-display-collector-v5'";replacement="finalReceipt.kind -eq 'sr0-display-collector-v4'"}
  'hold-status'=@{source=$worker;needle="status -eq 'qualification-held'";replacement="status -eq 'completed'"}
  'capture-proof'=@{source=$worker;needle='captureComplete';replacement='captureCompleteRemoved'}
  'coordinator-kind'=@{source=$worker;needle="coordReceipt.kind -eq 'sr0-display-coordinator-v5'";replacement="coordReceipt.kind -eq 'sr0-display-coordinator-v4'"}
  'manifest-schema'=@{source=$schedule;needle="schema='sr0-display-selfjob-v5-one-shot'";replacement="schema='sr0-display-selfjob-v4-one-shot'"}
}
foreach($name in $mutations.Keys){$m=$mutations[$name];Require ($m.source.Contains($m.needle)) "v5 mutation needle missing: $name";$changed=$m.source.Replace($m.needle,$m.replacement);Require ($changed -ne $m.source) "v5 mutation no effect: $name";$cases[$name]=[ordered]@{status='expected-rejected';changed=$true}}
$receipt=[ordered]@{kind='sr0-display-selfjob-v5-wrapper-controls';status='passed';workerPath=[IO.Path]::GetFullPath($WorkerPath);schedulePath=[IO.Path]::GetFullPath($SchedulePath);cases=$cases;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
$full=[IO.Path]::GetFullPath($OutputPath);$parent=Split-Path -Parent $full;if(-not(Test-Path -LiteralPath $parent -PathType Container)){[IO.Directory]::CreateDirectory($parent)|Out-Null};if(Test-Path -LiteralPath $full){throw 'controls output must be fresh'};[IO.File]::WriteAllText($full,($receipt|ConvertTo-Json -Depth 8)+"`r`n",(New-Object Text.UTF8Encoding($false)));exit 0
