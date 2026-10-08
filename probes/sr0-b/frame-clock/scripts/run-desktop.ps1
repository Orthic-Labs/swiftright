# SR0-B frame-clock probe: runs SwiftHost.exe in an interactive desktop session.
# Needed because SSH sessions (session 0) have no DirectX-capable desktop (DXGI_ERROR_NOT_CURRENTLY_AVAILABLE).
# Variants are interleaved per round: base (no timeBeginPeriod) and tbp (timeBeginPeriod(1) via --timer-res-1).
# Each run writes events.csv, dwm.csv, meta.txt, jobs.csv and ticks.csv into its own directory under $base\runs\<stamp>\.
# While each run is alive, samples every 250 ms whether the probe window is visible and foreground,
# using the process MainWindowHandle (the earlier title lookup did not match).
param(
    [int]$Runs = 5,
    [string]$OutFile = ''
)

$ErrorActionPreference = 'Continue'
$base = 'D:\Claude\sr0b-frame-clock'
$bin = "$base\scratch-1\out\Products\Release-windows-x86_64"
$exe = Join-Path $bin 'SwiftHost.exe'
$swiftBin = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $OutFile) { $OutFile = "$base\result-$stamp.txt" }
$runRoot = "$base\runs\$stamp"
New-Item -ItemType Directory -Force $runRoot | Out-Null

Add-Type -Namespace SR0F -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
'@

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) started=$(Get-Date -Format o)")
$lines.Add("exe=$exe exists=$(Test-Path $exe) runs_per_variant=$Runs runRoot=$runRoot")

$variants = @(
    @{ name = 'base'; extra = @() },
    @{ name = 'tbp';  extra = @('--timer-res-1') }
)

for ($r = 1; $r -le $Runs; $r++) {
    foreach ($v in $variants) {
        $id = "$($v.name)-$r"
        $outDir = "$runRoot\$id"
        New-Item -ItemType Directory -Force $outDir | Out-Null
        $lines.Add("=== RUN $id start=$(Get-Date -Format o)")

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exe
        $psi.Arguments = (@("--out=$outDir") + $v.extra) -join ' '
        $psi.WorkingDirectory = $bin
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.EnvironmentVariables['Path'] = "$swiftBin;$bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()

        $samples = 0; $visible = 0; $foreground = 0
        $deadline = (Get-Date).AddSeconds(120)
        while (-not $proc.HasExited -and (Get-Date) -lt $deadline) {
            $proc.Refresh()
            $hwnd = $proc.MainWindowHandle
            $fg = [SR0F.Win]::GetForegroundWindow()
            $samples++
            if ($hwnd -ne [IntPtr]::Zero) {
                $visible++
                if ($fg -eq $hwnd) { $foreground++ }
            }
            Start-Sleep -Milliseconds 250
        }
        if (-not $proc.HasExited) { $proc.Kill(); $lines.Add('TIMEOUT: killed after 120 s') }
        $proc.WaitForExit()
        $lines.Add("focus_samples: total=$samples window_visible=$visible window_foreground=$foreground")
        $lines.Add([string]$stdout.Result)
        $lines.Add([string]$stderr.Result)
        $lines.Add("exit=$($proc.ExitCode) end=$(Get-Date -Format o)")
    }
}

$lines.Add("finished=$(Get-Date -Format o)")
[System.IO.File]::WriteAllText($OutFile, [string]::Join("`r`n", $lines))
Write-Host "wrote $OutFile"
