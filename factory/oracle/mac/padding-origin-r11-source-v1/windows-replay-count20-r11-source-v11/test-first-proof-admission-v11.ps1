# Headless source control for explicit Count1 admission-root forwarding.
# Config supplies actual frozen paths/hashes; this control never starts native work.
param([Parameter(Mandatory=$true)][string]$ConfigPath)
$ErrorActionPreference='Stop'
$cfg=Get-Content -Raw -LiteralPath $ConfigPath|ConvertFrom-Json
if(-not(Test-Path -LiteralPath $cfg.coordinatorPath -PathType Leaf)){throw 'Coordinator source missing'}
if(-not(Test-Path -LiteralPath $cfg.controlRoot -PathType Container)){throw 'Control root missing'}
$coordHash=(Get-FileHash -LiteralPath $cfg.coordinatorPath).Hash.ToLowerInvariant()
if($coordHash -cne $cfg.coordinatorSha256){throw 'Coordinator source hash drift'}
$common=@{
 CompileReceiptHash=$cfg.compileReceiptHash;ExeHash=$cfg.exeHash;SerializerControlSha256=$cfg.serializerControlSha256
 IssuedMetadataPath=$cfg.issuedMetadataPath;IssuedMetadataHash=$cfg.issuedMetadataHash
 GuardControlsPath=$cfg.guardControlsPath;GuardControlsHash=$cfg.guardControlsHash
 MacSchemaReceiptPath=$cfg.macSchemaReceiptPath;MacSchemaReceiptHash=$cfg.macSchemaReceiptHash
 ProducerRoot=$cfg.producerRoot;ControlRoot=$cfg.controlRoot;RunRoot=$cfg.runRoot;OutputRoot=$cfg.outputRoot
 FreshGuardControlsPath=$cfg.freshGuardControlsPath;FreshGuardControlsHash=$cfg.freshGuardControlsHash
 IntegrationGuardPath=$cfg.integrationGuardPath;IntegrationGuardHash=$cfg.integrationGuardHash
 SchemaPath=$cfg.schemaPath;Count=20;PreflightOnly=$true
}
function Invoke-Admission([string]$Label,[string]$Root,[bool]$ExpectedPass){
 if([string]::IsNullOrWhiteSpace($Root)){throw ($Label+' root missing from control config')}
 $args=@{}+$common; $args['AdmissionRoot']=$Root
 $failed=$false
 try { $output=& $cfg.coordinatorPath @args 2>&1; if(-not $?){$failed=$true} } catch { $failed=$true }
 $passed=(-not $failed)
 if($passed -ne $ExpectedPass){throw ($Label+' admission expectation failed')}
 if($passed){
  $receipt=Get-Content -Raw -LiteralPath (Join-Path $cfg.controlRoot 'coordinator-preflight.json')|ConvertFrom-Json
  if($receipt.status -ne 'passed-source-only' -or $receipt.nativeWindowActions -ne 0 -or $receipt.compilerActions -ne 0 -or $receipt.guiActions -ne 0 -or $receipt.remoteActions -ne 0 -or $receipt.lockActions -ne 0){throw ($Label+' preflight effects/receipt mismatch')}
 }
 [ordered]@{name=$Label;accepted=$passed;nativeWindowActions=0;compilerActions=0;guiActions=0;remoteActions=0;lockActions=0}
}
$canonicalAdmission=[IO.Path]::GetFullPath($cfg.admissionRoot)
$staleAdmission=[IO.Path]::GetFullPath($cfg.staleAdmissionRoot)
if($canonicalAdmission -ceq $staleAdmission -or -not(Test-Path -LiteralPath $staleAdmission -PathType Container)){throw 'Stale admission root must be distinct existing source root'}
$results=@()
$results+=Invoke-Admission 'correct-admission-root' $cfg.admissionRoot $true
$results+=Invoke-Admission 'wrong-admission-root' $cfg.wrongAdmissionRoot $false
$results+=Invoke-Admission 'missing-admission-root' $cfg.missingAdmissionRoot $false
$results+=Invoke-Admission 'stale-admission-root' $cfg.staleAdmissionRoot $false
[ordered]@{kind='factory-first-proof-admission-controls-v1';status='passed-source-only';controls=$results;nativeWindowActions=0;compilerActions=0;guiActions=0;remoteActions=0;lockActions=0}|ConvertTo-Json -Depth 8
