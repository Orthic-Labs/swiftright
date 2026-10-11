$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$base='D:\Claude\swiftright\factory\native\windows\.work\rectangle-r11'
$control=Join-Path $base 'control-count20-r3'
foreach($name in @('coordinator.json','task-result.json','task-start.json','task.log')){$f=Join-Path $control $name;if(Test-Path $f){if((Get-Item $f).Length -gt 1MB){throw 'diagnostic cap'};Write-Output $name;Get-Content -Raw $f}}
Write-Output 'native-inventory';Get-ChildItem -LiteralPath (Join-Path $base 'native\count20-r3') -Directory | Select-Object Name | ConvertTo-Json
Write-Output 'lock';Get-Content -Raw 'D:\Claude\desktop.lock'
