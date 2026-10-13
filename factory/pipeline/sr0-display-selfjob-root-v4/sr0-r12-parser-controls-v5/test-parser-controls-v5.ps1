[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ResultPath,
  [Parameter(Mandatory)][string]$OriginalHelperPath,
  [Parameter(Mandatory)][string]$FreshHelperPath,
  [Parameter(Mandatory)][string]$SourcePinsPath,
  [Parameter(Mandatory)][string]$ControlRoot,
  [Parameter(Mandatory)][int]$WrapperPid,
  [int64]$MaxBytes = 2097152
)
$ErrorActionPreference='Stop'
if($MaxBytes -lt 1 -or $MaxBytes -gt 2097152){throw 'bound rejected'}
function Require-BoundedFile([string]$Path){$i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $i.Length -gt $MaxBytes){throw "bounded/reparse input rejected: $Path"};return $i}
$result=Require-BoundedFile $ResultPath;$original=Require-BoundedFile $OriginalHelperPath;$fresh=Require-BoundedFile $FreshHelperPath;$pinsFile=Require-BoundedFile $SourcePinsPath
if([IO.Path]::GetFullPath($original.FullName) -eq [IO.Path]::GetFullPath($fresh.FullName)){throw 'original and fresh helper paths must differ'}
if(Test-Path -LiteralPath $ControlRoot){throw "fresh control root required: $ControlRoot"}
$pins=[IO.File]::ReadAllText($pinsFile.FullName)|ConvertFrom-Json
if([string]$pins.rawResultSha256 -notmatch '^[0-9a-fA-F]{64}$' -or [int64]$pins.rawResultBytes -ne 2837){throw 'fixture source pin invalid'}
if([string]$pins.originalV7DonorSha256 -notmatch '^[0-9a-fA-F]{64}$'){throw 'original V7 source pin invalid'}
$observedResult=(Get-FileHash -LiteralPath $result.FullName -Algorithm SHA256).Hash.ToLowerInvariant();if($observedResult -cne ([string]$pins.rawResultSha256).ToLowerInvariant()){throw 'fixture hash mismatch'}
if($result.Length -ne [int64]$pins.rawResultBytes){throw 'fixture byte count mismatch'}
$observedOriginal=(Get-FileHash -LiteralPath $original.FullName -Algorithm SHA256).Hash.ToLowerInvariant();if($observedOriginal -cne ([string]$pins.originalV7DonorSha256).ToLowerInvariant()){throw 'original V7 helper hash mismatch'}
[IO.Directory]::CreateDirectory($ControlRoot)|Out-Null
$raw=[IO.File]::ReadAllText($result.FullName)
# Load original production helper first; archived CRLF must remain rejected.
. $original.FullName
$oldRejected=$false
try{[void](Resolve-WorkloadIdentityV7 -Path $result.FullName -ExpectedRuns 1 -WrapperPid $WrapperPid -CompletionGraceSeconds 1)}catch{$oldRejected=$true}
if(-not $oldRejected){throw 'original V7 unexpectedly accepted CRLF fixture'}
# Load fresh same-name helper second; only fresh helper may accept normalized line endings.
. $fresh.FullName
$normalizedPath=Join-Path $ControlRoot 'lf-result-workload.txt'
[IO.File]::WriteAllText($normalizedPath,$raw.Replace("`r`n","`n"),(New-Object Text.UTF8Encoding($false)))
$newCrLf=Resolve-WorkloadIdentityV7 -Path $result.FullName -ExpectedRuns 1 -WrapperPid $WrapperPid -CompletionGraceSeconds 1
$newLf=Resolve-WorkloadIdentityV7 -Path $normalizedPath -ExpectedRuns 1 -WrapperPid $WrapperPid -CompletionGraceSeconds 1
if(-not $newCrLf.workerExitIdentity -or -not $newCrLf.streamsDrained -or $newCrLf.workerPid -ne $newLf.workerPid){throw 'fresh V7 positive proof mismatch'}
$cases=@(
  @{name='missing-pid-exit';text=([regex]::Replace($raw,'(?m)^pid_exit .*\r?\n?',''))},
  @{name='mismatched-parent';text=([regex]::Replace($raw,'parent_pid=58252','parent_pid=58253',1))},
  @{name='invalid-handle';text=([regex]::Replace($raw,'handle=[1-9][0-9]*','handle=0',1))}
)
$rows=[System.Collections.Generic.List[object]]::new()
foreach($c in $cases){$dir=Join-Path $ControlRoot $c.name;[IO.Directory]::CreateDirectory($dir)|Out-Null;$path=Join-Path $dir 'result-workload.txt';[IO.File]::WriteAllText($path,$c.text,(New-Object Text.UTF8Encoding($false)));$rejected=$false;try{[void](Resolve-WorkloadIdentityV7 -Path $path -ExpectedRuns 1 -WrapperPid $WrapperPid -CompletionGraceSeconds 1)}catch{$rejected=$true};if(-not $rejected){throw "fresh V7 fault accepted: $($c.name)"};$rows.Add([ordered]@{name=$c.name;status='rejected'})}
[ordered]@{status='controls-pass';originalV7Sha256=$observedOriginal;fixtureSha256=$observedResult;originalV7CrLf='rejected';freshV7CrLf='accepted';freshV7Lf='accepted';faults=@($rows);qualificationClaim=$false}|ConvertTo-Json -Depth 12
