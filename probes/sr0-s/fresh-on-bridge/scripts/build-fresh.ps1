# Builds FreshOnBridge.exe on Windows (run through `win`). Layout under $Base mirrors the repo:
#   $Base\probes\sr0-s\fresh-runtime, $Base\probes\sr0-s\fresh-on-bridge, $Base\packages\SwiftRightBridge
#   $Base\render\swiftright-abi\include\swiftright.h (dereferenced copy, the bridge header symlink target)
# Renderer DLL: the ABI v0 payload already staged by examples/BridgeSmoke (no Rust build here).
# ComCtl v6 manifest dependency: the renderer DLL imports comctl32!TaskDialogIndirect (see BridgeSmoke).
param(
  [string]$Base = 'D:\Claude\sr0s-bridge',
  [string]$Dll = 'D:\Claude\sr0b-abi0\payload\bin\swiftright_render.dll'
)
$ErrorActionPreference = 'Stop'
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Set-Location "$Base\probes\sr0-s\fresh-on-bridge"
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
& swift build -c release --scratch-path "$Base\scratch" "-Xlinker" "/MANIFEST:EMBED" "-Xlinker" $dep
"swift build exit=$LASTEXITCODE"
# A failed build must stop here: the binary listing below would otherwise show a stale exe.
if ($LASTEXITCODE -ne 0) { throw "swift build failed (exit $LASTEXITCODE); no binary copied" }
$bin = (& swift build -c release --scratch-path "$Base\scratch" --show-bin-path).Trim()
Copy-Item $Dll $bin -Force
"bin=$bin"
Get-ChildItem $bin | Where-Object { $_.Extension -in ".exe", ".dll" } | ForEach-Object { "{0} {1} {2}" -f $_.Name, $_.Length, $_.LastWriteTime.ToString("o") }
