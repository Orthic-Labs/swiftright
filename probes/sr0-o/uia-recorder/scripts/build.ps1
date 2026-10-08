# Builds UIARecorder + UIACompare on Windows. Layout: $Base\comparator and $Base\uia-recorder (path dependency).
param([string]$Base = 'D:\Claude\sr0o-uia', [string]$Config = 'release')
$ErrorActionPreference = 'Continue'
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Set-Location "$Base\uia-recorder"
& swift build -c $Config --scratch-path "$Base\scratch" 2>&1 | ForEach-Object { $_.ToString() }
"swift build exit=$LASTEXITCODE"
$bin = (& swift build -c $Config --scratch-path "$Base\scratch" --show-bin-path)
"bin=$bin"
Get-ChildItem $bin -Filter *.exe | ForEach-Object { "{0} {1}" -f $_.Name, $_.Length }
