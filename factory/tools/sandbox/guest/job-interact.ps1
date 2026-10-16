# job-interact.ps1 - kind=interact (F2). Like job-capture.ps1 (same exe copy, renderer, host lease) but per run it also DRIVES the host window and dumps its UI Automation tree.
# args: {"exe":..., "runs":N, "renderer":..., "steps":[...], "settleMs":500}
# Steps (executed in order against the host's main window; every step may carry "target":"main"|"dialog" - "dialog" = the newest other top-level window the process owns,
# e.g. a TaskDialog; default main). All coordinates are client pixels of the target window:
#   {"op":"key","key":"Tab"|"Enter"|"Escape"|"Space"|"Left"|"Right"|"Up"|"Down"|"Backspace"|"Delete"|"Home"|"End"|"F1".."F12"|"A".."Z"|"0".."9"|"vk:0x..", "mods":["shift","ctrl","alt"], "input":false}
#        WM_KEYDOWN/WM_KEYUP posted to the window (no activation, no foreground). With "mods" (or "input":true) the keys go through keybd_event after the Sandbox gives the
#        window the foreground, because posted messages do not move GetKeyState (the Sandbox is its own desktop; nothing reaches the Dell).
#   {"op":"char","text":"héllo"}                         WM_CHAR per UTF-16 unit
#   {"op":"click","x":10,"y":20,"button":"left|right","count":1}   WM_MOUSEMOVE + button down/up
#   {"op":"move","x":10,"y":20,"down":false}                   WM_MOUSEMOVE posted at the client point (wParam MK_LBUTTON when "down"): a pointer move, with no button (hover) or with the primary button held (a drag in steps)
#   {"op":"drag","x0":10,"y0":20,"x1":90,"y1":20,"steps":6}    WM_MOUSEMOVE, left button down at (x0, y0), `steps` WM_MOUSEMOVE with MK_LBUTTON along the line, button up at (x1, y1)
#   {"op":"leave","real":false}                                 WM_MOUSELEAVE posted (real: the real cursor is moved just outside the window, by SendInput)
#   ("move" with "real":true moves the REAL cursor to the client point by SendInput (absolute, virtual desk) instead of posting a message; the cursor position read back
#    with GetCursorPos goes into the step result and into cursor-NN.txt. Never post synthetic WM_MOUSEMOVE for hover: the cases must prove real-cursor hover.)
#   {"op":"ime","action":"compose","text":"にほ"}        ImmSetCompositionStringW(SCS_SETSTR) on the window's input context, then WM_IME_COMPOSITION(GCS_COMPSTR); falls back to posting
#   {"op":"ime","action":"commit","text":"日本"}         WM_IME_COMPOSITION(GCS_RESULTSTR) when the IMM call is refused (recorded in the step log); "cancel" ends the composition
#   {"op":"invoke","name":"OK"}                          UIA InvokePattern on the first element (in the target window) whose Name equals `name` (dialog buttons; the Sandbox cannot click a TaskDialog by pixels reliably)
#   {"op":"foreground"}                                  give the target window the foreground inside the Sandbox (a task dialog's default button then reports keyboard focus in UIA)
#   {"op":"wait","ms":300}
#   {"op":"dump","label":"after-open"}                   extra UIA dump -> uia-NN-<label>.json
#   {"op":"shot","label":"mid"}                          extra PrintWindow capture -> native-NN-<label>.png
# After the steps: settle, final UIA dump of EVERY top-level window the process owns (name, role/control type, value, bounds, focus, enabled, toggle state, automation id, class) -> uia-NN.json,
# then PrintWindow of the main window -> native-NN.png. steps-NN.json logs what each step did (ok/error). done.json has one row per run.
param([Parameter(Mandatory)][string]$JobDir)
$ErrorActionPreference = 'Stop'
$job = Get-Content -LiteralPath "$JobDir\job.json" -Raw | ConvertFrom-Json
$runs = $(if ($job.args.runs) { [int]$job.args.runs } else { 1 })
$settle = $(if ($null -ne $job.args.settleMs) { [int]$job.args.settleMs } else { 500 })
$steps = @($job.args.steps)
$res = [ordered]@{ kind = 'interact'; ok = $false; runs = $runs; exe_source = [string]$job.args.exe; steps = $steps.Count }

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Collections.Generic; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices; using System.Text;
public static class IxNative {
 [StructLayout(LayoutKind.Sequential)] public struct RECT {public int left,top,right,bottom;}
 public delegate bool EnumProc(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h,IntPtr dc,uint f);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr a,int x,int y,int cx,int cy,uint f);
 [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
 [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern IntPtr SendMessageTimeoutW(IntPtr h,uint m,IntPtr w,IntPtr l,uint f,uint t,out IntPtr r);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h,uint cmd);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h,ref POINT p);
 [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
 [StructLayout(LayoutKind.Sequential)] public struct POINT {public int x,y;}
 public static int[] ClientScreen(IntPtr h){RECT r; GetClientRect(h,out r); POINT p=new POINT(); ClientToScreen(h,ref p); return new int[]{p.x,p.y,r.right-r.left,r.bottom-r.top};}
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 // Real-cursor moves (CI windows-2025 Hyper-V runner: SetCursorPos never reached the window; SendInput with absolute coordinates is the input path under test).
 [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT {public int dx,dy; public uint mouseData,dwFlags,time; public IntPtr dwExtraInfo;}
 [StructLayout(LayoutKind.Sequential)] public struct INPUT {public uint type; public MOUSEINPUT mi;}
 [DllImport("user32.dll")] public static extern uint SendInput(uint n,INPUT[] inputs,int size);
 [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
 [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
 // Virtual screen (SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN, SM_CXVIRTUALSCREEN, SM_CYVIRTUALSCREEN) in physical pixels (the process is per-monitor DPI aware).
 public static int[] Virt(){return new int[]{GetSystemMetrics(76),GetSystemMetrics(77),GetSystemMetrics(78),GetSystemMetrics(79)};}
 // Moves the real cursor to the screen point (x,y) with SendInput: MOUSEEVENTF_MOVE|ABSOLUTE|VIRTUALDESK, coordinates normalised to 0..65535 over the virtual screen.
 // Returns the number of inputs injected (1 on success).
 public static int SendAbsMove(int x,int y){
  int[] v=Virt(); if(v[2]<2||v[3]<2) return -1;
  INPUT i=new INPUT(); i.type=0;
  i.mi.dx=(int)Math.Round((x-v[0])*65535.0/(v[2]-1)); i.mi.dy=(int)Math.Round((y-v[1])*65535.0/(v[3]-1));
  i.mi.dwFlags=0x0001|0x8000|0x4000;
  return (int)SendInput(1,new INPUT[]{i},Marshal.SizeOf(typeof(INPUT)));
 }
 public static string Cur(){POINT p; GetCursorPos(out p); return p.x+","+p.y;}
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a,uint b,bool f);
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")] public static extern void keybd_event(byte vk,byte scan,uint flags,UIntPtr extra);
 [DllImport("user32.dll")] public static extern uint MapVirtualKeyW(uint code,uint type);
 [DllImport("imm32.dll")] public static extern IntPtr ImmGetContext(IntPtr h);
 [DllImport("imm32.dll")] public static extern bool ImmReleaseContext(IntPtr h,IntPtr c);
 [DllImport("imm32.dll")] public static extern bool ImmSetCompositionStringW(IntPtr c,uint index,byte[] comp,uint compLen,byte[] read,uint readLen);
 [DllImport("imm32.dll")] public static extern bool ImmNotifyIME(IntPtr c,uint action,uint index,uint value);
 public static IntPtr[] TopWindows(uint pid){
  var l=new List<IntPtr>();
  EnumWindows(delegate(IntPtr h,IntPtr x){uint p; GetWindowThreadProcessId(h,out p); if(p==pid) l.Add(h); return true;},IntPtr.Zero);
  return l.ToArray();
 }
 public static string Cls(IntPtr h){var b=new StringBuilder(256);GetClassNameW(h,b,256);return b.ToString();}
 public static string Txt(IntPtr h){var b=new StringBuilder(512);GetWindowTextW(h,b,512);return b.ToString();}
 // Settled-snapshot capture (as factory/tools/pair/capture.ps1): Grab returns the digest of one PrintWindow poll and keeps its bitmap; SavePng writes the
 // last settled bitmap, so a PrintWindow taken after the settle loop cannot replace the frame that produced the stable digest.
 public static Bitmap Last;
 public static string Grab(IntPtr h){
  RECT r; if(!GetClientRect(h,out r)) return "gone"; int w=r.right-r.left, ht=r.bottom-r.top; if(w<3||ht<3) return "";
  Bitmap b=new Bitmap(w,ht,PixelFormat.Format32bppArgb);
  using(Graphics g=Graphics.FromImage(b)){g.Clear(Color.Magenta);IntPtr dc=g.GetHdc();bool ok;try{ok=PrintWindow(h,dc,3);}finally{g.ReleaseHdc(dc);} if(!ok){b.Dispose();return "";}}
  var d=b.LockBits(new Rectangle(0,0,w,ht),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
  string dg;
  try{ byte[] px=new byte[d.Stride*ht]; Marshal.Copy(d.Scan0,px,0,px.Length); using(var sha=System.Security.Cryptography.SHA256.Create()){ dg=BitConverter.ToString(sha.ComputeHash(px)); } }
  finally{b.UnlockBits(d);}
  if(Last!=null){Last.Dispose();} Last=b; return dg;
 }
 public static string SavePng(string path){ if(Last==null) return "no settled bitmap"; Last.Save(path,ImageFormat.Png); return "ok"; }
 public static IntPtr Lp(int x,int y){return (IntPtr)(((y&0xFFFF)<<16)|(x&0xFFFF));}
 public static void Foreground(IntPtr h){
  IntPtr fg=GetForegroundWindow(); uint pid; uint ft=GetWindowThreadProcessId(fg,out pid); uint me=GetCurrentThreadId();
  if(ft!=0&&ft!=me) AttachThreadInput(me,ft,true);
  SetForegroundWindow(h);
  if(ft!=0&&ft!=me) AttachThreadInput(me,ft,false);
 }
}
'@
[void][IxNative]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))

$WM = @{ KEYDOWN = 0x100; KEYUP = 0x101; CHAR = 0x102; SYSKEYDOWN = 0x104; SYSKEYUP = 0x105; MOUSEMOVE = 0x200; LBUTTONDOWN = 0x201; LBUTTONUP = 0x202; RBUTTONDOWN = 0x204; RBUTTONUP = 0x205
         MOUSELEAVE = 0x2A3; IME_STARTCOMPOSITION = 0x10D; IME_ENDCOMPOSITION = 0x10E; IME_COMPOSITION = 0x10F }
$VK = @{ Tab = 9; Enter = 13; Return = 13; Escape = 27; Esc = 27; Space = 32; Left = 37; Up = 38; Right = 39; Down = 40; Backspace = 8; Delete = 46; Home = 36; End = 35; PageUp = 33; PageDown = 34; Shift = 16; Ctrl = 17; Alt = 18 }
function Get-Vk([string]$k) {
    if ($VK.ContainsKey($k)) { return [int]$VK[$k] }
    if ($k -match '^vk:(0x[0-9a-fA-F]+|\d+)$') { return [int]$Matches[1] }
    if ($k -match '^F(\d{1,2})$') { return 0x6F + [int]$Matches[1] }
    if ($k.Length -eq 1) { return [int][char]$k.ToUpper() }
    throw "unknown key '$k'"
}
function KeyLParam([int]$vk, [bool]$up, [bool]$ext = $false) {
    $scan = [IxNative]::MapVirtualKeyW([uint32]$vk, 0)
    [uint32]$v = 1 + ($scan * 65536)
    if ($ext) { $v += 16777216 }
    if ($up) { $v += 3221225472 }
    return [IntPtr][BitConverter]::ToInt32([BitConverter]::GetBytes($v), 0)
}

function Get-Windows([uint32]$procId) {
    # visible top-level windows the process owns, top of the Z order first (a TaskDialog is an owned popup, so it is listed before its owner)
    return @([IxNative]::TopWindows($procId) | Where-Object { $_ -ne [IntPtr]::Zero -and [IxNative]::IsWindowVisible($_) })
}
function Resolve-Target($proc, $step, $mainH) {
    $t = $(if ($step.target) { [string]$step.target } else { 'main' })
    if ($t -eq 'main') { return $mainH }
    $others = @(Get-Windows $proc.Id | Where-Object { $_ -ne $mainH })
    if ($others.Count -eq 0) { throw "no dialog window (target=dialog)" }
    return $others[0]    # EnumWindows is top of the Z order first: the newest
}

function Rect-Of($h) { $r = New-Object IxNative+RECT; [void][IxNative]::GetWindowRect($h, [ref]$r); return @($r.left, $r.top, $r.right, $r.bottom) }

function Dump-Element($el, [int]$depth, [int]$maxDepth) {
    $o = [ordered]@{}
    $c = $el.Current
    $o.name = $c.Name; $o.role = $c.ControlType.ProgrammaticName -replace '^ControlType\.', ''; $o.localizedRole = $c.LocalizedControlType
    $o.automationId = $c.AutomationId; $o.className = $c.ClassName
    $r = $c.BoundingRectangle
    $o.bounds = $(if ($r.IsEmpty) { $null } else { @([math]::Round($r.X, 1), [math]::Round($r.Y, 1), [math]::Round($r.Width, 1), [math]::Round($r.Height, 1)) })
    $o.enabled = [bool]$c.IsEnabled; $o.focus = [bool]$c.HasKeyboardFocus; $o.offscreen = [bool]$c.IsOffscreen; $o.focusable = [bool]$c.IsKeyboardFocusable
    try { $p = $null; if ($el.TryGetCurrentPattern([Windows.Automation.TogglePattern]::Pattern, [ref]$p)) { $o.toggle = $p.Current.ToggleState.ToString() } } catch { }
    try { $p = $null; if ($el.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern, [ref]$p)) { $o.value = $p.Current.Value } } catch { }
    try { $p = $null; if ($el.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$p)) { $o.selected = [bool]$p.Current.IsSelected } } catch { }
    # RangeValue (a slider, ABI 0.9): value, minimum, maximum, SmallChange, LargeChange
    try { $p = $null; if ($el.TryGetCurrentPattern([Windows.Automation.RangeValuePattern]::Pattern, [ref]$p)) { $c2 = $p.Current; $o.range = [ordered]@{ value = $c2.Value; minimum = $c2.Minimum; maximum = $c2.Maximum; smallChange = $c2.SmallChange; largeChange = $c2.LargeChange; readOnly = [bool]$c2.IsReadOnly } } } catch { }
    $kids = @()
    if ($depth -lt $maxDepth) {
        $w = [Windows.Automation.TreeWalker]::RawViewWalker
        try { $k = $w.GetFirstChild($el) } catch { $k = $null }
        while ($k) { $kids += , (Dump-Element $k ($depth + 1) $maxDepth); try { $k = $w.GetNextSibling($k) } catch { $k = $null } }
    }
    $o.children = $kids
    return $o
}

