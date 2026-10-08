# Runs INSIDE the interactive desktop session (via schedule-record.ps1): launches the target exe, waits for its window,
# runs UIARecorder (record or tree) against its PID, waits for the target to exit, writes everything under $OutDir.
param(
  [string]$Mode = 'record',                                   # record | tree
  [string]$Base = 'D:\Claude\sr0o-uia',
  [string]$Exe = 'D:\Claude\sr0b-abi0\scratch\out\Products\Release-windows-x86_64\BridgeSmoke.exe',
  [string]$Steps = 'D:\Claude\sr0o-uia\uia-recorder\fixtures\bridgesmoke-steps.json',
  [string]$OutDir = 'D:\Claude\sr0o-uia\out',
  [string]$Tag = 'run1'
)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$bin = (Get-ChildItem "$Base\scratch" -Recurse -Filter UIARecorder.exe | Where-Object { $_.FullName -match 'Release' } | Select-Object -First 1).FullName
$log = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $log.Add($s) }
Log "host=$env:COMPUTERNAME session=$((Get-Process -Id $PID).SessionId) started=$(Get-Date -Format o) recorder=$bin"

$exeDir = Split-Path $Exe
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Exe; $psi.WorkingDirectory = $exeDir; $psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.EnvironmentVariables['Path'] = "C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;$exeDir;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
$psi.EnvironmentVariables['SWR_SMOKE_TIMEOUT'] = '90'
$proc = [System.Diagnostics.Process]::Start($psi)
$so = $proc.StandardOutput.ReadToEndAsync(); $se = $proc.StandardError.ReadToEndAsync()
Start-Sleep -Milliseconds 2500     # let the first commit land before the recorder snapshots
Log "target pid=$($proc.Id)"

$rec = New-Object System.Diagnostics.ProcessStartInfo
$rec.FileName = $bin; $rec.UseShellExecute = $false; $rec.RedirectStandardOutput = $true; $rec.RedirectStandardError = $true
$rec.EnvironmentVariables['Path'] = "C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($Mode -eq 'tree') { $rec.Arguments = "tree --pid $($proc.Id) --out `"$OutDir\tree-$Tag.json`"" }
else { $rec.Arguments = "record --pid $($proc.Id) --steps `"$Steps`" --out `"$OutDir\trace-$Tag.json`" --sidecar `"$OutDir\sidecar-$Tag.json`"" }
Log "recorder args: $($rec.Arguments)"
$rp = [System.Diagnostics.Process]::Start($rec)
$rso = $rp.StandardOutput.ReadToEndAsync(); $rse = $rp.StandardError.ReadToEndAsync()
if (-not $rp.WaitForExit(90000)) { $rp.Kill(); Log 'RECORDER TIMEOUT' }
$rp.WaitForExit()
Log "recorder exit=$($rp.ExitCode)"
if (-not $proc.WaitForExit(30000)) { $proc.Kill(); Log 'target killed after 30 s' }
$proc.WaitForExit()
Log "target exit=$($proc.ExitCode) end=$(Get-Date -Format o)"
Log '--- recorder stdout ---'; Log ([string]$rso.Result)
Log '--- recorder stderr ---'; Log ([string]$rse.Result)
Log '--- target stdout ---'; Log ([string]$so.Result)
Log '--- target stderr ---'; Log ([string]$se.Result)
[System.IO.File]::WriteAllText("$OutDir\run-$Tag.log", [string]::Join("`r`n", $log))
