# Runs INSIDE the interactive desktop session. Launches FreshOnBridge.exe for one cross config (flags from
# cross\configs.json; no --self-test: the in-process script runs from launch), runs UIARecorder (record) against its pid with
# window-targeted typing (SR0O_KEY_DELIVERY=targeted: WM_CHAR posted to the fixture HWND only), waits for exit and writes
# everything under $OutDir. No Remove-Item. Window titles of other applications are never read.
param(
  [string]$Config = 'F1',
  [string]$Tag = 'r1',
  [string]$Base = 'D:\Claude\sr0o-f1',
  [string]$Recorder = 'D:\Claude\sr0o-f1\scratch\release\UIARecorder.exe',
  [string]$Bin = 'D:\Claude\sr0-r10\src\scratch\out\Products\Release-windows-x86_64',
  [string]$OutDir = 'D:\Claude\sr0o-f1\out'
)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$log = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $log.Add($s) }
$rt = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin'
$cfg = (Get-Content -Raw "$Base\cross\configs.json" | ConvertFrom-Json).$Config
if (-not $cfg) { throw "unknown config $Config" }
$steps = "$Base\cross\$Config\steps-win.json"
Log "host=$env:COMPUTERNAME session=$((Get-Process -Id $PID).SessionId) config=$Config tag=$Tag started=$(Get-Date -Format o)"
$exeItem = Get-Item "$Bin\FreshOnBridge.exe"
Log "exe=$($exeItem.FullName) size=$($exeItem.Length) mtime=$($exeItem.LastWriteTime.ToString('o'))"
$exeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath "$Bin\FreshOnBridge.exe").Hash.ToLower()
$dllHash = (Get-FileHash -Algorithm SHA256 -LiteralPath "$Bin\swiftright_render.dll").Hash.ToLower()
$recHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Recorder).Hash.ToLower()
Log "ARTIFACTS exe=$exeHash renderer=$dllHash recorder=$recHash"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "$Bin\FreshOnBridge.exe"; $psi.Arguments = [string]$cfg.winArgs; $psi.WorkingDirectory = $Bin; $psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$flag = "$OutDir\release-$Tag.flag"
if (Test-Path $flag) { throw "flag exists: $flag" }
$psi.EnvironmentVariables['SR0O_RELEASE_FLAG'] = $flag
$psi.EnvironmentVariables['Path'] = "$rt;$Bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
$proc = [System.Diagnostics.Process]::Start($psi)
$so = $proc.StandardOutput.ReadToEndAsync(); $se = $proc.StandardError.ReadToEndAsync()
Log "target pid=$($proc.Id) args=$($psi.Arguments)"
Start-Sleep -Milliseconds 2500

$rec = New-Object System.Diagnostics.ProcessStartInfo
$rec.FileName = $Recorder; $rec.UseShellExecute = $false; $rec.RedirectStandardOutput = $true; $rec.RedirectStandardError = $true
$rec.EnvironmentVariables['SR0O_RELEASE_FLAG'] = $flag
$rec.EnvironmentVariables['SR0O_KEY_DELIVERY'] = 'targeted'
$rec.EnvironmentVariables['Path'] = "$rt;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
$rec.Arguments = "record --pid $($proc.Id) --steps `"$steps`" --out `"$OutDir\winrec-$Tag.json`" --sidecar `"$OutDir\winside-$Tag.json`""
Log "recorder args: $($rec.Arguments)"
$rp = [System.Diagnostics.Process]::Start($rec)
$rso = $rp.StandardOutput.ReadToEndAsync(); $rse = $rp.StandardError.ReadToEndAsync()
if (-not $rp.WaitForExit(240000)) { $rp.Kill(); Log 'RECORDER TIMEOUT' }
$rp.WaitForExit()
Log "recorder exit=$($rp.ExitCode)"
if (-not $proc.HasExited) {
  [void]$proc.CloseMainWindow()
  if (-not $proc.WaitForExit(30000)) { $proc.Kill(); Log 'target killed after 30 s' }
}
$proc.WaitForExit()
Log "target exit=$($proc.ExitCode) end=$(Get-Date -Format o)"
[System.IO.File]::WriteAllText("$OutDir\events-$Tag.txt", [string]$so.Result)
[System.IO.File]::WriteAllText("$OutDir\target-stderr-$Tag.txt", [string]$se.Result)
Log '--- recorder stdout ---'; Log ([string]$rso.Result)
Log '--- recorder stderr ---'; Log ([string]$rse.Result)
[System.IO.File]::WriteAllText("$OutDir\run-$Tag.log", [string]::Join("`r`n", $log))
