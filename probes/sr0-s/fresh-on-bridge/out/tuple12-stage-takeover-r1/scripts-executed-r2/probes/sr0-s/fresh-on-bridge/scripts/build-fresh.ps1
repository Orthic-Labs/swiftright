# Builds FreshOnBridge.exe on Windows (run through `win`). Layout under $Base mirrors the repo:
#   $Base\probes\sr0-s\fresh-runtime, $Base\probes\sr0-s\fresh-on-bridge, $Base\packages\SwiftRightBridge
#   $Base\render\swiftright-abi\include\swiftright.h (dereferenced copy, the bridge header symlink target)
# Renderer DLL: the ABI v0 payload already staged by examples/BridgeSmoke (no Rust build here).
# ComCtl v6 manifest dependency: the renderer DLL imports comctl32!TaskDialogIndirect (see BridgeSmoke).
param(
  [string]$Base = 'D:\Claude\sr0s-bridge',
  [string]$Dll = 'D:\Claude\sr0b-abi0\payload\bin\swiftright_render.dll',
  # Optional identity gate: when set, the source DLL must hash to this value before anything is built, and the copy in
  # the release bin dir must hash to it afterwards. The 0.6 pass sets it to the sr1-abi06 payload hash.
  [string]$ExpectDllSha256 = ''
)
$ErrorActionPreference = 'Stop'
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
if ($ExpectDllSha256) {
  $srcHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Dll).Hash
  "dll_source=$Dll sha256=$srcHash"
  if ($srcHash -ne $ExpectDllSha256.ToUpper()) { throw "renderer DLL source hash mismatch ($srcHash); nothing built" }
}
Set-Location "$Base\probes\sr0-s\fresh-on-bridge"
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
& swift build -c release --scratch-path "$Base\scratch" "-Xlinker" "/MANIFEST:EMBED" "-Xlinker" $dep
"swift build exit=$LASTEXITCODE"
# A failed build must stop here: the binary listing below would otherwise show a stale exe.
if ($LASTEXITCODE -ne 0) { throw "swift build failed (exit $LASTEXITCODE); no binary copied" }
$bin = (& swift build -c release --scratch-path "$Base\scratch" --show-bin-path).Trim()
if ($LASTEXITCODE -ne 0 -or -not $bin) { throw "swift --show-bin-path failed (exit $LASTEXITCODE); no binary copied" }
Copy-Item $Dll $bin -Force
# Keep a copy of the renderer under the tree's own payload dir as well (the staged, identity-checked location).
New-Item -ItemType Directory -Force "$Base\payload\bin" | Out-Null
Copy-Item $Dll "$Base\payload\bin\swiftright_render.dll" -Force
"bin=$bin"
Get-ChildItem $bin | Where-Object { $_.Extension -in ".exe", ".dll" } | ForEach-Object { "{0} {1} {2}" -f $_.Name, $_.Length, $_.LastWriteTime.ToString("o") }
$binDll = (Get-FileHash -Algorithm SHA256 -LiteralPath "$bin\swiftright_render.dll").Hash
$payDll = (Get-FileHash -Algorithm SHA256 -LiteralPath "$Base\payload\bin\swiftright_render.dll").Hash
$exeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath "$bin\FreshOnBridge.exe").Hash
"dll_bin_sha256=$binDll"
"dll_payload_sha256=$payDll"
"exe_sha256=$exeHash"
if ($ExpectDllSha256 -and ($binDll -ne $ExpectDllSha256.ToUpper() -or $payDll -ne $ExpectDllSha256.ToUpper())) {
  throw "renderer DLL copy hash mismatch after staging"
}
