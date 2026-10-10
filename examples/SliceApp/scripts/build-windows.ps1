# Builds SliceApp.exe on Windows, verifies the embedded manifest with mt.exe, derives the Swift runtime DLL
# inventory from the import closure with dumpbin /dependents, and copies the verified exe to the fixed path
# that swift-package.json names (.build\payload\SliceApp.exe). It never launches the app.
#
# Root: the repository root two levels above examples\SliceApp (repo checkout or staging copy alike), unless
# -Base is given. Dependencies resolve by path: probes\sr0-s\fresh-runtime and packages\SwiftRightBridge.
# The renderer DLL is not needed to build (it is loaded explicitly at run time).
#
# Run through the Windows host:
#   win "powershell -NoProfile -ExecutionPolicy Bypass -File <root>\examples\SliceApp\scripts\build-windows.ps1"
# Inline ssh strips the manifest quotes; the build lives in this file.
param([string]$Base = '')
$ErrorActionPreference = 'Stop'
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

$app = Resolve-Path (Join-Path $PSScriptRoot '..')
if (-not $Base) { $Base = Resolve-Path (Join-Path $app '..\..') }
$manifest = Join-Path $app 'Windows\SliceApp.manifest'
$scratch = Join-Path $app '.build\swiftpm'
$payload = Join-Path $app '.build\payload'
Set-Location $app

# ComCtl v6 and PerMonitorV2 come from the manifest file, embedded by the linker.
# GUI subsystem: the packaged exe must not open a console window. /SUBSYSTEM:WINDOWS alone makes the linker look for WinMain;
# Swift's @main emits C `main`, so /ENTRY:mainCRTStartup keeps the CRT startup that calls it. Consumer link flags, not manifest
# flags (no unsafeFlags in Package.swift). @rightkit/release >= 0.2.145 checks the PE subsystem at stage (swift-package.json
# windows.subsystem "gui", SWIFT_STAGE_SUBSYSTEM). Windows/WindowsLog.swift sends stdout/stderr to a log file when no handle is attached.
& swift build -c release --scratch-path $scratch '-Xlinker' '/MANIFEST:EMBED' '-Xlinker' "/MANIFESTINPUT:$manifest" '-Xlinker' '/SUBSYSTEM:WINDOWS' '-Xlinker' '/ENTRY:mainCRTStartup'
"swift build exit=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) { throw "swift build failed (exit $LASTEXITCODE); nothing verified or copied" }
$bin = (& swift build -c release --scratch-path $scratch --show-bin-path).Trim()
$exe = Join-Path $bin 'SliceApp.exe'
if (-not (Test-Path $exe)) { throw "missing $exe" }
"exe=$exe bytes=$((Get-Item $exe).Length)"

# Embedded manifest check (mt.exe, x64 build of the Windows SDK).
$mt = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter mt.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\x64\\mt\.exe$' } | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $mt) { throw 'mt.exe (x64) not found in the Windows SDK' }
$verify = Join-Path $app '.build\verify'
New-Item -ItemType Directory -Force $verify | Out-Null
$extracted = Join-Path $verify 'SliceApp.embedded.manifest.xml'
& $mt.FullName "-inputresource:$exe;#1" "-out:$extracted"
"mt exit=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) { throw 'mt.exe could not read the embedded manifest (resource #1)' }
$text = Get-Content $extracted -Raw
if ($text -notmatch 'name="Microsoft\.Windows\.Common-Controls"[^>]*version="6\.0\.0\.0"') { throw 'embedded manifest lacks ComCtl v6' }
if ($text -notmatch '<dpiAwareness[^>]*>PerMonitorV2</dpiAwareness>') { throw 'embedded manifest lacks PerMonitorV2 DPI awareness' }
'manifest ok: ComCtl v6 + PerMonitorV2 embedded'

# Import closure: every dependency reachable from the exe, resolved in the Swift runtime, then System32.
$dumpbin = Get-ChildItem 'C:\Program Files\Microsoft Visual Studio' -Recurse -Filter dumpbin.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\Hostx64\\x64\\dumpbin\.exe$' } | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $dumpbin) { throw 'dumpbin.exe (Hostx64\x64) not found' }
$runtimeDir = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin'
$system32 = Join-Path $env:SystemRoot 'System32'
function Get-Dependents([string]$file) {
    & $dumpbin.FullName /dependents $file | ForEach-Object { if ($_ -match '^\s+(\S+\.dll)\s*$') { $Matches[1] } }
}
$queue = New-Object System.Collections.Queue
$queue.Enqueue($exe)
$seen = @{}
$swiftDlls = @{}
$unresolved = @{}
$systemDlls = @{}
while ($queue.Count -gt 0) {
    $file = $queue.Dequeue()
    foreach ($dep in (Get-Dependents $file)) {
        $key = $dep.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $inRuntime = Join-Path $runtimeDir $dep
        if (Test-Path $inRuntime) { $swiftDlls[$dep] = $inRuntime; $queue.Enqueue($inRuntime); continue }
        if ($dep -match '^(api|ext)-ms-win-') { $systemDlls[$dep] = 'api-set'; continue }
        if (Test-Path (Join-Path $system32 $dep)) { $systemDlls[$dep] = 'System32'; continue }
        $unresolved[$dep] = $file
    }
}
'--- swift runtime DLLs (import closure of SliceApp.exe)'
$swiftDlls.Keys | Sort-Object | ForEach-Object { "  $_" }
'--- system DLLs (System32 and api-sets)'
$systemDlls.Keys | Sort-Object | ForEach-Object { "  $_" }
'--- unresolved (must be empty)'
$unresolved.Keys | Sort-Object | ForEach-Object { "  $_ (needed by $($unresolved[$_]))" }
if ($unresolved.Count -gt 0) { throw 'unresolved import dependencies (see list above)' }

# Fixed payload path for the release stage (swift-package.json windows.exe).
New-Item -ItemType Directory -Force $payload | Out-Null
Copy-Item $exe (Join-Path $payload 'SliceApp.exe') -Force
"payload=$(Join-Path $payload 'SliceApp.exe') sha256=$((Get-FileHash (Join-Path $payload 'SliceApp.exe') -Algorithm SHA256).Hash)"
