Get-ChildItem D:\Claude -Name
"--- sr0s-bridge"
Get-ChildItem D:\Claude\sr0s-bridge -Name
"--- exes"
Get-ChildItem D:\Claude\sr0s-bridge\scratch\out\Products\Release-windows-x86_64 -Filter *.exe | Select-Object Name,LastWriteTime,Length | Format-Table | Out-String
"--- uia"
Get-ChildItem D:\Claude\sr0o-uia -Name
Get-Process | Where-Object { $_.ProcessName -match 'FreshOn|BridgeSmoke|UIARec' } | Select-Object Name | Out-String
Get-ScheduledTask | Where-Object { $_.TaskName -match 'SR0' } | Select-Object TaskName | Out-String
