$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\factory\native\windows\.work\rectangle-fixed-r11-v2';$control=Join-Path $root 'control-count1-r2';$run=Join-Path $root 'native\count1-r2'
$start=Get-Content (Join-Path $control 'task-start.json') -Raw|ConvertFrom-Json;$p=Get-Process -Id $start.pid -ErrorAction SilentlyContinue
$rows=@();foreach($name in @('task-start.json','desktop-availability.json','task-result.json','coordinator.json','task.log')){$f=Join-Path $control $name;if(Test-Path $f){if((Get-Item $f).Length -gt 2MB){throw 'diagnostic byte cap'};$rows+=@{name=$name;raw=Get-Content $f -Raw}}}
$files=@();if(Test-Path $run){$files=@(Get-ChildItem $run -Recurse -File|Select-Object -First 64 FullName,Length)}
$children=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$start.pid)|Select-Object ProcessId,ParentProcessId,Name,CommandLine)
@{lock=(Get-Content 'D:\Claude\desktop.lock' -Raw).Trim();process=if($p){$p|Select-Object Id,Path,StartTime,CPU,WorkingSet64,PrivateMemorySize64};children=$children;files=$files;rows=$rows}|ConvertTo-Json -Depth 22
