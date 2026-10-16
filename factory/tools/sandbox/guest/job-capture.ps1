# job-capture.ps1 - kind=capture. args: {"exe":"D:\\Claude\\swiftright\\.factory-work\\hosts\\<case>\\package\\scratch\\...\\FactoryProbe.exe","runs":N,"renderer":"D:\\...\\swiftright_render.dll"}.
# The renderer DLL is per job (args.renderer, a path under the mapped D:\Claude\swiftright\.factory-work); the host loads it through SWIFTRIGHT_RENDER_DLL. Without args.renderer the
# pinned default D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll is used (never overwritten). The host-built exe is read through the D: map, copied to a local
# folder, and run by the SAME capture.ps1 the Dell host uses (launch with --factory-capture-lease-seconds=40, HWND_BOTTOM, 500 ms, PrintWindow flags 3), in -Shared mode
# (no desktop.lock: the Sandbox is its own desktop). PNGs and done.json land in <JobDir>\out. Swift runtime DLLs come from C:\swiftrt via PATH.
param([Parameter(Mandatory)][string]$JobDir)
$ErrorActionPreference = 'Stop'
$job = Get-Content -LiteralPath "$JobDir\job.json" -Raw | ConvertFrom-Json
$runs = $(if ($job.args.runs) { [int]$job.args.runs } else { 1 })
$res = [ordered]@{ kind = 'capture'; ok = $false; runs = $runs; exe_source = [string]$job.args.exe }
try {
    $env:Path = 'C:\swiftrt;' + $env:Path
    $renderer = $(if ($job.args.renderer) { [string]$job.args.renderer } else { 'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll' })
    if (-not (Test-Path -LiteralPath $renderer)) { throw "renderer dll not visible in the guest: $renderer" }
    $env:SWIFTRIGHT_RENDER_DLL = $renderer   # inherited by capture.ps1 and the host it launches
    $src = [string]$job.args.exe
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "exe not visible in the guest: $src" }
    $work = 'C:\work\' + (Split-Path -Leaf $JobDir)
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    # Keep the exe's path relative to the package root and copy the root's top-level files (e.g. FactorySystemImageAssets.json),
    # because hosts search upward from the exe directory for resources.
    $pkg = $src -replace '\\scratch\\.*$', ''
    if ($pkg -ne $src -and (Test-Path -LiteralPath $pkg -PathType Container)) {
        $exe = Join-Path $work ($src.Substring($pkg.Length).TrimStart('\'))
        Get-ChildItem -LiteralPath $pkg -File | Copy-Item -Destination $work -Force
        # bundled fonts and other resources the host looks up beside the exe or above it
        if (Test-Path -LiteralPath "$pkg\Resources" -PathType Container) { Copy-Item -LiteralPath "$pkg\Resources" -Destination $work -Recurse -Force }
    } else { $exe = Join-Path $work 'FactoryProbe.exe' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $exe) | Out-Null
    Copy-Item -LiteralPath $src -Destination $exe -Force
    Get-ChildItem -LiteralPath (Split-Path -Parent $src) -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in ".dll",".json" } | Copy-Item -Destination (Split-Path -Parent $exe) -Force
    $res.exe_sha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLower()
    $res.renderer = $renderer
    $res.renderer_sha256 = (Get-FileHash -LiteralPath $renderer -Algorithm SHA256).Hash.ToLower()
    try { $res.video = @(Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name + ' ' + $_.DriverVersion }) } catch { }
    try { Add-Type -AssemblyName System.Windows.Forms; $b = [Windows.Forms.SystemInformation]::VirtualScreen; $res.screen = "$($b.Width)x$($b.Height)" } catch { }
    # The capture script: the sandbox copy (C:\sbq\guest, deployed by client.py sync_capture_tool) unless the job names one.
    # The GitHub runner passes factory/tools/pair/capture.ps1 from the checkout (ci_pair.py: args.captureScript).
    $capture = $(if ($job.args.captureScript) { [string]$job.args.captureScript } else { 'C:\sbq\guest\capture.ps1' })
    if (-not (Test-Path -LiteralPath $capture -PathType Leaf)) { throw "capture script not visible in the guest: $capture" }
    $out = "$JobDir\out"
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $capture -Exe $exe -Out $out -Runs $runs -Shared *>&1 | Out-File -LiteralPath "$JobDir\capture.log" -Encoding utf8
    $res.capture_exit = $LASTEXITCODE
    # PowerShell 5.1: piping ConvertFrom-Json into @() yields ONE element (the whole array), so the count was always wrong. Read it into a
    # variable, unwrap a {"value":[...]} envelope when there is one, then count the elements.
    $doneRaw = Get-Content -LiteralPath "$out\done.json" -Raw | ConvertFrom-Json
    if ($doneRaw -is [System.Management.Automation.PSCustomObject] -and $doneRaw.PSObject.Properties['value']) { $doneRaw = $doneRaw.value }
    $done = @($doneRaw)
    $res.done = $done
    $res.ok = [bool](@($done | Where-Object { $_.status -ne 'ok' }).Count -eq 0 -and $done.Count -eq $runs)
} catch { $res.error = $_.Exception.Message }
finally { Get-Process FactoryProbe -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
[IO.File]::WriteAllText("$JobDir\result.json", (ConvertTo-Json -InputObject $res -Depth 6), (New-Object Text.UTF8Encoding($false)))
exit 0
