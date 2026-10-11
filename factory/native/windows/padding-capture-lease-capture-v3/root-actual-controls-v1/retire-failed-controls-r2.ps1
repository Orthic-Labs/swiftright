$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$base='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3';$old=Join-Path $base 'coordinator-single-r1';$retired='D:\Claude\swiftright\.factory-work\retired-capture-control-r2'
$pins=@'
{"coordinator.json": "8773e3858ef1403cd68c3cd95f55ebfa8542085aeb9038954062fc6e32ab2ee5", "task-result.json": "7ce1bd2237cb254a49d5015bfacdc75bb764f1e93752850f8a0e3e51ff64bf17", "issued-metadata.json": "26ab10c102f2536110c373271cb377d8acda1a6983cb1f8e00238ff4e49d74d2", "candidate-tuple.json": "40b1a3cb5802bfd6e0e5b1836872e664bc2b85dd6b3c82fca08255aa22d8cb6d", "candidate-binding.json": "0c9b9768115ae39e7a77c627ac435db1f8b14f6ea0f77aa116f924ca2a467fa0", "mac-schema-receipt-r1.json": "5b0ca56887147453a26c658fbff086ad07f7cdfaec010c8f7d2f426dc9dfe48a"}
'@|ConvertFrom-Json
foreach($prop in $pins.PSObject.Properties){$f=Join-Path $old $prop.Name;if((Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $prop.Value){throw ('Archived failed control drift '+$prop.Name)}}
$c=Get-Content -Raw -LiteralPath (Join-Path $old 'coordinator.json')|ConvertFrom-Json;$t=Get-Content -Raw -LiteralPath (Join-Path $old 'task-result.json')|ConvertFrom-Json
if($c.lockReleased -ne $true -or $c.wholeBatchExitConfirmed -ne $true -or @($c.cleanupErrors).Count -ne 0 -or @($t.workerInventories).Count -ne 0 -or $c.status -cne 'hold-harness-error' -or $c.error -cne 'Interactive capture failed: Integration binding manifest drift'){throw 'Failed control retirement admission absent'}
if(Test-Path -LiteralPath (Join-Path $base 'actual-single-r1')){throw 'Native capture output exists; no namespace reuse'}
$task=Get-ScheduledTask -TaskName $c.taskName
if($task.State -notin @('Disabled','Ready') -or $task.Settings.Enabled -ne $false){throw 'Failed task not disabled/quiescent'}
$workers=@(Get-CimInstance Win32_Process|Where-Object{$_.CommandLine -like ('*'+(Join-Path $old 'hidden-task.vbs')+'*') -or $_.CommandLine -like ('*'+(Join-Path $old 'config.json')+'*')})
if($workers.Count){throw 'Prior hidden executor still present'}
if(([IO.File]::ReadAllText('D:\Claude\desktop.lock')).Trim() -cne 'free'){throw 'Desktop no longer free; retirement postponed'}
if(Test-Path -LiteralPath $retired){throw 'Fresh retired control namespace required'}
Move-Item -LiteralPath $old -Destination $retired
[IO.Directory]::CreateDirectory($old)|Out-Null
foreach($n in @('issued-metadata.json','candidate-tuple.json','candidate-binding.json','mac-schema-receipt-r1.json')){[IO.File]::Copy((Join-Path $retired $n),(Join-Path $old $n),$false);if((Get-FileHash -LiteralPath (Join-Path $old $n)).Hash.ToLowerInvariant() -cne $pins.$n){throw ('Restored immutable metadata drift '+$n)}}
[ordered]@{kind='root-capture-failed-control-retirement-v1';retired=$retired;restoredPreissued=$old;coordinatorSha256=$pins.'coordinator.json';taskResultSha256=$pins.'task-result.json';kernelWorkersObserved=0;priorOwnedNativeDirs=0;priorReleaseConfirmed=$true;nativeLaunches=0;lockActions=0;deleteActions=0;at=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8
