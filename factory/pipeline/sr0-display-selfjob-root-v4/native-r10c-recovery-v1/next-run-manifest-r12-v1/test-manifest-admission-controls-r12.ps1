[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$AdmissionManifestPath,
  [Parameter(Mandatory)][string]$ExpectedTaskName,
  [Parameter(Mandatory)][string]$ExpectedRunRoot,
  [Parameter(Mandatory)][string]$ControlRoot
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath($ControlRoot);if(Test-Path -LiteralPath $root){throw 'ControlRoot must be fresh'};[IO.Directory]::CreateDirectory($root)|Out-Null
function Require([bool]$ok,[string]$why){if(-not $ok){throw "admission control rejected: $why"}}
function ReadJson([string]$p){$f=Get-Item -LiteralPath $p -Force;Require (-not $f.PSIsContainer -and ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0 -and $f.Length -le 2097152) 'bounded regular JSON required';[IO.File]::ReadAllText($f.FullName)|ConvertFrom-Json}
function Validate-Admission([object]$m,[string]$task,[string]$runRoot){
 Require ([string]$m.schema -eq 'sr0-display-selfjob-v5-one-shot-admission-r12') 'admission schema'
 Require ([string]$m.candidateLineage -eq 'native-r10c-recovery-v1-r12') 'candidate lineage'
 Require ([string]$m.taskName -eq $task -and [string]$m.tag -eq $task) 'task/tag owner join'
 Require ([IO.Path]::GetFullPath([string]$m.runRoot) -ceq [IO.Path]::GetFullPath($runRoot)) 'run root join'
 Require ([bool]$m.noActivate -and [bool]$m.noResources -and [bool]$m.killOnJobClose -eq $false) 'desktop/job flags'
 Require ([int]$m.runs -eq 1 -and [int]$m.warmup -eq 10 -and [int]$m.measure -eq 60 -and [int]$m.rows -eq 200 -and [double]$m.keyRate -eq 10) 'workload bounds'
 Require ([int]$m.deadlineSeconds -eq 900 -and [int]$m.pollSeconds -eq 1) 'deadline/poll bounds'
 Require ([int64]$m.aggregateJobMemoryLimitBytes -eq 1073741824 -and [int]$m.aggregateLimitFlags -eq 512) 'memory bounds'
 Require ([string]$m.workloadExeSha256 -match '^[0-9a-fA-F]{64}$' -and [string]$m.rendererDllSha256 -match '^[0-9a-fA-F]{64}$' -and [string]$m.presentMonSha256 -match '^[0-9a-fA-F]{64}$') 'binary hashes'
 foreach($field in @('workloadExe','rendererDll','presentMonExe','sourceRowsPath','controlRoot','controlReceiptRoot','resultFile','memoryReceiptPath','startReceiptPath','coordinatorOutputPath','launcherReceiptPath')){Require (-not [string]::IsNullOrWhiteSpace([string]$m.$field)) "required path field: $field"}
}
$base=ReadJson $AdmissionManifestPath;$cases=@();$passed=0
function Case([string]$name,[scriptblock]$mutate,[bool]$expected){$dst=Join-Path $root ($name+'.json');$m=ReadJson $AdmissionManifestPath;&$mutate $m;[IO.File]::WriteAllText($dst,($m|ConvertTo-Json -Depth 24),[Text.UTF8Encoding]::new($false));$ok=$false;$detail='';try{Validate-Admission (ReadJson $dst) $ExpectedTaskName $ExpectedRunRoot;$ok=$true}catch{$detail=[string]$_.Exception.Message};$pass=($ok -eq $expected);$script:cases+=[ordered]@{name=$name;accepted=$ok;expectedAccepted=$expected;passed=$pass;detail=$detail};if(-not $pass){throw "control failed: $name"};if($pass){$script:passed++}}
Validate-Admission $base $ExpectedTaskName $ExpectedRunRoot;$cases+=[ordered]@{name='positive-admission';accepted=$true;expectedAccepted=$true;passed=$true};$passed++
Case 'wrong-task' {$args[0].taskName='foreign-task'} $false
Case 'wrong-tag' {$args[0].tag='foreign-task'} $false
Case 'wrong-owner-runroot' {$args[0].runRoot=(Join-Path $root 'foreign-run')} $false
Case 'wrong-deadline' {$args[0].deadlineSeconds=901} $false
Case 'wrong-memory' {$args[0].aggregateJobMemoryLimitBytes=536870912} $false
Case 'wrong-flags' {$args[0].aggregateLimitFlags=256} $false
Case 'wrong-noactivate' {$args[0].noActivate=$false} $false
Case 'wrong-binary-hash' {$args[0].workloadExeSha256='0'*64} $false
Case 'missing-runroot' {$args[0].runRoot=$null} $false
$receipt=[ordered]@{kind='sr0-display-selfjob-r12-admission-controls';status='passed-source-controls';cases=$cases.Count;passed=$passed;nativeActions=0;lockActions=0;qualificationClaim=$false;controlRoot=$root};$receipt|ConvertTo-Json -Depth 12;exit 0
