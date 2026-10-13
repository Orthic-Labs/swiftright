[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ResultPath,
  [Parameter(Mandatory)][string]$ControlRoot,
  [Parameter(Mandatory)][int]$WrapperPid
)
$ErrorActionPreference='Stop'
$f=Get-Item -LiteralPath $ResultPath -Force -ErrorAction Stop
if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $f.Length -gt 2097152){throw 'result fixture bound/reparse failure'}
if(Test-Path -LiteralPath $ControlRoot){throw "fresh control root required: $ControlRoot"}
[IO.Directory]::CreateDirectory($ControlRoot)|Out-Null
$raw=[IO.File]::ReadAllText($f.FullName)
# Existing production V7 is expected to reject archived CRLF receipt.
. (Join-Path $PSScriptRoot 'workload-identity-v7.ps1')
$oldRejected=$false
try{[void](Resolve-WorkloadIdentityV7 -Path $ResultPath -ExpectedRuns 1 -WrapperPid $WrapperPid -CompletionGraceSeconds 1)}catch{$oldRejected=$true}
if(-not $oldRejected){throw 'original V7 unexpectedly accepted CRLF fixture'}
# Fresh V7 keeps names & guards; only CRLF -> LF normalization differs.
$normalized=Join-Path $ControlRoot 'normalized'
[IO.Directory]::CreateDirectory($normalized)|Out-Null
$normalizedPath=Join-Path $normalized 'result-workload.txt'
[IO.File]::WriteAllText($normalizedPath,$raw.Replace("`r`n","`n"),(New-Object Text.UTF8Encoding($false)))
$newActual=Resolve-WorkloadIdentityV7 -Path $ResultPath -ExpectedRuns 1 -WrapperPid $WrapperPid -CompletionGraceSeconds 1
$newLf=Resolve-WorkloadIdentityV7 -Path $normalizedPath -ExpectedRuns 1 -WrapperPid $WrapperPid -CompletionGraceSeconds 1
if(-not $newActual.workerExitIdentity -or -not $newActual.streamsDrained -or $newActual.workerPid -ne $newLf.workerPid){throw 'normalized V7 positive proof mismatch'}
$cases=@(
  @{name='missing-pid-exit';text=([regex]::Replace($raw,'(?m)^pid_exit .*\r?\n?',''))},
  @{name='mismatched-parent';text=([regex]::Replace($raw,'parent_pid=58252','parent_pid=58253',1))},
  @{name='invalid-handle';text=([regex]::Replace($raw,'handle=[1-9][0-9]*','handle=0',1))}
)
$rows=[System.Collections.Generic.List[object]]::new()
foreach($c in $cases){$dir=Join-Path $ControlRoot $c.name;[IO.Directory]::CreateDirectory($dir)|Out-Null;$path=Join-Path $dir 'result-workload.txt';[IO.File]::WriteAllText($path,$c.text,(New-Object Text.UTF8Encoding($false)));$rejected=$false;try{[void](Resolve-WorkloadIdentityV7 -Path $path -ExpectedRuns 1 -WrapperPid $WrapperPid -CompletionGraceSeconds 1)}catch{$rejected=$true};if(-not $rejected){throw "V7 fault accepted: $($c.name)"};$rows.Add([ordered]@{name=$c.name;status='rejected'})}
[ordered]@{status='controls-pass';originalV7CrLf='rejected';normalizedV7CrLf='accepted';normalizedV7Lf='accepted';faults=@($rows);qualificationClaim=$false}|ConvertTo-Json -Depth 12
