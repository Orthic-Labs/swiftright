# Headless checks of WorkloadWin.exe (no window, no renderer, safe on a busy host): timer micro-benchmark, resolved node
# counts + runtime flush timing, and the model self-test (the latter only exists on macOS: the Windows main queue needs the
# renderer pump). Run as a file: win "powershell -NoProfile -ExecutionPolicy Bypass -File <this>"
param([string]$Base = 'D:\Claude\sr0b-workload')
$b = Get-Content -Raw "$Base\build.json" | ConvertFrom-Json
$bin = Split-Path $b.exe
$env:Path = "C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;$bin;" + $env:Path
Set-Location $bin
"exe_sha256=$($b.exe_sha256)"
& .\WorkloadWin.exe --overhead; "overhead exit=$LASTEXITCODE"
& .\WorkloadWin.exe --count-nodes; "count-nodes exit=$LASTEXITCODE"
& .\WorkloadWin.exe --model-selftest 5; "model-selftest exit=$LASTEXITCODE (2 = not available on Windows, by design)"
# Commit path: the incremental, flattened commit conversion must show the renderer exactly what a full commit shows (mock renderer,
# no window), then the per-commit timings at 200 rows.
& .\WorkloadWin.exe --bench --verify; "bench-verify exit=$LASTEXITCODE"
& .\WorkloadWin.exe --bench --iters 40; "bench exit=$LASTEXITCODE"
