# Compiles one probe variant on Windows (run through `win`; build only, nothing is launched).
# Layout under $Base mirrors the repo: $Base\probes\sr1-pulse-probe (+ out\variants\<v>) and
# $Base\probes\sr0-s\fresh-runtime. Expected to FAIL for nogaps/raw; the log is the product.
param([string]$Base = 'D:\Claude\sr1-pulse-probe', [string]$Variant = 'full')
$ErrorActionPreference = 'Continue'
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$root = "$Base\probes\sr1-pulse-probe"
Set-Location $root
Get-ChildItem "$root\out\src\*.swift" -ErrorAction SilentlyContinue | Remove-Item -Force
New-Item -ItemType Directory -Force "$root\out\src" | Out-Null
Copy-Item "$root\out\variants\$Variant\*.swift" "$root\out\src\" -Force
$log = "$root\out\win-$Variant.txt"
& swift build --target PulseProbe --scratch-path "$Base\scratch" *> $log
"swift build exit=$LASTEXITCODE variant=$Variant log=$log"
