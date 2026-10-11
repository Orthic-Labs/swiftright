# Source/config preflight only. Never launches host, acquires desktop lock, or retries.
param(
  [Parameter(Mandatory=$true)][string]$CompileReceiptPath,
  [Parameter(Mandatory=$true)][string]$ExecutablePath,
  [Parameter(Mandatory=$true)][string]$CompileReceiptHash,
  [Parameter(Mandatory=$true)][string]$ExeHash,
  [Parameter(Mandatory=$true)][string]$SerializerControlSha256,
  [ValidateSet(1,20)][int]$Count = 1,
  [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop'
$here=[IO.Path]::GetFullPath($PSScriptRoot)
$plan=Get-Content -Raw (Join-Path $here 'capture-plan.json')|ConvertFrom-Json
foreach($h in @($CompileReceiptHash,$ExeHash,$SerializerControlSha256)) { if($h -notmatch '^[0-9a-f]{64}$'){throw 'Actual compile/executable/serializer control hashes required'} }
if(-not (Test-Path -LiteralPath $CompileReceiptPath -PathType Leaf)){throw 'Compile receipt missing'}
if(-not (Test-Path -LiteralPath $ExecutablePath -PathType Leaf)){throw 'Compiled host missing'}
if([IO.Path]::GetFullPath($CompileReceiptPath) -cne [IO.Path]::GetFullPath((Join-Path $plan.compiledHostPackagePath 'build-settled-r2\observation.json'))){throw 'Exact compiled receipt path required'}
if([IO.Path]::GetFullPath($ExecutablePath) -cne [IO.Path]::GetFullPath((Join-Path $plan.compiledHostPackagePath 'build-settled-r2\FactoryProbe.exe'))){throw 'Exact compiled executable path required'}
if((Get-FileHash -LiteralPath $CompileReceiptPath).Hash.ToLowerInvariant() -ne $CompileReceiptHash){throw 'Compile receipt hash drift'}
if((Get-FileHash -LiteralPath $ExecutablePath).Hash.ToLowerInvariant() -ne $ExeHash){throw 'Executable hash drift'}
if(-not $plan.sourcePlanSha256 -or -not $plan.renderer.sha256){throw 'Capture plan pins missing'}
$sourcePlanPath=Join-Path $plan.sourcePackagePath 'plan.json'
if(-not (Test-Path -LiteralPath $sourcePlanPath -PathType Leaf)){throw 'Source package plan missing'}
if((Get-FileHash -LiteralPath $sourcePlanPath).Hash.ToLowerInvariant() -ne $plan.sourcePlanSha256.Replace('sha256:','')){throw 'Source package plan hash drift'}
$compiledPlanPath=Join-Path $plan.compiledHostPackagePath 'plan.json'
if(-not (Test-Path -LiteralPath $plan.sourcePackagePath -PathType Container)){throw 'Source package missing'}
if(-not (Test-Path -LiteralPath $plan.compiledHostPackagePath -PathType Container)){throw 'Compiled host package missing'}
if(-not (Test-Path -LiteralPath $compiledPlanPath -PathType Leaf)){throw 'Compiled host plan missing'}
if((Get-FileHash -LiteralPath $compiledPlanPath).Hash.ToLowerInvariant() -ne $plan.compiledPlanSha256.Replace('sha256:','')){throw 'Compiled host plan hash drift'}
$buildPreflightPath=Join-Path $plan.compiledHostPackagePath '..\preflight.ps1'
if(-not (Test-Path -LiteralPath $buildPreflightPath -PathType Leaf)){throw 'Reviewed build preflight missing'}
if((Get-FileHash -LiteralPath $buildPreflightPath).Hash.ToLowerInvariant() -ne $plan.reviewedBuildPreflightSha256.Replace('sha256:','')){throw 'Reviewed build preflight drift'}
$receipt=Get-Content -Raw $CompileReceiptPath|ConvertFrom-Json
if($receipt.exitCode -ne 0 -or $receipt.timedOut -or ($receipt.ownedExited -eq $false)){throw 'Compile receipt is not successful'}
if($receipt.planSha256 -ne $plan.compiledPlanSha256.Replace('sha256:','')){throw 'Compile receipt plan lineage mismatch'}
if($receipt.exeSha256 -and $receipt.exeSha256.ToLowerInvariant() -ne $ExeHash){throw 'Receipt executable hash mismatch'}
if($receipt.rendererSha256 -and $receipt.rendererSha256.ToLowerInvariant() -ne $plan.renderer.sha256.Replace('sha256:','')){throw 'Receipt renderer hash mismatch'}
& $buildPreflightPath -Phase Launch -CompileReceiptSha256 $CompileReceiptHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerControlSha256 | Out-Null
$out=[IO.Path]::GetFullPath($OutputPath)
if(-not $out.StartsWith($plan.captureRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Output outside owned capture root'}
if(Test-Path -LiteralPath $out){throw 'Fresh output namespace required'}
[ordered]@{
  kind='padding-settled-capture-preflight'; status='ready-for-root-dispatch'; nativeLaunches=0; retries=$false
  count=$Count; compileReceiptHash=$CompileReceiptHash; exeHash=$ExeHash; serializerControlSha256=$SerializerControlSha256
  sourcePlanSha256=$plan.sourcePlanSha256; rendererPath=$plan.renderer.rollingInputPath; rendererSha256=$plan.renderer.sha256
  compiledHostPackagePath=$plan.compiledHostPackagePath; outputPath=$out
  metricsEventMissing='diagnostic-only; no synthetic event'
}|ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $here ('prepared-dispatch-{0}.json' -f $Count))
