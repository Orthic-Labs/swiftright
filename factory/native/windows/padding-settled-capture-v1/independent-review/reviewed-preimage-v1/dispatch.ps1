# Root-coordinated capture dispatcher. Performs exact input gates, then invokes one or twenty owned runs.
param(
  [Parameter(Mandatory=$true)][string]$LockOwner,
  [Parameter(Mandatory=$true)][string]$CompileReceiptHash,
  [Parameter(Mandatory=$true)][string]$ExeHash,
  [ValidateSet(1,20)][int]$Count=1,
  [string]$RunRoot,
  [string]$FirstRunRoot
)
$ErrorActionPreference='Stop'
$here=[IO.Path]::GetFullPath($PSScriptRoot)
$plan=Get-Content -Raw (Join-Path $here 'capture-plan.json')|ConvertFrom-Json
if($CompileReceiptHash -notmatch '^[0-9a-f]{64}$' -or $ExeHash -notmatch '^[0-9a-f]{64}$'){throw 'Measured compile receipt/exe pins required'}
$expectedRunRoot=if($Count -eq 1){$plan.dispatch.first.runRoot}else{$plan.dispatch.repeat.runRoot}
if([string]::IsNullOrWhiteSpace($RunRoot)){$RunRoot=$expectedRunRoot}
if([IO.Path]::GetFullPath($RunRoot) -cne $expectedRunRoot){throw 'Exact fresh capture namespace required'}
if(Test-Path -LiteralPath $RunRoot){throw 'Capture namespace already exists; retries are disabled'}
if($Count -eq 20){
  if([string]::IsNullOrWhiteSpace($FirstRunRoot)){$FirstRunRoot=$plan.dispatch.first.runRoot}
  if([IO.Path]::GetFullPath($FirstRunRoot) -cne $plan.dispatch.first.runRoot){throw 'Exact first-run namespace required'}
  $firstObservation=Join-Path $FirstRunRoot 'native-observation.json'
  $firstOutcome=Join-Path $FirstRunRoot 'native-01\capture-outcome.json'
  if(-not (Test-Path -LiteralPath $firstObservation -PathType Leaf) -or -not (Test-Path -LiteralPath $firstOutcome -PathType Leaf)){throw 'Successful first observational capture required before repeat'}
  $rows=@(Get-Content -Raw $firstObservation|ConvertFrom-Json)
  $outcome=Get-Content -Raw $firstOutcome|ConvertFrom-Json
  if($rows.Count -ne 1 -or $rows[0].hostValid -ne $true -or $rows[0].exitCode -ne 0 -or $rows[0].compileReceiptHash -ne $CompileReceiptHash -or $rows[0].exeSha256 -ne $ExeHash -or $outcome.cleanup.confirmedOwnedExit -ne $true){throw 'First capture did not prove exact observational success & owned close'}
}
$dispatch=[ordered]@{kind='padding-settled-capture-dispatch';status='dispatching';count=$Count;runRoot=$RunRoot;firstRunRoot=$FirstRunRoot;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;nativeLaunchesBeforeDispatch=0;retries=$false;metricsEventMissing='diagnostic-only; no synthetic event'}
$dispatch|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $here ('dispatch-{0}.json' -f $Count))
& (Join-Path $here 'capture-repeat.ps1') -Package $plan.compiledHostPackagePath -LockOwner $LockOwner -RunRoot $RunRoot -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash -Count $Count
if(-not (Test-Path -LiteralPath (Join-Path $RunRoot 'native-observation.json') -PathType Leaf)){throw 'Capture produced no observation receipt'}
$dispatch.status='completed-source-bound-observation';$dispatch.nativeLaunchesAfterDispatch=$Count
$dispatch.observationSha256=(Get-FileHash -LiteralPath (Join-Path $RunRoot 'native-observation.json')).Hash.ToLowerInvariant()
$dispatch|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $RunRoot 'dispatch.json')
