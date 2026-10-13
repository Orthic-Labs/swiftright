$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$ns='D:\Claude\swiftright\.factory-work\windows-replay-r11\r14';$control=Join-Path $ns 'coordinator-r1'
function Read-BoundedJson([string]$p){$i=Get-Item -LiteralPath $p;if($i.Length -gt 1MB){throw 'Proof bound'};[IO.File]::ReadAllText($p)|ConvertFrom-Json}
$co=Read-BoundedJson (Join-Path $control 'coordinator.json');$task=Read-BoundedJson (Join-Path $control 'task-result.json')
if(-not $co.lockReleased -or -not $co.wholeBatchExitConfirmed -or -not $co.terminalResultConfirmed -or $task.memoryReceipt.activeProcessCount -ne 1){throw 'Failed capture cleanup not proven'}
$dirs=@();if(Test-Path -LiteralPath $co.runRoot){$dirs=@(Get-ChildItem -LiteralPath $co.runRoot -Directory)}
if($dirs.Count -ne 0 -or @($task.workerInventories).Count -ne 0){throw 'Unexpected native launches require separate audit'}
[ordered]@{kind='root-factory-failed-native-v15-audit-v1';status='failed-before-native-launch';nativeDirectories=$dirs.Count;task=$task;coordinator=$co;lockState=(Get-Content -Raw 'D:\Claude\desktop.lock').Trim();qualification='hold'}|ConvertTo-Json -Depth 12
