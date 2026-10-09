# Builds WorkloadWin.exe (SR0 plan v2 lane R10) on Windows. Run as a FILE through the bridge:
#   win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0b-workload\probes\sr0-b\workload\scripts\build-workload.ps1"
# Never inline: the manifest-dependency quoting below is stripped by inline ssh commands (frame-clock BATCH4-RUNBOOK).
# Layout under $Base mirrors the repo:
#   $Base\probes\sr0-b\workload, $Base\probes\sr0-s\fresh-runtime, $Base\packages\SwiftRightBridge,
#   $Base\render\swiftright-abi\include\swiftright.h (dereferenced copy)
# Renderer DLL: the ABI 0.6 payload (sha256 777F14C4... sr0s-bridge06b tuple), staged beside the exe and hash-checked before and after.
param(
  [string]$Base = 'D:\Claude\sr0b-workload',
  [string]$Dll = 'D:\Claude\sr0s-bridge06b\scratch\out\Products\Release-windows-x86_64\swiftright_render.dll',
  [string]$ExpectDllSha256 = '7533963D124C066159322EDF540BD45637CC294173FD9DB2AF95D4D4A3F149FC'
)
$ErrorActionPreference = 'Stop'
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
# The renderer payload is staged under $Base\payload\bin; the original build output may be gone. Fall back to the stage copy
# (the hash gate below still pins the exact bytes).
if (-not (Test-Path -LiteralPath $Dll)) { $Dll = "$Base\payload\bin\swiftright_render.dll" }
$srcHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Dll).Hash
"dll_source=$Dll sha256=$srcHash"
if ($srcHash -ne $ExpectDllSha256.ToUpper()) { throw "renderer DLL source hash mismatch ($srcHash); nothing built" }
Set-Location "$Base\probes\sr0-b\workload"
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
$sw = [Diagnostics.Stopwatch]::StartNew()
& swift build -c release --product WorkloadWin --scratch-path "$Base\scratch" "-Xlinker" "/MANIFEST:EMBED" "-Xlinker" $dep
$buildExit = $LASTEXITCODE
$buildS = [math]::Round($sw.Elapsed.TotalSeconds, 1)
"swift build exit=$buildExit seconds=$buildS"
if ($buildExit -ne 0) { throw "swift build failed (exit $buildExit); no binary copied" }
$bin = (& swift build -c release --scratch-path "$Base\scratch" --show-bin-path).Trim()
function Copy-Unless-Same([string]$from, [string]$to) {
  if (Test-Path -LiteralPath $to) { if ((Resolve-Path -LiteralPath $from).Path -eq (Resolve-Path -LiteralPath $to).Path) { return } }
  Copy-Item -LiteralPath $from -Destination $to -Force
}
Copy-Unless-Same $Dll "$bin\swiftright_render.dll"
New-Item -ItemType Directory -Force "$Base\payload\bin" | Out-Null
Copy-Unless-Same $Dll "$Base\payload\bin\swiftright_render.dll"
"bin=$bin"
Get-ChildItem $bin | Where-Object { $_.Extension -in '.exe', '.dll' } | ForEach-Object { "{0} {1} {2}" -f $_.Name, $_.Length, $_.LastWriteTime.ToString('o') }
$binDll = (Get-FileHash -Algorithm SHA256 -LiteralPath "$bin\swiftright_render.dll").Hash
$payDll = (Get-FileHash -Algorithm SHA256 -LiteralPath "$Base\payload\bin\swiftright_render.dll").Hash
$exeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath "$bin\WorkloadWin.exe").Hash
"dll_bin_sha256=$binDll"
"dll_payload_sha256=$payDll"
"exe_sha256=$exeHash"
if ($binDll -ne $ExpectDllSha256.ToUpper() -or $payDll -ne $ExpectDllSha256.ToUpper()) { throw 'renderer DLL copy hash mismatch after staging' }
$gitHead = ''
if (Test-Path "$Base\SOURCE-HEAD.txt") { $gitHead = (Get-Content -Raw "$Base\SOURCE-HEAD.txt").Trim() }
$build = [ordered]@{
  configuration = 'release'; exe = "$bin\WorkloadWin.exe"; exe_sha256 = $exeHash; dll_sha256 = $binDll
  dll_expected = $ExpectDllSha256.ToUpper(); build_seconds = $buildS; source_head = $gitHead
  swift = ((& swift --version 2>&1) -join ' '); built_utc = [DateTime]::UtcNow.ToString('o')
}
$build | ConvertTo-Json | Set-Content -Encoding utf8 "$Base\build.json"
"build.json written"
# Manifest check (mt.exe): the renderer DLL needs ComCtl v6 (comctl32!TaskDialogIndirect).
& "$Base\probes\sr0-b\workload\scripts\verify-manifest.ps1" -Base $Base
