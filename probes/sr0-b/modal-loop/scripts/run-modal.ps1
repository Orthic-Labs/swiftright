# SR0-B modal-loop runner. Executes INSIDE an interactive desktop session (one-shot scheduled task).
# 1. Launch SwiftHost.exe; wait for its main window.
# 2. Real live resize: SendInput mouse drag on the bottom-right border for 3 s.
# 3. From a separate runspace thread, 2,000 UIA Invoke calls on "Probe action";
#    WM_CLOSE is posted to the window after the 1,500th call (mid-stream).
# Writes everything to $Out.
param(
  [string]$Bin = 'D:\Claude\sr0b-modal-loop\scratch-1\out\Products\Release-windows-x86_64',
  [string]$Out = 'D:\Claude\sr0b-modal-loop\result-run.txt',
  [int]$InvokeTotal = 2000,
  [int]$CloseAfter = 1500
)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -Namespace SR0M -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
[DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
[DllImport("user32.dll", SetLastError = true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
[StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr extra; }
[StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public MOUSEINPUT mi; }
'@

$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $lines.Add($s); }
Log "host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) started=$(Get-Date -Format o)"
[void][SR0M.Native]::SetProcessDPIAware()

$exe = Join-Path $Bin 'SwiftHost.exe'
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exe
$psi.WorkingDirectory = $Bin
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.EnvironmentVariables['Path'] = "C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;$Bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
$proc = [System.Diagnostics.Process]::Start($psi)
$stdout = $proc.StandardOutput.ReadToEndAsync()
$stderr = $proc.StandardError.ReadToEndAsync()

# 1. Wait for the window.
$hwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 120 -and $hwnd -eq [IntPtr]::Zero -and -not $proc.HasExited; $i++) {
  Start-Sleep -Milliseconds 250; $proc.Refresh(); $hwnd = $proc.MainWindowHandle
}
Log "window_hwnd=$($hwnd.ToInt64()) found_after_polls=$i exited_early=$($proc.HasExited)"

if ($hwnd -ne [IntPtr]::Zero) {
  Start-Sleep -Milliseconds 1500
  [void][SR0M.Native]::SetForegroundWindow($hwnd)
  $r = New-Object SR0M.Native+RECT
  [void][SR0M.Native]::GetWindowRect($hwnd, [ref]$r)
  $sx = $r.right - 4; $sy = $r.bottom - 4
  Log "resize_start rect=($($r.left),$($r.top),$($r.right),$($r.bottom)) grip=($sx,$sy)"

  # 2. Live resize: 3 s of SendInput mouse drag on the border.
  $down = New-Object SR0M.Native+INPUT; $down.type = 0; $down.mi.dwFlags = 0x0002
  $up = New-Object SR0M.Native+INPUT; $up.type = 0; $up.mi.dwFlags = 0x0004
  $mv = New-Object SR0M.Native+INPUT; $mv.type = 0; $mv.mi.dwFlags = 0x0001
  [void][SR0M.Native]::SetCursorPos($sx, $sy)
  Start-Sleep -Milliseconds 200
  $sz = [System.Runtime.InteropServices.Marshal]::SizeOf([type][SR0M.Native+INPUT])
  $cp = New-Object SR0M.Native+POINT; [void][SR0M.Native]::GetCursorPos([ref]$cp); $wfp = [SR0M.Native]::WindowFromPoint((New-Object SR0M.Native+POINT -Property @{x=$sx;y=$sy}))
  Log ("pre_drag cursor=($($cp.x),$($cp.y)) window_at_grip_is_target={0} foreground_is_target={1} sizeof_input={2}" -f ($wfp -eq $hwnd), ([SR0M.Native]::GetForegroundWindow() -eq $hwnd), $sz)
  $ret = [SR0M.Native]::SendInput(1, [SR0M.Native+INPUT[]]@($down), $sz); Log "send_down_ret=$ret lasterr=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
  $steps = 200
  $moveRets = 0
  $t0 = Get-Date
  for ($s = 1; $s -le $steps; $s++) {
    $px = $sx + [int](320 * $s / $steps); $py = $sy + [int](220 * $s / $steps)
    [void][SR0M.Native]::SetCursorPos($px, $py)
    $mv.mi.dx = 0; $mv.mi.dy = 0
    $moveRets += [SR0M.Native]::SendInput(1, [SR0M.Native+INPUT[]]@($mv), $sz)
    Start-Sleep -Milliseconds 15
  }
  $retUp = [SR0M.Native]::SendInput(1, [SR0M.Native+INPUT[]]@($up), $sz); Log "send_up_ret=$retUp"
  $dragS = ((Get-Date) - $t0).TotalSeconds
  Log "move_sendinput_ok=$moveRets of $steps"
  [void][SR0M.Native]::GetWindowRect($hwnd, [ref]$r)
  Log ("resize_done drag_s={0:N2} rect_after=({1},{2},{3},{4})" -f $dragS, $r.left, $r.top, $r.right, $r.bottom)

  # 3. UIA Invoke storm from a separate thread (runspace); WM_CLOSE mid-stream.
  Start-Sleep -Milliseconds 800
  $sync = [hashtable]::Synchronized(@{ n = 0; ok = 0; err = 0; notfound = 0; closeSent = $false; closeAtMs = -1; first = '' })
  $rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'STA'; $rs.Open()
  $ps = [powershell]::Create(); $ps.Runspace = $rs
  [void]$ps.AddScript({
    param($h, $sync, $total)
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, 'Probe action')
    $btn = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($btn -eq $null) { $sync.notfound = 1; return }
    $pat = $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    for ($i = 0; $i -lt $total; $i++) {
      try { $pat.Invoke(); $sync.ok++ } catch { $sync.err++; if ($sync.first -eq '') { $sync.first = $_.Exception.Message; $sync.firstErrIdx = $i; $sync.firstErrMs = $sw.ElapsedMilliseconds } }
      $sync.n = $i + 1
      if ($i -eq 0) { $sync.firstInvokeMs = $sw.ElapsedMilliseconds }
      Start-Sleep -Milliseconds 3
    }
    $sync.totalMs = $sw.ElapsedMilliseconds
  }).AddArgument($hwnd).AddArgument($sync).AddArgument($InvokeTotal)
  $handle = $ps.BeginInvoke()
  $tStart = Get-Date
  while (-not $handle.IsCompleted -and ((Get-Date) - $tStart).TotalSeconds -lt 120) {
    if (-not $sync.closeSent -and $sync.n -ge $CloseAfter) {
      $sync.closeAtMs = [int]((Get-Date) - $tStart).TotalMilliseconds
      [void][SR0M.Native]::PostMessageW($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
      $sync.closeSent = $true
    }
    Start-Sleep -Milliseconds 5
  }
  if (-not $sync.closeSent) { [void][SR0M.Native]::PostMessageW($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero); $sync.closeSent = $true; Log 'close_forced_late=true' }
  try { $ps.EndInvoke($handle) | Out-Null } catch { Log "invoke_thread_exception=$($_.Exception.Message)" }
  $ps.Dispose(); $rs.Close()
  Log ("uia_first_err_idx={0} first_err_ms={1}" -f $sync.firstErrIdx, $sync.firstErrMs)
  Log ("uia_invoke n={0} ok={1} err={2} notfound={3} close_sent_at_ms={4} first_err='{5}' total_ms={6} first_invoke_ms={7}" -f $sync.n, $sync.ok, $sync.err, $sync.notfound, $sync.closeAtMs, $sync.first, $sync.totalMs, $sync.firstInvokeMs)
}

if (-not $proc.WaitForExit(60000)) { $proc.Kill(); Log 'TIMEOUT: killed after 60 s' }
$proc.WaitForExit()
Log "exit=$($proc.ExitCode) end=$(Get-Date -Format o)"
Log '--- stdout ---'
Log ([string]$stdout.Result)
Log '--- stderr ---'
Log ([string]$stderr.Result)
[System.IO.File]::WriteAllText($Out, [string]::Join("`r`n", $lines))
