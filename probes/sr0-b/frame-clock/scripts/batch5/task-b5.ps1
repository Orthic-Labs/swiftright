# Runs in the interactive session as scheduled task SR0B5Desktop: minimise all windows, then the v3 harness (10 runs per variant).
$ErrorActionPreference = 'Continue'
$base = 'D:\Claude\sr0b-frame-clock'
try { (New-Object -ComObject Shell.Application).MinimizeAll() } catch { }
Start-Sleep -Seconds 2
& "$base\scripts-v3\run-desktop-v3.ps1" -Runs 10 -OutFile "$base\result-desktop-v3-batch5.txt"
