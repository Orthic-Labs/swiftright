$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'
$os=Get-CimInstance Win32_OperatingSystem
[ordered]@{kind='sr0-renderer-recovery-host-capacity-v1';at=[DateTimeOffset]::UtcNow.ToString('o');machine=[Environment]::MachineName;memory=@{totalVisibleKB=$os.TotalVisibleMemorySize;freePhysicalKB=$os.FreePhysicalMemory;totalVirtualKB=$os.TotalVirtualMemorySize;freeVirtualKB=$os.FreeVirtualMemory};lock=[IO.File]::ReadAllText('D:\Claude\desktop.lock')}|ConvertTo-Json -Depth 8
Get-Process|Sort-Object WorkingSet64 -Descending|Select-Object -First 10 Id,ProcessName,WorkingSet64,PrivateMemorySize64|ConvertTo-Json
rightkit list
$lock='D:\.rightkit-managed\remote-workspaces\swiftright-render-815231d1\slot1\Cargo.lock'
if(Test-Path -LiteralPath $lock){Write-Output ('POST_CARGO_LOCK_SHA256 '+(Get-FileHash -LiteralPath $lock).Hash.ToLowerInvariant());Write-Output 'POST_CARGO_LOCK_BASE64';Write-Output ([Convert]::ToBase64String([IO.File]::ReadAllBytes($lock)))}
