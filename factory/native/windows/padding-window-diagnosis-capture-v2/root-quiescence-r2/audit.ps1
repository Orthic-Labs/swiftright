$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$rows=@()
foreach($id in @(56152,36616)) { $p=Get-Process -Id $id -ErrorAction SilentlyContinue;if($p){$rows+= [ordered]@{pid=$p.Id;path=$p.Path;startedAt=$p.StartTime.ToUniversalTime().ToString('o')}} }
$t=Get-ScheduledTask -TaskName 'PaddingWindowDiagnosis-59de3a438b2b4e7c97802f0fb5ff3457' -ErrorAction SilentlyContinue
[ordered]@{observedAt=[DateTime]::UtcNow.ToString('o');liveOriginalPidRows=$rows;task=@($t|Select-Object TaskName,State);factoryProcesses=@(Get-Process -Name FactoryProbe -ErrorAction SilentlyContinue|Select-Object Id,Path);desktopLock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw);scope='current quiescence only; original worker handle disposed; no retrospective qualification'}|ConvertTo-Json -Depth 6
