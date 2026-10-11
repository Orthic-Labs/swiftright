# Artifact identity check for one SR0-S build tree. The tree's release bin dir must hold FreshOnBridge.exe and
# swiftright_render.dll with exactly the expected SHA-256 values. Prints one "ARTIFACT base=..." line; prints ARTIFACT_OK
# and exits 0 only when both match. Exits 1 on a mismatch or a missing file. Run through `win` as a file.
param(
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$ExpectExe,
  [Parameter(Mandatory)][string]$ExpectDll
)
$ErrorActionPreference = 'Stop'
$bin = "$Base\scratch\out\Products\Release-windows-x86_64"
$exe = "$bin\FreshOnBridge.exe"
$dll = "$bin\swiftright_render.dll"
foreach ($f in @($exe, $dll)) {
  if (-not (Test-Path -LiteralPath $f)) { "ARTIFACT_MISSING $f"; exit 1 }
}
$exeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash
$dllHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dll).Hash
"ARTIFACT base=$Base exe_sha256=$exeHash dll_sha256=$dllHash expect_exe=$ExpectExe expect_dll=$ExpectDll"
if ($exeHash -ne $ExpectExe.ToUpper() -or $dllHash -ne $ExpectDll.ToUpper()) {
  'ARTIFACT_MISMATCH'
  exit 1
}
'ARTIFACT_OK'
