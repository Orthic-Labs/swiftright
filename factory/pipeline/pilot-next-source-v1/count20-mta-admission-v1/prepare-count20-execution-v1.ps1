# Prepare fresh Count20 coordinator configuration after issuer admission.
# Source-only: validates existing issuer/coordinator contracts & writes no native state.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$AdmissionPath,
 [Parameter(Mandatory=$true)][string]$SourceInputsPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$SourceInputsHash,
 [Parameter(Mandatory=$true)][string]$IssuedMetadataPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$IssuedMetadataHash,
 [Parameter(Mandatory=$true)][string]$IssuerPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$IssuerHash,
 [Parameter(Mandatory=$true)][string]$CoordinatorPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$CoordinatorHash,
 [Parameter(Mandatory=$true)][string]$Package,
 [Parameter(Mandatory=$true)][string]$ProducerRoot,
 [Parameter(Mandatory=$true)][string]$AdmissionRoot,
 [Parameter(Mandatory=$true)][string]$OverlayRoot,
 [Parameter(Mandatory=$true)][string]$ControlRoot,
 [Parameter(Mandatory=$true)][string]$OutputRoot,
 [Parameter(Mandatory=$true)][string]$RunRoot,
 [Parameter(Mandatory=$true)][string]$IntegrationGuardPath,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$IntegrationGuardHash,
 [Parameter(Mandatory=$true)][string]$OutputPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-BoundedItem([string]$Path,[int64]$Limit=4194304){
 $i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($i.PSIsContainer -or $i.LinkType -or (($i.Attributes-band [IO.FileAttributes]::ReparsePoint)-ne 0) -or $i.Length -gt $Limit){throw ('Bounded regular source required: '+$Path)}
 return $i
}
function Get-StreamHash([string]$Path,[int64]$Limit=67108864){
 $i=Get-BoundedItem $Path $Limit;$stream=$null;$sha=$null;$total=0L
 try{
  $stream=[IO.File]::Open($i.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$sha=[Security.Cryptography.SHA256]::Create();$buffer=New-Object byte[] 1048576
  while(($read=$stream.Read($buffer,0,$buffer.Length))-gt 0){$sha.TransformBlock($buffer,0,$read,$buffer,0)|Out-Null;$total+=$read;if($total -gt $Limit){throw 'Hash limit exceeded'}}
  $sha.TransformFinalBlock($buffer,0,0)|Out-Null;if($total -ne [int64]$i.Length){throw ('Input changed while hashing: '+$Path)}
  return ([BitConverter]::ToString($sha.Hash)-replace '-','').ToLowerInvariant()
 }finally{if($sha){$sha.Dispose()};if($stream){$stream.Dispose()}}
}
function Read-BoundedJson([string]$Path){$i=Get-BoundedItem $Path 4194304;return [IO.File]::ReadAllText($i.FullName,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json}
function Require-Hash([string]$Path,[string]$Expected,[int64]$Limit=67108864){$actual=Get-StreamHash $Path $Limit;if($actual -cne (($Expected-replace '^sha256:','').ToLowerInvariant())){throw ('Hash mismatch: '+$Path)};return $actual}
function Require-Path([string]$Path,[string]$Name,[int64]$Limit=67108864){[void](Get-BoundedItem $Path $Limit);if([string]::IsNullOrWhiteSpace($Path)){throw ($Name+' missing')};return [IO.Path]::GetFullPath($Path)}
function Reject-StaleAlias([string]$Value,[string]$Name){if($Value -match '(?i)(actual-single-r1|coordinator-single-r1|actual-repeat-r1|coordinator-repeat-r1|capture-count1)'){throw ($Name+' points at stale Count1/legacy namespace')}}
function Require-Count20Capture([object]$Issued,[string]$RunRoot){
 if($Issued.kind -cne 'factory-prelaunch-capture-metadata-v2' -or $Issued.version -ne 2 -or $Issued.expectedCount -ne 20){throw 'Issued metadata is not Count20 v2'}
 if([IO.Path]::GetFullPath([string]$Issued.runRoot) -cne [IO.Path]::GetFullPath($RunRoot)){throw 'Issued metadata runRoot mismatch'}
 $captures=@($Issued.captures);if($captures.Count -ne 20){throw 'Issued metadata must contain 20 captures'}
 for($n=1;$n -le 20;$n++){$row=@($captures|Where-Object{$_.run -eq $n});if($row.Count -ne 1 -or [string]$row[0].captureID -notmatch '^capture/[0-9a-f]{32}$' -or [string]$row[0].imageID -notmatch '^image/[0-9a-f]{32}$'){throw ('Count20 issuance identity mismatch: '+$n)}}
}

$admission=Read-BoundedJson $AdmissionPath
if($admission.status -ne 'source-admitted-pending-count20-metadata-and-native' -or $admission.count -ne 20){throw 'Count20 admission packet not source-admitted'}
$mtaAdmitted=$false;if($admission.PSObject.Properties.Name -contains 'closure' -and $null -ne $admission.closure -and $admission.closure.PSObject.Properties.Name -contains 'requireMtaInvoker'){$mtaAdmitted=($admission.closure.requireMtaInvoker -eq $true)};if(-not $mtaAdmitted -and $admission.PSObject.Properties.Name -contains 'workerContract' -and $null -ne $admission.workerContract -and $admission.workerContract.PSObject.Properties.Name -contains 'mtaInvoker'){$mtaAdmitted=($null -ne $admission.workerContract.mtaInvoker)};if(-not $mtaAdmitted){throw 'MTA worker closure is not admitted'}
$si=Read-BoundedJson $SourceInputsPath
$siHash=Require-Hash $SourceInputsPath $SourceInputsHash 4194304
if($si.count -ne 20){throw 'Source inputs count must be 20'}
foreach($name in @('caseID','caseHash','sourceHash','tupleID','planHash','compileReceiptHash','tupleHash','bindingHash','recipeHash','exeHash','runtimeSourceCommit','rendererPath','rendererSha256','serializerControlSha256','contextRef','rendererRef','exeRef','integrationBindingsRef','integrationBindingsHash')){if([string]::IsNullOrWhiteSpace([string]$si.$name)){throw ('Source input missing: '+$name)}}
$issued=Read-BoundedJson $IssuedMetadataPath
$issuedHash=Require-Hash $IssuedMetadataPath $IssuedMetadataHash 4194304
Require-Count20Capture $issued $RunRoot
if([string]$issued.sourceHash -cne [string]$si.sourceHash -or [string]$issued.case.id -cne [string]$si.caseID -or [string]$issued.case.hash -cne [string]$si.caseHash){throw 'Issued/source/case join mismatch'}
$issuerFull=Require-Path $IssuerPath 'IssuerPath';$issuerMeasured=Require-Hash $issuerFull $IssuerHash
$coordFull=Require-Path $CoordinatorPath 'CoordinatorPath';$coordMeasured=Require-Hash $coordFull $CoordinatorHash
$guardFull=Require-Path $IntegrationGuardPath 'IntegrationGuardPath';$guardMeasured=Require-Hash $guardFull $IntegrationGuardHash
$lifecycleSources=@($admission.lifecycleSources);if($lifecycleSources.Count -eq 0){throw 'Admission packet has no staged Count20 lifecycle sources'}
foreach($row in $lifecycleSources){if([string]::IsNullOrWhiteSpace([string]$row.path)-or [string]::IsNullOrWhiteSpace([string]$row.sha256)-or [int64]$row.bytes -le 0){throw 'Admission lifecycle source row incomplete'}}
foreach($name in @('Package','ProducerRoot','AdmissionRoot','OverlayRoot','ControlRoot','OutputRoot','RunRoot')){Reject-StaleAlias ([string](Get-Variable $name).Value) $name}
$config=[ordered]@{
 count=20;sourceBindings=$lifecycleSources;package=[IO.Path]::GetFullPath($Package);producerRoot=[IO.Path]::GetFullPath($ProducerRoot);admissionRoot=[IO.Path]::GetFullPath($AdmissionRoot);overlayRoot=[IO.Path]::GetFullPath($OverlayRoot);controlRoot=[IO.Path]::GetFullPath($ControlRoot);outputRoot=[IO.Path]::GetFullPath($OutputRoot);runRoot=[IO.Path]::GetFullPath($RunRoot);sourceInputsPath=[IO.Path]::GetFullPath($SourceInputsPath);sourceInputsHash=$siHash;issuedMetadataPath=[IO.Path]::GetFullPath($IssuedMetadataPath);issuedMetadataHash=$issuedHash;compileReceiptHash=[string]$si.compileReceiptHash;exeHash=[string]$si.exeHash;serializerControlSha256=[string]$si.serializerControlSha256;integrationGuardPath=$guardFull;integrationGuardHash=$guardMeasured;count1ProofPath=$null;count1ProofHash=$null;issuer=[ordered]@{path=$issuerFull;sha256=$issuerMeasured;bytes=[int64](Get-BoundedItem $issuerFull).Length};coordinator=[ordered]@{path=$coordFull;sha256=$coordMeasured;bytes=[int64](Get-BoundedItem $coordFull).Length};admission=[ordered]@{path=[IO.Path]::GetFullPath($AdmissionPath);sha256=(Get-StreamHash $AdmissionPath);bytes=[int64](Get-BoundedItem $AdmissionPath).Length};nativeActions=0;compilerActions=0;remoteActions=0;lockActions=0;status='prepared-source-only-count20-pending-root-execution'}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));New-Item -ItemType Directory -Force -Path $parent|Out-Null;if(Test-Path -LiteralPath $OutputPath){throw 'Execution output refuses overwrite'}
$config|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output ([IO.Path]::GetFullPath($OutputPath))