function Dump-Process($proc, $mainH, [string]$path) {
    $wins = @()
    $focused = $null
    try { $f = [Windows.Automation.AutomationElement]::FocusedElement; if ($f -and $f.Current.ProcessId -eq $proc.Id) { $focused = [ordered]@{ name = $f.Current.Name; role = $f.Current.ControlType.ProgrammaticName -replace '^ControlType\.', ''; automationId = $f.Current.AutomationId } } } catch { }
    foreach ($h in (Get-Windows $proc.Id)) {
        $w = [ordered]@{ hwnd = [int64]$h; main = ($h -eq $mainH); class = [IxNative]::Cls($h); title = [IxNative]::Txt($h); rect = (Rect-Of $h); client = [IxNative]::ClientScreen($h); dpi = [IxNative]::GetDpiForWindow($h) }
        try { $w.tree = Dump-Element ([Windows.Automation.AutomationElement]::FromHandle($h)) 0 24 } catch { $w.error = $_.Exception.Message }
        $wins += , $w
    }
    $doc = [ordered]@{ pid = $proc.Id; focusedElement = $focused; windows = $wins }
    [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $doc -Depth 40), (New-Object Text.UTF8Encoding($false)))
}

function Find-ByName($root, [string]$name) {
    $cond = New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty, $name)
    return $root.FindFirst([Windows.Automation.TreeScope]::Descendants, $cond)
}

