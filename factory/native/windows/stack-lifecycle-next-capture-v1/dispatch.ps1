# Root-coordinated capture dispatcher. Performs exact input gates, then invokes one or twenty owned runs.
param(
  [Parameter(Mandatory=$true)][string]$LockOwner,
  [Parameter(Mandatory=$true)][string]$CompileReceiptHash,
  [Parameter(Mandatory=$true)][string]$ExeHash,
  
  [ValidateSet(1)][int]$Count=1,
  [string]$RunRoot,
  [string]$FirstRunRoot
)
$ErrorActionPreference='Stop'
$here=[IO.Path]::GetFullPath($PSScriptRoot)
$plan=Get-Content -Raw (Join-Path $here 'capture-plan.json')|ConvertFrom-Json
. (Join-Path $here 'support\cleanup.ps1')
. (Join-Path $here 'support\stream-seal.ps1')
if($CompileReceiptHash -notmatch '^[0-9a-f]{64}$' -or $ExeHash -notmatch '^[0-9a-f]{64}$'){throw 'Measured compile receipt/exe pins required'}
$expectedRunRoot=$plan.dispatch.first.runRoot
if([string]::IsNullOrWhiteSpace($RunRoot)){$RunRoot=$expectedRunRoot}
if([IO.Path]::GetFullPath($RunRoot) -cne $expectedRunRoot){throw 'Exact fresh capture namespace required'}
if(Test-Path -LiteralPath $RunRoot){throw 'Capture namespace already exists; retries are disabled'}
$buildPreflightPath=$plan.launchPreflightPath
if(-not (Test-Path -LiteralPath $buildPreflightPath -PathType Leaf)){throw 'Reviewed build preflight missing'}
if((Get-FileHash -LiteralPath $buildPreflightPath).Hash.ToLowerInvariant() -ne $plan.launchPreflightSha256.Replace('sha256:','')){throw 'Reviewed build preflight drift'}
& $buildPreflightPath -Phase Launch -CompileReceiptSha256 $CompileReceiptHash -ExeSha256 $ExeHash  | Out-Null

$dispatch=[ordered]@{kind='stack-lifecycle-capture-dispatch';status='dispatching';count=$Count;runRoot=$RunRoot;firstRunRoot=$FirstRunRoot;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;nativeLaunchesBeforeDispatch=0;retries=$false;metricsEventMissing='diagnostic-only; no synthetic event'}
$dispatch|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $here ('dispatch-{0}.json' -f $Count))
& (Join-Path $here 'capture-repeat.ps1') -Package $plan.compiledHostPackagePath -LockOwner $LockOwner -RunRoot $RunRoot -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash  -Count $Count
if(-not (Test-Path -LiteralPath (Join-Path $RunRoot 'native-observation.json') -PathType Leaf)){throw 'Capture produced no observation receipt'}
$dispatch.status='completed-source-bound-observation';$dispatch.nativeLaunchesAfterDispatch=$Count
$dispatch.observationSha256=(Get-FileHash -LiteralPath (Join-Path $RunRoot 'native-observation.json')).Hash.ToLowerInvariant()
$dispatch|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $RunRoot 'dispatch.json')
