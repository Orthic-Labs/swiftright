<#
Runs frozen Assert-LeaseIssuedMetadata against one real root-issued metadata file,
then against resealed one-field mutations. No process launch, Add-Type, GUI, lock,
compiler, remote, or cleanup action is permitted.
#>
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$IssuedMetadataPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$IssuedMetadataHash,
 [Parameter(Mandatory=$true)][string]$RunRoot,
 [Parameter(Mandatory=$true)][ValidateSet(1,20)][int]$Count,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$CompileHash,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExeHash,
 [Parameter(Mandatory=$true)][string]$SerializerHash,
 [Parameter(Mandatory=$true)][string]$ProducerRoot,
 [Parameter(Mandatory=$true)][string]$ControlRoot,
 [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop'
$nativeWindowActions=0
$integration=Join-Path $PSScriptRoot '..\support\integration.ps1'
if(-not(Test-Path -LiteralPath $integration -PathType Leaf)){throw 'Frozen integration source missing'}
$integrationText=Get-Content -Raw -LiteralPath $integration
foreach($expectedGuardError in @(
 'Issued metadata admitted context mismatch',
 'Issued metadata source/template boundary mismatch',
 'Issued actual runtime module metadata mismatch'
)){
 if($integrationText.IndexOf($expectedGuardError,[System.StringComparison]::Ordinal) -lt 0){throw ('Frozen integration guard error missing: '+$expectedGuardError)}
}
. $integration
if(-not(Test-Path -LiteralPath $IssuedMetadataPath -PathType Leaf)){throw 'Issued metadata missing'}
$actualIssuedHash=(Get-FileHash -LiteralPath $IssuedMetadataPath -Algorithm SHA256).Hash.ToLowerInvariant()
if($actualIssuedHash -cne $IssuedMetadataHash){throw 'Issued metadata caller hash mismatch'}
if(Test-Path -LiteralPath $OutputPath){throw 'Controls output already exists'}
if(Test-Path -LiteralPath $ControlRoot){throw 'Fresh control root required; refusing overwrite'}
New-Item -ItemType Directory -Force -Path $ControlRoot | Out-Null
function Raw-Ref([string]$Path){
 $item=Get-Item -LiteralPath $Path
 return [ordered]@{path=$Path;sha256=('sha256:'+(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant());bytes=[int64]$item.Length}
}
function Write-Json([object]$Value,[string]$Path){
 $json=$Value|ConvertTo-Json -Depth 100
 Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}
function Prepare-Case([string]$Name){
 $caseRoot=Join-Path $ControlRoot $Name
 New-Item -ItemType Directory -Force -Path $caseRoot | Out-Null
 $srcRoot=Split-Path -Parent $IssuedMetadataPath
 $tupleSource=Join-Path $srcRoot 'candidate-tuple.json'
 $bindingSource=Join-Path $srcRoot 'candidate-binding.json'
 foreach($src in @($IssuedMetadataPath,$tupleSource,$bindingSource)){if(-not(Test-Path -LiteralPath $src -PathType Leaf)){throw ('Issued sibling missing: '+$src)}}
 $metadataPath=Join-Path $caseRoot 'issued-metadata.json'
 $tuplePath=Join-Path $caseRoot 'candidate-tuple.json'
 $bindingPath=Join-Path $caseRoot 'candidate-binding.json'
 Copy-Item -LiteralPath $IssuedMetadataPath -Destination $metadataPath
 Copy-Item -LiteralPath $tupleSource -Destination $tuplePath
 Copy-Item -LiteralPath $bindingSource -Destination $bindingPath
 return [pscustomobject]@{root=$caseRoot;metadataPath=$metadataPath;tuplePath=$tuplePath;bindingPath=$bindingPath;metadata=(Get-Content -Raw -LiteralPath $metadataPath|ConvertFrom-Json);tuple=(Get-Content -Raw -LiteralPath $tuplePath|ConvertFrom-Json);binding=(Get-Content -Raw -LiteralPath $bindingPath|ConvertFrom-Json)}
}
function Reseal-Case($Case){
 Write-Json $Case.tuple $Case.tuplePath
 $Case.binding.canonicalTupleRef=Raw-Ref $Case.tuplePath
 Write-Json $Case.binding $Case.bindingPath
 $Case.metadata.sourceBoundCandidateTuple=Raw-Ref $Case.bindingPath
 $Case.metadata.candidateTuple=Raw-Ref $Case.tuplePath
 Write-Json $Case.metadata $Case.metadataPath
 return (Get-FileHash -LiteralPath $Case.metadataPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Run-Guard([string]$Path,[string]$Hash){
 try {
  $null=Assert-LeaseIssuedMetadata $Path $Hash $RunRoot $Count $CompileHash $ExeHash $SerializerHash $ProducerRoot
  return [ordered]@{accepted=$true;rejected=$false;nativeWindowActions=$nativeWindowActions}
 } catch {
  return [ordered]@{accepted=$false;rejected=$true;nativeWindowActions=$nativeWindowActions;reason=$_.Exception.Message}
 }
}
$controls=[System.Collections.Generic.List[object]]::new()
$baseline=Run-Guard $IssuedMetadataPath $IssuedMetadataHash
if(-not $baseline.accepted){throw ('Actual issued metadata baseline rejected: '+$baseline.reason)}
$controls.Add([ordered]@{name='admitted-baseline-actual';accepted=$true;rejected=$false;nativeWindowActions=$nativeWindowActions})
# Relocate clean metadata, tuple, and binding through the exact reseal path used by faults.
# This positive proves path relocation itself does not trigger the first context guard.
$relocated=Prepare-Case 'relocated-positive'
$relocatedHash=Reseal-Case $relocated
$relocatedResult=Run-Guard $relocated.metadataPath $relocatedHash
if(-not $relocatedResult.accepted){throw ('Relocated clean positive rejected: '+$relocatedResult.reason)}
$controls.Add([ordered]@{name='admitted-baseline-relocated-resealed';accepted=$true;rejected=$false;nativeWindowActions=$nativeWindowActions;outerMetadataResealed=$true})
$faults=@(
 @{name='metadata-expected-count';expected='Issued metadata admitted context mismatch'},
 @{name='metadata-host-argument';expected='Issued metadata admitted context mismatch'},
 @{name='metadata-source-hash';expected='Issued metadata source/template boundary mismatch'},
 @{name='metadata-serializer-prefix';expected='Issued metadata admitted context mismatch'},
 @{name='metadata-runtime-modules';expected='Issued actual runtime module metadata mismatch'},
 @{name='tuple-case';expected='candidate-guard:case'},
 @{name='tuple-runtime';expected='candidate-guard:runtime'},
 @{name='tuple-renderer';expected='candidate-guard:renderer'},
 @{name='binding-frozen';expected='candidate-guard:tuple-ref'},
 @{name='binding-canonical-input-hash';expected='Candidate binding raw/source joins missing'},
 @{name='mac-context-path';expected='Mac context source ref missing'}
)
foreach($fault in $faults){
 $case=Prepare-Case $fault.name
 switch($fault.name){
  'metadata-expected-count' { $case.metadata.expectedCount=$Count+1 }
  'metadata-host-argument' { $case.metadata.hostArguments=@('--factory-capture-lease-seconds=41') }
  'metadata-source-hash' { $case.metadata.sourceHash=('0'*64) }
  'metadata-serializer-prefix' { $case.metadata.serializerControlSha256='sha256:'+ $SerializerHash }
  'metadata-runtime-modules' { $case.metadata.producedRuntimeModules=[pscustomobject]@{mutated=$true} }
  'tuple-case' { $case.tuple.case.id='mutated-case-id' }
  'tuple-runtime' { $case.tuple.tuple.runtimeCommit=('0'*40) }
  'tuple-renderer' { $case.tuple.tuple.rendererHash='sha256:'+('0'*64) }
  'binding-frozen' { $case.binding.frozenTupleBound=$true }
  'binding-canonical-input-hash' { $case.binding.canonicalInputs.sha256='sha256:'+('0'*64) }
  'mac-context-path' { $case.tuple.sourceInputs.macContext_capture_index.path='factory/oracle/mac/mutated.json' }
 }
 $hash=Reseal-Case $case
 $result=Run-Guard $case.metadataPath $hash
 if(-not $result.rejected -or $result.reason -notlike ('*'+$fault.expected+'*')){throw ('Fault control failed: '+$fault.name+' => '+[string]$result.reason)}
 $controls.Add([ordered]@{name=$fault.name;accepted=$false;rejected=$true;reason=$result.reason;nativeWindowActions=$nativeWindowActions;outerMetadataResealed=$true})
}
$result=[ordered]@{kind='factory-issued-metadata-full-guard-controls-v1';status='passed-source-only';frozenIntegrationPath=$integration;issuedMetadataPath=$IssuedMetadataPath;issuedMetadataSha256=$IssuedMetadataHash;count=$Count;baseline=$controls[0];faultControls=@($controls|Select-Object -Skip 1);nativeWindowActions=$nativeWindowActions;compilerActions=0;guiActions=0;remoteActions=0;lockActions=0;qualification='hold'}
Write-Json $result $OutputPath
$result|ConvertTo-Json -Depth 20
