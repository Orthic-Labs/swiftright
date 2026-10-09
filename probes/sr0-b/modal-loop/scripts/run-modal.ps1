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
  # Order matters: Swift buckets latency by WM_ENTERSIZEMOVE ordinal: 1 = SC_SIZE resize, 2 = SC_MOVE, 3 = injected border drag.
  # Each posted SYSCOMMAND enters the modal size/move loop; the loop is ended with Enter (commit).

  # (a) live resize: SC_SIZE | WMSZ_BOTTOMRIGHT.
  $r0 = Rect; $t0 = Get-Date
  $sx = $r0.right - 4; $sy = $r0.bottom - 4
  [void][SR0M.Native]::SetForegroundWindow($hwnd); [void][SR0M.Native]::SetCursorPos($sx, $sy); Start-Sleep -Milliseconds 100
  $pm = [SR0M.Native]::PostMessageW($hwnd, 0x0112, [IntPtr]0xF008, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 400
  $mv = MoveForMs $HOLD_MS $sx $sy ($sx + 240) ($sy + 160)
  PressEnter
  $r = Rect
  Log ("loop_a_resize SC_SIZE post_ok={0} moves_ok={1} hold_ms={2} s={3:N2} rect ({4},{5},{6},{7}) -> ({8},{9},{10},{11}) changed={12}" -f $pm, $mv, $HOLD_MS, ((Get-Date) - $t0).TotalSeconds, $r0.left, $r0.top, $r0.right, $r0.bottom, $r.left, $r.top, $r.right, $r.bottom, (($r.right -ne $r0.right) -or ($r.bottom -ne $r0.bottom)))
  Start-Sleep -Milliseconds 700

  # (b) move loop: WM_SYSCOMMAND 0xF012 (SC_MOVE | HTCAPTION).
  $r1 = Rect; $t0 = Get-Date
  $cx = [int](($r1.left + $r1.right) / 2); $cy = $r1.top + 40
  [void][SR0M.Native]::SetForegroundWindow($hwnd); [void][SR0M.Native]::SetCursorPos($cx, $cy); Start-Sleep -Milliseconds 100
  $pm = [SR0M.Native]::PostMessageW($hwnd, 0x0112, [IntPtr]0xF012, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 400
  $cp2 = New-Object SR0M.Native+POINT; [void][SR0M.Native]::GetCursorPos([ref]$cp2)
  $mv = MoveForMs $HOLD_MS $cp2.x $cp2.y ($cp2.x - 200) ($cp2.y + 120)
  PressEnter
  $r2 = Rect
  Log ("loop_b_move SC_MOVE0xF012 post_ok={0} moves_ok={1} hold_ms={2} s={3:N2} rect ({4},{5},{6},{7}) -> ({8},{9},{10},{11}) moved={12}" -f $pm, $mv, $HOLD_MS, ((Get-Date) - $t0).TotalSeconds, $r1.left, $r1.top, $r1.right, $r1.bottom, $r2.left, $r2.top, $r2.right, $r2.bottom, (($r2.left -ne $r1.left) -or ($r2.top -ne $r1.top)))
  Start-Sleep -Milliseconds 700

  # (c) injected SendInput border drag on the bottom-right border: cursor at an HTBOTTOMRIGHT point, hover 1 s (real-drag
  #     recipe from result-realdrag.txt), left down, stepped moves for HOLD_MS, left up. Swift verifies ENTERSIZEMOVE fired (3rd enter).
  $r3 = Rect; $t0 = Get-Date
  $inset = 4
  foreach ($d in @(4, 2, 6, 8, 3, 5, 12)) { if ((HitTest ($r3.right - $d) ($r3.bottom - $d)) -eq 17) { $inset = $d; break } }
  $gx = $r3.right - $inset; $gy = $r3.bottom - $inset
  [void][SR0M.Native]::SetForegroundWindow($hwnd); [void][SR0M.Native]::SetCursorPos($gx, $gy); Start-Sleep -Milliseconds 200
  [void](MouseMoveTo ($gx + 1) $gy); [void](MouseMoveTo $gx $gy); Start-Sleep -Milliseconds 1000
  $cp3 = New-Object SR0M.Native+POINT; [void][SR0M.Native]::GetCursorPos([ref]$cp3)
  $hit3 = HitTest $cp3.x $cp3.y
  $dn = MouseBtn $LDOWN; Start-Sleep -Milliseconds 100
  $mv = MoveForMs $HOLD_MS $cp3.x $cp3.y ($cp3.x + 160) ($cp3.y + 100)
  $up = MouseBtn $LUP; Start-Sleep -Milliseconds 300
  $r4 = Rect
  Log ("loop_c_border_drag grip=({0},{1}) hit_at_grip={2} down={3} moves_ok={4} up={5} hold_ms={6} s={7:N2} rect ({8},{9},{10},{11}) -> ({12},{13},{14},{15}) changed={16}" -f $cp3.x, $cp3.y, $hit3, $dn, $mv, $up, $HOLD_MS, ((Get-Date) - $t0).TotalSeconds, $r3.left, $r3.top, $r3.right, $r3.bottom, $r4.left, $r4.top, $r4.right, $r4.bottom, (($r4.right -ne $r3.right) -or ($r4.bottom -ne $r3.bottom)))
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
Log '--- stderr ---'
Log ([string]$stderr.Result)
[System.IO.File]::WriteAllText($Out, [string]::Join("`r`n", $lines))
