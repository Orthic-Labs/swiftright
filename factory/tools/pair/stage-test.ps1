# Run `swift test` (default build system, --jobs 1) for one package of a staged product tree. Output: <Log>; exit code = swift's.
param([Parameter(Mandatory)][string]$Stage,[Parameter(Mandatory)][string]$Package,[Parameter(Mandatory)][string]$Log)
$ErrorActionPreference='Stop'
$tc='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin'
$env:Path="$tc;C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;"+$env:Path
$pkg=Join-Path $Stage $Package
$name=Split-Path $Stage -Leaf
$scratch="D:\Claude\swiftright\.factory-work\product-test-scratch\$name\"+($Package -replace '[\\/]','_')
New-Item -ItemType Directory -Force (Split-Path $scratch) | Out-Null
New-Item -ItemType Directory -Force (Split-Path $Log) | Out-Null
$ErrorActionPreference='Continue'   # swift prints progress on stderr
& "$tc\swift.exe" test --package-path $pkg --scratch-path $scratch --jobs 1 *> $Log
exit $LASTEXITCODE
