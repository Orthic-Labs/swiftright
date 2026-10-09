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
# Memory: the workload's whole schedule (20 ops/s, reorders, animations, cancellations, 10 keys/s, 60 Hz scrolling) on the mock renderer for 90 simulated seconds.
# Prints process heap / private bytes next to every table's size and the growth slope after warm-up; app-only heap slope must be ~0 (R10 memory diagnosis).
& .\WorkloadWin.exe --soak --marshal --soak-s 90 --report-s 30 --warm-s 30; "soak exit=$LASTEXITCODE"
