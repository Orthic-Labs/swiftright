$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\stack-lifecycle-next-capture-v1'
if((Get-FileHash (Join-Path $root 'actual-single-r1/native-01/lifecycle-timing.json')).Hash.ToLowerInvariant() -cne '49e5595a786b71a2ffc6e915e37935b5c8719276cff96255483568d43e1adb30'){throw 'Pinned recovery raw receipt drift'}
if((Get-FileHash (Join-Path $root 'actual-single-r1/native-01/capture-outcome.json')).Hash.ToLowerInvariant() -cne '67d8bd2ee190d3b94cca3e9c50fb1465eabf18c84126308e7b6d64081d653d87'){throw 'Pinned recovery raw receipt drift'}
if((Get-FileHash (Join-Path $root 'actual-single-r1/native-01/owned-process.json')).Hash.ToLowerInvariant() -cne '782a19e00fc3c0643bcf5d0f77801bd456c60986f8904fb4db0478411dbebef0'){throw 'Pinned recovery raw receipt drift'}
if((Get-FileHash (Join-Path $root 'actual-single-r1/native-01/host.stdout.txt')).Hash.ToLowerInvariant() -cne 'fbaa9dfb0405075b0fc8848caea51018f4e131fe2011e7627a41c85320f8cc81'){throw 'Pinned recovery raw receipt drift'}
if((Get-FileHash (Join-Path $root 'actual-single-r1/native-01/host.stderr.txt')).Hash.ToLowerInvariant() -cne '87767e96167eee2141e40a6617aeb7da7e07b991d4bc90b1d8f1daca46c8bddd'){throw 'Pinned recovery raw receipt drift'}
if((Get-FileHash (Join-Path $root 'coordinator-single-r1/coordinator.json')).Hash.ToLowerInvariant() -cne '5afe1b8c72e376b542205311c4dd9f97c13f619d493baba175efbf95d02d930f'){throw 'Pinned recovery raw receipt drift'}
$timing=Get-Content (Join-Path $root 'actual-single-r1\native-01\lifecycle-timing.json') -Raw|ConvertFrom-Json
$outcome=Get-Content (Join-Path $root 'actual-single-r1\native-01\capture-outcome.json') -Raw|ConvertFrom-Json
$owned=Get-Content (Join-Path $root 'actual-single-r1\native-01\owned-process.json') -Raw|ConvertFrom-Json
$control=Get-Content (Join-Path $root 'coordinator-single-r1\coordinator.json') -Raw|ConvertFrom-Json
$expectedOwner='stack-lifecycle-56139c623126439d83b9d03cfed65ce1 2026-10-11T09:57:38.0922755+00:00'
if($control.owner -cne $expectedOwner -or $outcome.lockOwner -cne $expectedOwner -or $control.lockReleased -ne $false -or $control.terminalResultConfirmed -ne $true){throw 'Exact original coordinator lineage required'}
if($owned.pid -ne 57184 -or $timing.ownedIdentity.pid -ne $owned.pid -or $outcome.ownedIdentity.pid -ne $owned.pid -or $timing.ownedIdentity.startedAt -cne $owned.startedAt -or $outcome.ownedIdentity.startedAt -cne $owned.startedAt -or $timing.ownedIdentity.path -cne $owned.path -or $outcome.ownedIdentity.path -cne $owned.path){throw 'Original start lineage drift'}
if($timing.compileReceiptHash -cne '99a0332b765518e97a8200ef25612fa5c31671037eccdf5504a1fcec091dcae8' -or $timing.exeHash -cne 'abf82f6f133f1d4dd9a48b3075f9af5fe4632db2b9fdc9763114661196bf6c2c'){throw 'Actual compiled ownership drift'}
$observations=@($timing.observations);$final=$observations[-1]
if($final.phase -cne 'raw-closure-final' -or $final.retainedHandle -ne 1832 -or $final.handlePid -ne $owned.pid -or $final.kernelBefore -ne 0 -or $final.kernelAfter -ne 0 -or $final.hasExited -ne $true -or $final.getExitCodeSucceeded -ne $true -or $final.exitCode -ne 0 -or @($final.errors).Count){throw 'Final original retained kernel exit proof absent'}
foreach($sample in $observations){if($sample.retainedHandle -ne $final.retainedHandle -or $sample.handlePid -ne $owned.pid){throw 'Same original retained handle required'}}
if($outcome.rawHashesQualification -cne 'sealed-raw' -or $timing.rawHashesQualification -cne 'sealed-raw' -or @($outcome.streamErrors).Count){throw 'Both closed raw streams required'}
foreach($stream in $outcome.rawStreams){if($stream.copyCompleted -ne $true -or $stream.destinationClosed -ne $true -or $stream.sealed -ne $true -or $stream.taskStatus -cne 'RanToCompletion' -or $stream.closureTaskStatus -cne 'RanToCompletion'){throw 'Raw closure proof absent'}}
$q=@(Get-CimInstance Win32_Process -Filter ('ProcessId='+$owned.pid));if($q.Count -ne 0){throw 'Original PID still present; retain lock'}
$task=Get-ScheduledTask -TaskName $control.taskName -ErrorAction Stop;if([string]$task.State -ceq 'Running'){throw 'Interactive task still running; retain lock'}
$path='D:\Claude\desktop.lock';$stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{$reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true,1024,$true);try{$observed=$reader.ReadToEnd().Trim()}finally{$reader.Dispose()};if($observed -cne $expectedOwner){throw 'Lock owner drift; retain foreign owner'};$data=[Text.Encoding]::UTF8.GetBytes('free');$stream.Position=0;$stream.SetLength(0);$stream.Write($data,0,$data.Length);$stream.Flush($true)}finally{$stream.Dispose()}
@{at=[DateTimeOffset]::UtcNow.ToString('o');expectedOwner=$expectedOwner;observedOwner=$observed;pid=$owned.pid;actualCimCount=$q.Count;taskState=[string]$task.State;retainedOriginalHandle=$final.retainedHandle;finalKernelBefore=$final.kernelBefore;finalKernelAfter=$final.kernelAfter;rawStreamsClosed=$true;released=$true;noKill=$true;noDelete=$true;primaryDeadlinePreserved=$outcome.primaryError;qualification='failed-diagnostic-only'}|ConvertTo-Json
