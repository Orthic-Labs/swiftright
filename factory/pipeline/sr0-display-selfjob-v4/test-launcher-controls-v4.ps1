# Bounded launcher source controls. No process, task, job, or lock actions.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$WorkerPath,
  [Parameter(Mandatory)][string]$SchedulePath,
  [Parameter(Mandatory)][string]$HelperPath,
  [Parameter(Mandatory)][string]$LauncherHelperPath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
function Read-Bounded([string]$Path,[int64]$Limit=2097152){$item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $item.Length -gt $Limit){throw "bounded launcher source rejected: $Path"};return [IO.File]::ReadAllText($item.FullName)}
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$worker=Read-Bounded $WorkerPath;$schedule=Read-Bounded $SchedulePath;$helper=Read-Bounded $HelperPath;$launcherHelper=Read-Bounded $LauncherHelperPath
function Assert-Launcher([string]$w,[string]$s,[string]$h,[string]$lh,[string]$label){
  Require ($w -match 'CreateCurrentProcess\(\[int64\]\$manifest\.aggregateJobMemoryLimitBytes\)') "$label missing outer job creation"
  Require ($w -match 'Add-Type -Path \(\[string\]\$manifest\.launcherHelperPath\)') "$label missing launcher helper load"
  Require ($w -match '\$outer\.TerminateOwnedChildren\(1,30000\)') "$label missing owned descendant termination"
  Require ($w -match '\$manifest\.aggregateJobMemoryLimitBytes\s*-eq\s*1073741824') "$label missing exact outer 1GiB preflight"
  Require ($w -match '\$outerFinal\s*=\$outer\.WaitForOnlyCurrent\(30000\)') "$label missing bounded descendant wait"
  Require ($w -match 'aggregateDescendantsQuiesced=\(\$null -ne \$outerFinal -and \$null -ne \$outerActiveAfter -and \$outerActiveAfter -eq 1\)') "$label missing truthful quiescence receipt"
  Require ($w -match '\$coordinatorHandle=\$coordinator\.Handle') "$label missing coordinator handle retention"
  Require ($w -match '\$collectorHandle=\$collector\.Handle') "$label missing collector handle retention"
  Require ($w -match '\$h=\$process\.Handle') "$label missing immediate owned-child handle acquisition"
  Require ($w -match 'WaitForExit\(15000\)') "$label missing bounded child wait"
  Require ($w -match 'GetExitCodeProcess') "$label missing kernel exit proof"
  Require ($w -match 'Write-AtomicFresh') "$label missing atomic launcher receipt"
  Require ($s -match 'if\(\[string\]::IsNullOrWhiteSpace\(\$Tag\)\)\{\$Tag=\$TaskName\}') "$label missing Tag default binding"
  Require ($s -match '\$Tag\s*-cne\s*\$TaskName') "$label missing TaskName/Tag equality gate"
  Require ($s -match 'aggregateJobMemoryLimitBytes=1073741824') "$label missing exact manifest budget"
  Require ($h -match 'budgetBytes\s*!=\s*1073741824UL') "$label missing helper exact 1GiB guard"
  Require ($h -match 'JobMemoryOnlyFlags\s*=\s*0x200') "$label missing memory-only flag guard"
  Require ($h -notmatch '0x2000|KillOnJobClose') "$label enables kill-on-close"
  Require ($lh -match 'class Sr0LauncherOwnedJobProcessV4') "$label missing launcher helper class"
  Require ($lh -match 'public CleanupSnapshot TerminateOwnedChildren\(') "$label missing owned cleanup API"
  Require ($lh -match 'GetCurrentProcessId') "$label missing self exclusion identity"
  Require ($lh -match 'pid == self') "$label missing current-process exclusion"
  Require ($lh -match 'IsProcessInJob') "$label missing handle membership revalidation"
  Require ($lh -match 'QueryOwnedProcessIds\(\)') "$label missing repeated owned PID query"
  Require ($lh -match 'Stopwatch\.StartNew\(\)') "$label missing rollover-safe cleanup deadline"
  Require ($lh -match 'listed > \(uint\)max') "$label missing process-list truncation guard"
  Require ($lh -match 'HashSet<uint>') "$label missing process-list identity uniqueness guard"
  Require ($lh -notmatch 'TerminateJobObject') "$label may terminate launcher itself"
}
Assert-Launcher $worker $schedule $helper $launcherHelper 'baseline'
$mutations=@(
  @{name='outer-budget';w=$worker.Replace('$manifest.aggregateJobMemoryLimitBytes -eq 1073741824','$manifest.aggregateJobMemoryLimitBytes -eq 536870912')},
  @{name='outer-wait';w=$worker.Replace('$outer.WaitForOnlyCurrent(30000)','$outer.QueryPeakJobMemory()')},
  @{name='coordinator-handle';w=$worker.Replace('$coordinatorHandle=$coordinator.Handle','$coordinatorHandle=[IntPtr]::Zero')},
  @{name='quiescence';w=$worker.Replace('$outerActiveAfter -eq 1','$outerActiveAfter -eq 0')},
  @{name='tag-binding';s=$schedule.Replace('$Tag -cne $TaskName','$Tag -eq $TaskName')},
  @{name='helper-budget';h=$helper.Replace('budgetBytes != 1073741824UL','budgetBytes != 536870912UL')},
  @{name='cleanup-api';lh=$launcherHelper.Replace('TerminateOwnedChildren','TerminateOwnedChildrenRemoved')}
)
foreach($m in $mutations){$mw=$worker;$ms=$schedule;$mh=$helper;$mlh=$launcherHelper;if($null -ne $m.w){$mw=$m.w;if($mw -ceq $worker){throw "launcher mutation was a no-op: $($m.name)"}};if($null -ne $m.s){$ms=$m.s;if($ms -ceq $schedule){throw "launcher mutation was a no-op: $($m.name)"}};if($null -ne $m.h){$mh=$m.h;if($mh -ceq $helper){throw "launcher mutation was a no-op: $($m.name)"}};if($null -ne $m.lh){$mlh=$m.lh;if($mlh -ceq $launcherHelper){throw "launcher mutation was a no-op: $($m.name)"}};$rejected=$false;try{Assert-Launcher $mw $ms $mh $mlh "mutation/$($m.name)"}catch{$rejected=$true};if(-not $rejected){throw "launcher control mutation escaped: $($m.name)"}}
$out=[ordered]@{kind='sr0-display-launcher-v4-controls';status='passed';nativeActions=0;taskActions=0;jobActions=0;mutationsRejected=$mutations.Count;outerBudgetBytes=1073741824;childWaitMilliseconds=30000;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$out|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8;$out|ConvertTo-Json -Depth 8
