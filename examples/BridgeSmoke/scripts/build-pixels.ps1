# Builds BridgePixels.exe (SR0 T4) on Windows (run through `win`). Layout under $Base mirrors the repo, as build-smoke.ps1:
#   $Base\packages\SwiftRightBridge, $Base\examples\BridgeSmoke, and the pinned renderer DLL copied next to the exe (hash-checked).
# BridgeSmoke.exe is NOT rebuilt here: the tuple exe stays where the tuple put it.
param(
  [string]$Base = 'D:\Claude\sr0-t4',
  [string]$RendererSrc = 'D:\Claude\sr0-r08\smoke\payload\bin\swiftright_render.dll',
  [string]$RendererSha = 'e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'
)
$ErrorActionPreference = 'Stop'
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$h = (Get-FileHash -Algorithm SHA256 -LiteralPath $RendererSrc).Hash.ToLower()
if ($h -ne $RendererSha.ToLower()) { throw "renderer hash $h is not the expected $RendererSha" }
Set-Location "$Base\examples\BridgeSmoke"
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
& swift build -c release --product BridgePixels --scratch-path "$Base\scratch" "-Xlinker" "/MANIFEST:EMBED" "-Xlinker" $dep
"swift build exit=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) { throw 'swift build failed' }
$bin = "$Base\scratch\out\Products\Release-windows-x86_64"
if (-not (Test-Path $bin)) { $bin = (& swift build -c release --scratch-path "$Base\scratch" --show-bin-path).Trim(); if ($LASTEXITCODE -ne 0 -or -not $bin) { throw "swift --show-bin-path failed (exit $LASTEXITCODE)" } }
New-Item -ItemType Directory -Force "$Base\bin" | Out-Null
Copy-Item "$bin\BridgePixels.exe" "$Base\bin\BridgePixels.exe" -Force
Copy-Item $RendererSrc "$Base\bin\swiftright_render.dll" -Force
Get-ChildItem "$Base\bin\*" -Include *.exe, *.dll | ForEach-Object { "{0} {1} bytes sha256={2}" -f $_.Name, $_.Length, (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower() }
