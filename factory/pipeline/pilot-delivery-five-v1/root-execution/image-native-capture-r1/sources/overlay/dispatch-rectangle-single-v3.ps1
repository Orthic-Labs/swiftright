# Root-coordinated Rectangle Count1 dispatcher. Performs exact input gates, then invokes one owned run.
param(
  [Parameter(Mandatory=$true)][string]$Package,
  [Parameter(Mandatory=$true)][string]$LockOwner,
  [Parameter(Mandatory=$true)][string]$CompileReceiptHash,
  [Parameter(Mandatory=$true)][string]$ExeHash,
  [Parameter(Mandatory=$true)][string]$SerializerControlSha256,
  [ValidateSet(1)][int]$Count=1,
  [Parameter(Mandatory=$true)][string]$ProducerRoot,
  [Parameter(Mandatory=$true)][string]$AdmissionRoot,
  [Parameter(Mandatory=$true)][string]$ControlRoot,
  [Parameter(Mandatory=$true)][string]$OutputRoot,
  [Parameter(Mandatory=$true)][string]$IntegrationGuardPath,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$IntegrationGuardHash,
  [Parameter(Mandatory=$true)][string]$SourceInputsPath,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$SourceInputsHash,
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [Parameter(Mandatory=$true)][string]$IssuedMetadataPath,[Parameter(Mandatory=$true)][string]$IssuedMetadataHash,
  [string]$FirstRunRoot,[switch]$PreflightOnly
)
$ErrorActionPreference='Stop'
$overlayRoot=[IO.Path]::GetFullPath($PSScriptRoot)
$here=[IO.Path]::GetFullPath($ProducerRoot)
$controlRoot=[IO.Path]::GetFullPath($ControlRoot)
$plan=Get-Content -Raw (Join-Path $here 'capture-plan.json')|ConvertFrom-Json
. (Join-Path $here 'support\cleanup.ps1')
. (Join-Path $here 'support\stream-seal.ps1')
$guardPath=[IO.Path]::GetFullPath($IntegrationGuardPath)
if((Get-FileHash -LiteralPath $guardPath).Hash.ToLowerInvariant() -cne $IntegrationGuardHash){throw 'Prefixed integration guard drift'}
. $guardPath
. (Join-Path $here 'support\final-exit-certificate.ps1')
. (Join-Path $here 'dependencies\uia-worker\support\final-exit-certificate.ps1')
. (Join-Path $here 'support\all-owned-release.ps1')
. (Join-Path $here 'dependencies\uia-worker\schema.ps1')
if($CompileReceiptHash -notmatch '^[0-9a-f]{64}$' -or $ExeHash -notmatch '^[0-9a-f]{64}$' -or $SerializerControlSha256 -notmatch '^[0-9a-f]{64}$'){throw 'Measured compile receipt/exe/serializer control pins required'}
if($null -eq $plan.dispatch.first){throw 'Reviewed dispatch.first plan required before Rectangle Count1 capture'}
$sourceInputs=[IO.Path]::GetFullPath($SourceInputsPath)
if(-not (Test-Path -LiteralPath $sourceInputs -PathType Leaf) -or (Get-FileHash -LiteralPath $sourceInputs).Hash.ToLowerInvariant() -cne $SourceInputsHash){throw 'Rectangle source-input manifest missing or drifted'}
$sourceDocument=Get-Content -Raw -LiteralPath $sourceInputs|ConvertFrom-Json
if($sourceDocument.kind -notin @('factory-rectangle-source-inputs-v1','factory-pilot-source-inputs-v1') -or $sourceDocument.count -ne 1 -or $sourceDocument.caseID -ne $plan.case.id -or $sourceDocument.sourceHash -ne $plan.sourceHash -or $sourceDocument.tupleID -ne $plan.tuple.id -or $sourceDocument.compileReceiptHash -ne $CompileReceiptHash -or $sourceDocument.exeHash -ne $ExeHash){throw 'Rectangle source-input identity mismatch'}
Assert-FactoryIntegrationSources $here $sourceDocument
$expectedRunRoot=[IO.Path]::GetFullPath($RunRoot)
if(-not [IO.Path]::GetFullPath($RunRoot).StartsWith([IO.Path]::GetFullPath($OutputRoot)+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Run root outside fresh output namespace'}
if(Test-Path -LiteralPath $RunRoot){throw 'Capture namespace already exists; retries are disabled'}
$buildPreflightPath=[IO.Path]::GetFullPath([string]$sourceDocument.buildPreflightPath)
if(-not (Test-Path -LiteralPath $buildPreflightPath -PathType Leaf)){throw 'Reviewed build preflight missing'}
if($sourceDocument.buildPreflightHash -notmatch '^[0-9a-f]{64}$' -or (Get-FileHash -LiteralPath $buildPreflightPath).Hash.ToLowerInvariant() -ne $sourceDocument.buildPreflightHash){throw 'Reviewed Rectangle build preflight drift'}
& $buildPreflightPath -Phase Launch -CompileReceiptSha256 $CompileReceiptHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerControlSha256 -CompileReceiptBytes 3054 -ExeBytes 3911680 -SerializerControlBytes 932 -RendererBytes 11885056 | Out-Null

$dispatch=[ordered]@{kind='factory-rectangle-capture-dispatch-v1';status=if($PreflightOnly){'preflight'}else{'dispatching'};count=$Count;runRoot=$RunRoot;firstRunRoot=$FirstRunRoot;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;serializerControlSha256=$SerializerControlSha256;sourceInputsHash=$SourceInputsHash;nativeLaunchesBeforeDispatch=0;retries=$false;metricsEventMissing='diagnostic-only; no synthetic event'}
$dispatch|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $controlRoot ('dispatch-{0}.json' -f $Count))
& (Join-Path $overlayRoot 'capture-rectangle-single-v3.ps1') -Package $Package -LockOwner $LockOwner -ProducerRoot $ProducerRoot -AdmissionRoot $AdmissionRoot -ControlRoot $ControlRoot -OutputRoot $OutputRoot -IntegrationGuardPath $IntegrationGuardPath -IntegrationGuardHash $IntegrationGuardHash -SourceInputsPath $SourceInputsPath -SourceInputsHash $SourceInputsHash -RunRoot $RunRoot -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash -SerializerControlSha256 $SerializerControlSha256 -Count $Count -IssuedMetadataPath $IssuedMetadataPath -IssuedMetadataHash $IssuedMetadataHash -PreflightOnly:$PreflightOnly
if($PreflightOnly){return}
if(-not (Test-Path -LiteralPath (Join-Path $RunRoot 'native-observation.json') -PathType Leaf)){throw 'Capture produced no observation receipt'}
$dispatch.status='completed-source-bound-observation';$dispatch.nativeLaunchesAfterDispatch=$Count
$dispatch.observationSha256=(Get-FileHash -LiteralPath (Join-Path $RunRoot 'native-observation.json')).Hash.ToLowerInvariant()
$dispatch|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $RunRoot 'dispatch.json')
