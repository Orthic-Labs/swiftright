# SR0-B modal-loop runner. Executes INSIDE an interactive desktop session (one-shot scheduled task).
# 1. Launch SwiftHost.exe; wait for its main window.
# 2. Three modal size/move loops, each held >= 3 s while the Swift producer posts jobs at 1 kHz:
#    (a) SC_SIZE live resize, (b) SC_MOVE (0xF012) move, (c) injected SendInput bottom-right border drag.
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
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
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
[DllImport("user32.dll")] public static extern IntPtr SetProcessDpiAwarenessContext(IntPtr c);
[DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint tid, ref GUITHREADINFO gi);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
[DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
[StructLayout(LayoutKind.Sequential)] public struct GUITHREADINFO { public uint cbSize; public uint flags; public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret; public RECT rcCaret; }
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
[StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr extra; }
[StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public MOUSEINPUT mi; }
'@

$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $lines.Add($s); }
Log "host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) started=$(Get-Date -Format o)"
$dpiPm = [SR0M.Native]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))
if ($dpiPm -eq [IntPtr]::Zero) { [void][SR0M.Native]::SetProcessDPIAware() }
Log "dpi_awareness_per_monitor_v2_set=$($dpiPm -ne [IntPtr]::Zero)"
$swAll = [System.Diagnostics.Stopwatch]::StartNew()

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
  # Time-based sweep: HOLD_MS of motion in 15 ms steps (linear from (fx,fy) to (tx,ty)), jobs keep flowing meanwhile.
  $HOLD_MS = 3300
  function MoveForMs([int]$ms, [int]$fx, [int]$fy, [int]$tx, [int]$ty) {
    $ok = 0; $n = 0; $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $ms) {
      $f = $sw.ElapsedMilliseconds / [double]$ms
      $ok += MouseMoveTo ($fx + [int](($tx - $fx) * $f)) ($fy + [int](($ty - $fy) * $f)); $n++
      Start-Sleep -Milliseconds 15
    }
    return "$ok/$n"
  }
  function PressEnter() {
    [SR0M.Native]::keybd_event(0x0D, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50
    [SR0M.Native]::keybd_event(0x0D, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 300
  }
  function Rect() { $q = New-Object SR0M.Native+RECT; [void][SR0M.Native]::GetWindowRect($hwnd, [ref]$q); return $q }

  # ---- helpers for (b)/(c): absolute SendInput over the virtual desktop (DPI aware), state diagnostics ----
  $vx = [SR0M.Native]::GetSystemMetrics(76); $vy = [SR0M.Native]::GetSystemMetrics(77)
  $vw = [SR0M.Native]::GetSystemMetrics(78); $vh = [SR0M.Native]::GetSystemMetrics(79)
  Log "virtual_desktop=($vx,$vy) ${vw}x${vh}"
  $tid = [SR0M.Native]::GetWindowThreadProcessId($hwnd, [ref]([uint32]0))
  function AbsMove([int]$x, [int]$y) {
    $i = New-Object SR0M.Native+INPUT; $i.type = 0
    $i.mi.dx = [int][Math]::Round((($x - $vx) + 0.5) * 65535.0 / $vw)
    $i.mi.dy = [int][Math]::Round((($y - $vy) + 0.5) * 65535.0 / $vh)
    $i.mi.dwFlags = 0x8000 -bor 0x4000 -bor 0x0001   # ABSOLUTE | VIRTUALDESK | MOVE
    return [SR0M.Native]::SendInput(1, [SR0M.Native+INPUT[]]@($i), $sz)
  }
  # Absolute move then verify with GetCursorPos; fall back to SetCursorPos if the mapping missed by > 2 px.
  function AbsMoveVerified([int]$x, [int]$y) {
    [void](AbsMove $x $y)
    $p = New-Object SR0M.Native+POINT; [void][SR0M.Native]::GetCursorPos([ref]$p)
    if ([Math]::Abs($p.x - $x) -gt 2 -or [Math]::Abs($p.y - $y) -gt 2) { [void][SR0M.Native]::SetCursorPos($x, $y); [void](AbsMove $x $y) }
    return $p
  }
  function AbsMoveForMs([int]$ms, [int]$fx, [int]$fy, [int]$tx, [int]$ty) {
    $ok = 0; $n = 0; $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $ms) {
      $f = $sw.ElapsedMilliseconds / [double]$ms
      $ok += AbsMove ($fx + [int](($tx - $fx) * $f)) ($fy + [int](($ty - $fy) * $f)); $n++
      Start-Sleep -Milliseconds 15
    }
    [void](AbsMove $tx $ty)
    return "$ok/$n"
  }
  function Diag([string]$tag) {
    $gi = New-Object SR0M.Native+GUITHREADINFO; $gi.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][SR0M.Native+GUITHREADINFO])
    [void][SR0M.Native]::GetGUIThreadInfo($tid, [ref]$gi)
    $cp = New-Object SR0M.Native+POINT; [void][SR0M.Native]::GetCursorPos([ref]$cp)
    $wfp = [SR0M.Native]::WindowFromPoint($cp)
    $root = if ($wfp -ne [IntPtr]::Zero) { [SR0M.Native]::GetAncestor($wfp, 2) } else { [IntPtr]::Zero }
    $fg = [SR0M.Native]::GetForegroundWindow()
    $lb = ([SR0M.Native]::GetAsyncKeyState(1) -band 0x8000) -ne 0
    Log ("diag[{0}] t={1}ms cursor=({2},{3}) under_cursor_is_host={4} fg_is_host={5} gui_flags=0x{6:X} capture={7} movesize={8} lbutton_down={9}" -f $tag, $swAll.ElapsedMilliseconds, $cp.x, $cp.y, ($root -eq $hwnd), ($fg -eq $hwnd), $gi.flags, $gi.hwndCapture.ToInt64(), $gi.hwndMoveSize.ToInt64(), $lb)
  }
  function EndStuckLoop() {
    $gi = New-Object SR0M.Native+GUITHREADINFO; $gi.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf([type][SR0M.Native+GUITHREADINFO])
    [void][SR0M.Native]::GetGUIThreadInfo($tid, [ref]$gi)
    if (($gi.flags -band 2) -ne 0) { Log 'stuck_move_size_loop_detected: sending Escape'; [SR0M.Native]::keybd_event(0x1B, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 50; [SR0M.Native]::keybd_event(0x1B, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 300 }
  }
  $loopWin = @{}   # loop name -> @(start_ms, end_ms) on the driver clock
  $calibPostMs = -1

  # Order matters: Swift buckets latency by WM_ENTERSIZEMOVE ordinal: 1 = SC_SIZE resize, 2 = SC_MOVE, 3 = injected border drag.
  # Each posted SYSCOMMAND enters the modal size/move loop; the loop is ended with Enter (commit).

  $r0start = Rect
  # (a) live resize: SC_SIZE | WMSZ_BOTTOMRIGHT.
  $r0 = Rect; $t0 = Get-Date
  $sx = $r0.right - 4; $sy = $r0.bottom - 4
  [void][SR0M.Native]::SetForegroundWindow($hwnd); [void][SR0M.Native]::SetCursorPos($sx, $sy); Start-Sleep -Milliseconds 100
  $loopStartA = $swAll.ElapsedMilliseconds
  $pm = [SR0M.Native]::PostMessageW($hwnd, 0x0112, [IntPtr]0xF008, [IntPtr]::Zero)
  $calibPostMs = $swAll.ElapsedMilliseconds
  Start-Sleep -Milliseconds 400
  $mv = MoveForMs $HOLD_MS $sx $sy ($sx + 240) ($sy + 160)
  PressEnter
  $r = Rect
  Log ("loop_a_resize SC_SIZE post_ok={0} moves_ok={1} hold_ms={2} s={3:N2} rect ({4},{5},{6},{7}) -> ({8},{9},{10},{11}) changed={12}" -f $pm, $mv, $HOLD_MS, ((Get-Date) - $t0).TotalSeconds, $r0.left, $r0.top, $r0.right, $r0.bottom, $r.left, $r.top, $r.right, $r.bottom, (($r.right -ne $r0.right) -or ($r.bottom -ne $r0.bottom)))
  $loopWin['loop_a'] = @($loopStartA, $swAll.ElapsedMilliseconds)
  Start-Sleep -Milliseconds 700

  # (b) move loop. Real left button DOWN on the client (top strip), THEN WM_SYSCOMMAND SC_MOVE|HTCAPTION (0xF012)
  #     so DefWindowProc's DoSizeMove sees the button held; stepped absolute moves for HOLD_MS; left up.
  #     Fallback (rect unchanged): keyboard move loop = SC_MOVE (0xF010) + arrow keys + Enter.
  EndStuckLoop
  $r1 = Rect; $t0 = Get-Date; $loopStartB = $swAll.ElapsedMilliseconds
  $cx = [int](($r1.left + $r1.right) / 2); $cy = $r1.top + 100
  foreach ($dy in @(100, 60, 160, 240)) { if ((HitTest $cx ($r1.top + $dy)) -in @(1, 2)) { $cy = $r1.top + $dy; break } }
  [void][SR0M.Native]::SetForegroundWindow($hwnd)
  [void](AbsMoveVerified ($cx - 30) ($cy - 30)); Start-Sleep -Milliseconds 100
  [void](AbsMoveVerified $cx $cy); Start-Sleep -Milliseconds 400
  Diag 'b_before_down'
  $dn = MouseBtn $LDOWN; Start-Sleep -Milliseconds 100
  $pm = [SR0M.Native]::PostMessageW($hwnd, 0x0112, [IntPtr]0xF012, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 300
  Diag 'b_after_post'
  $cp2 = New-Object SR0M.Native+POINT; [void][SR0M.Native]::GetCursorPos([ref]$cp2)
  $mv = AbsMoveForMs $HOLD_MS $cp2.x $cp2.y ($cp2.x - 200) ($cp2.y + 120)
  $up = MouseBtn $LUP; Start-Sleep -Milliseconds 400
  EndStuckLoop
  $r2 = Rect
  $moved = (($r2.left -ne $r1.left) -or ($r2.top -ne $r1.top))
  $mode = 'mouse_down+0xF012'
  if (-not $moved) {
    Log 'loop_b mouse path did not move the window; fallback to keyboard SC_MOVE 0xF010 + arrows'
    $mv2 = ''
    [void][SR0M.Native]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 200
    $pm = [SR0M.Native]::PostMessageW($hwnd, 0x0112, [IntPtr]0xF010, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 400
    Diag 'b_kb_after_post'
    $sw2 = [System.Diagnostics.Stopwatch]::StartNew(); $k = 0
    while ($sw2.ElapsedMilliseconds -lt $HOLD_MS) {
      $vk = if (($k % 2) -eq 0) { 0x25 } else { 0x28 }   # Left, Down
      [SR0M.Native]::keybd_event($vk, 0, 1, [UIntPtr]::Zero); Start-Sleep -Milliseconds 8
      [SR0M.Native]::keybd_event($vk, 0, 3, [UIntPtr]::Zero); Start-Sleep -Milliseconds 22; $k++
    }
    PressEnter; EndStuckLoop
    $r2 = Rect; $moved = (($r2.left -ne $r1.left) -or ($r2.top -ne $r1.top)); $mode = "keyboard_0xF010 keys=$k"
  }
  Log ("loop_b_move mode={0} down={1} up={2} post_ok={3} moves_ok={4} hold_ms={5} s={6:N2} rect ({7},{8},{9},{10}) -> ({11},{12},{13},{14}) moved={15}" -f $mode, $dn, $up, $pm, $mv, $HOLD_MS, ((Get-Date) - $t0).TotalSeconds, $r1.left, $r1.top, $r1.right, $r1.bottom, $r2.left, $r2.top, $r2.right, $r2.bottom, $moved)
  $loopWin['loop_b'] = @($loopStartB, $swAll.ElapsedMilliseconds)
  Start-Sleep -Milliseconds 700

  # (c) injected SendInput border drag at the HTBOTTOMRIGHT grip. DPI-aware absolute (virtual-desktop) coordinates,
  #     cursor walked onto the grip in steps, 1 s hover so WM_NCHITTEST/WM_SETCURSOR run, left down, stepped moves
  #     for HOLD_MS, left up. Up to 2 attempts (second uses a different inset); Swift verifies the 3rd ENTERSIZEMOVE.
  EndStuckLoop
  # The keyboard move in (b) can leave the window partly off-screen, hiding the corner grip: put it back at its
  # starting position (SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE) before the drag.
  $rb = Rect; [void][SR0M.Native]::SetWindowPos($hwnd, [IntPtr]::Zero, $r0start.left, $r0start.top, 0, 0, 0x0001 -bor 0x0004 -bor 0x0010)
  Start-Sleep -Milliseconds 300; $ra = Rect
  Log ("loop_c_reposition ({0},{1}) -> ({2},{3})" -f $rb.left, $rb.top, $ra.left, $ra.top)
  $loopStartC = $swAll.ElapsedMilliseconds
  foreach ($attempt in 1, 2) {
    $r3 = Rect; $t0 = Get-Date
    $inset = if ($attempt -eq 1) { 4 } else { 8 }
    foreach ($d in (@($inset, 4, 6, 8, 3, 5, 12) | Select-Object -Unique)) { if ((HitTest ($r3.right - $d) ($r3.bottom - $d)) -eq 17) { $inset = $d; break } }
    $gx = $r3.right - $inset; $gy = $r3.bottom - $inset
    [void][SR0M.Native]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 150
    # approach from inside/outside diagonally in 6 steps
    for ($s = 0; $s -le 6; $s++) { [void](AbsMove ($gx - 60 + [int](60 * $s / 6)) ($gy - 60 + [int](60 * $s / 6))); Start-Sleep -Milliseconds 30 }
    [void](AbsMoveVerified $gx $gy); Start-Sleep -Milliseconds 1000
    $cp3 = New-Object SR0M.Native+POINT; [void][SR0M.Native]::GetCursorPos([ref]$cp3)
    $hit3 = HitTest $cp3.x $cp3.y
    Diag "c_attempt${attempt}_before_down"
    $dn = MouseBtn $LDOWN; Start-Sleep -Milliseconds 150
    Diag "c_attempt${attempt}_after_down"
    $mv = AbsMoveForMs $HOLD_MS $cp3.x $cp3.y ($cp3.x + 160) ($cp3.y + 100)
    $up = MouseBtn $LUP; Start-Sleep -Milliseconds 300
    EndStuckLoop
    $r4 = Rect
    $chg = (($r4.right -ne $r3.right) -or ($r4.bottom -ne $r3.bottom))
    Log ("loop_c_border_drag attempt={0} grip=({1},{2}) hit_at_grip={3} down={4} moves_ok={5} up={6} hold_ms={7} s={8:N2} rect ({9},{10},{11},{12}) -> ({13},{14},{15},{16}) changed={17}" -f $attempt, $cp3.x, $cp3.y, $hit3, $dn, $mv, $up, $HOLD_MS, ((Get-Date) - $t0).TotalSeconds, $r3.left, $r3.top, $r3.right, $r3.bottom, $r4.left, $r4.top, $r4.right, $r4.bottom, $chg)
    if ($chg) { break }
  }
  $loopWin['loop_c'] = @($loopStartC, $swAll.ElapsedMilliseconds)
  $r = $r4
  $dragS = ((Get-Date) - $t0).TotalSeconds

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
$errText = [string]$stderr.Result
try {
  $evs = @(); foreach ($ln in ($errText -split "`r?`n")) { if ($ln -match '\[sr0-b ev t=(\d+)ms\] (\S+)') { $evs += [pscustomobject]@{ t = [int]$matches[1]; n = $matches[2] } } }
  $cal = $evs | Where-Object { $_.n -eq 'SYSCOMMAND' } | Select-Object -First 1
  if ($cal -and $calibPostMs -ge 0) {
    $off = $cal.t - $calibPostMs
    Log "msg_clock_offset_ms=$off (probe event t minus driver clock, calibrated on loop_a SYSCOMMAND)"
    foreach ($k in 'loop_a', 'loop_b', 'loop_c') {
      if (-not $loopWin.ContainsKey($k)) { continue }
      $lo = $loopWin[$k][0] + $off - 50; $hi = $loopWin[$k][1] + $off + 400
      $sel = @($evs | Where-Object { $_.t -ge $lo -and $_.t -le $hi })
      $cnt = ($sel | Group-Object n | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' '
      Log "msgs_$k window_ms=[$lo,$hi]: $cnt"
    }
  } else { Log 'msg_summary_unavailable: no SYSCOMMAND event to calibrate' }
} catch { Log "msg_summary_error=$($_.Exception.Message)" }
Log '--- stderr ---'
Log $errText
[System.IO.File]::WriteAllText($Out, [string]::Join("`r`n", $lines))
