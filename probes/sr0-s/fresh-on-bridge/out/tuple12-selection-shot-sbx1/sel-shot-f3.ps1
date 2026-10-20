# Runs inside Windows Sandbox: tuple 13 FreshOnBridge --fixture F3 (launch focus on Row 1, whole text selected; AX moves focus
# to Row 4 ~2.2 s later). PrintWindow(PW_RENDERFULLCONTENT) frames at ~1.2 s and ~4 s after launch.
$ErrorActionPreference = 'Continue'
$out = 'C:\sb\out'; $bin = 'C:\sb\bin'; $log = "$out\sel-shot.log"
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class PW { [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r); public struct R { public int L, T, Rt, B; } }
"@
"exe=$((Get-FileHash -Algorithm SHA256 "$bin\FreshOnBridge.exe").Hash.ToLower()) renderer=$((Get-FileHash -Algorithm SHA256 "$bin\swiftright_render.dll").Hash.ToLower())" | Out-File $log
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "$bin\FreshOnBridge.exe"; $psi.Arguments = '--fixture F3'; $psi.WorkingDirectory = $bin; $psi.UseShellExecute = $false
$flag = "$out\release-selshot.flag"
$psi.EnvironmentVariables['SR0O_RELEASE_FLAG'] = $flag
$psi.EnvironmentVariables['Path'] = "C:\sb\rt;$bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
$t0 = Get-Date
$p = [System.Diagnostics.Process]::Start($psi)
"pid=$($p.Id)" | Out-File -Append $log
function Shot([string]$name) {
  $p.Refresh(); $h = $p.MainWindowHandle
  $r = New-Object PW+R; [void][PW]::GetWindowRect($h, [ref]$r)
  $bmp = New-Object System.Drawing.Bitmap ($r.Rt - $r.L), ($r.B - $r.T)
  $g = [System.Drawing.Graphics]::FromImage($bmp); $dc = $g.GetHdc(); $ok = [PW]::PrintWindow($h, $dc, 2); $g.ReleaseHdc($dc)
  $bmp.Save("$out\$name.png"); "$name ok=$ok t=$([int]((Get-Date) - $t0).TotalMilliseconds)ms" | Out-File -Append $log
}
Start-Sleep -Milliseconds 1200
$ws = New-Object -ComObject WScript.Shell
"activated=$($ws.AppActivate($p.Id))" | Out-File -Append $log
Shot 'sel-F3-launch'
Start-Sleep -Milliseconds 2800
Shot 'sel-F3-after-ax'
Set-Content -Path $flag -Value 'release'
if (-not $p.WaitForExit(15000)) { $p.Kill(); "killed" | Out-File -Append $log } else { "exit=$($p.ExitCode)" | Out-File -Append $log }
