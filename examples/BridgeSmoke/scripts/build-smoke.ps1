# Builds BridgeSmoke.exe on Windows (run through `win`). Layout under $Base mirrors the repo:
#   $Base\packages\SwiftRightBridge, $Base\examples\BridgeSmoke, $Base\payload\bin\swiftright_render.dll
# The ComCtl v6 manifest dependency is required because the renderer DLL (GPUI) imports
# comctl32!TaskDialogIndirect; the consumer invocation supplies it (no unsafeFlags in manifests).
param([string]$Base = 'D:\Claude\sr0b-abi0')
$ErrorActionPreference = 'Stop'
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Set-Location "$Base\examples\BridgeSmoke"
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
& swift build -c release --scratch-path "$Base\scratch" "-Xlinker" "/MANIFEST:EMBED" "-Xlinker" $dep
"swift build exit=$LASTEXITCODE"
$bin = "$Base\scratch\out\Products\Release-windows-x86_64"
if (-not (Test-Path $bin)) { $bin = (& swift build -c release --scratch-path "$Base\scratch" --show-bin-path) }
Copy-Item "$Base\payload\bin\swiftright_render.dll" $bin -Force
"bin=$bin"
Get-ChildItem $bin -Filter *.exe, *.dll | ForEach-Object { "{0} {1}" -f $_.Name, $_.Length }
