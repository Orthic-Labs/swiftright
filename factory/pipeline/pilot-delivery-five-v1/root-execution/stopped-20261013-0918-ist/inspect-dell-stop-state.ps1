$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Root='D:\Claude\swiftright\.factory-work'
$Processes=@(Get-CimInstance Win32_Process | Where-Object {$_.Name -in @('swift.exe','swiftc.exe','swift-build.exe','swift-frontend.exe','clang.exe','cl.exe','FactoryProbe.exe','FontCollectionVisibilityProbe.exe')} | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath)
$Stages=@(Get-ChildItem -LiteralPath (Join-Path $Root 'hosts') -Directory | Select-Object -ExpandProperty Name)
[ordered]@{kind='factory-stopped-readonly-dell-state-v1';observedAt=[DateTimeOffset]::UtcNow.ToString('o');desktopLock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim();compilerOrNativeProcesses=$Processes;activeHostStages=$Stages;deletion=$false;nativeActions=0}|ConvertTo-Json -Depth 8
