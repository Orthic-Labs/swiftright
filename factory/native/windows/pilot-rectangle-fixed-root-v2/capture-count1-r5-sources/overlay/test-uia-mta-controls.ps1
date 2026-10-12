# Source-only controls; root may execute after staging. No native/window actions here.
param([Parameter(Mandatory=$true)][string]$WorkerPath,[Parameter(Mandatory=$true)][string]$InvokerPath)
$ErrorActionPreference='Stop'
$worker=Get-Content -Raw -LiteralPath $WorkerPath;$invoker=Get-Content -Raw -LiteralPath $InvokerPath
foreach($marker in @('Invoke-UiaFromHandleBounded','CurrentThread.GetApartmentState','FromHandle($Hwnd)','requires dedicated MTA worker','before-from-handle-mta','after-from-handle-mta','workerApartment=$c.apartment',"deadline='parent-15s'")){if($worker -notmatch [regex]::Escape($marker)){throw ('MTA worker marker missing: '+$marker)}}
foreach($marker in @("workerApartment='MTA'",'-MTA','parentApartment=$apartment','worker-contract.json','worker-exit-v2')){if($invoker -notmatch [regex]::Escape($marker)){throw ('MTA invoker marker missing: '+$marker)}}
if($worker -match 'Task\[object\]|Task\.Run|Start-NewThread'){throw 'MTA worker must use dedicated process thread'}
if($invoker -match "-\$apartment|workerApartment=\$apartment"){throw 'Invoker must request fixed MTA worker'}
if($invoker -match 'AddSeconds\((?:1[6-9]|[2-9][0-9])\)'){throw 'worker deadline expanded'}
if($worker -match 'TimeoutMilliseconds|timeoutMilliseconds'){throw 'worker claims independent timeout'}
[ordered]@{kind='factory-uia-fromhandle-mta-controls-v3';status='SOURCE_CONTROLS_PASS';workerApartment='MTA';parentApartment='observed';parentWorkerDeadlineSeconds=15;nativeActions=0;compilerActions=0}|ConvertTo-Json -Depth 6
