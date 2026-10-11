# Builds TextGeom06.exe and Modal06.exe on the Dell (run through `win "powershell -NoProfile -ExecutionPolicy Bypass -File <this>"`).
# Layout under $Base mirrors the repo: packages\SwiftRightBridge, examples\BridgeGeoModal, payload\bin\swiftright_render.dll.
# The renderer is NOT rebuilt: the final DLL is copied (hash-checked) from its pinned location, and the hosts link nothing
# from it (explicit LoadLibraryW). ComCtl v6 manifest dependency: the renderer imports comctl32!TaskDialogIndirect.
# -RendererSha: expected hash of $RendererSrc when it is not the final tuple (the modal-stall fix build is a new DLL).
param(
  [string]$Base = 'D:\Claude\sr0-geomodal',
  [string]$RendererSrc = 'D:\Claude\sr0b-abi06f\bin\swiftright_render.dll',
  [string]$RendererSha = '7533963d124c066159322edf540bd45637cc294173fd9db2af95d4d4a3f149fc'
)
$ErrorActionPreference = 'Stop'
$pinned = $RendererSha.ToLower()
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$h = (Get-FileHash -Algorithm SHA256 -LiteralPath $RendererSrc).Hash.ToLower()
if ($h -ne $pinned) { throw "renderer hash $h is not the expected $pinned" }
New-Item -ItemType Directory -Force "$Base\payload\bin", "$Base\bin" | Out-Null
Copy-Item $RendererSrc "$Base\payload\bin\swiftright_render.dll" -Force
Set-Location "$Base\examples\BridgeGeoModal"
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
& swift build -c release --scratch-path "$Base\scratch" "-Xlinker" "/MANIFEST:EMBED" "-Xlinker" $dep
"swift build exit=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) { throw "swift build failed" }
$bin = "$Base\scratch\out\Products\Release-windows-x86_64"
if (-not (Test-Path $bin)) { $bin = (& swift build -c release --scratch-path "$Base\scratch" --show-bin-path).Trim(); if ($LASTEXITCODE -ne 0 -or -not $bin) { throw "swift --show-bin-path failed (exit $LASTEXITCODE)" } }
"bin=$bin"
foreach ($e in 'TextGeom06.exe', 'Modal06.exe', 'ColdOpen06.exe') { Copy-Item (Join-Path $bin $e) "$Base\bin\$e" -Force }
Copy-Item "$Base\payload\bin\swiftright_render.dll" "$Base\bin\swiftright_render.dll" -Force
Get-ChildItem "$Base\bin\*" -Include *.exe, *.dll | ForEach-Object { "{0} {1} bytes {2} sha256={3}" -f $_.Name, $_.Length, $_.LastWriteTime.ToString('o'), (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLower() }
# manifest check (best effort): the embedded manifest must carry the comctl32 v6 dependency
$mt = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\mt.exe' -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -Last 1
if ($mt) {
  foreach ($e in 'TextGeom06.exe', 'Modal06.exe', 'ColdOpen06.exe') {
    $tmp = Join-Path $env:TEMP ("$e.$([guid]::NewGuid().ToString('N')).manifest")
    & $mt.FullName "-inputresource:$Base\bin\$e;#1" "-out:$tmp" | Out-Null
    $mtExit = $LASTEXITCODE
    if ($mtExit -ne 0) { throw "mt.exe failed for $e (exit $mtExit)" }
    $manifestOk = (Test-Path $tmp) -and ((Get-Content -Raw $tmp) -match 'Microsoft.Windows.Common-Controls')
    "{0} manifest comctl32 v6 dependency: {1} output={2}" -f $e, $manifestOk, $tmp
    if (-not $manifestOk) { throw "manifest lacks comctl32 v6 for $e" }
  }
} else { throw 'mt.exe not found: manifest not inspected' }
