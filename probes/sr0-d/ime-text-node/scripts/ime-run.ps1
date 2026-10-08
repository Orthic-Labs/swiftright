# SR0-D IME text-node probe: interactive desktop run.
# Run from an interactive PowerShell on the Windows host (not over SSH; IMM32 needs the desktop session).
# Launches the built probe, captures stderr (one [ime-probe] line per InputHandler call),
# waits until you close the window, then prints the log.
param(
  [string]$Exe = 'D:\.rightkit-managed\rightkit-build-control\ws\23805cb9144c\g\001\target\x86_64-pc-windows-msvc\release\sr0d-ime-text-node.exe',
  [string]$OutDir = 'D:\Claude\sr0d-ime'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Exe)) {
  throw "probe exe not found: $Exe (take the target dir from the rightkit status receipt 'command' field)"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log = Join-Path $OutDir 'stderr.log'
$out = Join-Path $OutDir 'stdout.log'
Remove-Item -LiteralPath $log, $out -ErrorAction SilentlyContinue

Write-Host "Exe:    $Exe"
Write-Host "Log:    $log"
Write-Host ''
Write-Host 'Enable the Microsoft Japanese IME (Settings > Time & language > Language) and switch to it (Win+Space).'
Write-Host 'Click inside the probe window, then run the protocol from RESULT.md.'
Write-Host 'Close the probe window when finished; the log is printed below.'
Write-Host ''

$p = Start-Process -FilePath $Exe -PassThru -RedirectStandardError $log -RedirectStandardOutput $out -WindowStyle Normal
Write-Host "started pid=$($p.Id); waiting for the window to close..."
$p.WaitForExit()
Write-Host "probe exited with code $($p.ExitCode)"
Write-Host ''

if (Test-Path -LiteralPath $log) {
  [string](Get-Content -Raw -LiteralPath $log)
} else {
  Write-Host 'no stderr log was produced'
}
