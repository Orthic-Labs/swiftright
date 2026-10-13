[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$IssuedMetadataPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$IssuedMetadataHash,
 [Parameter(Mandatory=$true)][string]$RunRoot,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$CompileHash,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExeHash,
 [Parameter(Mandatory=$true)][string]$SerializerHash,
 [Parameter(Mandatory=$true)][string]$ProducerRoot,
 [Parameter(Mandatory=$true)][string]$ControlRoot,
 [Parameter(Mandatory=$true)][string]$OutputPath,
 [Parameter(Mandatory=$true)][string]$IntegrationScript
)
$ErrorActionPreference='Stop'
$nativeWindowActions=0
if([IO.Path]::IsPathRooted($ControlRoot) -eq $false){throw 'ControlRoot must be absolute'}
$controlFull=[IO.Path]::GetFullPath($ControlRoot)
if($controlFull -notmatch '(?i)\\\.factory-work\\' -or $controlFull -match '(?i)\\\.factory-work\\?$'){throw 'ControlRoot must be fresh repo-owned .factory-work child'}
if(Test-Path -LiteralPath $controlFull){throw 'Fresh control root required; refusing overwrite'}
if(Test-Path -LiteralPath $OutputPath){throw 'Controls output already exists'}
if(-not(Test-Path -LiteralPath $IntegrationScript -PathType Leaf)){throw 'Integration source missing'}
. (Get-Item -LiteralPath $IntegrationScript).FullName
if(-not(Test-Path -LiteralPath $IssuedMetadataPath -PathType Leaf)){throw 'Issued metadata missing'}
if((Get-FileHash -LiteralPath $IssuedMetadataPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $IssuedMetadataHash){throw 'Issued metadata caller hash mismatch'}
New-Item -ItemType Directory -Force -Path $controlFull|Out-Null
function Write-V7Json($Value,[string]$Path){$Value|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $Path -Encoding UTF8}
function Raw-V7Ref([string]$Path){$i=Get-Item -LiteralPath $Path;[ordered]@{path=$Path;sha256=('sha256:'+(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant());bytes=[int64]$i.Length}}
function New-V7Case([string]$Name){
 $r=Join-Path $controlFull $Name;New-Item -ItemType Directory -Force -Path $r|Out-Null
 $src=Split-Path -Parent $IssuedMetadataPath;$tuple=Join-Path $src 'candidate-tuple.json';$binding=Join-Path $src 'candidate-binding.json'
 foreach($p in @($tuple,$binding)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ('Issued sibling missing: '+$p)}}
 $mp=Join-Path $r 'issued-metadata.json';$tp=Join-Path $r 'candidate-tuple.json';$bp=Join-Path $r 'candidate-binding.json'
 Copy-Item -LiteralPath $IssuedMetadataPath -Destination $mp;Copy-Item -LiteralPath $tuple -Destination $tp;Copy-Item -LiteralPath $binding -Destination $bp
 [pscustomobject]@{root=$r;metadataPath=$mp;tuplePath=$tp;bindingPath=$bp;metadata=(Get-Content -Raw -LiteralPath $mp|ConvertFrom-Json);tuple=(Get-Content -Raw -LiteralPath $tp|ConvertFrom-Json);binding=(Get-Content -Raw -LiteralPath $bp|ConvertFrom-Json)}
}
function Seal-V7Case($Case){
 Write-V7Json $Case.tuple $Case.tuplePath;$Case.binding.canonicalTupleRef=Raw-V7Ref $Case.tuplePath;Write-V7Json $Case.binding $Case.bindingPath
 $Case.metadata.sourceBoundCandidateTuple=Raw-V7Ref $Case.bindingPath;$Case.metadata.candidateTuple=Raw-V7Ref $Case.tuplePath;Write-V7Json $Case.metadata $Case.metadataPath
 (Get-FileHash -LiteralPath $Case.metadataPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Invoke-V7Guard([string]$Path,[string]$Hash){try{$null=Assert-LeaseIssuedMetadata $Path $Hash $RunRoot 20 $CompileHash $ExeHash $SerializerHash $ProducerRoot;[ordered]@{accepted=$true;rejected=$false;nativeWindowActions=$nativeWindowActions}}catch{[ordered]@{accepted=$false;rejected=$true;nativeWindowActions=$nativeWindowActions;reason=$_.Exception.Message}}}
$controls=[System.Collections.Generic.List[object]]::new();$b=Invoke-V7Guard $IssuedMetadataPath $IssuedMetadataHash
if(-not $b.accepted){throw ('Actual issued metadata baseline rejected: '+$b.reason)}
$baseline=[ordered]@{name='admitted-baseline-actual';accepted=$true;rejected=$false;nativeWindowActions=0};$controls.Add($baseline)|Out-Null
$positive=New-V7Case 'relocated-positive';$ph=Seal-V7Case $positive;$pr=Invoke-V7Guard $positive.metadataPath $ph
if(-not $pr.accepted){throw ('Relocated clean positive rejected: '+$pr.reason)}
$controls.Add([ordered]@{name='admitted-baseline-relocated-resealed';accepted=$true;rejected=$false;nativeWindowActions=0;outerMetadataResealed=$true})|Out-Null
$faults=@(
 @{name='metadata-expected-count';expected='Fresh issued metadata context mismatch';apply={param($c)$c.metadata.expectedCount=21}},
 @{name='metadata-host-argument';expected='Fresh issued metadata context mismatch';apply={param($c)$c.metadata.hostArguments=@('--factory-capture-lease-seconds=41')}},
 @{name='metadata-source-hash';expected='Fresh issued metadata context mismatch';apply={param($c)$c.metadata.sourceHash='sha256:'+('0'*64)}},
 @{name='metadata-serializer-prefix';expected='Fresh issued metadata context mismatch';apply={param($c)$c.metadata.serializerControlSha256='sha256:'+$SerializerHash}},
 @{name='metadata-runtime-modules';expected='Issued actual runtime module metadata mismatch';apply={param($c)$c.metadata.producedRuntimeModules=[pscustomobject]@{mutated=$true}}},
 @{name='tuple-case';expected='fresh candidate case mismatch';apply={param($c)$c.tuple.case.id='mutated-case-id'}},
 @{name='tuple-runtime';expected='fresh host/runtime envelope mismatch';apply={param($c)$c.tuple.tuple.runtimeCommit=('0'*40)}},
 @{name='tuple-renderer';expected='fresh host/runtime envelope mismatch';apply={param($c)$c.tuple.tuple.rendererHash='sha256:'+('0'*64)}},
 @{name='binding-frozen';expected='fresh tuple reference mismatch';apply={param($c)$c.binding.frozenTupleBound=$true}},
 @{name='binding-canonical-input-hash';expected='fresh candidate binding source-input hash mismatch';apply={param($c)$c.binding.canonicalInputs.sha256='sha256:'+('0'*64)}},
 @{name='mac-context-path';expected='Mac context source ref mismatch';apply={param($c)$c.tuple.sourceInputs.freshCase.path=$c.tuple.sourceInputs.freshManifest.path;$c.tuple.sourceInputs.freshCase.sha256=$c.tuple.sourceInputs.freshManifest.sha256;$c.tuple.sourceInputs.freshCase.bytes=$c.tuple.sourceInputs.freshManifest.bytes}}
)
foreach($f in $faults){$c=New-V7Case $f.name;& $f.apply $c;$h=Seal-V7Case $c;$r=Invoke-V7Guard $c.metadataPath $h;if(-not $r.rejected -or $r.reason -notlike ('*'+$f.expected+'*')){throw ('Fault control failed: '+$f.name+' => '+[string]$r.reason)};$controls.Add([ordered]@{name=$f.name;accepted=$false;rejected=$true;reason=$r.reason;nativeWindowActions=0;outerMetadataResealed=$true})|Out-Null}
$result=[ordered]@{kind='factory-issued-metadata-full-guard-controls-v1';status='passed-source-only';frozenIntegrationPath=$IntegrationScript;issuedMetadataPath=$IssuedMetadataPath;issuedMetadataSha256=$IssuedMetadataHash;count=20;baseline=$baseline;faultControls=@($controls|Select-Object -Skip 1);nativeWindowActions=0;compilerActions=0;guiActions=0;remoteActions=0;lockActions=0;qualification='hold'}
Write-V7Json $result $OutputPath;$result|ConvertTo-Json -Depth 30
