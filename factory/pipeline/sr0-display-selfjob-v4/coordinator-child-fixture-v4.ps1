# Executable coordinator fixture. It emits collector-shaped receipts from its own live process,
# remains alive while coordinator retains its kernel handle, then exits with requested code.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$StartPath,
  [Parameter(Mandatory)][string]$FinalPath,
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$TaskName,
  [Parameter(Mandatory)][ValidateRange(-255,255)][int]$ExitCode,
  [ValidateRange(1,30)][int]$HoldSeconds=8
)
$ErrorActionPreference='Stop'
function Write-AtomicFresh([string]$Path,[object]$Value){
  if(Test-Path -LiteralPath $Path){throw "fixture receipt must be fresh: $Path"}
  $text=($Value|ConvertTo-Json -Depth 16)+"`r`n"
  $bytes=[Text.Encoding]::UTF8.GetBytes($text)
  $tmp="$Path.$PID.$([guid]::NewGuid().ToString('N')).tmp"
  if(Test-Path -LiteralPath $tmp){throw "fixture receipt temp must be fresh: $tmp"}
  $stream=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
  [IO.File]::Move($tmp,$Path)
}
$self=[Diagnostics.Process]::GetCurrentProcess()
$parentPath=$self.MainModule.FileName
$parentStartUtc=$self.StartTime.ToUniversalTime().ToString('o')
$session=[int64]$self.SessionId
$handle=$self.Handle
$common=[ordered]@{taskName=$TaskName;parentPid=$self.Id;parentPath=$parentPath;parentStartTimeUtc=$parentStartUtc;parentOriginalHandle=$handle.ToInt64();parentOriginalHandleRetained=($handle -ne [IntPtr]::Zero);sessionMatch=$true;currentSession=$session;activeConsoleSession=$session;jobMemoryLimitBytes=1073741824;limitFlags=512;activeProcessCount=1;noActivate=$true}
$start=[ordered]@{kind='sr0-display-collector-v4-start';status='admitted';parentHandle=$handle.ToInt64();parentHandleRetained=($handle -ne [IntPtr]::Zero);startedAt=[DateTimeOffset]::UtcNow.ToString('o')}
foreach($entry in $common.GetEnumerator()){$start[$entry.Key]=$entry.Value}
Write-AtomicFresh $StartPath $start
$final=[ordered]@{kind='sr0-display-collector-v4';status=if($ExitCode -eq 0){'completed'}else{'qualification-failed'};presentMonStarted=$true;presentMonTerminal=$true;presentMonExit=0;presentMonExitIdentity=$true;presentMonSessionAbsent=$true;workloadTerminal=$true;workloadExit=$ExitCode;workloadExitRaw=$ExitCode;workloadExitIdentity=$true;activeReadableAfter=$true;activeAfter=1;activeSelfOnly=$true;workloadProof=[ordered]@{ownershipTerminal=$true};lockReleased=$true;failure=$null;endedAt=[DateTimeOffset]::UtcNow.ToString('o')}
foreach($entry in $common.GetEnumerator()){$final[$entry.Key]=$entry.Value}
Write-AtomicFresh $FinalPath $final
Start-Sleep -Seconds $HoldSeconds
exit $ExitCode