# Settled capture, the capture.ps1 rule (CI 38852596361, 38854967920): poll PrintWindow every 200 ms until three identical digests in a row (20 s limit),
# save the last settled bitmap itself, and warn when a poll differed from the stable digest. Every poll digest goes to $log (settle-NN-*.txt).
# Host lifetime (CI 38865487951 ime-composing-v1 runs 1-2): the host ends its own process after its capture lease, counted from its first tick. The lease is requested
# with --factory-capture-lease-seconds (below), but a host whose main.swift keeps a compiled 10 s check ignores the flag. $script:tWin is when this run first saw the
# window; Gone-Report puts the elapsed time and the requested lease into the error so a closed window names how long it lived.
$script:tWin = $null; $script:proc = $null; $script:leaseS = 120
function Window-Ms { if ($script:tWin) { return [int]([DateTime]::UtcNow - $script:tWin).TotalMilliseconds } return -1 }
function Gone-Report([string]$where) {
    $exited = [bool]($script:proc -and $script:proc.HasExited)
    return "GetClientRect failed: host window gone $where, $(Window-Ms) ms after the window was first seen; host process exited=$exited; requested lease=$($script:leaseS) s (a host with a compiled lease ignores the flag)"
}
function Test-Alive($h) { $r = New-Object IxNative+RECT; return [bool][IxNative]::GetClientRect($h, [ref]$r) }

