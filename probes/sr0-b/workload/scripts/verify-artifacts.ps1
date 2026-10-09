# Artifact identity gate for the workload tree: WorkloadWin.exe and swiftright_render.dll hashes. Prints one ARTIFACT line,
# then ARTIFACT_OK (exit 0) or ARTIFACT_MISMATCH / ARTIFACT_MISSING (exit 1). Pass -ExpectExe to bind a specific build.
param(
  [string]$Base = 'D:\Claude\sr0b-workload',
  [string]$ExpectExe = '',
  [string]$ExpectDll = '4FB068F0B6C73DE9A5DDE1A536E97EEDD08E2FEA3C0DD8B92FC0E4A78E53298F'
)
$ErrorActionPreference = 'Stop'
$b = Get-Content -Raw "$Base\build.json" | ConvertFrom-Json
$bin = Split-Path $b.exe
foreach ($f in @("$bin\WorkloadWin.exe", "$bin\swiftright_render.dll")) { if (-not (Test-Path -LiteralPath $f)) { "ARTIFACT_MISSING $f"; exit 1 } }
$e = (Get-FileHash -Algorithm SHA256 -LiteralPath "$bin\WorkloadWin.exe").Hash
$d = (Get-FileHash -Algorithm SHA256 -LiteralPath "$bin\swiftright_render.dll").Hash
"ARTIFACT base=$Base bin=$bin exe_sha256=$e dll_sha256=$d expect_exe=$ExpectExe expect_dll=$ExpectDll"
if ($d -ne $ExpectDll.ToUpper() -or ($ExpectExe -and $e -ne $ExpectExe.ToUpper()) -or $e -ne $b.exe_sha256.ToUpper()) { 'ARTIFACT_MISMATCH'; exit 1 }
'ARTIFACT_OK'
