# Source-only observer controls. No scheduler, process, job, desktop, or lock actions.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SourcePath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
function Read-Bounded([string]$Path,[int64]$Limit=2097152){$item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $item.Length -gt $Limit){throw "bounded observer source rejected: $Path"};return [IO.File]::ReadAllText($item.FullName)}
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$source=Read-Bounded $SourcePath
function Assert-Observer([string]$s,[string]$label){
  Require ($s -match '\$scheduleParams\s*=\s*@\{') "$label missing named schedule parameter table"
  Require ($s -match '&\s*\$schedule\s*@scheduleParams') "$label missing hashtable splat invocation"
  Require ($s -match '\$scheduleInvokedAt=\[DateTimeOffset\]::UtcNow;&\s*\$schedule\s*@scheduleParams') "$label timestamps schedule invocation"
  Require ($s -match 'Get-CimInstance\s+Win32_Process\s+-Filter') "$label missing bounded worker discovery"
  Require ($s -match '(?i)-File\s') "$label missing worker file argument identity"
  Require ($s -match '(?i)-ManifestPath\s') "$label missing manifest argument identity"
  Require ($s -match '\$candidateHandle=\$candidate\.Handle') "$label missing immediate worker handle retention"
  Require ($s -match '\$candidateStart\s*-lt\s*\$scheduleInvokedAt\.UtcDateTime') "$label missing worker start lower bound"
  Require ($s -match 'ActiveConsoleSession') "$label missing active console session check"
  Require ($s -match 'WaitForSingleObject') "$label missing kernel wait binding"
  Require ($s -match 'GetExitCodeProcess') "$label missing kernel exit binding"
  Require ($s -match 'SignedDword') "$label missing raw signed exit conversion"
  Require ($s -match '\$kernelSigned\s*-ne\s*\$dotnetExit') "$label missing kernel/.NET exit join"
  Require ($s -match 'aggregateDescendantsQuiesced') "$label missing aggregate quiescence receipt"
  Require ($s -match 'aggregateActiveAfter\s*-eq\s*1') "$label missing self-only aggregate proof"
  Require ($s -match '\$schedulerState\s*-eq\s*''Running''\s*-or\s*\$schedulerState\s*-eq\s*''Queued''') "$label missing scheduler queued grace"
  Require ($s -match 'Write-AtomicFresh') "$label missing fresh atomic receipt"
  Require ($s -notmatch 'Stop-Process|taskkill|TerminateJobObject|Remove-Item|\[IO\.File\]::Delete') "$label contains unsafe unrelated-process cleanup"
}
Assert-Observer $source 'baseline'
$mutations=@(
  @{name='array-splat';s=$source.Replace('$scheduleParams=@{','$scheduleArgs=@(')},
  @{name='unnamed-invocation';s=$source.Replace('& $schedule @scheduleParams','& $schedule @scheduleArgs')},
  @{name='start-bound';s=$source.Replace('$candidateStart -lt $scheduleInvokedAt.UtcDateTime','$false')},
  @{name='original-handle';s=$source.Replace('$candidateHandle=$candidate.Handle','$candidateHandle=[IntPtr]::Zero')},
  @{name='exit-join';s=$source.Replace('$kernelSigned -ne $dotnetExit','$kernelSigned -eq $dotnetExit')},
  @{name='queued-grace';s=$source.Replace('$schedulerState -eq ''Running'' -or $schedulerState -eq ''Queued''','$schedulerState -eq ''Running''')}
)
foreach($m in $mutations){if($m.s -ceq $source){throw "observer mutation was a no-op: $($m.name)"};$rejected=$false;try{Assert-Observer $m.s "mutation/$($m.name)"}catch{$rejected=$true};if(-not $rejected){throw "observer control mutation escaped: $($m.name)"}}
$out=[ordered]@{kind='sr0-display-observer-v4-controls';status='passed';nativeActions=0;processActions=0;schedulerActions=0;mutationsRejected=$mutations.Count;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$out|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8;$out|ConvertTo-Json -Depth 8
