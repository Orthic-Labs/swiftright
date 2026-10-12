# Real Windows job lifecycle controls. Root runs this on Windows; source lane never invokes it.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$LauncherHelperPath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
function Read-Bounded([string]$Path,[int64]$Limit=2097152){$item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $item.Length -gt $Limit){throw "bounded helper rejection: $Path"};return $item}
$item=Read-Bounded $LauncherHelperPath;Add-Type -Path $item.FullName
$ps=Join-Path $PSHOME 'powershell.exe';$foreign=$null;$owned=$null;$job=$null;$failure=$null;$cleanup=$null
try {
  $foreign=[Diagnostics.Process]::Start((New-Object Diagnostics.ProcessStartInfo -Property @{FileName=$ps;Arguments='-NoProfile -ExecutionPolicy Bypass -Command "Start-Sleep -Seconds 30"';UseShellExecute=$false;CreateNoWindow=$true}))
  if($null -eq $foreign){throw 'foreign fixture did not start'};$foreignHandle=$foreign.Handle
  $job=[Sr0LauncherOwnedJobProcessV4]::CreateCurrentProcess(1073741824)
  if($job.IsOwnedHandle($foreignHandle)){throw 'foreign process incorrectly admitted to launcher job'}
  $owned=[Diagnostics.Process]::Start((New-Object Diagnostics.ProcessStartInfo -Property @{FileName=$ps;Arguments='-NoProfile -ExecutionPolicy Bypass -Command "Start-Sleep -Seconds 120"';UseShellExecute=$false;CreateNoWindow=$true}))
  if($null -eq $owned){throw 'owned fixture did not start'}
  $initial=$job.QueryPeakJobMemory();if($initial.ActiveProcessCount -ne 2){throw "owned fixture active count mismatch: $($initial.ActiveProcessCount)"}
  $cleanup=$job.TerminateOwnedChildren(137,5000);if(-not $cleanup.Attempted -or $cleanup.TerminatedCount -lt 1){throw 'owned timeout cleanup did not terminate child'}
  $final=$job.WaitForOnlyCurrent(5000);[Sr0LauncherOwnedJobProcessV4]::RequireOnlyCurrent($final)
  $owned.Refresh();if(-not $owned.HasExited){throw 'owned fixture remained alive after cleanup'}
  $foreign.Refresh();if($foreign.HasExited){throw 'foreign fixture was terminated by owned cleanup'}
  $out=[ordered]@{kind='sr0-display-launcher-job-controls-v4';status='passed';foreignMember=$false;ownedActiveBefore=$initial.ActiveProcessCount;cleanupAttempted=$cleanup.Attempted;cleanupTerminated=$cleanup.TerminatedCount;cleanupForeignSkipped=$cleanup.ForeignSkippedCount;cleanupAfter=$cleanup.AfterCount;cleanupSelfOnly=$cleanup.SelfOnly;outerActiveAfter=$final.ActiveProcessCount;nativeActions=2;foreignTermination=0}
} catch { $failure=$_.Exception.Message;$out=[ordered]@{kind='sr0-display-launcher-job-controls-v4';status='held';failure=$failure;cleanupAttempted=if($cleanup){$cleanup.Attempted}else{$false};cleanupTerminated=if($cleanup){$cleanup.TerminatedCount}else{$null}} }
finally {
  if($owned){try{if(-not $owned.HasExited){$owned.Kill()};[void]$owned.WaitForExit(5000)}catch{}}
  if($foreign){try{if(-not $foreign.HasExited){$foreign.Kill()};[void]$foreign.WaitForExit(5000)}catch{}}
  if($job){try{$job.Dispose()}catch{}}
}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$out|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $OutputPath -Encoding UTF8;if($out.status -ne 'passed'){throw $out.failure};$out|ConvertTo-Json -Depth 8
