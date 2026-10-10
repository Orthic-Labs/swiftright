# Read-only session feasibility inventory. Does not open windows, switch sessions,
# acquire/release desktop.lock, change policies, or delete any files.
$ErrorActionPreference = 'Stop'
$os = Get-CimInstance Win32_OperatingSystem
$sessions = @(& qwinsta 2>&1 | ForEach-Object { [string]$_ })
$sessionExit = $LASTEXITCODE
$lock = 'D:\Claude\desktop.lock'
$lockState = if (Test-Path -LiteralPath $lock) { ([string](Get-Content -Raw -LiteralPath $lock)).Trim() } else { 'missing' }
$edition = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$rdp = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
[ordered]@{
    schema = 'sr1.session-preflight/0.1'
    observedAt = [DateTimeOffset]::UtcNow.ToString('o')
    evidence = 'read-only-host-inventory'
    os = [ordered]@{ caption = $os.Caption; version = $os.Version; build = $os.BuildNumber; sku = $os.OperatingSystemSKU; edition = $edition.EditionID }
    sessionQueryExit = $sessionExit
    sessions = $sessions
    rdpConnectionsDenied = $rdp.fDenyTSConnections
    desktopLock = [ordered]@{ path = $lock; state = $lockState; acquired = $false }
    isolatedSessionQualified = $false
    windowedRunPerformed = $false
    next = 'Native-only runs use shared desktop under desktop.lock with foreground checks and abort-on-focus-loss until isolated session qualifies.'
} | ConvertTo-Json -Depth 5
if ($sessionExit -ne 0) { exit 2 }