function Save-SettledShot([IntPtr]$h, [string]$path, [string]$log) {
    $start = [DateTime]::UtcNow; $digests = @(); $prev = $null; $same = 0; $stable = $null
    while ($null -eq $stable) {
        if ([DateTime]::UtcNow -gt $start.AddSeconds(20)) { return 'first present not observed within 20 s' }
        Start-Sleep -Milliseconds 200
        $dg = [IxNative]::Grab($h); $digests += , $dg
        if ($dg -eq 'gone') { return (Gone-Report 'during the settle poll') }
        if ($dg -ne '' -and $dg -eq $prev) { $same++ } else { $same = 0 }
        $prev = $dg
        if ($same -ge 2) { $stable = $dg }
    }
    $differs = @(); for ($q = 0; $q -lt $digests.Count; $q++) { if ($digests[$q] -ne $stable) { $differs += ("poll$($q + 1)=" + $digests[$q]) } }
    if ($differs.Count -gt 0) { Write-Warning ((Split-Path $path -Leaf) + ': ' + $differs.Count + ' of ' + $digests.Count + ' PrintWindow poll(s) differ from the stable digest: ' + ($differs -join ' ')) }
    Set-Content -Path $log -Value ('settled polls=' + $digests.Count + ' stable=' + $stable + ' differing=' + $differs.Count + $(if ($differs.Count) { ' ' + ($differs -join ' ') } else { '' }))
    return [IxNative]::SavePng($path)
}

