# Production-function controls for diagnostic branch; root runs on Windows.
[CmdletBinding()]param([Parameter(Mandatory=$true)][string]$GuardPath,[Parameter(Mandatory=$true)][string]$SourceInputsPath,[Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop';. $GuardPath
$si=Get-DiagnosticJson $SourceInputsPath
function Clone($x){$x|ConvertTo-Json -Depth 40|ConvertFrom-Json}
function Reject([string]$Name,[scriptblock]$Mutate){$x=Clone $si;& $Mutate $x;$ok=$false;try{Assert-CircleDiagnosticSourceInputs $Root $x|Out-Null}catch{$ok=$true};if(-not $ok){throw "accepted diagnostic source fault: $Name"};return [ordered]@{name=$Name;rejected=$true}}
function Reject-RunRoot([string]$Name,[string]$OutputRoot,[string]$RunRoot){$ok=$false;try{Assert-CircleNestedRunRoot $OutputRoot $RunRoot|Out-Null}catch{$ok=$true};if(-not $ok){throw "accepted run-root fault: $Name"};return [ordered]@{name=$Name;rejected=$true}}
$nested=Assert-CircleNestedRunRoot 'C:\stage\native' 'C:\stage\native\replays\r1';if($nested -cne 'C:\stage\native\replays\r1'){throw 'nested run-root baseline mismatch'}
$rows=@();$rows+=Reject-RunRoot 'sibling' 'C:\stage\native' 'C:\stage\replays\r1';$rows+=Reject-RunRoot 'outside' 'C:\stage\native' 'C:\other\r1';$rows+=Reject-RunRoot 'equal' 'C:\stage\native' 'C:\stage\native';$rows+=Reject 'kind' {$args[0].kind='factory-circle-source-inputs-v1'};$rows+=Reject 'count' {$args[0].count=20};$rows+=Reject 'candidate' {$args[0].candidate='swiftui.circle.fixed.pilot-next'};$rows+=Reject 'case' {$args[0].caseID='fault-case'};$rows+=Reject 'source' {$args[0].sourceHash='sha256:'+'0'*64};$rows+=Reject 'tuple' {$args[0].tupleID='fault-tuple'};$rows+=Reject 'plan' {$args[0].planHash='0'*64};$rows+=Reject 'compile' {$args[0].compileReceiptHash='0'*64};$rows+=Reject 'exe' {$args[0].exeHash='0'*64};$rows+=Reject 'renderer' {$args[0].rendererSha256='0'*64};$rows+=Reject 'budget' {$args[0].serializerControlSha256='0'*64}
$plan=Get-DiagnosticJson $si.planRef.path;$receipt=Get-DiagnosticJson $si.receiptRef.path;$tuple=Get-DiagnosticJson $si.tupleRef.path
$dispatchMode=Assert-CircleDiagnosticDispatchPlan $plan $si 1
if($dispatchMode -ne 'diagnostic-final-eligible' -and $dispatchMode -ne 'legacy-dispatch-first'){throw 'baseline diagnostic dispatch admission missing'}
function RejectDispatch([string]$Name,[scriptblock]$Mutate,[int]$N=1){$p=Clone $plan;$x=Clone $si;& $Mutate $p $x;$ok=$false;try{Assert-CircleDiagnosticDispatchPlan $p $x $N|Out-Null}catch{$ok=$true};if(-not $ok){throw "accepted diagnostic dispatch fault: $Name"};return [ordered]@{name=$Name;rejected=$true}}
$rows+=RejectDispatch 'missing-eligibility' {$args[0].executionEligible=$false}
$rows+=RejectDispatch 'wrong-phase' {$args[0].phase='prebuild'}
$rows+=RejectDispatch 'candidate' {$args[0].candidate='swiftui.circle.fixed.pilot-next'}
$rows+=RejectDispatch 'count20' {$args[0].candidate=$args[0].candidate} 20
function RejectPlan([string]$Name,[scriptblock]$Mutate){$p=Clone $plan;$r=Clone $receipt;$t=Clone $tuple;& $Mutate $p $r $t;$ok=$false;try{Assert-CircleDiagnosticPlanReceipt $si $p $r $t|Out-Null}catch{$ok=$true};if(-not $ok){throw "accepted diagnostic plan/receipt fault: $Name"};return [ordered]@{name=$Name;rejected=$true}}
$rows+=RejectPlan 'plan-kind' {$args[0].kind='factory-circle-compiler-plan-v1'};$rows+=RejectPlan 'receipt-kind' {$args[1].kind='factory-circle-owned-compile-v1'};$rows+=RejectPlan 'qualification' {$args[0].qualification='qualified'};$rows+=RejectPlan 'job-flags' {$args[1].jobFlags=0};$rows+=RejectPlan 'active-processes' {$args[1].jobActiveCount=1};$rows+=RejectPlan 'native-actions' {$args[1].nativeActions=1}
[ordered]@{kind='factory-circle-diagnostic-controls-v1';status='passed-source-only';faults=$rows;nativeActions=0;compilerActions=0;lockActions=0}|ConvertTo-Json -Depth 8
