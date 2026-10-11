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
. (Join-Path $here 'support\cleanup.ps1')
. (Join-Path $here 'support\stream-seal.ps1')
$firstProofHelper=Join-Path $here 'support\first-proof.ps1'
if((Get-FileHash -LiteralPath $firstProofHelper).Hash.ToLowerInvariant() -ne '355d2d10aa1806ff02e82c21bfe48788dca70dd5a024a8afa78beff890987fb0'){throw 'First-proof helper drift'}
. $firstProofHelper
if($CompileReceiptHash -notmatch '^[0-9a-f]{64}$' -or $ExeHash -notmatch '^[0-9a-f]{64}$'){throw 'Measured compile receipt/exe pins required'}
$expectedRunRoot=if($Count -eq 1){$plan.dispatch.first.runRoot}else{$plan.dispatch.repeat.runRoot}
if([string]::IsNullOrWhiteSpace($RunRoot)){$RunRoot=$expectedRunRoot}
if([IO.Path]::GetFullPath($RunRoot) -cne $expectedRunRoot){throw 'Exact fresh capture namespace required'}
if(Test-Path -LiteralPath $RunRoot){throw 'Capture namespace already exists; retries are disabled'}
if($Count -eq 20){
  if([string]::IsNullOrWhiteSpace($FirstRunRoot)){$FirstRunRoot=$plan.dispatch.first.runRoot}
  if([IO.Path]::GetFullPath($FirstRunRoot) -cne $plan.dispatch.first.runRoot){throw 'Exact fresh first-run namespace required'}
  if($FirstRunRoot -cne $plan.dispatch.first.runRoot){throw 'Exact fresh first-run namespace required'}
  Assert-PaddingFirstCaptureProof -CaptureRoot $here -CompiledReceiptPath (Join-Path $plan.compiledHostPackagePath 'build-settled-r2\observation.json') -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash -ExpectedRunRoot $FirstRunRoot
}
$dispatch=[ordered]@{kind='padding-settled-capture-dispatch';status='dispatching';count=$Count;runRoot=$RunRoot;firstRunRoot=$FirstRunRoot;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;nativeLaunchesBeforeDispatch=0;retries=$false;metricsEventMissing='diagnostic-only; no synthetic event'}
$dispatch|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $here ('dispatch-{0}.json' -f $Count))
& (Join-Path $here 'capture-repeat.ps1') -Package $plan.compiledHostPackagePath -LockOwner $LockOwner -RunRoot $RunRoot -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash -Count $Count
if(-not (Test-Path -LiteralPath (Join-Path $RunRoot 'native-observation.json') -PathType Leaf)){throw 'Capture produced no observation receipt'}
$dispatch.status='completed-source-bound-observation';$dispatch.nativeLaunchesAfterDispatch=$Count
$dispatch.observationSha256=(Get-FileHash -LiteralPath (Join-Path $RunRoot 'native-observation.json')).Hash.ToLowerInvariant()
$dispatch|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $RunRoot 'dispatch.json')
