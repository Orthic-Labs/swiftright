# UI-only incremental build check (architecture section 11): after a screen-source edit, an incremental release rebuild
# must invoke the Rust toolchain ZERO times and leave the renderer DLL (and any engine artifact) byte-identical.
# Mechanism: a shim directory is placed FIRST on PATH with cargo/rustc/rustup/rightkit shims (.cmd and .exe-named .cmd are
# found before real tools); any invocation appends to shim.log and fails the build. Hashes are taken before and after.
# Edits: appends a marker comment to Sources\WorkloadCore\WorkloadScreen.swift (restored afterwards), -Edits times.
#   win "powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr0b-workload\probes\sr0-b\workload\scripts\build-incremental.ps1"
param(
  [string]$Base = 'D:\Claude\sr0b-workload',
  [int]$Edits = 3,
  [string[]]$EngineArtifacts = @()
)
$ErrorActionPreference = 'Stop'
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$work = "$Base\probes\sr0-b\workload"
$shim = "$Base\shim"
$log = "$shim\shim.log"
New-Item -ItemType Directory -Force $shim | Out-Null
if (Test-Path $log) { Remove-Item $log -Force }
foreach ($n in 'cargo', 'rustc', 'rustup', 'rightkit', 'rustdoc', 'cargo-clippy') {
  "@echo off`r`necho %DATE% %TIME% $n %* >> `"$log`"`r`nexit /b 97`r`n" | Set-Content -Encoding ascii "$shim\$n.cmd"
}
$env:Path = "$shim;$env:Path"
$env:RUSTC_WRAPPER = "$shim\rustc.cmd"
$b = Get-Content -Raw "$Base\build.json" | ConvertFrom-Json
$bin = Split-Path $b.exe
$target = "$work\Sources\WorkloadCore\WorkloadScreen.swift"
$backup = "$Base\WorkloadScreen.swift.orig"
Copy-Item $target $backup -Force
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
function Hashes { $h = [ordered]@{}; foreach ($f in @("$bin\swiftright_render.dll") + $EngineArtifacts) { $h[$f] = (Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash }; $h }
$before = Hashes
$trials = @()
Set-Location $work
try {
  for ($i = 1; $i -le $Edits; $i++) {
    Add-Content -Path $target -Value "`n// R10 incremental edit $i $(Get-Date -Format o)"
    $before_log = if (Test-Path $log) { (Get-Content $log).Count } else { 0 }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & swift build -c release --product WorkloadWin --scratch-path "$Base\scratch" "-Xlinker" "/MANIFEST:EMBED" "-Xlinker" $dep *> "$Base\incremental-build-$i.txt"
    $rc = $LASTEXITCODE
    $sec = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    $after_log = if (Test-Path $log) { (Get-Content $log).Count } else { 0 }
    $trials += [ordered]@{ edit = $i; exit = $rc; seconds = $sec; rust_invocations = ($after_log - $before_log) }
    "edit=$i exit=$rc seconds=$sec rust_invocations=$($after_log - $before_log)"
  }
} finally {
  Copy-Item $backup $target -Force
}
$after = Hashes
$identical = $true
foreach ($k in $before.Keys) { if ($before[$k] -ne $after[$k]) { $identical = $false } }
$rust = ($trials | Measure-Object -Property rust_invocations -Sum).Sum
$shimLines = if (Test-Path $log) { @(Get-Content $log) } else { @() }
$out = [ordered]@{
  platform = 'windows'; edits = $Edits; trials = $trials; rust_invocations_total = $rust; shim_log = $shimLines
  artifact_hashes_before = $before; artifact_hashes_after = $after; hashes_identical = $identical
  builds_ok = (@($trials | Where-Object { $_.exit -ne 0 }).Count -eq 0)
  note = 'The renderer DLL is a prebuilt payload copied beside the exe; there is no engine artifact in this workload unless -EngineArtifacts is given.'
}
$out | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 "$Base\incremental.json"
"rust_invocations_total=$rust hashes_identical=$identical builds_ok=$($out.builds_ok) -> $Base\incremental.json"
