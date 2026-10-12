# Source-only controls for observer-source-r2. No process, scheduler, job, desktop, or lock actions.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SourcePath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Read-Bounded([string]$Path,[int64]$Limit=2097152){$item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;Require (-not $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0 -and $item.Length -le $Limit) 'bounded observer source required';return [IO.File]::ReadAllText($item.FullName)}
function Assert-Observer([string]$s,[string]$label){
  Require ($s.Contains('[Parameter(Mandatory)][string]$TransportHelperPath')) "$label helper path parameter missing"
  Require ($s.Contains('[Parameter(Mandatory)][string]$TransportHelperSha256')) "$label helper hash parameter missing"
  Require ($s.Contains('$failure=$null')) "$label failure state not initialized"
  Require ($s.Contains('$launcherReceiptPath=$null')) "$label launcher path state not initialized"
  Require ($s.Contains('Require ((Get-FileHash -LiteralPath $transportHelper.FullName')) "$label helper hash admission missing"
  Require ($s.Contains('Add-Type -Path $transportHelper.FullName')) "$label helper load missing"
  Require ($s.Contains('$job=[Sr0RootTransportJobV1]::CreateCurrentProcess()')) "$label inner job admission missing"
  Require ($s.Contains('[Sr0RootTransportJobV1]::RequireMemoryOnly($initial)')) "$label memory proof missing"
  Require ($s.Contains('public static class Sr0ObserverKernelR2')) "$label bounded console-session kernel type missing"
  Require ($s.Contains('[DllImport("kernel32.dll", EntryPoint="WTSGetActiveConsoleSessionId"')) "$label console-session API binding missing"
  Require ($s.Contains('[Sr0ObserverKernelR2]::ActiveConsoleSession()')) "$label console-session call missing"
  Require ($s.Contains('$initial=$job.Query()')) "$label initial memory query missing"
  Require ($s.Contains('transportInitialLimitBytes=if($initial)')) "$label initial memory limit receipt missing"
  Require ($s.Contains('transportInitialLimitFlags=if($initial)')) "$label initial memory flags receipt missing"
  Require ($s.Contains('transportFinalLimitBytes=if($final)')) "$label final memory limit receipt missing"
  Require ($s.Contains('$plan=Read-BoundedJson $planAbs')) "$label bounded plan read missing"
  Require ($s.Contains('[string]$plan.memoryLimitFlags -ceq ''0x200''')) "$label plan memory flags admission missing"
  Require ($s.Contains('[int]$plan.deadlineSeconds -eq 900')) "$label plan native deadline admission missing"
  Require ($s.Contains('[int]$plan.pollSeconds -eq 1')) "$label plan poll admission missing"
  Require ($s.Contains('[int]$plan.runs -eq 1')) "$label plan run-count admission missing"
  Require ($s.Contains('[string]$plan.wscriptPath')) "$label plan wscript binding missing"
  Require ($s.Contains('WscriptPath=[string]$plan.wscriptPath')) "$label schedule wscript binding missing"
  Require ($s.Contains('$outputParent=Split-Path -Parent $outputAbs')) "$label output parent admission missing"
  Require ($s.Contains('[IO.Directory]::CreateDirectory($outputParent)')) "$label output parent creation missing"
  Require ($s.Contains("observer receipt/stream files must be fresh")) "$label output freshness guard missing"
  Require ($s.IndexOf('[IO.Directory]::CreateDirectory($outputParent)',[StringComparison]::Ordinal) -lt $s.IndexOf('[Sr0RootTransportJobV1]::StartBoundedDrain',[StringComparison]::Ordinal)) "$label output parent created after drain start"
  Require ($s.IndexOf('Add-Type -Path $transportHelper.FullName',[StringComparison]::Ordinal) -lt $s.IndexOf('$plan=Read-BoundedJson $planAbs',[StringComparison]::Ordinal)) "$label plan read precedes helper admission"
  Require ($s.Contains('$scheduleSha -ceq ([string]$plan.scheduleSha256).ToLowerInvariant()')) "$label schedule path/hash admission missing"
  Require ($s.Contains('[Diagnostics.Stopwatch]::StartNew()')) "$label monotonic deadline missing"
  Require ($s.Contains('RedirectStandardOutput=$true')) "$label stdout redirection missing"
  Require ($s.Contains('RedirectStandardError=$true')) "$label stderr redirection missing"
  Require ($s.Contains('[Sr0RootTransportJobV1]::StartBoundedDrain')) "$label bounded stream drains missing"
  Require ($s.Contains('8388608')) "$label 8MiB stream cap missing"
  Require ($s.Contains('$scheduleHandle=$scheduleProcess.Handle')) "$label schedule original handle retention missing"
  Require ($s.Contains('$workerArgPattern=')) "$label worker argv file identity missing"
  Require ($s.Contains('$manifestArgPattern=')) "$label worker argv manifest identity missing"
  Require ($s.Contains('$workerFullArgPattern=')) "$label worker argv mode identity missing"
  Require ($s.Contains('$candidatePath.Equals($expectedWorkerExe')) "$label worker executable identity missing"
  Require ($s.Contains('$candidateStart -lt $scheduleInvokedAt.UtcDateTime')) "$label worker start identity missing"
  Require ($s.Contains('$candidateSession -ne [int]$activeConsole')) "$label worker session identity missing"
  Require ($s.Contains('$workerCommandLine=$cmd')) "$label worker command receipt missing"
  Require ($s.Contains('workerOriginalHandleAcquired=$workerHandleAcquired')) "$label worker handle receipt missing"
  Require ($s.Contains('workerExitIdentity=$workerExitIdentity')) "$label worker exit receipt missing"
  Require ($s.Contains('$overallWatch=[Diagnostics.Stopwatch]::StartNew()')) "$label overall deadline missing"
  Require ($s.Contains('Remaining-Milliseconds')) "$label shared deadline helper missing"
  Require ($s.Contains('overallWithinDeadline=$overallWithinDeadline')) "$label deadline receipt missing"
  Require ($s.Contains('if($workerProcess){try{$workerProcess.Dispose()}')) "$label worker process disposal missing"
  Require ($s -notmatch '\$workerWatch|\$workerWait|\$schedulerDeadline') "$label reset per-phase deadline present"
  Require ($s.Contains('$scheduleProcess.StandardOutput.Dispose()')) "$label stdout close missing"
  Require ($s.Contains('$scheduleProcess.StandardError.Dispose()')) "$label stderr close missing"
  $dispose=$s.IndexOf('$scheduleProcess.StandardOutput.Dispose()',[StringComparison]::Ordinal)
  $proof=$s.IndexOf('Get-StreamProof',$dispose,[StringComparison]::Ordinal)
  Require ($dispose -ge 0 -and $proof -gt $dispose) "$label stream proof precedes close"
  Require ($s.Contains('$scheduleStreamsSealed=$true')) "$label sealed stream receipt missing"
  Require ($s.Contains('scheduleStdoutCapExceeded=if($scheduleStdout)')) "$label stdout cap receipt missing"
  Require ($s.Contains('scheduleStderrCapExceeded=if($scheduleStderr)')) "$label stderr cap receipt missing"
  Require ($s.Contains('scheduleStdoutDrainError=if($scheduleStdout)')) "$label stdout drain error receipt missing"
  Require ($s.Contains('scheduleStderrDrainError=if($scheduleStderr)')) "$label stderr drain error receipt missing"
  Require ($s.Contains('scheduleExitIdentity=$scheduleExitIdentity')) "$label schedule exit join missing"
  Require ($s.Contains('transportFinalActive=if($final)')) "$label final active receipt missing"
  Require ($s.Contains('[Sr0RootTransportJobV1]::RequireMemoryOnly($final)')) "$label final memory proof missing"
  Require ($s.Contains('$scheduleExitIdentity -and $workerExitIdentity')) "$label final exit qualification missing"
  Require ($s.Contains('status=if($runStatus -eq ''passed''')) "$label held status gate missing"
  Require ($s.Contains('Write-AtomicFresh $outputAbs $receipt')) "$label atomic failure receipt missing"
  Require ($s -notmatch 'DateTime\]::UtcNow\.AddSeconds|DateTimeOffset\]::UtcNow\.AddSeconds') "$label wall-clock deadline used"
  Require ($s -notmatch 'ReadToEnd|ReadToEndAsync|Stop-Process|taskkill|Remove-Item|\[IO\.File\]::Delete') "$label unsafe/unbounded operation present"
}
$source=Read-Bounded $SourcePath
Assert-Observer $source 'baseline'
$mutations=@(
  @{name='schedule-hash';s=$source.Replace('$scheduleSha -ceq ([string]$plan.scheduleSha256).ToLowerInvariant()','$true')},
  @{name='inner-admission';s=$source.Replace('$job=[Sr0RootTransportJobV1]::CreateCurrentProcess()','$job=$null')},
  @{name='monotonic';s=$source.Replace('[Diagnostics.Stopwatch]::StartNew()','[DateTimeOffset]::UtcNow')},
  @{name='argv-path';s=$source.Replace('if(-not $candidatePath.Equals($expectedWorkerExe,[StringComparison]::OrdinalIgnoreCase)','if($false)')},
  @{name='session';s=$source.Replace('$candidateSession -ne [int]$activeConsole','$false')},
  @{name='stream-close';s=$source.Replace('$scheduleProcess.StandardOutput.Dispose()','$null')},
  @{name='held-receipt';s=$source.Replace("status=if(`$runStatus -eq 'passed'", "status='passed';if(`$runStatus -eq 'passed'")},
  @{name='console-api';s=$source.Replace('[Sr0ObserverKernelR2]::ActiveConsoleSession()','$null')},
  @{name='overall-receipt';s=$source.Replace('overallWithinDeadline=$overallWithinDeadline','overallWithinDeadline=$true')},
  @{name='worker-dispose';s=$source.Replace('if($workerProcess){try{$workerProcess.Dispose()}','if($workerProcess){$null')}
)
foreach($m in $mutations){Require ($m.s -cne $source) "observer mutation was a no-op: $($m.name)";$rejected=$false;try{Assert-Observer $m.s "mutation/$($m.name)"}catch{$rejected=$true};Require $rejected "observer control mutation escaped: $($m.name)"}
$out=[ordered]@{kind='sr0-display-observer-v4-source-controls-r2';status='passed-source-controls';sourcePath=[IO.Path]::GetFullPath($SourcePath);sourceBytes=$source.Length;nativeActions=0;processActions=0;schedulerActions=0;mutationsRejected=$mutations.Count;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$out|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8;$out|ConvertTo-Json -Depth 8
