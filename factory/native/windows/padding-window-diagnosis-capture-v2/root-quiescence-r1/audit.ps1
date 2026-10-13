$ErrorActionPreference='Stop'
$ids=@(56152,36616)
$found=@(Get-CimInstance Win32_Process | Where-Object { $ids -contains [int]$_.ProcessId } | Select-Object ProcessId,ExecutablePath,CreationDate,CommandLine)
$tasks=@(Get-ScheduledTask | Where-Object {$_.TaskName -eq 'PaddingWindowDiagnosis-59de3a438b2b4e7c97802f0fb5ff3457'} | Select-Object TaskName,State)
$factory=@(Get-CimInstance Win32_Process | Where-Object {$_.Name -eq 'FactoryProbe.exe'} | Select-Object ProcessId,ExecutablePath,CreationDate)
[ordered]@{observedAt=[DateTime]::UtcNow.ToString('o');originalPids=$ids;liveOriginalPidRows=$found;task=$tasks;factoryProcesses=$factory;desktopLock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw);scope='current quiescence only; original worker retained handle disposed, no retrospective exit qualification'}|ConvertTo-Json -Depth 8
