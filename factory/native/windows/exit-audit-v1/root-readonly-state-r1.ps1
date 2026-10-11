$ErrorActionPreference='Stop'
$observedAt=[DateTime]::UtcNow.ToString('o')
$lock=[IO.File]::ReadAllText('D:\Claude\desktop.lock')
$rows=@(Get-CimInstance Win32_Process -Filter "ProcessId=16068 OR ProcessId=45236" | Select-Object ProcessId,CreationDate,ExecutablePath,CommandLine)
$factory=@(Get-CimInstance Win32_Process -Filter "Name='FactoryProbe.exe'" | Select-Object ProcessId,CreationDate,ExecutablePath,CommandLine)
[ordered]@{kind='readonly-current-state';observedAt=$observedAt;desktopLock=$lock;priorFailedOwnedPids=@(16068,45236);currentPriorPids=$rows;currentFactoryProcesses=$factory;historicalKernelExitProved=$false;mutation=$false} | ConvertTo-Json -Depth 8
