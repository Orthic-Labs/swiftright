# Dell desktop: tuple 13 FreshOnBridge --fixture F5, every presented frame of its HWND recorded by FactoryWGCRecord for 10 s.
$ErrorActionPreference = 'Continue'
$w = 'D:\Claude\swiftright\.work\sr0-sel-desktop'
$bin = 'D:\Claude\swiftright\.work\sr0-r13\typecheck\src\scratch\out\Products\Release-windows-x86_64'
$log = "$w\wgc.log"
"exe=$((Get-FileHash "$bin\FreshOnBridge.exe").Hash.ToLower()) renderer=$((Get-FileHash "$bin\swiftright_render.dll").Hash.ToLower()) recorder=$((Get-FileHash "$w\FactoryWGCRecord.exe").Hash.ToLower())" | Out-File $log
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "$bin\FreshOnBridge.exe"; $psi.Arguments = '--fixture F5'; $psi.WorkingDirectory = $bin; $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$flag = "$w\release-wgc.flag"; Remove-Item $flag -EA SilentlyContinue
$psi.EnvironmentVariables['SR0O_RELEASE_FLAG'] = $flag
$psi.EnvironmentVariables['Path'] = "C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;$bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
$p = [System.Diagnostics.Process]::Start($psi)
$so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
$h = 0; for ($i = 0; $i -lt 100 -and $h -eq 0; $i++) { Start-Sleep -Milliseconds 20; $p.Refresh(); $h = [int64]$p.MainWindowHandle }
"pid=$($p.Id) hwnd=$h" | Out-File -Append $log
$out = "$w\wgc-frames-f5"
$r = Start-Process -FilePath "$w\FactoryWGCRecord.exe" -ArgumentList @('--hwnd', "$h", '--out', $out, '--seconds', '10') -PassThru -NoNewWindow -RedirectStandardOutput "$w\wgc.out" -RedirectStandardError "$w\wgc.err"
$r.WaitForExit(20000) | Out-Null
"recorder exit=$($r.ExitCode)" | Out-File -Append $log
Set-Content -Path $flag -Value 'release'
if (-not $p.WaitForExit(15000)) { $p.Kill(); "killed" | Out-File -Append $log } else { "exit=$($p.ExitCode)" | Out-File -Append $log }

$so.Result | Set-Content "$w\app-stdout.txt"; $se.Result | Set-Content "$w\app-stderr.txt"
