# Drives BridgeSmoke.exe from INSIDE an interactive desktop session (one-shot scheduled task):
#  - launches the exe, waits for its window
#  - logs WS_EX styles, WM_NCHITTEST and WindowFromPoint 2 px inside the client edge
#  - real mouse click 2 px inside the client edge (must reach the window: pointer event)
#  - UIA Invoke on the "Press me" button
#  - defocuses the window for ~2.5 s (frames must keep presenting), refocuses
#  - types 'a' with a virtual-key (never Unicode packets) into the focused editable node
#  - reads the edit node's UIA Value
param(
  [string]$Bin = 'D:\Claude\sr0b-abi0\scratch\out\Products\Release-windows-x86_64',
  [string]$Out = 'D:\Claude\sr0b-abi0\result-smoke.txt'
)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -Namespace SW -Name N -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern IntPtr GetShellWindow();
[DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, UIntPtr e);
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
[DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr h, int i);
[DllImport("user32.dll", SetLastError = true)] public static extern IntPtr SendMessageTimeoutW(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
'@
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $lines.Add($s) }
if (-not [SW.N]::SetProcessDpiAwarenessContext([IntPtr]-4)) { [void][SW.N]::SetProcessDPIAware() }  # per-monitor v2: coordinates match the GPUI window
Log "host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) started=$(Get-Date -Format o)"

$exe = Join-Path $Bin 'BridgeSmoke.exe'
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exe
$psi.WorkingDirectory = $Bin
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.EnvironmentVariables['Path'] = "C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;$Bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
$psi.EnvironmentVariables['SWR_SMOKE_EXPECT_EDGE_CLICK'] = '1'
$proc = [System.Diagnostics.Process]::Start($psi)
$stdout = $proc.StandardOutput.ReadToEndAsync()
$stderr = $proc.StandardError.ReadToEndAsync()

$hwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 120 -and $hwnd -eq [IntPtr]::Zero -and -not $proc.HasExited; $i++) {
  Start-Sleep -Milliseconds 250; $proc.Refresh(); $hwnd = $proc.MainWindowHandle
}
Log "window_hwnd=$($hwnd.ToInt64()) polls=$i exited_early=$($proc.HasExited)"

if ($hwnd -ne [IntPtr]::Zero) {
  Start-Sleep -Milliseconds 1500
  [void][SW.N]::SetForegroundWindow($hwnd)
  $style = [SW.N]::GetWindowLongPtr($hwnd, -16).ToInt64(); $ex = [SW.N]::GetWindowLongPtr($hwnd, -20).ToInt64()
  Log ("styles style=0x{0:X} exstyle=0x{1:X} WS_EX_LAYERED={2} WS_EX_TRANSPARENT={3} WS_EX_NOREDIRECTIONBITMAP={4}" -f $style, $ex, (($ex -band 0x80000) -ne 0), (($ex -band 0x20) -ne 0), (($ex -band 0x200000) -ne 0))
  $cr = New-Object SW.N+RECT; [void][SW.N]::GetClientRect($hwnd, [ref]$cr)
  $org = New-Object SW.N+POINT; [void][SW.N]::ClientToScreen($hwnd, [ref]$org)
  $ex2 = $org.x + 2; $ey = $org.y + 100
  $pt = New-Object SW.N+POINT; $pt.x = $ex2; $pt.y = $ey
  $wfp = [SW.N]::WindowFromPoint($pt)
  $res = [IntPtr]::Zero
  $lp = [IntPtr](([int64]($ey -band 0xFFFF) -shl 16) -bor [int64]($ex2 -band 0xFFFF))
  [void][SW.N]::SendMessageTimeoutW($hwnd, 0x0084, [IntPtr]::Zero, $lp, 2, 1000, [ref]$res)
  Log ("client={0}x{1} origin=({2},{3}) edge_point=({4},{5}) window_from_point_is_target={6} wm_nchittest={7} (1=HTCLIENT)" -f $cr.right, $cr.bottom, $org.x, $org.y, $ex2, $ey, ($wfp -eq $hwnd), $res.ToInt64())
  # real click 2 px inside the client edge
  [void][SW.N]::SetCursorPos($ex2, $ey); Start-Sleep -Milliseconds 150
  [SW.N]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
  [SW.N]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 300
  Log "edge_click_sent=true"

  # UIA Invoke on the button
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
  $btnCond = New-Object System.Windows.Automation.AndCondition(
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, 'Press me')),
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)))
  $btn = $null
  for ($k = 0; $k -lt 40 -and $btn -eq $null; $k++) { $btn = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $btnCond); if ($btn -eq $null) { Start-Sleep -Milliseconds 250 } }
  if ($btn -eq $null) { Log 'uia_button=NOT_FOUND' } else {
    try { $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Log 'uia_invoke=ok' } catch { Log "uia_invoke=ERR $($_.Exception.Message)" }
  }
  Start-Sleep -Milliseconds 500

  # defocus, keep the window alive and presenting
  [void][SW.N]::SetForegroundWindow([SW.N]::GetShellWindow()); Start-Sleep -Milliseconds 300
  Log ("defocused foreground_is_target={0}" -f ([SW.N]::GetForegroundWindow() -eq $hwnd))
  Start-Sleep -Milliseconds 2500
  [void][SW.N]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 500
  Log ("refocused foreground_is_target={0}" -f ([SW.N]::GetForegroundWindow() -eq $hwnd))

  # type 'a' with a virtual key
  [SW.N]::keybd_event(0x41, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 40
  [SW.N]::keybd_event(0x41, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 800
  $editCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
  $edit = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $editCond)
  if ($edit -eq $null) { Log 'uia_edit=NOT_FOUND' } else {
    try { $v = $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value; Log "uia_edit_value=[$v]" } catch { Log "uia_edit_value=ERR $($_.Exception.Message)" }
  }
}

if (-not $proc.WaitForExit(60000)) { $proc.Kill(); Log 'TIMEOUT: killed after 60 s' }
$proc.WaitForExit()
Log "exit=$($proc.ExitCode) end=$(Get-Date -Format o)"
Log '--- stdout ---'
Log ([string]$stdout.Result)
Log '--- stderr ---'
Log ([string]$stderr.Result)
[System.IO.File]::WriteAllText($Out, [string]::Join("`r`n", $lines))
