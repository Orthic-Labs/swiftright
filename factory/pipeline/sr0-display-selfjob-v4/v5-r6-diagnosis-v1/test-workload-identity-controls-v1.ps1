[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$IdentityHelperPath,
  [Parameter(Mandatory)][string]$ResultPath,
  [Parameter(Mandatory)][string]$OutputPath,
  [Parameter(Mandatory)][int]$ExpectedRuns,
  [Parameter(Mandatory)][int64]$WrapperPid,
  [Parameter(Mandatory)][int64]$ExpectedWorkerPid,
  [Parameter(Mandatory)][string]$MutationRoot
)
$ErrorActionPreference='Stop'
function Read-BoundedIdentityText([string]$Path){
  $f=Get-Item -LiteralPath $Path -Force
  if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $f.Length -gt 2097152){throw 'identity fixture is not bounded'}
  return [IO.File]::ReadAllText($f.FullName)
}
if(-not(Test-Path -LiteralPath $IdentityHelperPath -PathType Leaf)){throw 'identity helper missing'}
. $IdentityHelperPath
$text=Read-BoundedIdentityText $ResultPath
if(-not(Test-Path -LiteralPath $MutationRoot)){[IO.Directory]::CreateDirectory($MutationRoot)|Out-Null}
function Write-FreshFixture([string]$Name,[string]$Body){$p=Join-Path $MutationRoot $Name;if(Test-Path -LiteralPath $p){throw "fixture already exists: $p"};[IO.File]::WriteAllText($p,$Body,(New-Object Text.UTF8Encoding($false)));return $p}
function Expect-Reject([string]$Name,[string]$Body){$p=Write-FreshFixture $Name $Body;$rejected=$false;try{Resolve-WorkloadIdentityV6 -Path $p -ExpectedRuns $ExpectedRuns -WrapperPid $WrapperPid|Out-Null}catch{$rejected=$true};if(-not $rejected){throw "identity fault accepted: $Name"};return $p}
$baseline=Resolve-WorkloadIdentityV6 -Path $ResultPath -ExpectedRuns $ExpectedRuns -WrapperPid $WrapperPid
if([int64]$baseline.workerPid -ne $ExpectedWorkerPid){throw "unexpected nested workload PID: $($baseline.workerPid) vs $ExpectedWorkerPid"}
if(-not $baseline.workerExitIdentity){throw 'baseline worker exit identity absent'}
$faults=[ordered]@{}
$faults.parentMismatch=Expect-Reject 'parent-mismatch.txt' ($text -replace ('parent_pid='+[string]$WrapperPid),'parent_pid=99999')
$faults.workerPidMismatch=Expect-Reject 'worker-pid-mismatch.txt' ($text -replace ('pid='+[string]$ExpectedWorkerPid),'pid=99999')
$faults.exitIdentityMismatch=Expect-Reject 'exit-identity-mismatch.txt' ($text -replace 'kernel_exit_raw=0','kernel_exit_raw=1')
$workerLine=[regex]::Match($text,'(?m)^worker run=.*\r?\n')
if(-not $workerLine.Success){throw 'fixture worker row missing'}
$faults.workerRowMissing=Expect-Reject 'worker-row-missing.txt' $text.Remove($workerLine.Index,$workerLine.Length)
$out=[ordered]@{status='passed-source-controls';productionHelper=(Split-Path -Leaf $IdentityHelperPath);baseline=[ordered]@{workerPid=$baseline.workerPid;parentPid=$baseline.parentPid;workerExit=$baseline.workerExit;streamsDrained=$baseline.streamsDrained};faults=$faults;resultPath=$ResultPath;mutationRoot=$MutationRoot}
$parent=Split-Path -Parent $OutputPath;if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};[IO.File]::WriteAllText($OutputPath,(ConvertTo-Json $out -Depth 8)+"`r`n",(New-Object Text.UTF8Encoding($false)))
exit 0
