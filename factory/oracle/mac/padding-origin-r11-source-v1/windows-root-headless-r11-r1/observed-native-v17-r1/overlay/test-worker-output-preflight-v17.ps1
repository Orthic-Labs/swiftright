param([Parameter(Mandatory=$true)][string]$ControlRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'worker-output-preflight-v17.ps1')
$root=[IO.Path]::GetFullPath($ControlRoot)
if(Test-Path -LiteralPath $root){throw 'Control root must be fresh'}
New-Item -ItemType Directory -Path $root -Force|Out-Null
$factory='D:\Claude\swiftright\factory\native\windows'
$suffix=[Guid]::NewGuid().ToString('N')
$namespace=Join-Path $factory ('.work\worker-output-preflight-v17\'+$suffix+'\positive')
$run=Join-Path $namespace 'replays\r1'
$rows=@()
try{Assert-FreshFactoryWorkerOutputPlan $namespace $run 20|Out-Null;$rows+= [ordered]@{name='positive';rejected=$false;reason=''} }catch{$rows+=[ordered]@{name='positive';rejected=$true;reason=[string]$_}}
$wrong='D:\Claude\swiftright\.work\worker-output-preflight-v17\'+$suffix+'\wrong'
try{Assert-FreshFactoryWorkerOutputPlan $wrong (Join-Path $wrong 'replays\r1') 20|Out-Null;$rows+=[ordered]@{name='wrong-namespace';rejected=$false;reason='expected rejection missing'}}catch{$rows+=[ordered]@{name='wrong-namespace';rejected=$true;reason=[string]$_}}
$existing=Join-Path $factory ('.work\worker-output-preflight-v17\'+$suffix+'\existing')
$existingWorker=Join-Path $existing 'replays\r1\native-01\uia-worker'
New-Item -ItemType Directory -Path $existingWorker -Force|Out-Null
try{Assert-FreshFactoryWorkerOutputPlan $existing (Join-Path $existing 'replays\r1') 20|Out-Null;$rows+=[ordered]@{name='existing-worker';rejected=$false;reason='expected rejection missing'}}catch{$rows+=[ordered]@{name='existing-worker';rejected=$true;reason=[string]$_}}
if($rows[0].rejected -or -not $rows[1].rejected -or -not $rows[2].rejected){throw 'Worker output preflight controls failed'}
[ordered]@{kind='factory-worker-output-preflight-controls-v17';status='passed-source-only';controls=$rows;nativeWindowActions=0;compilerActions=0;guiActions=0;remoteActions=0;lockActions=0}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $root 'controls.json') -Encoding UTF8
