# SR0-B drain probe: run SwiftHost.exe N times in an interactive desktop session.
# Needed because SSH sessions (session 0) have no DirectX-capable desktop: gpui fails with
# DXGI_ERROR_NOT_CURRENTLY_AVAILABLE (0x887A0022) when creating its renderer.
# While each run is alive, samples every 250 ms whether the gpui window ("SR0-B drain")
# exists and whether it is the foreground window. Writes D:\Claude\sr0b-gpui-drain\result.txt.
# The binary is unchanged; latency sample timestamps and per-frame intervals are not emitted by it.
# Late-dispatch fault test (ABI 0.2) build: pass -Base D:\Claude\sr0b-gpui-drain-late; look for the
# `late_dispatch ...` lines and `late_dispatch_verdict=PASS` in each run (also folded into verdict=).
param([int]$Runs = 5, [string]$Base = 'D:\Claude\sr0b-gpui-drain')

$ErrorActionPreference = 'Continue'
$base = $Base
$bin = "$base\scratch-1\out\Products\Release-windows-x86_64"
$exe = Join-Path $bin 'SwiftHost.exe'
$resultPath = "$base\result.txt"
$swiftBin = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin'

Add-Type -Namespace SR0B -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowW(string cls, string title);
'@

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) started=$(Get-Date -Format o)")
$lines.Add("exe=$exe exists=$(Test-Path $exe)")

for ($r = 1; $r -le $Runs; $r++) {
    $lines.Add("=== RUN $r start=$(Get-Date -Format o)")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.WorkingDirectory = $bin
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['Path'] = "$swiftBin;$bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEndAsync()
    $stderr = $proc.StandardError.ReadToEndAsync()

    $samples = 0; $visible = 0; $foreground = 0
    $firstState = $null; $lastState = $null
    $deadline = (Get-Date).AddSeconds(240)
    while (-not $proc.HasExited -and (Get-Date) -lt $deadline) {
        $hwnd = [SR0B.Win]::FindWindowW($null, 'SR0-B drain')
        $fg = [SR0B.Win]::GetForegroundWindow()
        $samples++
        $state = $null
        if ($hwnd -ne [IntPtr]::Zero) {
            $visible++
            $isFg = ($fg -eq $hwnd)
            if ($isFg) { $foreground++ }
            $state = "$(Get-Date -Format 'HH:mm:ss.fff') foreground=$isFg"
            if ($firstState -eq $null) { $firstState = $state }
            $lastState = $state
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $proc.HasExited) { $proc.Kill(); $lines.Add('TIMEOUT: killed after 240 s') }
    $proc.WaitForExit()
    $lines.Add("focus_samples: total=$samples window_visible=$visible window_foreground=$foreground")
    $lines.Add("focus_first_visible: $firstState")
    $lines.Add("focus_last_visible: $lastState")
    $lines.Add([string]$stdout.Result)
    $lines.Add([string]$stderr.Result)
    $lines.Add("exit=$($proc.ExitCode) end=$(Get-Date -Format o)")
}

$lines.Add("finished=$(Get-Date -Format o)")
[System.IO.File]::WriteAllText($resultPath, [string]::Join("`r`n", $lines))
Write-Host ([string][System.IO.File]::ReadAllText($resultPath))
