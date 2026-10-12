param([Parameter(Mandatory=$true)][string]$ControlRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'assert-uia-source-closure.ps1')

function Write-UiaJson([string]$Path,[object]$Value){$Value|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $Path -Encoding UTF8}
function New-UiaFixture([string]$Name){
 $root=Join-Path $ControlRoot ('uia-closure-'+$Name+'-'+[Guid]::NewGuid().ToString('N'));$producer=Join-Path $root 'producer';$worker=Join-Path $producer 'dependencies/uia-worker';$support=Join-Path $worker 'support'
 New-Item -ItemType Directory -Force -Path $support|Out-Null
 foreach($file in @('worker.ps1','invoke-worker-mta.ps1','read-uia.ps1','schema.ps1')){Set-Content -LiteralPath (Join-Path $worker $file) -Value ('# '+$file) -Encoding UTF8}
 Set-Content -LiteralPath (Join-Path $support 'cleanup.ps1') -Value '# cleanup' -Encoding UTF8
 $sourceBindings=@();foreach($relative in @('worker.ps1','invoke-worker-mta.ps1','read-uia.ps1','schema.ps1','support/cleanup.ps1')){$path=Join-Path $worker $relative;$item=Get-UiaClosureItem $path;$sourceBindings+=@([ordered]@{path=$relative;sha256=(Get-UiaClosureHash $path);bytes=[int64]$item.Length})}
 $contract=Join-Path $worker 'worker-contract.json';Write-UiaJson $contract ([ordered]@{kind='factory-uia-fromhandle-mta-worker-contract-v1';workerApartment='MTA';sourceBindings=$sourceBindings})
 $contractItem=Get-UiaClosureItem $contract;$files=@();foreach($binding in $sourceBindings){$files+=@([ordered]@{path='dependencies/uia-worker/'+$binding.path;sha256=$binding.sha256;bytes=$binding.bytes})};$files+=@([ordered]@{path='dependencies/uia-worker/worker-contract.json';sha256=(Get-UiaClosureHash $contract);bytes=[int64]$contractItem.Length})
 $integration=Join-Path $producer 'integration-bindings.json';Write-UiaJson $integration ([ordered]@{kind='root-uia-helper-bindings-v1';files=$files})
 $integrationItem=Get-UiaClosureItem $integration
 [pscustomobject]@{root=$root;producer=$producer;worker=$worker;contract=$contract;integration=$integration;integrationBytes=[int64]$integrationItem.Length;integrationHash=(Get-UiaClosureHash $integration);bindings=$sourceBindings}
}
function Invoke-UiaFixture($Case,[object]$Bindings=$null,[string]$IntegrationHash=$null,[int64]$IntegrationBytes=0){
 if($null -eq $Bindings){$Bindings=$Case.bindings};if([string]::IsNullOrWhiteSpace($IntegrationHash)){$IntegrationHash=$Case.integrationHash};if($IntegrationBytes -le 0){$IntegrationBytes=$Case.integrationBytes}
 Assert-FactoryUiaSourceClosure -ProducerRoot $Case.producer -WorkerSourceRoot $Case.worker -WorkerContractPath $Case.contract -IntegrationBindingsPath $Case.integration -IntegrationBindingsBytes $IntegrationBytes -IntegrationBindingsHash $IntegrationHash -SourceBindings $Bindings -RequireMtaInvoker|Out-Null
}
New-Item -ItemType Directory -Force -Path $ControlRoot|Out-Null
Invoke-UiaFixture (New-UiaFixture 'positive')
$faults=@(
 @{name='missing-mta-row';mutate={param($c);$doc=Read-UiaClosureJson $c.integration;$doc.files=@($doc.files|Where-Object{$_.path -ne 'dependencies/uia-worker/invoke-worker-mta.ps1'});Write-UiaJson $c.integration $doc;$c.integrationBytes=[int64](Get-UiaClosureItem $c.integration).Length;$c.integrationHash=Get-UiaClosureHash $c.integration}},
 @{name='mutated-source-row';mutate={param($c);Add-Content -LiteralPath (Join-Path $c.worker 'invoke-worker-mta.ps1') -Value '# drift' -Encoding UTF8;$doc=Read-UiaClosureJson $c.integration;$row=@($doc.files|Where-Object{$_.path -eq 'dependencies/uia-worker/invoke-worker-mta.ps1'})[0];$row.sha256=Get-UiaClosureHash (Join-Path $c.worker 'invoke-worker-mta.ps1');$row.bytes=[int64](Get-UiaClosureItem (Join-Path $c.worker 'invoke-worker-mta.ps1')).Length;Write-UiaJson $c.integration $doc;$c.integrationBytes=[int64](Get-UiaClosureItem $c.integration).Length;$c.integrationHash=Get-UiaClosureHash $c.integration}},
 @{name='missing-source-file';mutate={param($c);$doc=Read-UiaClosureJson $c.integration;$doc.files+=@([pscustomobject]@{path='dependencies/uia-worker/missing.ps1';sha256=('0'*64);bytes=1});Write-UiaJson $c.integration $doc;$c.integrationBytes=[int64](Get-UiaClosureItem $c.integration).Length;$c.integrationHash=Get-UiaClosureHash $c.integration}},
 @{name='wrong-binding-hash';mutate={param($c);$b=@($c.bindings|ForEach-Object{[pscustomobject]@{path=$_.path;sha256=$_.sha256;bytes=$_.bytes}});$b[1].sha256=('0'*64);$c.bindings=$b}},
 @{name='traversal-binding';mutate={param($c);$b=@($c.bindings|ForEach-Object{[pscustomobject]@{path=$_.path;sha256=$_.sha256;bytes=$_.bytes}});$b[0].path='../escape.ps1';$c.bindings=$b}},
 @{name='duplicate-binding';mutate={param($c);$b=@($c.bindings)+$c.bindings[0];$c.bindings=$b}}
)
foreach($fault in $faults){$case=New-UiaFixture $fault.name;& $fault.mutate $case;$rejected=$false;try{Invoke-UiaFixture $case $case.bindings $case.integrationHash $case.integrationBytes}catch{$rejected=$true};if(-not $rejected){throw ('UIA source closure fault accepted: '+$fault.name)}}
Write-Output 'SOURCE_CONTROLS_PASS uia-source-closure-admission'
