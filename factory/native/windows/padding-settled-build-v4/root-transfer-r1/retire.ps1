$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\padding-settled'
$owned=@(Get-Process -Name FactoryProbe -ErrorAction SilentlyContinue|Where-Object{$_.Path -and $_.Path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)})
if($owned.Count){throw 'Owned host still active'}
$coordinator=Get-Content 'D:\Claude\swiftright\factory\native\windows\padding-settled-capture-v1\coordinator-single-r1\coordinator.json' -Raw|ConvertFrom-Json
if($coordinator.lockReleased -ne $true -or $coordinator.wholeBatchExitConfirmed -ne $true -or (Get-ScheduledTask -TaskName $coordinator.taskName).State -in @('Running','Queued')){throw 'Prior hidden capture is not quiescent'}
$old='D:\Claude\_factory-old-DELETE-ME\padding-v3-completed-20261011'
if(Test-Path $old){throw 'Retirement namespace exists'}
New-Item -ItemType Directory $old|Out-Null
$moved=@()
foreach($name in @('control-results','control-fixtures','stream-control-results','stream-parse.json','stream-admission-faults','json-array-controls','source-scope-controls','package\build-settled-r1')){
 $from=Join-Path $root $name
 if(Test-Path -LiteralPath $from){$to=Join-Path $old $name;New-Item -ItemType Directory -Path (Split-Path $to -Parent) -Force|Out-Null;Move-Item -LiteralPath $from -Destination $to;$moved+=$name}
}
@{moved=$moved;retired=$old;ownedActive=0;nativeActions=0;remoteDeleted=0}|ConvertTo-Json -Depth 5
