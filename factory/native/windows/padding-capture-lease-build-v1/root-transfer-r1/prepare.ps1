$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis'
$archive='D:\Claude\_factory-old-DELETE-ME\padding-window-diagnosis-pre-lease-20261011T1056Z'
foreach($id in @(56152,36616)){if(Get-Process -Id $id -ErrorAction SilentlyContinue){throw 'Prior original PID unexpectedly exists; audit identity before staging'}}
$live=@(Get-Process -Name FactoryProbe -ErrorAction SilentlyContinue|Where-Object{$_.Path -and $_.Path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)})
if($live.Count){throw 'Owned rolling host still active'}
$t=Get-ScheduledTask -TaskName 'PaddingWindowDiagnosis-59de3a438b2b4e7c97802f0fb5ff3457' -ErrorAction SilentlyContinue
if($t -and [string]$t.State -eq 'Running'){throw 'Prior own task still running'}
if(Test-Path -LiteralPath $archive){throw 'Fresh retired archive destination required'}
if(!(Test-Path -LiteralPath $root)){throw 'Prior rolling root expected'}
New-Item -ItemType Directory -Path 'D:\Claude\_factory-old-DELETE-ME' -Force|Out-Null
Move-Item -LiteralPath $root -Destination $archive
New-Item -ItemType Directory -Path $root|Out-Null
[ordered]@{status='OWNED_QUIESCENT_ROLLING_ROOT_MOVED';root=$root;archive=$archive;desktopLock=[IO.File]::ReadAllText('D:\Claude\desktop.lock');compilerActions=0;nativeActions=0;deleteActions=0}|ConvertTo-Json -Depth 3
