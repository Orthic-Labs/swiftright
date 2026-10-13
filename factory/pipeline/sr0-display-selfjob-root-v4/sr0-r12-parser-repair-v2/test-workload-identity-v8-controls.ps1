[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$ResultPath,
  [Parameter(Mandatory)][string]$ControlRoot,
  [Parameter(Mandatory)][int]$WrapperPid
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'workload-identity-v8-crlf.ps1')
$f=Get-Item -LiteralPath $ResultPath -Force
if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $f.Length -gt 2097152){throw 'result fixture bound/reparse failure'}
if(-not(Test-Path -LiteralPath $ControlRoot -PathType Container)){[IO.Directory]::CreateDirectory($ControlRoot)|Out-Null}
$raw=[IO.File]::ReadAllText($f.FullName)
$actual=Resolve-WorkloadIdentityV8 -Path $ResultPath -ExpectedRuns 1 -WrapperPid $WrapperPid
if(-not $actual.workerExitIdentity -or -not $actual.streamsDrained){throw 'actual result identity/drain proof failed'}
$cases=@(
  @{name='crlf';text=$raw;mustPass=$true},
  @{name='lf';text=$raw.Replace("`r`n","`n");mustPass=$true},
  @{name='missing-pid-exit';text=([regex]::Replace($raw,'(?m)^pid_exit .*\r?\n?',''));mustPass=$false},
  @{name='wrong-handle';text=$raw.Replace('handle=2812','handle=2813');mustPass=$false},
  @{name='wrong-parent';text=$raw.Replace('parent_pid=58252','parent_pid=58253');mustPass=$false}
)
$rows=[System.Collections.Generic.List[object]]::new()
foreach($c in $cases){$dir=Join-Path $ControlRoot $c.name;if(-not(Test-Path -LiteralPath $dir -PathType Container)){[IO.Directory]::CreateDirectory($dir)|Out-Null};$path=Join-Path $dir 'result-workload.txt';[IO.File]::WriteAllText($path,$c.text,(New-Object Text.UTF8Encoding($false)));$ok=$true;try{[void](Resolve-WorkloadIdentityV8 -Path $path -ExpectedRuns 1 -WrapperPid $WrapperPid)}catch{$ok=$false};if($ok -ne [bool]$c.mustPass){throw "identity control mismatch: $($c.name)"};$rows.Add([ordered]@{name=$c.name;accepted=$ok;expected=[bool]$c.mustPass})}
[ordered]@{status='controls-pass';actual=[ordered]@{workerPid=$actual.workerPid;parentPid=$actual.parentPid;workerExit=$actual.workerExit;streamDrainRows=$actual.streamDrainRows};cases=@($rows);qualificationClaim=$false}|ConvertTo-Json -Depth 12
