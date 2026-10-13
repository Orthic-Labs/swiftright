# Source controls for Circle final-plan predicate; no native, lock, compiler or file effects.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'final-plan-eligibility.ps1')
$baseline=[pscustomobject]@{kind='factory-circle-compiler-plan-v1';phase='final';executionEligible=$true}
$cases=@(
 @{name='baseline';plan=$baseline;accept=$true},
 @{name='prebuild-phase';plan=[pscustomobject]@{kind='factory-circle-compiler-plan-v1';phase='prebuild';executionEligible=$true};accept=$false},
 @{name='ineligible';plan=[pscustomobject]@{kind='factory-circle-compiler-plan-v1';phase='final';executionEligible=$false};accept=$false},
 @{name='wrong-kind';plan=[pscustomobject]@{kind='factory-text-compiler-plan-v1';phase='final';executionEligible=$true};accept=$false},
 @{name='explicit-wrong-host';plan=[pscustomobject]@{kind='factory-circle-compiler-plan-v1';phase='final';executionEligible=$true;hostMode='prebuild'};accept=$false},
 @{name='missing-phase';plan=[pscustomobject]@{kind='factory-circle-compiler-plan-v1';executionEligible=$true};accept=$false}
)
$out=@()
foreach($case in $cases){
 $accepted=$false;$reason=''
 try{Assert-CircleFinalPlanAdmission $case.plan|Out-Null;$accepted=$true}catch{$reason=[string]$_}
 if($accepted -ne $case.accept){throw ('Circle eligibility fault escaped: '+$case.name)}
 $out+=([ordered]@{name=$case.name;accepted=$accepted;reason=$reason})
}
([ordered]@{kind='factory-circle-final-plan-eligibility-controls-v1';status='SOURCE_CONTROLS_PASS';nativeActions=0;cases=$out}|ConvertTo-Json -Depth 8)
