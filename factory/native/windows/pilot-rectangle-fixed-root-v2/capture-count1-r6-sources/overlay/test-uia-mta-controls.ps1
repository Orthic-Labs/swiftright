# Source-only controls; root may execute after staging. No native/window actions here.
param([Parameter(Mandatory=$true)][string]$WorkerPath,[Parameter(Mandatory=$true)][string]$InvokerPath,[string]$SchemaPath=(Join-Path $PSScriptRoot 'schema.ps1'))
$ErrorActionPreference='Stop'
$worker=Get-Content -Raw -LiteralPath $WorkerPath;$invoker=Get-Content -Raw -LiteralPath $InvokerPath;$schema=Get-Content -Raw -LiteralPath $SchemaPath
foreach($marker in @('Invoke-UiaFromHandleBounded','CurrentThread.GetApartmentState','FromHandle($Hwnd)','requires dedicated MTA worker','before-from-handle-mta','after-from-handle-mta','workerApartment=$c.apartment',"deadline='parent-15s'")){if($worker -notmatch [regex]::Escape($marker)){throw ('MTA worker marker missing: '+$marker)}}
foreach($marker in @("workerApartment='MTA'",'-MTA','parentApartment=$apartment','worker-contract.json','worker-exit-v2')){if($invoker -notmatch [regex]::Escape($marker)){throw ('MTA invoker marker missing: '+$marker)}}
if($worker -match 'Task\[object\]|Task\.Run|Start-NewThread'){throw 'MTA worker must use dedicated process thread'}
if($invoker -match '-\$apartment|workerApartment=\$apartment'){throw 'Invoker must request fixed MTA worker'}
if($invoker -match 'AddSeconds\((?:1[6-9]|[2-9][0-9])\)'){throw 'worker deadline expanded'}
if($worker -match 'TimeoutMilliseconds|timeoutMilliseconds'){throw 'worker claims independent timeout'}
foreach($marker in @('factory-uia-snapshot-worker-exit-v2','parentApartment -cnotin @(''STA'',''MTA'')','workerApartment -cne ''MTA''','worker natural kernel0 exit required')){if($schema -notmatch [regex]::Escape($marker)){throw ('v2 schema marker missing: '+$marker)}}
$schemaFaults=@('missing-parent-apartment','wrong-worker-apartment','legacy-proof-kind')
foreach($fault in $schemaFaults){$mut=$schema;switch($fault){'missing-parent-apartment'{$mut=$mut.Replace('$Proof.parentApartment -cnotin','$Proof.parentApartment -cne')};'wrong-worker-apartment'{$mut=$mut.Replace('$Proof.workerApartment -cne ''MTA''','$Proof.workerApartment -cne ''STA''')};'legacy-proof-kind'{$mut=$mut.Replace('factory-uia-snapshot-worker-exit-v2','factory-uia-snapshot-worker-exit-v1')}};if($mut -eq $schema){throw ('schema mutation was no-op: '+$fault)}}
[ordered]@{kind='factory-uia-fromhandle-mta-controls-v4';status='SOURCE_CONTROLS_PASS';workerApartment='MTA';parentApartment='observed-STA-or-MTA';parentWorkerDeadlineSeconds=15;schemaPositive='v2 parent/worker apartment + natural receipt';schemaFaultsRejected=$schemaFaults;nativeActions=0;compilerActions=0}|ConvertTo-Json -Depth 6
