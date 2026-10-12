# Generic Text capture admission preflight. It performs no compiler, GUI, lock, or native action.
param(
 [ValidateSet('Launch')][string]$Phase='Launch',
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$CompileReceiptSha256,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExeSha256,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$SerializerControlSha256,
 [string]$SourceInputsPath,[ValidatePattern('^[0-9a-f]{64}$')][string]$SourceInputsHash,
 [string]$PlanPath,[ValidatePattern('^[0-9a-f]{64}$')][string]$PlanHash,
 [string]$CompileReceiptPath,[string]$ExePath,[string]$RendererPath,[string]$SerializerPath
)
$ErrorActionPreference='Stop'
function Hash([string]$Path,[long]$Limit=67108864){$item=Get-Item -LiteralPath $Path -Force;if($item.PSIsContainer -or $item.LinkType -or $item.Length -gt $Limit){throw 'bounded regular file required'};(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
function Json([string]$Path){if((Get-Item -LiteralPath $Path -Force).Length -gt 2097152){throw 'bounded JSON required'};Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json}
if($CompileReceiptSha256 -notmatch '^[0-9a-f]{64}$' -or $ExeSha256 -notmatch '^[0-9a-f]{64}$' -or $SerializerControlSha256 -notmatch '^[0-9a-f]{64}$'){throw 'measured launch pins required'}
if([string]::IsNullOrWhiteSpace($SourceInputsPath) -or [string]::IsNullOrWhiteSpace($PlanPath) -or [string]::IsNullOrWhiteSpace($CompileReceiptPath) -or [string]::IsNullOrWhiteSpace($ExePath) -or [string]::IsNullOrWhiteSpace($RendererPath) -or [string]::IsNullOrWhiteSpace($SerializerPath)){throw 'exact source/plan/receipt/exe/renderer/serializer refs required'}
$source=Json $SourceInputsPath
if((Hash $SourceInputsPath) -cne $SourceInputsHash){throw 'source inputs drift'}
$profile=if($source.kind -like 'factory-text-*'){'text'}elseif($source.kind -like 'factory-circle-*'){'circle'}else{throw 'generic profile source kind required'}
$expectedPlanKind=if($profile -eq 'text'){'factory-text-compiler-plan-v1'}else{'factory-circle-compiler-plan-v1'}
$expectedReceiptKind=if($profile -eq 'text'){'factory-text-owned-compile-v1'}else{'factory-circle-owned-compile-v1'}
if((Hash $PlanPath) -cne $PlanHash -or $source.planHash -cne $PlanHash){throw 'plan hash join drift'}
$plan=Json $PlanPath
if($plan.kind -cne $expectedPlanKind -or $plan.sourceHash -ne $source.sourceHash -or $plan.case.id -cne $source.caseID -or $plan.tuple.id -cne $source.tupleID -or $plan.runtimeSourceCommit -ne $source.runtimeSourceCommit -or $plan.rendererPath -ne $source.rendererPath -or $plan.rendererSha256 -ne $source.rendererSha256){throw 'plan/source identity mismatch'}
if((Hash $CompileReceiptPath) -cne $CompileReceiptSha256 -or $source.compileReceiptHash -cne $CompileReceiptSha256){throw 'compile receipt hash join drift'}
$receipt=Json $CompileReceiptPath
if($receipt.kind -cne $expectedReceiptKind -or $receipt.exitCode -ne 0 -or $receipt.timedOut -or $receipt.outputCapExceeded -or -not $receipt.ownedExited -or -not $receipt.originalHandleRetained -or $receipt.kernelWait -ne 0 -or -not $receipt.streamDrainComplete -or -not $receipt.streamsSealed -or $receipt.jobActiveCount -ne 0 -or $receipt.sourceHash -ne $source.sourceHash -or $receipt.planSha256 -ne $source.planHash -or $receipt.runtimeSourceCommit -ne $source.runtimeSourceCommit -or $receipt.rendererSha256 -ne $source.rendererSha256){throw 'compile receipt lifecycle/source mismatch'}
if((Hash $ExePath) -cne $ExeSha256 -or $source.exeHash -ne $ExeSha256 -or $receipt.exeSha256 -ne $ExeSha256){throw 'executable hash join drift'}
if((Hash $RendererPath) -cne $source.rendererSha256){throw 'renderer hash join drift'}
if((Hash $SerializerPath) -cne $SerializerControlSha256 -or $source.serializerControlSha256 -ne $SerializerControlSha256){throw 'serializer hash join drift'}
[ordered]@{kind='factory-generic-capture-preflight-v1';profile=$profile;phase=$Phase;status='passed';sourceInputsHash=$SourceInputsHash;planHash=$PlanHash;compileReceiptHash=$CompileReceiptSha256;exeHash=$ExeSha256;serializerControlSha256=$SerializerControlSha256;nativeActions=0;compilerActions=0;lockActions=0}|ConvertTo-Json -Depth 8
