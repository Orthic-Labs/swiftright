param([string]$ReceiptsDir, [string]$Hb, [int]$StaleSec = 360)
$ErrorActionPreference = 'Continue'
$done = Join-Path $ReceiptsDir 'DONE'
while ($true) {
    Start-Sleep -Seconds 10
    if (Test-Path -LiteralPath $done) { exit 0 }
    $age = 0
    try { $age = ((Get-Date) - [datetime]::Parse((Get-Content -LiteralPath $Hb -Raw).Trim())).TotalSeconds } catch { $age = 0 }
    if ($age -gt $StaleSec) {
        $o = @('WATCHDOG: no heartbeat for ' + [int]$age + ' s at ' + (Get-Date -Format o))
        try { $o += (Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'powershell|SliceApp|AppInstaller|explorer' } | ForEach-Object { 'pid=' + $_.ProcessId + ' ' + $_.Name + ' ' + $_.CommandLine }) } catch { }
        try {
            Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
            $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
            $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height); $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size); $bmp.Save((Join-Path $ReceiptsDir 'watchdog.jpg'), [System.Drawing.Imaging.ImageFormat]::Jpeg)
        } catch { $o += ('screenshot failed: ' + $_.Exception.Message) }
        [IO.File]::WriteAllLines((Join-Path $ReceiptsDir 'watchdog.txt'), $o)
        Set-Content -LiteralPath $done -Value 'watchdog'
        Start-Sleep -Seconds 5
        Stop-Computer -Force
        exit 0
    }
}