function Do-Step($proc, $mainH, $step, [string]$out, [string]$n) {
    $op = [string]$step.op
    $h = $(if ($op -in 'wait', 'dump', 'shot') { $mainH } else { Resolve-Target $proc $step $mainH })
    switch ($op) {
        'foreground' { [IxNative]::Foreground($h); Start-Sleep -Milliseconds 300; return 'ok' }
        'wait' { Start-Sleep -Milliseconds ([int]$step.ms); return 'ok' }
        'dump' { Dump-Process $proc $mainH (Join-Path $out ("uia-$n-" + [string]$step.label + '.json')); return 'ok' }
        'shot' { return Save-SettledShot $mainH (Join-Path $out ("native-$n-" + [string]$step.label + '.png')) (Join-Path $out ("settle-$n-" + [string]$step.label + '.txt')) }
        'key' {
            $keyVk = Get-Vk ([string]$step.key); $mods = @($step.mods | Where-Object { $_ })
            $ext = $keyVk -in 33, 34, 35, 36, 37, 38, 39, 40, 45, 46
            if ($mods.Count -gt 0 -or $step.input) {
                [IxNative]::Foreground($h); Start-Sleep -Milliseconds 80
                $mv = @($mods | ForEach-Object { Get-Vk ([string]$_) })
                foreach ($m in $mv) { [IxNative]::keybd_event([byte]$m, 0, 0, [UIntPtr]::Zero) }
                [IxNative]::keybd_event([byte]$keyVk, 0, $(if ($ext) { 1 } else { 0 }), [UIntPtr]::Zero); Start-Sleep -Milliseconds 30
                [IxNative]::keybd_event([byte]$keyVk, 0, $(if ($ext) { 3 } else { 2 }), [UIntPtr]::Zero)
                [array]::Reverse($mv); foreach ($m in $mv) { [IxNative]::keybd_event([byte]$m, 0, 2, [UIntPtr]::Zero) }
                return 'ok(input)'
            }
            [void][IxNative]::PostMessageW($h, $WM.KEYDOWN, [IntPtr]$keyVk, (KeyLParam $keyVk $false $ext)); Start-Sleep -Milliseconds 30
            [void][IxNative]::PostMessageW($h, $WM.KEYUP, [IntPtr]$keyVk, (KeyLParam $keyVk $true $ext)); return 'ok(post)'
        }
        'char' {
            foreach ($ch in ([string]$step.text).ToCharArray()) { [void][IxNative]::PostMessageW($h, $WM.CHAR, [IntPtr][int]$ch, [IntPtr]1); Start-Sleep -Milliseconds 15 }
            return 'ok'
        }
        'click' {
            $x = [int]$step.x; $y = [int]$step.y; $right = ([string]$step.button -eq 'right')
            $dn = $(if ($right) { $WM.RBUTTONDOWN } else { $WM.LBUTTONDOWN }); $up = $(if ($right) { $WM.RBUTTONUP } else { $WM.LBUTTONUP }); $mk = $(if ($right) { 2 } else { 1 })
            $count = $(if ($step.count) { [int]$step.count } else { 1 })
            [void][IxNative]::PostMessageW($h, $WM.MOUSEMOVE, [IntPtr]0, [IxNative]::Lp($x, $y)); Start-Sleep -Milliseconds 40
            for ($i = 0; $i -lt $count; $i++) {
                [void][IxNative]::PostMessageW($h, $dn, [IntPtr]$mk, [IxNative]::Lp($x, $y)); Start-Sleep -Milliseconds 40
                [void][IxNative]::PostMessageW($h, $up, [IntPtr]0, [IxNative]::Lp($x, $y)); Start-Sleep -Milliseconds 40
            }
            return 'ok'
        }
        'move' {
            $x = [int]$step.x; $y = [int]$step.y; $wp = $(if ($step.down) { 1 } else { 0 })
            if ($step.real) {
                # the real cursor, moved by SendInput: the OS then sends WM_MOUSEMOVE and, when it leaves, WM_MOUSELEAVE (a posted move leaves the real cursor elsewhere, so the window's own mouse tracking reports a leave at once)
                $cs = [IxNative]::ClientScreen($h); $tx = $cs[0] + $x; $ty = $cs[1] + $y
                $sent = [IxNative]::SendAbsMove($tx, $ty)
                if ($sent -ne 1) { throw "SendInput injected $sent of 1 input(s) for the cursor move to $tx,$ty (virtual screen $(([IxNative]::Virt()) -join ','))" }
                Start-Sleep -Milliseconds 80
                $cur = [IxNative]::Cur()
                Add-Content -LiteralPath (Join-Path $out "cursor-$n.txt") -Value ("move client=$x,$y screen=$tx,$ty cursor-after=$cur")
                return "ok(cursor=$cur target=$tx,$ty)"
            }
            [void][IxNative]::PostMessageW($h, $WM.MOUSEMOVE, [IntPtr]$wp, [IxNative]::Lp($x, $y)); Start-Sleep -Milliseconds 40
            return 'ok'
        }
        'drag' {
            $x0 = [int]$step.x0; $y0 = [int]$step.y0; $x1 = [int]$step.x1; $y1 = [int]$step.y1; $n = $(if ($step.steps) { [int]$step.steps } else { 6 })
            [void][IxNative]::PostMessageW($h, $WM.MOUSEMOVE, [IntPtr]0, [IxNative]::Lp($x0, $y0)); Start-Sleep -Milliseconds 40
            [void][IxNative]::PostMessageW($h, $WM.LBUTTONDOWN, [IntPtr]1, [IxNative]::Lp($x0, $y0)); Start-Sleep -Milliseconds 40
            for ($i = 1; $i -le $n; $i++) {
                $x = [int][math]::Round($x0 + ($x1 - $x0) * $i / $n); $y = [int][math]::Round($y0 + ($y1 - $y0) * $i / $n)
                [void][IxNative]::PostMessageW($h, $WM.MOUSEMOVE, [IntPtr]1, [IxNative]::Lp($x, $y)); Start-Sleep -Milliseconds 40
            }
            [void][IxNative]::PostMessageW($h, $WM.LBUTTONUP, [IntPtr]0, [IxNative]::Lp($x1, $y1)); Start-Sleep -Milliseconds 40
            return 'ok'
        }
        'leave' {
            if ($step.real) {
                # the real cursor is moved by SendInput to the first point 60 px outside the client area (right, left, below, above) that lies on the virtual screen
                $cs = [IxNative]::ClientScreen($h); $v = [IxNative]::Virt()
                $mx = $cs[0] + [int]($cs[2] / 2); $my = $cs[1] + [int]($cs[3] / 2)
                $cands = @(@(($cs[0] + $cs[2] + 60), $my), @(($cs[0] - 60), $my), @($mx, ($cs[1] + $cs[3] + 60)), @($mx, ($cs[1] - 60)))
                $pick = $null
                foreach ($c in $cands) { if ($c[0] -ge $v[0] -and $c[0] -lt ($v[0] + $v[2]) -and $c[1] -ge $v[1] -and $c[1] -lt ($v[1] + $v[3])) { $pick = $c; break } }
                if ($null -eq $pick) { throw "no point 60 px outside the window lies on the virtual screen ($($v -join ','))" }
                $sent = [IxNative]::SendAbsMove([int]$pick[0], [int]$pick[1])
                if ($sent -ne 1) { throw "SendInput injected $sent of 1 input(s) for the cursor leave to $($pick[0]),$($pick[1])" }
                Start-Sleep -Milliseconds 120
                $cur = [IxNative]::Cur()
                $outside = -not ([int]$pick[0] -ge $cs[0] -and [int]$pick[0] -lt ($cs[0] + $cs[2]) -and [int]$pick[1] -ge $cs[1] -and [int]$pick[1] -lt ($cs[1] + $cs[3]))
                Add-Content -LiteralPath (Join-Path $out "cursor-$n.txt") -Value ("leave target=$($pick[0]),$($pick[1]) client=$($cs -join ',') cursor-after=$cur outside-client=$outside")
                return "ok(cursor=$cur target=$($pick[0]),$($pick[1]) outside-client=$outside)"
            }
            [void][IxNative]::PostMessageW($h, $WM.MOUSELEAVE, [IntPtr]0, [IntPtr]0); Start-Sleep -Milliseconds 40
            return 'ok'
        }
        'ime' {
            $act = [string]$step.action; $text = [string]$step.text
            $GCS_COMPSTR = 0x8; $GCS_RESULTSTR = 0x800; $GCS_CURSORPOS = 0x80; $SCS_SETSTR = 9; $CPS_COMPLETE = 1; $CPS_CANCEL = 4; $NI_COMPOSITIONSTR = 0x15
            $imc = [IxNative]::ImmGetContext($h); $how = 'imm'
            $bytes = [Text.Encoding]::Unicode.GetBytes($text + [char]0)
            $ok = $false
            if ($act -eq 'compose') {
                [void][IxNative]::PostMessageW($h, $WM.IME_STARTCOMPOSITION, [IntPtr]0, [IntPtr]0)
                if ($imc -ne [IntPtr]::Zero) { $ok = [IxNative]::ImmSetCompositionStringW($imc, $SCS_SETSTR, $bytes, [uint32]($bytes.Length), $null, 0) }
                [void][IxNative]::PostMessageW($h, $WM.IME_COMPOSITION, [IntPtr]($text.Length), [IntPtr]($GCS_COMPSTR -bor $GCS_CURSORPOS))
            } elseif ($act -eq 'commit') {
                if ($imc -ne [IntPtr]::Zero) { $ok = [IxNative]::ImmSetCompositionStringW($imc, $SCS_SETSTR, $bytes, [uint32]($bytes.Length), $null, 0); if ($ok) { [void][IxNative]::ImmNotifyIME($imc, $NI_COMPOSITIONSTR, $CPS_COMPLETE, 0) } }
                [void][IxNative]::PostMessageW($h, $WM.IME_COMPOSITION, [IntPtr]($text.Length), [IntPtr]($GCS_RESULTSTR))
                [void][IxNative]::PostMessageW($h, $WM.IME_ENDCOMPOSITION, [IntPtr]0, [IntPtr]0)
            } elseif ($act -eq 'cancel') {
                if ($imc -ne [IntPtr]::Zero) { $ok = [IxNative]::ImmNotifyIME($imc, $NI_COMPOSITIONSTR, $CPS_CANCEL, 0) }
                [void][IxNative]::PostMessageW($h, $WM.IME_ENDCOMPOSITION, [IntPtr]0, [IntPtr]0)
            } else { throw "unknown ime action '$act'" }
            if ($imc -ne [IntPtr]::Zero) { [void][IxNative]::ImmReleaseContext($h, $imc) }
            return ('ok(imc=' + ($imc -ne [IntPtr]::Zero) + ',imm-accepted=' + $ok + ',messages-posted)')
        }
        'invoke' {
            $el = Find-ByName ([Windows.Automation.AutomationElement]::FromHandle($h)) ([string]$step.name)
            if (-not $el) { throw "no element named '$($step.name)'" }
            $p = $el.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern); $p.Invoke(); return 'ok'
        }
        default { throw "unknown op '$op'" }
    }
}

