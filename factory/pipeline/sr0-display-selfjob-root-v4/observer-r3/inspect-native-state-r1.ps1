$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-r1'
$task=Get-ScheduledTask -TaskName 'SR0-factory-display-selfjob-v4-root-r1' -ErrorAction SilentlyContinue
$result=[ordered]@{taskExists=($null -ne $task);taskState=if($task){[string]$task.State}else{$null};lockText=[IO.File]::ReadAllText('D:\Claude\desktop.lock');manifestExists=(Test-Path -LiteralPath (Join-Path $root 'one-shot-manifest.json'));launcherReceiptExists=(Test-Path -LiteralPath (Join-Path $root 'launcher-receipt.json'));checkedAt=[DateTimeOffset]::UtcNow.ToString('o')}
$result|ConvertTo-Json -Depth 4
exit 0
