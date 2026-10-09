# Builds SR1Gallery.exe on Windows (run through `win`; see the RESULT notes for the exact command).
# Layout under $Base mirrors the repo (dereferenced copies, because the bridge header is a symlink):
#   $Base\probes\sr0-s\fresh-runtime   (path dependency)
#   $Base\probes\sr1-win-backend        (this package, includes sr1-gallery.manifest)
#   $Base\packages\SwiftRightBridge     (path dependency)
#   $Base\render\swiftright-abi\include\swiftright.h   (symlink target of the bridge header)
# Renderer DLL: the ABI 0.5 payload, verified by SHA-256 before it is copied next to the exe. No Rust build here.
# The exe is linked with the app manifest (ComCtl v6 + PerMonitorV2) and the manifest is checked in the binary.
# This script builds only. It never starts SR1Gallery.exe (a run needs the interactive desktop).
param(
  [string]$Base = 'D:\Claude\sr1-gallery',
  [string]$Dll = 'D:\Claude\sr0b-abi0\payload\bin\swiftright_render.dll'
)
$ErrorActionPreference = 'Stop'
$expectedSha = '2DC4B6F783EF7BC78163C3B02B6413CD4539CD0F9A0D64C92C0B4C0254EBF1E1'
$actualSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $Dll).Hash
"dll_sha256=$actualSha"
if ($actualSha -ne $expectedSha) { throw "renderer DLL SHA-256 mismatch (expected $expectedSha)" }

$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$pkg = "$Base\probes\sr1-win-backend"
Set-Location $pkg
$manifest = "$pkg\sr1-gallery.manifest"
if (-not (Test-Path $manifest)) { throw "missing manifest $manifest" }

& swift build -c release --scratch-path "$Base\scratch" "-Xlinker" "/MANIFEST:EMBED" "-Xlinker" "/MANIFESTINPUT:$manifest"
"swift build exit=$LASTEXITCODE"
if ($LASTEXITCODE -ne 0) { throw "swift build failed (exit $LASTEXITCODE); no binary copied" }

$bin = (& swift build -c release --scratch-path "$Base\scratch" --show-bin-path).Trim()
Copy-Item $Dll $bin -Force
"bin=$bin"
Set-Content -Path "$Base\bin-path.txt" -Value $bin -Encoding ASCII
$exe = Join-Path $bin 'SR1Gallery.exe'
if (-not (Test-Path $exe)) { throw "SR1Gallery.exe not produced" }

# Manifest check in the binary: the embedded RT_MANIFEST is plain UTF-8 XML, so search the bytes for the markers.
$bytes = [IO.File]::ReadAllBytes($exe)
$text = [Text.Encoding]::UTF8.GetString($bytes)
$markers = @('Microsoft.Windows.Common-Controls', 'version="6.0.0.0"', 'PerMonitorV2', 'true/pm')
foreach ($m in $markers) { "manifest_marker[$m]=$($text.Contains($m))" }
$missing = $markers | Where-Object { -not $text.Contains($_) }
if ($missing) { throw "embedded manifest lacks: $($missing -join ', ')" }

Get-ChildItem $bin | Where-Object { $_.Extension -in '.exe', '.dll' } | ForEach-Object {
  '{0} {1} {2}' -f $_.Name, $_.Length, $_.LastWriteTime.ToString('o')
}
"dll_in_bin_sha256=$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $bin 'swiftright_render.dll')).Hash)"
"BUILD OK"
