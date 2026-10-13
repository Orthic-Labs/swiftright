param(
 [Parameter(Mandatory=$true)][string]$HostReceipt,
 [Parameter(Mandatory=$true)][string]$WorkerReceipt,
 [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$MaxBytes=262144;$MaxPhases=32
function Read-BoundedJson([string]$Path){
 if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw "Receipt missing: $Path"}
 $item=Get-Item -LiteralPath $Path -Force
 if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "Receipt reparse point: $Path"}
 if($item.Length -gt $MaxBytes){throw "Receipt exceeds $MaxBytes bytes: $Path"}
 $raw=[IO.File]::ReadAllText($item.FullName,[Text.Encoding]::UTF8)
 if([string]::IsNullOrWhiteSpace($raw)){throw "Receipt empty: $Path"}
 return ($raw|ConvertFrom-Json)
}
function Need([object]$Value,[string]$Name){if($null -eq $Value){throw "Missing $Name"};return $Value}
function Hex64([object]$Value,[string]$Name){$s=[string](Need $Value $Name);if($s -cnotmatch '^[0-9a-fA-F]{64}$'){throw "Invalid $Name"};return $s.ToLowerInvariant()}
function Utc([object]$Value,[string]$Name){$dt=[DateTimeOffset]::MinValue;if(-not [DateTimeOffset]::TryParse([string](Need $Value $Name),[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$dt)){throw "Invalid $Name"};return $dt}
function PosInt([object]$Value,[string]$Name){$n=[int64](Need $Value $Name);if($n -lt 0){throw "Invalid $Name"};return $n}
function Phases([object]$Receipt,[string]$Name,[string[]]$Expected){
 $rows=@($Receipt.phases);if($rows.Count -eq 0 -or $rows.Count -gt $MaxPhases){throw "$Name phase count invalid"}
 $last=-1L;$lastQ=-1L;$seen=@{};$names=@()
 foreach($p in $rows){
  $n=[string](Need $p.phase "$Name phase.name");if($seen.ContainsKey($n)){throw "$Name duplicate phase $n"};$seen[$n]=$true
  $mono=PosInt $p.monoMs "$Name $n monoMs";$qpc=PosInt $p.qpc "$Name $n qpc";Utc $p.utc "$Name $n utc"
  if($mono -lt $last -or $qpc -lt $lastQ){throw "$Name clock regression at $n"};$last=$mono;$lastQ=$qpc;$names+=$n
 }
 $complete=($names.Count -eq $Expected.Count)
 for($i=0;$i -lt $names.Count;$i++){if($i -ge $Expected.Count -or $names[$i] -cne $Expected[$i]){throw "$Name phase order mismatch at $i"}}
 return [pscustomobject]@{Names=$names;Complete=$complete;LastMono=$last;LastQpc=$lastQ}
}
function Join-PhaseEvidence([object]$Host,[object]$Worker){
 if([string](Need $Host.kind 'host.kind') -cne 'factory-stack-host-phase-receipt-v2'){throw 'Host kind mismatch'}
 if([string](Need $Worker.kind 'worker.kind') -notin @('factory-uia-snapshot-worker-observation-v1','factory-stack-uia-phase-receipt-v2')){throw 'Worker kind mismatch'}
 $run=[string](Need $Host.runId 'host.runId');if($run -cne [string](Need $Worker.runId 'worker.runId')){throw 'runId mismatch'}
 $hp=Need $Host.host 'host.host';$wp=Need $Worker.worker 'worker.worker'
 $pid=[int64](Need $hp.pid 'host.pid');if($pid -le 0 -or [int64](Need $wp.parentPid 'worker.parentPid') -ne $pid){throw 'parent PID mismatch'}
 $start=(Utc $hp.startedUtc 'host.startedUtc').ToUniversalTime();$wstart=(Utc $wp.parentStartedUtc 'worker.parentStartedUtc').ToUniversalTime();if($start -ne $wstart){throw 'parent start mismatch'}
 $path=[IO.Path]::GetFullPath([string](Need $hp.path 'host.path'));if(-not [IO.File]::Exists($path)){throw 'host path missing'}
 $hashes=[ordered]@{};foreach($k in @('sourceHash','rendererHash','bridgeHash','runtimeHash')){$hashes[$k]=Hex64 $hp.$k "host.$k"}
 if([int64](Need $wp.sessionId 'worker.sessionId') -ne [int64](Need $hp.sessionId 'host.sessionId')){throw 'session mismatch'}
 return [pscustomobject]@{runId=$run;pid=$pid;hostPath=$path;startedUtc=$start;sessionId=[int64]$hp.sessionId;hashes=$hashes}
}
function Classify([object]$H,[object]$W,[object]$HJ,[object]$WJ){
 if(-not $HJ.Complete){if($HJ.Names -notcontains 'after-bridge-load'){return 'loader-or-abi'};if($HJ.Names -notcontains 'loop-ready'){return 'gpui-before-window'};return 'window-callback-publication'}
 if(-not $WJ.Complete){if($WJ.Names -notcontains 'after-from-handle'){return 'uia-window-exposure'};return 'uia-content'}
 return 'uia-content'
}
$result=[ordered]@{kind='factory-stack-lifecycle-join-v2';status='rejected';classification='evidence-incomplete';hostReceipt=[IO.Path]::GetFullPath($HostReceipt);workerReceipt=[IO.Path]::GetFullPath($WorkerReceipt);errors=@();runId='';hostPid=0;hostPhaseCount=0;workerPhaseCount=0;sourceHashes=@()}
try{
 $h=Read-BoundedJson $HostReceipt;$w=Read-BoundedJson $WorkerReceipt
 $hj=Phases $h 'host' @('before-bridge-load','after-bridge-load','hook-installed','before-bridge-run','dpi-configured','loop-ready','on-ready','first-window-metrics','window-closed','after-bridge-run')
 $wj=Phases $w 'worker' @('config-accepted','source-pins-verified','before-ui-automation-assembly','after-ui-automation-assembly','before-from-handle','after-from-handle','before-read-uia','after-read-uia','before-scalar-validation','after-scalar-validation','before-uia-publication','after-uia-publication')
 $join=Join-PhaseEvidence $h $w;$result.runId=$join.runId;$result.hostPid=$join.pid;$result.hostPhaseCount=$hj.Names.Count;$result.workerPhaseCount=$wj.Names.Count;$result.sourceHashes=$join.hashes
 $result.classification=Classify $h $w $hj $wj;$result.status='observed';$result.hostComplete=$hj.Complete;$result.workerComplete=$wj.Complete;$result.join=[ordered]@{hostLastMonoMs=$hj.LastMono;workerLastMonoMs=$wj.LastMono;hostLastQpc=$hj.LastQpc;workerLastQpc=$wj.LastQpc}
}catch{$result.errors=@([string]$_);$result.status='rejected';$result.classification='evidence-incomplete'}
$parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($OutputPath));if(-not (Test-Path -LiteralPath $parent -PathType Container)){throw "Output directory missing: $parent"}
$tmp="$OutputPath.tmp-$PID";$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $OutputPath -Force
if($result.status -eq 'rejected'){exit 2}
