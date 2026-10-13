# Root-coordinated capture dispatcher. Performs exact input gates, then invokes twenty owned runs.
param(
  [Parameter(Mandatory=$true)][string]$LockOwner,
  [Parameter(Mandatory=$true)][string]$CompileReceiptHash,
  [Parameter(Mandatory=$true)][string]$ExeHash,
  [Parameter(Mandatory=$true)][string]$SerializerControlSha256,
  [ValidateSet(20)][int]$Count=20,
  [string]$RunRoot,
  [Parameter(Mandatory=$true)][string]$IssuedMetadataPath,[Parameter(Mandatory=$true)][string]$IssuedMetadataHash,
  [string]$FirstRunRoot
)
$ErrorActionPreference='Stop'
$overlayRoot=[IO.Path]::GetFullPath($PSScriptRoot)
$here=[IO.Path]::GetFullPath((Join-Path $overlayRoot '..\..'))
$plan=Get-Content -Raw (Join-Path $here 'capture-plan.json')|ConvertFrom-Json
. (Join-Path $here 'support\cleanup.ps1')
. (Join-Path $here 'support\stream-seal.ps1')
$rootManifest=Get-Content -Raw (Join-Path $here 'root-stage-manifest.json')|ConvertFrom-Json
$bindingEntry=@($rootManifest.files|Where-Object{$_.path -eq 'factory/native/windows/padding-capture-lease-capture-v3/integration-bindings.json'})
if($bindingEntry.Count -ne 1 -or $bindingEntry[0].sha256 -ne ('sha256:'+(Get-FileHash -LiteralPath (Join-Path $here 'integration-bindings.json')).Hash.ToLowerInvariant()) -or $bindingEntry[0].bytes -ne (Get-Item -LiteralPath (Join-Path $here 'integration-bindings.json')).Length){throw 'Integration binding manifest drift'}
. (Join-Path $here 'support\integration.ps1')
Assert-FactoryIntegrationSources $here
. (Join-Path $here 'support\final-exit-certificate.ps1')
. (Join-Path $here 'dependencies\uia-worker\support\final-exit-certificate.ps1')
. (Join-Path $here 'support\all-owned-release.ps1')
. (Join-Path $here 'support\first-proof.ps1')
if($CompileReceiptHash -notmatch '^[0-9a-f]{64}$' -or $ExeHash -notmatch '^[0-9a-f]{64}$' -or $SerializerControlSha256 -notmatch '^[0-9a-f]{64}$'){throw 'Measured compile receipt/exe/serializer control pins required'}
if($null -eq $plan.dispatch.repeat){throw 'Reviewed dispatch.repeat plan required before Count20 resume'}
$expectedRunRoot=$plan.dispatch.repeat.runRoot
if([string]::IsNullOrWhiteSpace($RunRoot)){$RunRoot=$expectedRunRoot}
if([IO.Path]::GetFullPath($RunRoot) -cne $expectedRunRoot){throw 'Exact fresh capture namespace required'}
if(Test-Path -LiteralPath $RunRoot){throw 'Capture namespace already exists; retries are disabled'}
$buildPreflightPath=$plan.launchPreflightPath
if(-not (Test-Path -LiteralPath $buildPreflightPath -PathType Leaf)){throw 'Reviewed build preflight missing'}
if((Get-FileHash -LiteralPath $buildPreflightPath).Hash.ToLowerInvariant() -ne $plan.launchPreflightSha256.Replace('sha256:','')){throw 'Reviewed build preflight drift'}
& $buildPreflightPath -Phase Launch -CompileReceiptSha256 $CompileReceiptHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerControlSha256 | Out-Null

Assert-PaddingFirstCaptureProof -CaptureRoot $here -CompiledReceiptPath (Join-Path $plan.compiledHostPackagePath 'build-capture-lease-r1\observation.json') -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash -SerializerControlSha256 $SerializerControlSha256 -ExpectedRunRoot $plan.dispatch.first.runRoot
$dispatch=[ordered]@{kind='padding-window-diagnosis-capture-dispatch';status='dispatching';count=$Count;runRoot=$RunRoot;firstRunRoot=$FirstRunRoot;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;serializerControlSha256=$SerializerControlSha256;nativeLaunchesBeforeDispatch=0;retries=$false;metricsEventMissing='diagnostic-only; no synthetic event'}
$dispatch|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $here ('dispatch-{0}.json' -f $Count))
& (Join-Path $overlayRoot 'capture-repeat-repeat.ps1') -Package $plan.compiledHostPackagePath -LockOwner $LockOwner -RunRoot $RunRoot -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash -SerializerControlSha256 $SerializerControlSha256 -Count $Count -IssuedMetadataPath $IssuedMetadataPath -IssuedMetadataHash $IssuedMetadataHash
if(-not (Test-Path -LiteralPath (Join-Path $RunRoot 'native-observation.json') -PathType Leaf)){throw 'Capture produced no observation receipt'}
$dispatch.status='completed-source-bound-observation';$dispatch.nativeLaunchesAfterDispatch=$Count
$dispatch.observationSha256=(Get-FileHash -LiteralPath (Join-Path $RunRoot 'native-observation.json')).Hash.ToLowerInvariant()
$dispatch|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $RunRoot 'dispatch.json')
