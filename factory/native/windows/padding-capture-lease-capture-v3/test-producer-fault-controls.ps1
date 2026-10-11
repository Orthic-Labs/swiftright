# Pure production guard controls; no compiler, native window, GUI, lock or remote action.
param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputPath){throw 'Fresh producer-control output required'}
. (Join-Path $PSScriptRoot 'support\integration.ps1')
function Copy-ProducerFixture($x){$x|ConvertTo-Json -Depth 40|ConvertFrom-Json}
$plan=[pscustomobject]@{case=[pscustomobject]@{id='swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258';hash=('sha256:'+'a'*64)};runtimeSourceCommit='37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b';rendererSha256=('b'*64)}
$context=[pscustomobject]@{candidateID='sr1-source-bound-r11-20261011'}
$tuple=[pscustomobject]@{kind='factory-source-bound-candidate-canonical-tuple-v1';version=1;frozenTupleBound=$false;case=$plan.case;tuple=[pscustomobject]@{id=$context.candidateID;runtimeCommit=$plan.runtimeSourceCommit;rendererHash=('sha256:'+$plan.rendererSha256);hostHashes=[pscustomobject]@{windows=('sha256:'+'c'*64);macos='sha256:13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777'};acceptanceConfigHash='sha256:c12eaec44a65627e6f546925664482736bfede7665ab593024c5fcd401998245'};sourceInputs=[pscustomobject]@{canonicalInputs=[pscustomobject]@{};sourceBinding=[pscustomobject]@{};macContext_capture=[pscustomobject]@{}}}
$candidate=[pscustomobject]@{kind='factory-source-bound-candidate-binding-v1';version=1;frozenTupleBound=$false;canonicalTupleRef=[pscustomobject]@{sha256='sha256:'+'d'*64};runtime=[pscustomobject]@{sourceCommit=$plan.runtimeSourceCommit};renderer=[pscustomobject]@{sha256=('sha256:'+$plan.rendererSha256)}}
$metadata=[pscustomobject]@{kind='factory-prelaunch-capture-metadata-v2';version=2;expectedCount=1;frozenTupleBound=$false;historicalTemplateTupleClosed=$false;candidateTuple=[pscustomobject]@{sha256='sha256:'+'d'*64}}
$tupleHash='sha256:'+'d'*64;$compileHash='c'*64;$exeHash='c'*64
$results=@();$actions=0
function Invoke-Positive {
 $script:actions=0;Assert-CandidateMetadataAdmission $metadata $plan $compileHash $exeHash $tuple $candidate $context $tupleHash 1 { $script:actions++ }|Out-Null
 if($script:actions -ne 1){throw 'Positive producer guard did not reach one admitted action'}
 $script:results+=@([ordered]@{name='admitted-baseline';passed=$true;nativeWindowActions=$script:actions;expected='admitted'})
}
function Invoke-Fault([string]$Name,[string]$Expected,[scriptblock]$Mutate){
 $t=Copy-ProducerFixture $tuple;$c=Copy-ProducerFixture $candidate;$m=Copy-ProducerFixture $metadata;$script:actions=0;& $Mutate $t $c $m
 $rejected=$false;$reason=''
 try{Assert-CandidateMetadataAdmission $m $plan $compileHash $exeHash $t $c $context $tupleHash 1 { $script:actions++ }|Out-Null}catch{$rejected=$true;$reason=$_.Exception.Message}
 if(-not $rejected -or $reason -notlike ('*'+$Expected+'*') -or $script:actions -ne 0){throw ('Producer fault control failed: '+$Name+' reason='+$reason+' actions='+$script:actions)}
 $script:results+=@([ordered]@{name=$Name;passed=$true;nativeWindowActions=$script:actions;expected=$Expected;reason=$reason})
}
Invoke-Positive
Invoke-Fault 'wrong-tuple-kind' 'candidate-guard:tuple-kind' {param($t,$c,$m)$t.kind='wrong'}
Invoke-Fault 'wrong-case' 'candidate-guard:case' {param($t,$c,$m)$t.case.id='wrong.case'}
Invoke-Fault 'wrong-runtime' 'candidate-guard:runtime' {param($t,$c,$m)$t.tuple.runtimeCommit='0'*40}
Invoke-Fault 'wrong-renderer' 'candidate-guard:renderer' {param($t,$c,$m)$t.tuple.rendererHash='sha256:'+'f'*64}
Invoke-Fault 'wrong-metadata' 'candidate-guard:metadata' {param($t,$c,$m)$m.frozenTupleBound=$true}

$script:actions=0;$phaseRejected=$false;$phaseReason='';try{Assert-CandidatePhaseAdmission ([pscustomobject]@{phase='pixels-start';nativeWindowActions=0;compilerActions=0})}catch{$phaseRejected=$true;$phaseReason=$_.Exception.Message};if(-not $phaseRejected -or $phaseReason -notlike '*candidate-guard:phase*' -or $script:actions -ne 0){throw 'Producer phase fault control failed'};$script:results+=@([ordered]@{name='wrong-phase';passed=$true;nativeWindowActions=$script:actions;expected='candidate-guard:phase';reason=$phaseReason})
$phase=[pscustomobject]@{phase='close-pending';nativeWindowActions=0;compilerActions=0};Assert-CandidatePhaseAdmission $phase
$script:results+=@([ordered]@{name='phase-baseline';passed=$true;nativeWindowActions=0;expected='close-pending'})
[ordered]@{kind='factory-producer-candidate-fault-controls-v1';status='passed';controls=$results;nativeWindowActions=0;compilerActions=0;guiActions=0;remoteActions=0;lockActions=0}|ConvertTo-Json -Depth 20|Set-Content -Encoding UTF8 $OutputPath
