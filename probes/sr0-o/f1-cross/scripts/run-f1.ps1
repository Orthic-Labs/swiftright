# Runs INSIDE the interactive desktop session. Launches FreshOnBridge.exe --fixture F1 (stdout captured to a file),
# runs UIARecorder (tree|record) against its pid, waits for exit, writes everything under $OutDir. No Remove-Item.
param(
  [string]$Mode = 'tree',
  [string]$Tag = 'r1',
  [string]$Base = 'D:\Claude\sr0o-f1',
  [string]$Recorder = 'D:\Claude\sr0o-f1\scratch\release\UIARecorder.exe',
  [string]$Steps = 'D:\Claude\sr0o-f1\f1-steps-win.json',
  [string]$Bin = 'D:\Claude\sr0s-bridge\scratch\out\Products\Release-windows-x86_64',
  [string]$OutDir = 'D:\Claude\sr0o-f1\out'
)
$ErrorActionPreference = 'Continue'

New-Item -ItemType Directory -Force $OutDir | Out-Null
$log = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $log.Add($s) }
$rt = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin'
Log "host=$env:COMPUTERNAME session=$((Get-Process -Id $PID).SessionId) mode=$Mode tag=$Tag started=$(Get-Date -Format o)"
$exeItem = Get-Item "$Bin\FreshOnBridge.exe"
Log "exe=$($exeItem.FullName) size=$($exeItem.Length) mtime=$($exeItem.LastWriteTime.ToString('o'))"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "$Bin\FreshOnBridge.exe"; $psi.Arguments = '--fixture F1'; $psi.WorkingDirectory = $Bin; $psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$flag = "$OutDir\release-$Tag.flag"
if (Test-Path $flag) { throw "flag exists: $flag" }
$psi.EnvironmentVariables['SR0O_RELEASE_FLAG'] = $flag
$psi.EnvironmentVariables['Path'] = "$rt;$Bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
$proc = [System.Diagnostics.Process]::Start($psi)
$so = $proc.StandardOutput.ReadToEndAsync(); $se = $proc.StandardError.ReadToEndAsync()
Log "target pid=$($proc.Id)"
Start-Sleep -Milliseconds 2500

$rec = New-Object System.Diagnostics.ProcessStartInfo
$rec.FileName = $Recorder; $rec.UseShellExecute = $false; $rec.RedirectStandardOutput = $true; $rec.RedirectStandardError = $true
$rec.EnvironmentVariables['SR0O_RELEASE_FLAG'] = $flag
$rec.EnvironmentVariables['Path'] = "$rt;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($Mode -eq 'tree') { $rec.Arguments = "tree --pid $($proc.Id) --out `"$OutDir\tree-$Tag.json`"" }
else { $rec.Arguments = "record --pid $($proc.Id) --steps `"$Steps`" --out `"$OutDir\winrec-$Tag.json`" --sidecar `"$OutDir\winside-$Tag.json`"" }
Log "recorder args: $($rec.Arguments)"
$rp = [System.Diagnostics.Process]::Start($rec)
$rso = $rp.StandardOutput.ReadToEndAsync(); $rse = $rp.StandardError.ReadToEndAsync()
if (-not $rp.WaitForExit(120000)) { $rp.Kill(); Log 'RECORDER TIMEOUT' }
$rp.WaitForExit()
Log "recorder exit=$($rp.ExitCode)"
if ($Mode -eq 'tree') { if (-not $proc.HasExited) { $proc.Kill(); Log 'target killed (tree mode)' } }
elseif (-not ($proc.CloseMainWindow() -or $true) -or -not $proc.WaitForExit(30000)) { $proc.Kill(); Log 'target killed after 30 s' }
$proc.WaitForExit()
Log "target exit=$($proc.ExitCode) end=$(Get-Date -Format o)"
[System.IO.File]::WriteAllText("$OutDir\events-$Tag.txt", [string]$so.Result)
[System.IO.File]::WriteAllText("$OutDir\target-stderr-$Tag.txt", [string]$se.Result)
Log '--- recorder stdout ---'; Log ([string]$rso.Result)
Log '--- recorder stderr ---'; Log ([string]$rse.Result)
[System.IO.File]::WriteAllText("$OutDir\run-$Tag.log", [string]::Join("`r`n", $log))
