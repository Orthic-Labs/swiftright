param([string]$Base = 'D:\Claude\sr0o-f1')
$ErrorActionPreference = 'Continue'
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Set-Location "$Base\uia-recorder"
& swift build -c release --scratch-path "$Base\scratch" 2>&1 | ForEach-Object { $_.ToString() }
"swift build exit=$LASTEXITCODE"
$bin = (& swift build -c release --scratch-path "$Base\scratch" --show-bin-path)
"bin=$bin"
Get-ChildItem $bin -Filter *.exe | ForEach-Object { "{0} {1}" -f $_.Name, $_.Length }
