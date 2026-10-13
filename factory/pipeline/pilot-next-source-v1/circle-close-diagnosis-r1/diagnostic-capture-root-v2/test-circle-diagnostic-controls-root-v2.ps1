# Production-function controls for incremental Circle diagnostic branch.
# Root runs this after source admission, before lock/native action.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$GuardPath,[Parameter(Mandatory=$true)][string]$SourceInputsPath,[Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop';. $GuardPath
$si=Get-DiagnosticJson $SourceInputsPath
function Clone([object]$Value){$Value|ConvertTo-Json -Depth 64|ConvertFrom-Json}
function Reject-Source([string]$Name,[scriptblock]$Mutate){$x=Clone $si;& $Mutate $x;$rejected=$false;try{Assert-CircleDiagnosticSourceInputs $Root $x|Out-Null}catch{$rejected=$true};if(-not $rejected){throw "accepted source fault: $Name"};[ordered]@{name=$Name;rejected=$true}}
function Reject-Plan([string]$Name,[scriptblock]$Mutate){$p=Get-DiagnosticJson $si.planRef.path;$r=Get-DiagnosticJson $si.receiptRef.path;$t=Get-DiagnosticJson $si.tupleRef.path;& $Mutate $p $r $t;$rejected=$false;try{Assert-CircleDiagnosticPlanReceipt $si $p $r $t|Out-Null}catch{$rejected=$true};if(-not $rejected){throw "accepted plan fault: $Name"};[ordered]@{name=$Name;rejected=$true}}
$rows=@()
$rows+=Reject-Source 'kind' {$args[0].kind='factory-circle-source-inputs-v1'}
$rows+=Reject-Source 'count' {$args[0].count=20}
$rows+=Reject-Source 'candidate' {$args[0].candidate='swiftui.circle.fixed.pilot-next'}
$rows+=Reject-Source 'case-id' {$args[0].caseID='fault-case'}
$rows+=Reject-Source 'case-hash' {$args[0].caseHash='sha256:'+'0'*64}
$rows+=Reject-Source 'source-hash' {$args[0].sourceHash='sha256:'+'0'*64}
$rows+=Reject-Source 'tuple-id' {$args[0].tupleID='fault-tuple'}
$rows+=Reject-Source 'plan-hash' {$args[0].planHash='0'*64}
$rows+=Reject-Source 'compile-hash' {$args[0].compileReceiptHash='0'*64}
$rows+=Reject-Source 'exe-hash' {$args[0].exeHash='0'*64}
$rows+=Reject-Source 'renderer-hash' {$args[0].rendererSha256='0'*64}
$rows+=Reject-Source 'runtime-commit' {$args[0].runtimeSourceCommit='fault-runtime'}
$rows+=Reject-Source 'serializer-hash' {$args[0].serializerControlSha256='0'*64}
$rows+=Reject-Source 'binding-ref' {$args[0].bindingRef.sha256='sha256:'+'0'*64}
$rows+=Reject-Source 'context-ref' {$args[0].contextRef.path='fault/context.json'}
$rows+=Reject-Plan 'plan-kind' {$args[0].kind='factory-circle-compiler-plan-v1'}
$rows+=Reject-Plan 'candidate' {$args[0].candidate='swiftui.circle.fixed.recipe'}
$rows+=Reject-Plan 'execution-eligibility' {$args[0].executionEligible=$false}
$rows+=Reject-Plan 'receipt-kind' {$args[1].kind='factory-circle-owned-compile-v1'}
$rows+=Reject-Plan 'receipt-plan-hash' {$args[1].planSha256='0'*64}
$rows+=Reject-Plan 'native-actions' {$args[1].nativeActions=1}
$rows+=Reject-Plan 'active-job' {$args[1].jobActiveCount=1}
$rows+=Reject-Plan 'stream-seal' {$args[1].streamsSealed=$false}
if($rows.Count -ne 23){throw "unexpected control count: $($rows.Count)"}
[ordered]@{kind='factory-circle-incremental-diagnostic-controls-v2';status='SOURCE_CONTROLS_PASS';faults=$rows;faultCount=$rows.Count;nativeActions=0;compilerActions=0;lockActions=0}|ConvertTo-Json -Depth 12
