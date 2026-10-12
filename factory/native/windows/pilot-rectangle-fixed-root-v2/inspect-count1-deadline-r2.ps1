$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$ns='D:\Claude\swiftright\factory\native\windows\.work\rectangle-fixed-r11-v2';$c=Join-Path $ns 'control-count1-r1';$s=Get-Content -Raw (Join-Path $c 'task-start.json')|ConvertFrom-Json
$process=Get-Process -Id $s.pid -ErrorAction SilentlyContinue
$kids=@(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$s.pid)|Select-Object ProcessId,ParentProcessId,Name,CommandLine)
$files=@();$root=Join-Path $ns 'native\count1-r1';if(Test-Path $root){$files=@(Get-ChildItem -LiteralPath $root -Recurse -File|Select-Object -First 90 FullName,Length)}
$receipts=@();foreach($n in @('task-result.json','coordinator.json','scheduled-task-receipt.json')){$p=Join-Path $c $n;if(Test-Path $p){$receipts+=@{name=$n;value=(Get-Content -Raw $p|ConvertFrom-Json)}}}
@{lock=(Get-Content -Raw 'D:\Claude\desktop.lock').Trim();process=if($process){$process|Select-Object Id,Path,StartTime,CPU,WorkingSet64,PrivateMemorySize64};children=$kids;files=$files;receipts=$receipts;task=Get-ScheduledTask -TaskName 'FactoryRectangle-cfff60cec8e64932944b43b3e54ed975'|Select-Object TaskName,State}|ConvertTo-Json -Depth 20
