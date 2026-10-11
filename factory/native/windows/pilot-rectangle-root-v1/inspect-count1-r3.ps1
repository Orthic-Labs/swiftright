$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';$c='D:\Claude\swiftright\factory\native\windows\.work\rectangle-r11\control-count1-r3'
foreach($name in @('coordinator.json','task-result.json','task-start.json','task.log','scheduled-task-receipt.json')){$f=Join-Path $c $name;if(Test-Path $f){if((Get-Item $f).Length -gt 1MB){throw 'diagnostic cap'};Write-Output $name;Get-Content -Raw $f}}
Write-Output 'lock';Get-Content -Raw 'D:\Claude\desktop.lock'
Write-Output 'source-inputs';$s=Get-Content -Raw 'D:\Claude\swiftright\factory\native\windows\.work\rectangle-r11\admission-count1-r3\source-inputs.json'|ConvertFrom-Json;$s|Select-Object kind,count,caseID,tupleID|ConvertTo-Json