try {
    $env:Path = 'C:\swiftrt;' + $env:Path
    $renderer = $(if ($job.args.renderer) { [string]$job.args.renderer } else { 'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll' })
    if (-not (Test-Path -LiteralPath $renderer)) { throw "renderer dll not visible in the guest: $renderer" }
    $env:SWIFTRIGHT_RENDER_DLL = $renderer
    $src = [string]$job.args.exe
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "exe not visible in the guest: $src" }
    $work = 'C:\work\' + (Split-Path -Leaf $JobDir)
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $pkg = $src -replace '\\scratch\\.*$', ''
    if ($pkg -ne $src -and (Test-Path -LiteralPath $pkg -PathType Container)) {
        $exe = Join-Path $work ($src.Substring($pkg.Length).TrimStart('\'))
        Get-ChildItem -LiteralPath $pkg -File | Copy-Item -Destination $work -Force
        if (Test-Path -LiteralPath "$pkg\Resources" -PathType Container) { Copy-Item -LiteralPath "$pkg\Resources" -Destination $work -Recurse -Force }
    } else { $exe = Join-Path $work 'FactoryProbe.exe' }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $exe) | Out-Null
    Copy-Item -LiteralPath $src -Destination $exe -Force
    Get-ChildItem -LiteralPath (Split-Path -Parent $src) -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in ".dll", ".json" } | Copy-Item -Destination (Split-Path -Parent $exe) -Force
    $res.exe_sha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLower()
    $res.renderer = $renderer
    $res.renderer_sha256 = (Get-FileHash -LiteralPath $renderer -Algorithm SHA256).Hash.ToLower()
    try { $res.video = @(Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name + ' ' + $_.DriverVersion }) } catch { }
    $out = "$JobDir\out"
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    $results = @()
    # The host honours this flag only when its main.swift parses it (213 of the 353 FactoryProbe copies at HEAD). The other 140, among them ime-composing-v1 and
    # imet-badregion-v1, have a compiled 10 s lease (10_000_000_000 ns) and ignore the argument, so the window closes about 10 s after its first tick whatever is
    # requested here. The fix for those copies is in the host source, not this harness; see Gone-Report for what a closed window now reports.
    $script:leaseS = $(if ($job.args.leaseSeconds) { [int]$job.args.leaseSeconds } else { 120 })
    $leaseArg = "--factory-capture-lease-seconds=$($script:leaseS)"
    for ($i = 1; $i -le $runs; $i++) {
        $n = '{0:00}' -f $i; $p = $null; $status = 'failed'; $log = @(); $script:tWin = $null; $script:proc = $null
        try {
            $si = [Diagnostics.ProcessStartInfo]::new($exe); $si.Arguments = $leaseArg; $si.UseShellExecute = $false; $si.CreateNoWindow = $true
            $si.RedirectStandardOutput = $true; $si.RedirectStandardError = $true
            # Park the real cursor at the bottom-right corner of the primary screen, outside the window the host is about to create (the host's window sits at the
            # top-left, so the origin is inside it): the cursor is shared across jobs, so a cursor left over the window would be a hover at creation (an extra
            # enter, then an exit square in the event strip, and every later square shifted; block 38 rows/adjacent).
            $scr = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            [void][IxNative]::SetCursorPos($scr.Right - 1, $scr.Bottom - 1)
            $p = [Diagnostics.Process]::Start($si); $script:proc = $p; $so = $p.StandardOutput.ReadToEndAsync(); $se = $p.StandardError.ReadToEndAsync()
            $deadline = [DateTime]::UtcNow.AddSeconds(30)
            do { Start-Sleep -Milliseconds 100; $p.Refresh(); if ($p.HasExited) { throw "host exited early code=$($p.ExitCode)" }; if ([DateTime]::UtcNow -gt $deadline) { throw 'window deadline' } } while ($p.MainWindowHandle -eq [IntPtr]::Zero)
            $h = $p.MainWindowHandle; $script:tWin = [DateTime]::UtcNow
            if (-not [IxNative]::SetWindowPos($h, [IntPtr]::new(1), 0, 0, 0, 0, 0x0013)) { throw 'SetWindowPos failed' }
            Start-Sleep -Milliseconds $settle
            $k = 0
            foreach ($s in $steps) {
                $k++
                $r = 'ok'; $t0 = Window-Ms
                try { $r = Do-Step $p $h $s $out $n } catch { $r = 'ERROR: ' + $_.Exception.Message }
                $log += [ordered]@{ step = $k; op = [string]$s.op; result = $r; window_ms_start = $t0; window_ms_end = (Window-Ms) }
                if ($r -like 'ERROR*') { throw "step $k ($($s.op)): $r" }
                if ($p.HasExited -or -not (Test-Alive $h)) { throw (Gone-Report "during step $k ($($s.op))") }
            }
            Start-Sleep -Milliseconds $settle
            if ($p.HasExited -or -not (Test-Alive $h)) { throw (Gone-Report 'before the final UIA dump') }
            Dump-Process $p $h (Join-Path $out "uia-$n.json")
            $r = Save-SettledShot $h (Join-Path $out "native-$n.png") (Join-Path $out "settle-$n.txt"); if ($r -ne 'ok') { throw $r }
            $status = 'ok'
        } catch { $status = [string]$_ }
        finally {
            [IO.File]::WriteAllText((Join-Path $out "steps-$n.json"), (ConvertTo-Json -InputObject @($log) -Depth 5), (New-Object Text.UTF8Encoding($false)))
            if ($p) {
                try { if (-not $p.HasExited) { $p.Kill() }; [void]$p.WaitForExit(10000) } catch { }
                try { [void]$so.Wait(5000); $so.Result | Set-Content (Join-Path $out "host-$n.stdout.txt"); $se.Result | Set-Content (Join-Path $out "host-$n.stderr.txt") } catch { }
            }
        }
        $results += [ordered]@{ run = $i; status = $status; lease_s_requested = $script:leaseS; window_ms_at_end = (Window-Ms) }
    }
    ConvertTo-Json -InputObject @($results) | Set-Content (Join-Path $out 'done.json')
    $res.done = $results
    $res.ok = [bool](@($results | Where-Object { $_.status -ne 'ok' }).Count -eq 0 -and $results.Count -eq $runs)
} catch { $res.error = $_.Exception.Message }
finally { Get-Process FactoryProbe -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
[IO.File]::WriteAllText("$JobDir\result.json", (ConvertTo-Json -InputObject $res -Depth 6), (New-Object Text.UTF8Encoding($false)))
exit 0
