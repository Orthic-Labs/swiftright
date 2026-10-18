# Runs inside Windows Sandbox: launches tuple 12 FreshOnBridge --fixture F1 (launch focus selects all of "Row 1"),
# captures the desktop after 4 s, records exe/renderer hashes, then lets the fixture exit via its release flag.
$ErrorActionPreference = 'Continue'
$out = 'C:\sb\out'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$bin = 'C:\sb\bin'
$log = "$out\sel-shot.log"
"exe=$((Get-FileHash -Algorithm SHA256 "$bin\FreshOnBridge.exe").Hash.ToLower()) renderer=$((Get-FileHash -Algorithm SHA256 "$bin\swiftright_render.dll").Hash.ToLower())" | Out-File $log
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "$bin\FreshOnBridge.exe"; $psi.Arguments = '--fixture F1'; $psi.WorkingDirectory = $bin; $psi.UseShellExecute = $false
$flag = "$out\release-selshot.flag"
$psi.EnvironmentVariables['SR0O_RELEASE_FLAG'] = $flag
$psi.EnvironmentVariables['Path'] = "C:\sb\rt;$bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
$p = [System.Diagnostics.Process]::Start($psi)
"pid=$($p.Id)" | Out-File -Append $log
Start-Sleep -Seconds 3
$ws = New-Object -ComObject WScript.Shell
"activated=$($ws.AppActivate($p.Id))" | Out-File -Append $log
Start-Sleep -Seconds 2
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
$bmp.Save("$out\sel-shot-F1-active.png")
"captured $($b.Width)x$($b.Height)" | Out-File -Append $log
Set-Content -Path $flag -Value 'release'
if (-not $p.WaitForExit(15000)) { $p.Kill(); "killed" | Out-File -Append $log } else { "exit=$($p.ExitCode)" | Out-File -Append $log }
