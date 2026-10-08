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
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
[DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
[DllImport("user32.dll", SetLastError = true)] public static extern IntPtr SendMessageTimeoutW(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
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
  # 2. Live resize. WM_NCHITTEST is logged first (SendMessageTimeout) at diagonal insets from
  #    the bottom-right corner; the drag starts at a point where it returns HTBOTTOMRIGHT (17).
  #    Method A: SendInput absolute-move + left down, 80 moves, left up (real non-client drag).
  #    Method B (fallback if A leaves the rect unchanged): post WM_SYSCOMMAND SC_SIZE|WMSZ_BOTTOMRIGHT
  #    to enter the size loop deterministically, SendInput moves, then a click to end the loop.
  $sz = [System.Runtime.InteropServices.Marshal]::SizeOf([type][SR0M.Native+INPUT])
  $scrW = [SR0M.Native]::GetSystemMetrics(0); $scrH = [SR0M.Native]::GetSystemMetrics(1)
  Log "screen=${scrW}x${scrH} sizeof_input=$sz"
  function HitTest([int]$x, [int]$y) {
    $lp = [IntPtr](([int64]($y -band 0xFFFF) -shl 16) -bor [int64]($x -band 0xFFFF))
    $res = [IntPtr]::Zero
    $ok = [SR0M.Native]::SendMessageTimeoutW($hwnd, 0x0084, [IntPtr]::Zero, $lp, 2, 1000, [ref]$res)
    if ($ok -eq [IntPtr]::Zero) { return -1 }
    return [int]($res.ToInt64() -band 0xFFFF)
  }
  $hits = @()
  foreach ($d in @(-3, 1, 2, 4, 6, 8, 12, 16, 24)) {
    $hits += ("inset{0}={1}" -f $d, (HitTest ($r.right - $d) ($r.bottom - $d)))
  }
  Log ("nchittest_corner " + ($hits -join ' ') + "  (17=HTBOTTOMRIGHT 15=HTBOTTOM 16=HTBOTTOMLEFT 11=HTRIGHT 1=HTCLIENT 0=HTNOWHERE 18=HTBORDER)")
  $inset = 4
  foreach ($d in @(4, 2, 6, 8, 1, 12, 3, 5)) { if ((HitTest ($r.right - $d) ($r.bottom - $d)) -eq 17) { $inset = $d; break } }
  $sx = $r.right - $inset; $sy = $r.bottom - $inset
  Log "resize_start rect=($($r.left),$($r.top),$($r.right),$($r.bottom)) grip=($sx,$sy) inset=$inset hit_at_grip=$(HitTest $sx $sy)"

  # Positioning uses SetCursorPos (exact, verified: absolute SendInput mapped to the wrong point on this
  # multi-DPI display in run3). Button events use SendInput at the current cursor. Motion = SetCursorPos
  # followed by a 1 px relative SendInput so the system generates a real WM_MOUSEMOVE.
  function MouseBtn([int]$flags) {
    $i = New-Object SR0M.Native+INPUT; $i.type = 0; $i.mi.dwFlags = [uint32]$flags
    return [SR0M.Native]::SendInput(1, [SR0M.Native+INPUT[]]@($i), $sz)
  }
  function MouseMoveTo([int]$x, [int]$y) {
    [void][SR0M.Native]::SetCursorPos($x, $y)
    $i = New-Object SR0M.Native+INPUT; $i.type = 0; $i.mi.dwFlags = 0x0001; $i.mi.dx = 1; $i.mi.dy = 0
    return [SR0M.Native]::SendInput(1, [SR0M.Native+INPUT[]]@($i), $sz)
  }
  $LDOWN = 0x0002; $LUP = 0x0004
  function MoveSteps([int]$n, [int]$fx, [int]$fy, [int]$tx, [int]$ty) {
    $ok = 0
    for ($s = 1; $s -le $n; $s++) {
      $ok += MouseMoveTo ($fx + [int](($tx - $fx) * $s / $n)) ($fy + [int](($ty - $fy) * $s / $n))
      Start-Sleep -Milliseconds 15
    }
    return $ok
  }
  $r0 = $r
  $t0 = Get-Date
  [void][SR0M.Native]::SetForegroundWindow($hwnd)
  [void][SR0M.Native]::SetCursorPos($sx, $sy); Start-Sleep -Milliseconds 200
  $cp = New-Object SR0M.Native+POINT; [void][SR0M.Native]::GetCursorPos([ref]$cp)
  $wfp = [SR0M.Native]::WindowFromPoint($cp)
  Log ("pre_drag cursor=($($cp.x),$($cp.y)) window_at_grip_is_target={0} foreground_is_target={1}" -f ($wfp -eq $hwnd), ([SR0M.Native]::GetForegroundWindow() -eq $hwnd))
  $dnRet = MouseBtn $LDOWN; Start-Sleep -Milliseconds 100
  $mvOk = MoveSteps 80 $sx $sy ($sx + 240) ($sy + 160)
  $upRet = MouseBtn $LUP; Start-Sleep -Milliseconds 300
  [void][SR0M.Native]::GetWindowRect($hwnd, [ref]$r)
  $changedA = ($r.right -ne $r0.right) -or ($r.bottom -ne $r0.bottom)
  Log ("method_A_sendinput_border_drag down={0} moves_ok={1}/80 up={2} rect_after=({3},{4},{5},{6}) rect_changed={7}" -f $dnRet, $mvOk, $upRet, $r.left, $r.top, $r.right, $r.bottom, $changedA)
  $method = 'A_sendinput_border'
  if (-not $changedA) {
    $method = 'B_sc_size'
    $r1 = $r
    $sx = $r.right - 4; $sy = $r.bottom - 4
    [void][SR0M.Native]::SetForegroundWindow($hwnd)
    [void][SR0M.Native]::SetCursorPos($sx, $sy); Start-Sleep -Milliseconds 100
    $pm = [SR0M.Native]::PostMessageW($hwnd, 0x0112, [IntPtr]0xF008, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 400
    $mvOk = MoveSteps 80 $sx $sy ($sx + 240) ($sy + 160)
    # Enter ends the keyboard/SC_SIZE size loop (a click did not in run3).
    [SR0M.Native]::keybd_event(0x0D, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
    [SR0M.Native]::keybd_event(0x0D, 0, 2, [UIntPtr]::Zero); $d2 = 1; $u2 = 1; Start-Sleep -Milliseconds 300
    [void][SR0M.Native]::GetWindowRect($hwnd, [ref]$r)
    Log ("method_B_sc_size post_ok={0} moves_ok={1}/80 end_enter={2}/{3} rect_after=({4},{5},{6},{7}) rect_changed={8}" -f $pm, $mvOk, $d2, $u2, $r.left, $r.top, $r.right, $r.bottom, (($r.right -ne $r1.right) -or ($r.bottom -ne $r1.bottom)))
  }
  $dragS = ((Get-Date) - $t0).TotalSeconds
  Log ("resize_done method=$method drag_s={0:N2} rect_before=({1},{2},{3},{4}) rect_after=({5},{6},{7},{8})" -f $dragS, $r0.left, $r0.top, $r0.right, $r0.bottom, $r.left, $r.top, $r.right, $r.bottom)

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
