param(
 [Parameter(Mandatory=$true)][string]$SourcePath,
 [Parameter(Mandatory=$true)][string]$ControlRoot,
 [Parameter(Mandatory=$true)][string]$Output
)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($ControlRoot)
if(Test-Path -LiteralPath $root){throw 'ControlRoot must be fresh'}
[IO.Directory]::CreateDirectory($root)|Out-Null
Add-Type -Path ([IO.Path]::GetFullPath($SourcePath))
$results=@()
function Invoke-Control([string]$Name,[bool]$ExpectedReject,[scriptblock]$Action,[string]$RequiredError=''){
 $accepted=$true;$error=''
 try{& $Action}catch{$accepted=$false;$error=[string]$_}
 if($accepted -ne (-not $ExpectedReject)){throw "Control expectation failed: $Name"}
 if($ExpectedReject -and $RequiredError -and -not $error.Contains($RequiredError)){throw "Wrong rejection reason: $Name : $error"}
 $script:results+=,[ordered]@{name=$Name;accepted=$accepted;expectedRejected=$ExpectedReject;error=$error}
}
$job=$null
try{
 Invoke-Control 'wrong-memory-limit-flags' $true { [Sr0OwnedJobProcess]::ValidateFlagsForControl(0x2200) } 'Only JOB_OBJECT_LIMIT_JOB_MEMORY is admitted'
 $job=[Sr0OwnedJobProcess]::CreateCurrentProcess(1073741824)
 Invoke-Control 'positive-1GiB-memory-job' $false {
  $s=$job.QueryPeakJobMemory();if($s.JobMemoryLimitBytes -ne 1073741824 -or $s.LimitFlags -ne [Sr0OwnedJobProcess]::JobMemoryOnlyFlags -or $s.ActiveProcessCount -ne 1){throw 'positive memory proof mismatch'}
  [Sr0OwnedJobProcess]::RequireOnlyCurrent($s)
 }
 Invoke-Control 'live-child-guard-rejects' $true {
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe';$psi.Arguments='-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
  $child=[Diagnostics.Process]::Start($psi);$cleanupError=$null
  $handle=$child.Handle
  try{
   Start-Sleep -Milliseconds 150
   $s=$job.WaitForOnlyCurrent(250)
   if($s.ActiveProcessCount -lt 2){throw 'Actual inherited child not observed'}
   [Sr0OwnedJobProcess]::RequireOnlyCurrent($s)
  }finally{
   if($null -ne $child){
    try{
     if(-not $child.HasExited -and -not $child.WaitForExit(500)){try{$child.Kill()}catch{};if(-not $child.WaitForExit(2000)){throw 'child terminal drain timeout'}}
     $child.Refresh();if(-not $child.HasExited){throw 'child terminal proof failed'}
     $script:childProof=[ordered]@{pid=$child.Id;originalHandleRetained=($handle -ne [IntPtr]::Zero);terminal=$child.HasExited;exitCode=$child.ExitCode;deadlineMilliseconds=2500;noWindow=$true}
    }catch{$cleanupError=$_.Exception}finally{$child.Dispose()}
   }
   if($null -ne $cleanupError){throw $cleanupError}
  }
 } 'Live child process remains in memory job'
 Invoke-Control 'self-only-after-child-terminal' $false {
  $s=$job.WaitForOnlyCurrent(3000);[Sr0OwnedJobProcess]::RequireOnlyCurrent($s)
 }
 if(-not $script:childProof.originalHandleRetained -or -not $script:childProof.terminal){throw 'Retained child terminal proof absent'}
 $result=[ordered]@{schema='factory-interactive-job-memory-controls-v2';status='passed-source-only';controls=$results;childProof=$script:childProof;jobMemoryLimitBytes=1073741824;jobMemoryLimitFlag=[Sr0OwnedJobProcess]::JobMemoryOnlyFlags;killOnJobClose=$false;nativeWindowActions=0;compilerActions=0;remoteActions=0;lockActions=0}
 $out=[IO.Path]::GetFullPath($Output);$parent=[IO.Directory]::GetParent($out);if($null -ne $parent){$parent.Create()};$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $out -Encoding UTF8
}finally{if($null -ne $job){$job.Dispose()}}
