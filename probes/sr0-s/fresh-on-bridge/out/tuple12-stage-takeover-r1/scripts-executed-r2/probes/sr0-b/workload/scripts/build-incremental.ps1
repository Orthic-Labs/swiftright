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
$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')
$shim = "$Base\shim-runs\$runId"
$log = "$shim\shim.log"
New-Item -ItemType Directory -Force $shim | Out-Null
foreach ($n in 'cargo', 'rustc', 'rustup', 'rightkit', 'rustdoc', 'cargo-clippy') {
  "@echo off`r`necho %DATE% %TIME% $n %* >> `"$log`"`r`nexit /b 97`r`n" | Set-Content -Encoding ascii "$shim\$n.cmd"
}
$env:Path = "$shim;$env:Path"
$env:RUSTC_WRAPPER = "$shim\rustc.cmd"
$b = Get-Content -Raw "$Base\build.json" | ConvertFrom-Json
$bin = Split-Path $b.exe
$target = "$work\Sources\WorkloadCore\WorkloadScreen.swift"
$backup = "$Base\incremental-runs\$runId\WorkloadScreen.swift.orig"
$runOut = "$Base\incremental-runs\$runId"
New-Item -ItemType Directory -Force $runOut | Out-Null
Copy-Item $target $backup -Force
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
function Hashes { $h = [ordered]@{}; foreach ($f in @("$bin\swiftright_render.dll") + $EngineArtifacts) { $h[$f] = (Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash }; $h }
$before = Hashes
# The incremental builds relink WorkloadWin.exe in the pinned bin dir (a different hash: the PE timestamp). The workload identity gate
# (verify-artifacts.ps1) binds the exe hash in build.json, so the pinned exe is copied aside first and put back byte-for-byte afterwards.
$pinExe = "$bin\WorkloadWin.exe"
$pinHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $pinExe).Hash
$pinCopy = "$runOut\WorkloadWin.exe.pinned"
Copy-Item $pinExe $pinCopy -Force
$trials = @()
Set-Location $work
try {
  for ($i = 1; $i -le $Edits; $i++) {
    Add-Content -Path $target -Value "`n// R10 incremental edit $i $(Get-Date -Format o)"
    $before_log = if (Test-Path $log) { (Get-Content $log).Count } else { 0 }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & swift build -c release --product WorkloadWin --scratch-path "$Base\scratch" "-Xlinker" "/MANIFEST:EMBED" "-Xlinker" $dep *> "$runOut\incremental-build-$i.txt"
    $rc = $LASTEXITCODE
    $sec = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    $after_log = if (Test-Path $log) { (Get-Content $log).Count } else { 0 }
    $trials += [pscustomobject]@{ edit = $i; exit = $rc; seconds = $sec; rust_invocations = ($after_log - $before_log) }
    "edit=$i exit=$rc seconds=$sec rust_invocations=$($after_log - $before_log)"
  }
} finally {
  Copy-Item $backup $target -Force
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $pinExe).Hash -ne $pinHash) {
    Copy-Item $pinCopy $pinExe -Force
    "pinned WorkloadWin.exe restored (sha256 $pinHash)"
  }
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
  pinned_exe_sha256 = $pinHash
  note = 'The renderer DLL is a prebuilt payload copied beside the exe; there is no engine artifact in this workload unless -EngineArtifacts is given.'
}
$out | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 "$Base\incremental.json"
"rust_invocations_total=$rust hashes_identical=$identical builds_ok=$($out.builds_ok) -> $Base\incremental.json"
if (-not $out.builds_ok -or $rust -ne 0 -or -not $identical) {
  throw "incremental qualification failed: builds_ok=$($out.builds_ok) rust_invocations=$rust hashes_identical=$identical"
}
