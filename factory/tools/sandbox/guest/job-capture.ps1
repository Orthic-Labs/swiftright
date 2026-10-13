# job-capture.ps1 - kind=capture. args: {"exe":"D:\\Claude\\swiftright\\.factory-work\\hosts\\<case>\\package\\scratch\\...\\FactoryProbe.exe","runs":N}.
# The host-built exe is read through the D: map (the host source hard-codes D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll), copied to a local
# folder, and run by the SAME capture.ps1 the Dell host uses (launch with --factory-capture-lease-seconds=40, HWND_BOTTOM, 500 ms, PrintWindow flags 3), in -Shared mode
# (no desktop.lock: the Sandbox is its own desktop). PNGs and done.json land in <JobDir>\out. Swift runtime DLLs come from C:\swiftrt via PATH.
param([Parameter(Mandatory)][string]$JobDir)
$ErrorActionPreference = 'Stop'
$job = Get-Content -LiteralPath "$JobDir\job.json" -Raw | ConvertFrom-Json
$runs = $(if ($job.args.runs) { [int]$job.args.runs } else { 1 })
$res = [ordered]@{ kind = 'capture'; ok = $false; runs = $runs; exe_source = [string]$job.args.exe }
try {
    $env:Path = 'C:\swiftrt;' + $env:Path
    if (-not (Test-Path -LiteralPath 'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll')) { throw 'D: map missing: renderer dll not visible at the path the host hard-codes' }
    $src = [string]$job.args.exe
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "exe not visible in the guest: $src" }
    $work = 'C:\work\' + (Split-Path -Leaf $JobDir)
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $exe = Join-Path $work 'FactoryProbe.exe'
    Copy-Item -LiteralPath $src -Destination $exe -Force
    $res.exe_sha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLower()
    $res.renderer_sha256 = (Get-FileHash -LiteralPath 'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll' -Algorithm SHA256).Hash.ToLower()
    try { $res.video = @(Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name + ' ' + $_.DriverVersion }) } catch { }
    try { Add-Type -AssemblyName System.Windows.Forms; $b = [Windows.Forms.SystemInformation]::VirtualScreen; $res.screen = "$($b.Width)x$($b.Height)" } catch { }
    $out = "$JobDir\out"
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File 'C:\sbq\guest\capture.ps1' -Exe $exe -Out $out -Runs $runs -Shared *>&1 | Out-File -LiteralPath "$JobDir\capture.log" -Encoding utf8
    $res.capture_exit = $LASTEXITCODE
    $done = @(Get-Content -LiteralPath "$out\done.json" -Raw | ConvertFrom-Json)
    $res.done = $done
    $res.ok = [bool](@($done | Where-Object { $_.status -ne 'ok' }).Count -eq 0 -and $done.Count -eq $runs)
} catch { $res.error = $_.Exception.Message }
finally { Get-Process FactoryProbe -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
[IO.File]::WriteAllText("$JobDir\result.json", (ConvertTo-Json -InputObject $res -Depth 6), (New-Object Text.UTF8Encoding($false)))
exit 0
