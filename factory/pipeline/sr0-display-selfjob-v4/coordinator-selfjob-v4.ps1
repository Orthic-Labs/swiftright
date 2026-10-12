# Bounded receipt coordinator. It polls explicit collector receipts, preserves lock on missing proof, & writes one atomic verdict.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$StartReceiptPath,
  [Parameter(Mandatory)][string]$FinalReceiptPath,
  [Parameter(Mandatory)][string]$OutputPath,
  [Parameter(Mandatory)][string]$LockPath,
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$TaskName,
  [ValidateRange(1,900)][int]$MaxWaitSeconds=900,
  [ValidateRange(1,30)][int]$PollSeconds=1
)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Sr0DisplayCoordinatorKernelV4 {
  [DllImport("kernel32.dll",EntryPoint="WaitForSingleObject",SetLastError=true)] static extern uint WaitForSingleObject(IntPtr h,uint ms);
  [DllImport("kernel32.dll",EntryPoint="GetExitCodeProcess",SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr h,out uint code);
  public static bool Terminal(IntPtr h,out uint code){code=259;if(h==IntPtr.Zero)return false;if(WaitForSingleObject(h,0)!=0)return false;if(!GetExitCodeProcess(h,out code))return false;return code!=259;}
  public static long SignedDword(uint code){return unchecked((int)code);}
}
'@
function Read-BoundedJson([string]$Path,[int64]$Limit=2097152){
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
  $item=Get-Item -LiteralPath $Path -Force
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $item.Length -gt $Limit){throw "bounded receipt rejected: $Path"}
  return ([IO.File]::ReadAllText($item.FullName)|ConvertFrom-Json)
}
function Require([bool]$Condition,[string]$Reason,[System.Collections.Generic.List[string]]$Errors){if(-not $Condition){[void]$Errors.Add($Reason)}}
function Write-AtomicJson([string]$Path,[object]$Object){
  $full=[IO.Path]::GetFullPath($Path);$parent=Split-Path -Parent $full;if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
  if(Test-Path -LiteralPath $full){throw "coordinator output must be fresh: $full"}
  $tmp="$full.$PID.tmp";[IO.File]::WriteAllText($tmp,(ConvertTo-Json $Object -Depth 16)+"`r`n",(New-Object Text.UTF8Encoding($false)));[IO.File]::Move($tmp,$full)
}
$startFull=[IO.Path]::GetFullPath($StartReceiptPath);$finalFull=[IO.Path]::GetFullPath($FinalReceiptPath);$lockFull=[IO.Path]::GetFullPath($LockPath);$outputFull=[IO.Path]::GetFullPath($OutputPath)
$errors=New-Object 'System.Collections.Generic.List[string]';$start=$null;$final=$null;$parentProcess=$null;$parentHandle=[IntPtr]::Zero;[uint32]$parentExitRaw=259;$parentExitSigned=$null;$parentExitDotnet=$null;$parentKernelTerminal=$false;$deadline=[DateTime]::UtcNow.AddSeconds($MaxWaitSeconds)
while($null -eq $start -and [DateTime]::UtcNow -lt $deadline){$start=Read-BoundedJson $startFull;if($null -eq $start){Start-Sleep -Seconds $PollSeconds}}
if($null -eq $start){[void]$errors.Add('parent-certificate-missing:start-receipt-timeout')}
else{
  Require ([string]$start.kind -eq 'sr0-display-collector-v4-start') 'start-kind' $errors
  Require ([string]$start.status -eq 'admitted') 'start-not-admitted' $errors
  Require ([string]$start.taskName -eq $TaskName) 'start-task-mismatch' $errors
  Require ([bool]$start.sessionMatch) 'start-session-mismatch' $errors
  Require ([bool]$start.parentHandleRetained) 'parent-handle-not-retained' $errors
  Require (-not [string]::IsNullOrWhiteSpace([string]$start.parentPath)) 'parent-path-missing' $errors
  Require (-not [string]::IsNullOrWhiteSpace([string]$start.parentStartTimeUtc)) 'parent-start-time-missing' $errors
  Require ([int64]$start.jobMemoryLimitBytes -eq 1073741824) 'start-job-memory-limit' $errors
  Require ([int64]$start.activeProcessCount -eq 1) 'start-active-count' $errors
  Require ([bool]$start.noActivate) 'start-noactivate-missing' $errors
  try{
    $parentProcess=[Diagnostics.Process]::GetProcessById([int]$start.parentPid)
    $observedPath=$parentProcess.MainModule.FileName;$observedStart=$parentProcess.StartTime.ToUniversalTime().ToString('o');$observedSession=$parentProcess.SessionId;$parentHandle=$parentProcess.Handle
    Require ($observedPath -ceq [string]$start.parentPath) 'parent-live-path-mismatch' $errors
    Require ($observedStart -ceq [string]$start.parentStartTimeUtc) 'parent-live-start-mismatch' $errors
    Require ([int64]$observedSession -eq [int64]$start.currentSession) 'parent-live-session-mismatch' $errors
    Require ($parentHandle -ne [IntPtr]::Zero) 'parent-kernel-handle-missing' $errors
  }catch{[void]$errors.Add("parent-certificate-invalid:$($_.Exception.Message)")}
}
while($null -eq $final -and [DateTime]::UtcNow -lt $deadline){$final=Read-BoundedJson $finalFull;if($null -eq $final){Start-Sleep -Seconds $PollSeconds}}
if($null -eq $final){[void]$errors.Add('parent-certificate-missing:final-receipt-timeout')}
else{
  Require ([string]$final.kind -eq 'sr0-display-collector-v4') 'final-kind' $errors
  Require ([string]$final.taskName -eq $TaskName) 'final-task-mismatch' $errors
  if($start){
    Require ([int64]$final.parentPid -eq [int64]$start.parentPid) 'parent-pid-drift' $errors
    Require ([string]$final.parentPath -ceq [string]$start.parentPath) 'parent-path-drift' $errors
    Require ([string]$final.parentStartTimeUtc -ceq [string]$start.parentStartTimeUtc) 'parent-start-drift' $errors
    Require ([int64]$final.currentSession -eq [int64]$start.currentSession) 'parent-session-drift' $errors
    Require ([int64]$final.parentOriginalHandle -eq [int64]$start.parentHandle) 'parent-handle-drift' $errors
  }
  Require ([bool]$final.parentOriginalHandleRetained) 'final-parent-handle-not-retained' $errors
  Require ([bool]$final.presentMonStarted) 'presentmon-start-proof' $errors
  Require ([bool]$final.presentMonTerminal) 'presentmon-terminal-proof' $errors
  Require ([bool]$final.presentMonExitIdentity) 'presentmon-exit-identity' $errors
  Require ([bool]$final.presentMonSessionAbsent) 'presentmon-session-absence' $errors
  Require ([bool]$final.workloadTerminal) 'workload-terminal-proof' $errors
  Require ([bool]$final.workloadExitIdentity) 'workload-exit-identity' $errors
  Require ([bool]$final.activeReadableAfter -and [int64]$final.activeAfter -eq 1 -and [bool]$final.activeSelfOnly) 'active-self-final-proof' $errors
  Require ($final.workloadProof -and [bool]$final.workloadProof.ownershipTerminal) 'workload-ownership-proof' $errors
  Require ([bool]$final.lockReleased) 'lock-release-proof' $errors
}
$parentWaitDeadline=[DateTime]::UtcNow.AddSeconds($MaxWaitSeconds)
if($parentProcess){while(-not $parentKernelTerminal -and [DateTime]::UtcNow -lt $parentWaitDeadline){$parentKernelTerminal=[Sr0DisplayCoordinatorKernelV4]::Terminal($parentHandle,[ref]$parentExitRaw);if(-not $parentKernelTerminal){Start-Sleep -Seconds $PollSeconds}};if($parentKernelTerminal){$parentProcess.Refresh();$parentExitDotnet=[int64]$parentProcess.ExitCode;$parentExitSigned=[Sr0DisplayCoordinatorKernelV4]::SignedDword($parentExitRaw);Require ($parentExitSigned -eq $parentExitDotnet) 'parent-exit-identity' $errors}else{[void]$errors.Add('parent-certificate-missing:kernel-terminal-timeout')}}else{[void]$errors.Add('parent-certificate-missing:no-retained-process')}
$parentCertificatePresent=[bool]($parentProcess -and $parentHandle -ne [IntPtr]::Zero -and $parentKernelTerminal -and $parentExitRaw -ne 259 -and $parentExitSigned -eq $parentExitDotnet)
$parentCertificatePresent=$parentCertificatePresent -and ($errors.Count -eq 0)
$lockText='';if(Test-Path -LiteralPath $lockFull -PathType Leaf){$li=Get-Item -LiteralPath $lockFull -Force;if(($li.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0 -and $li.Length -le 1048576){$lockText=[IO.File]::ReadAllText($li.FullName)}}
$owner="SR0-DISPLAY-SELFJOB-$TaskName";$out=[ordered]@{kind='sr0-display-coordinator-v4';status=if($errors.Count -eq 0){'passed'}else{'held'};taskName=$TaskName;startReceipt=$startFull;finalReceipt=$finalFull;parentCertificatePresent=$parentCertificatePresent;parentPid=if($start){$start.parentPid}else{$null};parentPath=if($start){$start.parentPath}else{$null};parentStartTimeUtc=if($start){$start.parentStartTimeUtc}else{$null};session=if($start){$start.currentSession}else{$null};parentKernelTerminal=$parentKernelTerminal;parentExitRaw=$parentExitRaw;parentExitSigned=$parentExitSigned;parentExitDotnet=$parentExitDotnet;lockOwnerObserved=($lockText.Trim() -eq $owner);lockMutated=$false;errors=@($errors);checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
Write-AtomicJson $outputFull $out
if($errors.Count -ne 0){exit 1}else{exit 0}
