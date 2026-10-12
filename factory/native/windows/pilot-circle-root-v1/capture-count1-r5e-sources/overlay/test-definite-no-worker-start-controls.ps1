param([Parameter(Mandatory=$true)][string]$ControlRoot,[Parameter(Mandatory=$true)][string]$ValidatorPath,[Parameter(Mandatory=$true)][string]$WorkerInvokerPath,[Parameter(Mandatory=$true)][string]$WorkerContractPath)
Set-StrictMode -Version Latest
. $ValidatorPath
function Write-Json([string]$Path,[object]$Value){$Value|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $Path -Encoding UTF8}
function New-Case([string]$Name){$root=Join-Path $ControlRoot ('definite-no-start-'+$Name+'-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root -Force|Out-Null;$source=Join-Path $root 'source';New-Item -ItemType Directory -Path $source|Out-Null;$invoker=Join-Path $source 'invoke.ps1';$contract=Join-Path $source 'worker-contract.json';[IO.File]::WriteAllText($invoker,[IO.File]::ReadAllText($WorkerInvokerPath),[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllText($contract,[IO.File]::ReadAllText($WorkerContractPath),[Text.UTF8Encoding]::new($false));$receipt=Join-Path $root 'uia-no-start.json';$worker=Join-Path $root 'worker';Write-Json $receipt ([ordered]@{kind='factory-uia-slot-no-start-v1';root=$worker;lockOwner='control-owner';attempted=$true;noInvocationConfirmed=$false;processStartReached=$false;contractFailureBeforeWorkerStart=$true});[pscustomobject]@{root=$root;receipt=$receipt;worker=$worker;invoker=$invoker;contract=$contract;expectedInvokerHash=(Get-FactoryNoStartHash $invoker);expectedContractHash=(Get-FactoryNoStartHash $contract)}}
function Invoke-Case($Case,[string]$Failure='Cannot find path worker-contract.json because it does not exist.'){$ih=$Case.expectedInvokerHash;$ch=$Case.expectedContractHash;Assert-FactoryDefiniteNoWorkerStart -ReceiptPath $Case.receipt -FailureText $Failure -WorkerRoot $Case.worker -WorkerSourceRoot (Split-Path -Parent $Case.contract) -WorkerInvokerPath $Case.invoker -WorkerContractPath $Case.contract -ExpectedInvokerHash $ih -ExpectedWorkerContractHash $ch -Owner 'control-owner'|Out-Null}
Invoke-Case (New-Case 'positive')
$faults=@(
 @{name='started';mutate={param($c);$x=Get-Content -Raw $c.receipt|ConvertFrom-Json;$x.processStartReached=$true;Write-Json $c.receipt $x}},
 @{name='attempt-lineage';mutate={param($c);$x=Get-Content -Raw $c.receipt|ConvertFrom-Json;$x.attempted=$false;Write-Json $c.receipt $x}},
 @{name='worker-artifact';mutate={param($c);New-Item -ItemType Directory -Path $c.worker|Out-Null;Set-Content -LiteralPath (Join-Path $c.worker 'worker-launch-attempt.json') -Value '{}' -Encoding UTF8}},
 @{name='wrong-error';mutate={param($c);$c|Add-Member -NotePropertyName failure -NotePropertyValue 'unrelated failure'}},
 @{name='source-drift';mutate={param($c);Add-Content -LiteralPath $c.invoker -Value "`n# drift"}}
)
foreach($fault in $faults){$case=New-Case $fault.name;& $fault.mutate $case;$rejected=$false;try{Invoke-Case $case $(if($case.PSObject.Properties.Name -contains 'failure'){$case.failure}else{'Cannot find path worker-contract.json because it does not exist.'})}catch{$rejected=$true};if(-not $rejected){throw ('Definite no-start fault accepted: '+$fault.name)}}
Write-Output 'SOURCE_CONTROLS_PASS definite-no-worker-start'
