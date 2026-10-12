$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$c='D:\Claude\swiftright\factory\native\windows\.work\rectangle-fixed-r11-v2\control-count1-r1'
$files=@();foreach($n in @('task-start.json','task-result.json','coordinator.json')){$p=Join-Path $c $n;if(Test-Path $p){if((Get-Item $p).Length -gt 2MB){throw 'receipt bound'};$files+=@{name=$n;value=(Get-Content -Raw $p|ConvertFrom-Json)}}}
$log=Join-Path $c 'task.log';$tail=if(Test-Path $log){Get-Content -LiteralPath $log -Tail 20|Out-String}else{''}
@{lock=(Get-Content -Raw 'D:\Claude\desktop.lock').Trim();files=$files;tail=$tail;tasks=@(Get-ScheduledTask|Where-Object{$_.TaskName -like 'FactoryRectangle-*' -and $_.State -in @('Running','Queued')}|Select-Object TaskName,State)}|ConvertTo-Json -Depth 20
