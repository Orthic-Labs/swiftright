$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\rectangle-fixed-r11-v2';$control=Join-Path $root 'control-count1-r2';$run=Join-Path $root 'native\count1-r2\native-01'
$rows=@();foreach($name in @('task-start.json','desktop-availability.json','task-result.json','coordinator.json')){$p=Join-Path $control $name;if(Test-Path -LiteralPath $p){if((Get-Item $p).Length -gt 2MB){throw 'bounded diagnostic'};$rows+=@{name=$name;value=(Get-Content $p -Raw|ConvertFrom-Json)}}}
foreach($name in @('final-start.json','window-inventory-after-process-start.json','window-inventory-window-deadline.json','final-exit.json','stderr.bin')){$p=Join-Path $run $name;if(Test-Path -LiteralPath $p){if((Get-Item $p).Length -gt 2MB){throw 'bounded native diagnostic'};$rows+=@{name=$name;bytes=(Get-Item $p).Length;raw=(Get-Content $p -Raw)}}}
@{lock=(Get-Content 'D:\Claude\desktop.lock' -Raw).Trim();rows=$rows}|ConvertTo-Json -Depth 20
