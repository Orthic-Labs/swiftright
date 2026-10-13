# Root-coordinated capture dispatcher. Performs exact input gates, then invokes twenty owned runs.
param(
  [Parameter(Mandatory=$true)][string]$LockOwner,
  [Parameter(Mandatory=$true)][string]$CompileReceiptHash,
  [Parameter(Mandatory=$true)][string]$ExeHash,
  [Parameter(Mandatory=$true)][string]$SerializerControlSha256,
  [ValidateSet(20)][int]$Count=20,
  [Parameter(Mandatory=$true)][string]$ProducerRoot,
  [Parameter(Mandatory=$true)][string]$ControlRoot,
  [Parameter(Mandatory=$true)][string]$OutputRoot,
  [Parameter(Mandatory=$true)][string]$IntegrationGuardPath,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$IntegrationGuardHash,
  [Parameter(Mandatory=$true)][string]$FreshGuardControlsPath,
  [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$FreshGuardControlsHash,
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
$rootManifest=Get-Content -Raw (Join-Path $here 'root-stage-manifest.json')|ConvertFrom-Json
$bindingEntry=@($rootManifest.files|Where-Object{$_.path -eq 'factory/native/windows/padding-capture-lease-capture-v3/integration-bindings.json'})
if($bindingEntry.Count -ne 1 -or $bindingEntry[0].sha256 -ne ('sha256:'+(Get-FileHash -LiteralPath (Join-Path $here 'integration-bindings.json')).Hash.ToLowerInvariant()) -or $bindingEntry[0].bytes -ne (Get-Item -LiteralPath (Join-Path $here 'integration-bindings.json')).Length){throw 'Integration binding manifest drift'}
$guardPath=[IO.Path]::GetFullPath($IntegrationGuardPath)
if((Get-FileHash -LiteralPath $guardPath).Hash.ToLowerInvariant() -cne $IntegrationGuardHash){throw 'Prefixed integration guard drift'}
. $guardPath
Assert-FactoryIntegrationSources $here
. (Join-Path $here 'support\final-exit-certificate.ps1')
. (Join-Path $here 'dependencies\uia-worker\support\final-exit-certificate.ps1')
. (Join-Path $here 'support\all-owned-release.ps1')
. (Join-Path $here 'support\first-proof-fresh-r11.ps1')
if($CompileReceiptHash -notmatch '^[0-9a-f]{64}$' -or $ExeHash -notmatch '^[0-9a-f]{64}$' -or $SerializerControlSha256 -notmatch '^[0-9a-f]{64}$'){throw 'Measured compile receipt/exe/serializer control pins required'}
if($null -eq $plan.dispatch.repeat){throw 'Reviewed dispatch.repeat plan required before Count20 resume'}
$expectedRunRoot=[IO.Path]::GetFullPath($RunRoot)
if(-not [IO.Path]::GetFullPath($RunRoot).StartsWith([IO.Path]::GetFullPath($OutputRoot)+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Run root outside fresh output namespace'}
if(Test-Path -LiteralPath $RunRoot){throw 'Capture namespace already exists; retries are disabled'}
$buildPreflightPath=$plan.launchPreflightPath
if(-not (Test-Path -LiteralPath $buildPreflightPath -PathType Leaf)){throw 'Reviewed build preflight missing'}
if((Get-FileHash -LiteralPath $buildPreflightPath).Hash.ToLowerInvariant() -ne $plan.launchPreflightSha256.Replace('sha256:','')){throw 'Reviewed build preflight drift'}
& $buildPreflightPath -Phase Launch -CompileReceiptSha256 $CompileReceiptHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerControlSha256 | Out-Null

Assert-PaddingFirstCaptureProof -CaptureRoot $here -CompiledReceiptPath (Join-Path $plan.compiledHostPackagePath 'build-capture-lease-r1\observation.json') -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash -SerializerControlSha256 $SerializerControlSha256 -ExpectedRunRoot $plan.dispatch.first.runRoot
$dispatch=[ordered]@{kind='padding-window-diagnosis-capture-dispatch';status=if($PreflightOnly){'preflight'}else{'dispatching'};count=$Count;runRoot=$RunRoot;firstRunRoot=$FirstRunRoot;compileReceiptHash=$CompileReceiptHash;exeHash=$ExeHash;serializerControlSha256=$SerializerControlSha256;nativeLaunchesBeforeDispatch=0;retries=$false;metricsEventMissing='diagnostic-only; no synthetic event'}
$dispatch|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $controlRoot ('dispatch-{0}.json' -f $Count))
& (Join-Path $overlayRoot 'capture-fresh-r11-v10.ps1') -Package $plan.compiledHostPackagePath -LockOwner $LockOwner -ProducerRoot $ProducerRoot -ControlRoot $ControlRoot -OutputRoot $OutputRoot -IntegrationGuardPath $IntegrationGuardPath -IntegrationGuardHash $IntegrationGuardHash -FreshGuardControlsPath $FreshGuardControlsPath -FreshGuardControlsHash $FreshGuardControlsHash -RunRoot $RunRoot -CompileReceiptHash $CompileReceiptHash -ExeHash $ExeHash -SerializerControlSha256 $SerializerControlSha256 -Count $Count -IssuedMetadataPath $IssuedMetadataPath -IssuedMetadataHash $IssuedMetadataHash -PreflightOnly:$PreflightOnly
if($PreflightOnly){return}
if(-not (Test-Path -LiteralPath (Join-Path $RunRoot 'native-observation.json') -PathType Leaf)){throw 'Capture produced no observation receipt'}
$dispatch.status='completed-source-bound-observation';$dispatch.nativeLaunchesAfterDispatch=$Count
$dispatch.observationSha256=(Get-FileHash -LiteralPath (Join-Path $RunRoot 'native-observation.json')).Hash.ToLowerInvariant()
$dispatch|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $RunRoot 'dispatch.json')
