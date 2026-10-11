$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$pkg='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3';$control=Join-Path $pkg 'coordinator-single-r1\coordinator.json'
if((Get-FileHash -LiteralPath $control).Hash.ToLowerInvariant() -cne '7afff50656e2cce55c5a9bd4a2cecf100d8c428e83ad2f46410cfdd8267b7342'){throw 'Archived Count1 terminal differs'}
$c=Get-Content -Raw -LiteralPath $control|ConvertFrom-Json;if(-not$c.lockReleased -or -not$c.wholeBatchExitConfirmed -or $c.cleanupErrors.Count){throw 'Count1ownedexit notconfirmed'}
$tasks=@(Get-ScheduledTask -TaskName $c.taskName);if($tasks.Count -ne 1 -or $tasks[0].State -in @('Running','Queued')){throw 'Original task nonquiescent'}
$exe='D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package\build-capture-lease-r1\scratch\out\Products\Release-windows-x86_64\FactoryProbe.exe';$busy=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -ieq $exe -or ($_.CommandLine -like '*padding-capture-lease-capture-v3*' -and $_.CommandLine -match '(interactive-task-r3\.ps1|dispatch-r3\.ps1|capture-repeat-r3\.ps1)')});if($busy.Count){throw 'Originalexactownedprocess active'}
if(Test-Path -LiteralPath (Join-Path $pkg 'actual-repeat-r1')){throw 'Count20 unexpectedlystarted'}
$dest='D:\Claude\swiftright\.factory-work\retired\capture-canonical-id-rejected-r3';if(Test-Path -LiteralPath $dest){throw 'Retirementtargetalreadyexists'}
[IO.Directory]::CreateDirectory($dest)|Out-Null
$rows=@();foreach($name in @('actual-single-r1','coordinator-single-r1','coordinator-repeat-r1','root-actual-repeat-v1')){$src=Join-Path $pkg $name;$to=Join-Path $dest $name;if(-not(Test-Path -LiteralPath $src -PathType Container)){throw ('Archivedsourceabsent '+$name)};Move-Item -LiteralPath $src -Destination $to;$rows+=@{source=$src;destination=$to;deleted=$false}}
@{kind='root-canonical-id-rejected-workspace-retirement-v1';status='moved-after-mac-archive';moves=$rows;ownedProcesses=0;nativeActions=0;lockActions=0;deleted=$false}|ConvertTo-Json -Depth 8
