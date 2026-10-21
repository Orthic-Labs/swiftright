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
#   {"op":"wheel","x":160,"y":120,"delta":-120,"times":3}      WM_MOUSEWHEEL posted to the target window (window-targeted like the other ops: no SendInput, no focus change). x, y are POINTS
#        (client px = pt * scale, scale = the step's "scale", default 2.5 = the host's factoryRenderScale); lParam is the screen point (ClientToScreen), wParam's high word the
#        delta (WHEEL_DELTA units, -120 = one notch with the content moving toward its end); `times` notches, 120 ms apart. Result "ok(screen=X,Y delta=D times=N)".
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
# SWIFTRIGHT_SCREEN_RECORD (factory-pairs input screen_record): gdigrab (legacy value 1 also means gdigrab) = per run, a continuous ffmpeg recording of the whole desktop ->
# record-NN.mkv and its sidecar record-NN.json; wgc = per run, FactoryWGCRecord.exe (env SWIFTRIGHT_WGC_RECORDER) writes every Windows.Graphics.Capture frame of the host HWND ->
# record-NN-wgc\ (frames.jsonl + frame-NNNNNN.png) and the same sidecar record-NN.json (recorder:"wgc"). See Start-ScreenRecord. Unset or none, nothing below runs.
param([Parameter(Mandatory)][string]$JobDir)
$ErrorActionPreference = 'Stop'
$job = Get-Content -LiteralPath "$JobDir\job.json" -Raw | ConvertFrom-Json
$runs = $(if ($job.args.runs) { [int]$job.args.runs } else { 1 })
$settle = $(if ($null -ne $job.args.settleMs) { [int]$job.args.settleMs } else { 500 })
$script:probe = [bool]$job.args.flickerProbe   # args.flickerProbe: the screen-grab probe in Save-SettledShot (flicker-*.tsv); absent for a normal run
$script:recMode = $(switch (([string]$env:SWIFTRIGHT_SCREEN_RECORD).Trim().ToLowerInvariant()) { '1' { 'gdigrab' } 'gdigrab' { 'gdigrab' } 'wgc' { 'wgc' } default { '' } })
$script:screenRecord = ($script:recMode -ne '')   # opt-in continuous recording (Start-ScreenRecord); absent for a normal run
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
 [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
 [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h,uint flags);
 [DllImport("user32.dll")] public static extern bool IsChild(IntPtr parent,IntPtr child);
 static string Who(IntPtr w){ if(w==IntPtr.Zero) return "none"; uint pid; GetWindowThreadProcessId(w,out pid); string pn="?"; try{ pn=System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; }catch{} return "hwnd="+w.ToInt64()+" class="+Cls(w)+" title="+Txt(w)+" pid="+pid+" process="+pn; }
 // WindowFromPoint at a screen point: the host itself, one of its children, a root that is the host, or another window (named by hwnd, class, pid, process).
 public static string PointWho(int x,int y,IntPtr host){
  POINT p=new POINT(); p.x=x; p.y=y;
  IntPtr w=WindowFromPoint(p);
  string rel = w==IntPtr.Zero ? "none" : w==host ? "host" : IsChild(host,w) ? "child-of-host" : GetAncestor(w,2)==host ? "root-is-host" : "other";
  return "WindowFromPoint[" + rel + "] " + Who(w);
 }
 // Z order of the host among the visible top-level windows (index 0 = top), the foreground window, and every window above the host that overlaps the client area.
 public static string ZInfo(IntPtr host,int[] client){
  var l=new List<IntPtr>(); EnumWindows(delegate(IntPtr h,IntPtr x){ if(IsWindowVisible(h)) l.Add(h); return true; },IntPtr.Zero);
  int idx=l.IndexOf(host); IntPtr fg=GetForegroundWindow();
  var cov=new List<string>(); int lim = idx<0 ? l.Count : idx;
  for(int i=0;i<lim;i++){ RECT r; if(GetWindowRect(l[i],out r) && r.left<client[0]+client[2] && r.right>client[0] && r.top<client[1]+client[3] && r.bottom>client[1]) cov.Add("["+i+"] "+Who(l[i])); }
  string top = l.Count>0 ? "[0] "+Who(l[0]) : "none";
  return "zpos=" + (idx<0 ? "not-visible" : idx.ToString()) + " of " + l.Count + " visible; top=" + top + "; foreground=" + Who(fg) + " host-is-foreground=" + (fg==host) + "; above-and-overlapping-client=" + (cov.Count==0 ? "none" : string.Join(" | ",cov));
 }
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

$WM = @{ KEYDOWN = 0x100; KEYUP = 0x101; CHAR = 0x102; SYSKEYDOWN = 0x104; SYSKEYUP = 0x105; MOUSEMOVE = 0x200; MOUSEWHEEL = 0x20A; LBUTTONDOWN = 0x201; LBUTTONUP = 0x202; RBUTTONDOWN = 0x204; RBUTTONUP = 0x205
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
    # ABI 0.13 accessibility extras: HelpText (hint/placeholder), FullDescription (30159), HeadingLevel (30173), AriaRole; absent or unsupported properties are left out
    try { if ($c.HelpText) { $o.helpText = $c.HelpText } } catch { }
    try { $v = $el.GetCurrentPropertyValue([Windows.Automation.AutomationProperty]::LookupById(30159), $true); if ($v -is [string] -and $v) { $o.fullDescription = $v } } catch { }
    try { $v = $el.GetCurrentPropertyValue([Windows.Automation.AutomationProperty]::LookupById(30173), $true); if ($v -is [int] -and $v -gt 0) { $o.headingLevel = $v } } catch { }
    try { if ($c.AriaRole) { $o.ariaRole = $c.AriaRole } } catch { }
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
    # FlickerProbe (args.flickerProbe, as capture.ps1): the screen region is BitBlt-grabbed at the same instant as each PrintWindow poll; the window is made topmost first
    $sGrabs = @(); $pwStats = @()
    if ($script:probe) { [FlickerScreen]::Clear(); [void][IxNative]::SetWindowPos($h, [IntPtr]::new(-1), 0, 0, 0, 0, 0x0013) }
    while ($null -eq $stable) {
        if ([DateTime]::UtcNow -gt $start.AddSeconds(20)) { return 'first present not observed within 20 s' }
        Start-Sleep -Milliseconds 200
        if ($script:probe) { $tS = [DateTime]::UtcNow.ToString('HH:mm:ss.fff'); $sg = [FlickerScreen]::Grab($h) }
        $dg = [IxNative]::Grab($h); $digests += , $dg
        if ($dg -eq 'gone') { return (Gone-Report 'during the settle poll') }
        if ($script:probe) { $sGrabs += , @($tS, $sg); $pwStats += , @([DateTime]::UtcNow.ToString('HH:mm:ss.fff'), $(if ($dg -ne '') { [FlickerScreen]::Stats([IxNative]::Last) } else { "empty`t`t`t" })) }
        if ($dg -ne '' -and $dg -eq $prev) { $same++ } else { $same = 0 }
        $prev = $dg
        if ($same -ge 2) { $stable = $dg }
    }
    $differs = @(); for ($q = 0; $q -lt $digests.Count; $q++) { if ($digests[$q] -ne $stable) { $differs += ("poll$($q + 1)=" + $digests[$q]) } }
    if ($differs.Count -gt 0) { Write-Warning ((Split-Path $path -Leaf) + ': ' + $differs.Count + ' of ' + $digests.Count + ' PrintWindow poll(s) differ from the stable digest: ' + ($differs -join ' ')) }
    Set-Content -Path $log -Value ('settled polls=' + $digests.Count + ' stable=' + $stable + ' differing=' + $differs.Count + $(if ($differs.Count) { ' ' + ($differs -join ' ') } else { '' }))
    if ($script:probe) {
        $dir = Split-Path $path -Parent; $base = [IO.Path]::GetFileNameWithoutExtension($path)
        $sStable = ($sGrabs[-1][1] -split "`t")[1]
        $tsv = @("poll`tutc_screen`tutc_pw`tscreen_idx`tscreen_digest`tscreen_darkfrac`tscreen_darkrows`tscreen_black`tscreen_topwin_ours`tscreen_rect`tpw_digest`tpw_darkfrac`tpw_darkrows`tpw_black`tscreen_differs`tpw_differs")
        for ($q = 0; $q -lt $sGrabs.Count; $q++) {
            $sf = @($sGrabs[$q][1] -split "`t"); $pf = @($pwStats[$q][1] -split "`t")
            $sd = [int]($sf[1] -ne $sStable); $pd = [int]($digests[$q] -ne $stable)
            $tsv += ((@(($q + 1), $sGrabs[$q][0], $pwStats[$q][0]) + $sf + $pf + @($sd, $pd)) -join "`t")
            if ($sf[0] -ne '-1' -and $sd) { [void][FlickerScreen]::Save([int]$sf[0], (Join-Path $dir ('flicker-' + $base + '-poll' + ($q + 1) + '-screen.png'))) }
        }
        Set-Content -Path (Join-Path $dir ('flicker-' + $base + '.tsv')) -Value $tsv
        [FlickerScreen]::Clear()
    }
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
                $who = [IxNative]::PointWho($tx, $ty, $h); $zi = [IxNative]::ZInfo($h, $cs)
                Add-Content -LiteralPath (Join-Path $out "cursor-$n.txt") -Value ("move client=$x,$y screen=$tx,$ty cursor-after=$cur " + $who + " | " + $zi)
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
        'wheel' {
            # WM_MOUSEWHEEL posted to the target window: no SendInput, no focus change. Points -> client px -> screen point (ClientToScreen) for lParam.
            $scale = $(if ($null -ne $step.scale) { [double]$step.scale } else { 2.5 })
            $cs = [IxNative]::ClientScreen($h)
            $sx = [int][math]::Round($cs[0] + [double]$step.x * $scale); $sy = [int][math]::Round($cs[1] + [double]$step.y * $scale)
            $delta = [int]$step.delta
            $wp = [IntPtr]([long](($delta -band 0xFFFF) -shl 16))
            $lp = [IxNative]::Lp($sx, $sy)
            $times = $(if ($step.times) { [int]$step.times } else { 1 })
            for ($i = 0; $i -lt $times; $i++) {
                [void][IxNative]::PostMessageW($h, $WM.MOUSEWHEEL, $wp, $lp); Start-Sleep -Milliseconds 120
            }
            return "ok(screen=$sx,$sy delta=$delta times=$times)"
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
                $who = [IxNative]::PointWho([int]$pick[0], [int]$pick[1], $h); $zi = [IxNative]::ZInfo($h, $cs)
                Add-Content -LiteralPath (Join-Path $out "cursor-$n.txt") -Value ("leave target=$($pick[0]),$($pick[1]) client=$($cs -join ',') cursor-after=$cur outside-client=$outside " + $who + " | " + $zi)
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

if ($script:probe) {
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Collections.Generic; using System.Drawing; using System.Drawing.Imaging; using System.Globalization; using System.Runtime.InteropServices;
public static class FlickerScreen {
 [StructLayout(LayoutKind.Sequential)] public struct RECT {public int left,top,right,bottom;}
 [StructLayout(LayoutKind.Sequential)] public struct POINT {public int x,y;}
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h,out RECT r);
 [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h,ref POINT p);
 [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
 [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h,IntPtr dc);
 [DllImport("gdi32.dll")] public static extern bool BitBlt(IntPtr dst,int x,int y,int cx,int cy,IntPtr src,int sx,int sy,uint rop);
 [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
 [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h,uint flags);
 public static List<Bitmap> Kept=new List<Bitmap>();
 public static void Clear(){ foreach(Bitmap b in Kept){ b.Dispose(); } Kept.Clear(); }
 public static string Save(int idx,string path){ if(idx<0||idx>=Kept.Count) return "no frame "+idx; Kept[idx].Save(path,ImageFormat.Png); return "ok"; }
 // SHA-256 of the 32bpp rows (as PairNative.Grab), share of pixels with R,G,B < 8, rows at least 90% that dark, and 1 when the frame is black (>= 99% dark).
 public static string Stats(Bitmap b){
  int w=b.Width, ht=b.Height;
  var d=b.LockBits(new Rectangle(0,0,w,ht),ImageLockMode.ReadOnly,PixelFormat.Format32bppArgb);
  byte[] px=new byte[d.Stride*ht];
  try{ Marshal.Copy(d.Scan0,px,0,px.Length); } finally{ b.UnlockBits(d); }
  string dg; using(var sha=System.Security.Cryptography.SHA256.Create()){ dg=BitConverter.ToString(sha.ComputeHash(px)); }
  long dark=0; int darkRows=0;
  for(int y=0;y<ht;y++){ int rd=0; int off=y*d.Stride; for(int x=0;x<w;x++){ int i=off+4*x; if(px[i]<8&&px[i+1]<8&&px[i+2]<8) rd++; } dark+=rd; if(rd>=0.9*w) darkRows++; }
  double frac=(double)dark/((double)w*ht);
  return dg+"\t"+frac.ToString("F4",CultureInfo.InvariantCulture)+"\t"+darkRows+"\t"+(frac>=0.99?1:0);
 }
 // One screen grab of the client area: BitBlt from the screen DC (what the desktop composed at this instant), not PrintWindow.
 // Returns idx, digest, darkfrac, darkrows, black, topwin_ours (1 when the topmost window at the client centre is this window), screen rect sx,sy,w,h.
 // A failed grab has idx -1 and its reason in the last field.
 public static string Grab(IntPtr h){
  RECT r; if(!GetClientRect(h,out r)) return "-1\t\t\t\t\t\tgone";
  int w=r.right-r.left, ht=r.bottom-r.top; if(w<3||ht<3) return "-1\t\t\t\t\t\tsize "+w+"x"+ht;
  POINT o=new POINT(); ClientToScreen(h,ref o);
  POINT c=new POINT(); c.x=o.x+w/2; c.y=o.y+ht/2;
  IntPtr top=WindowFromPoint(c);
  int ours=(top!=IntPtr.Zero && (top==h || GetAncestor(top,2)==h))?1:0;
  Bitmap b=new Bitmap(w,ht,PixelFormat.Format32bppArgb);
  using(Graphics g=Graphics.FromImage(b)){ IntPtr dc=g.GetHdc(); IntPtr sdc=GetDC(IntPtr.Zero); bool ok; try{ ok=BitBlt(dc,0,0,w,ht,sdc,o.x,o.y,0x00CC0020|0x40000000); } finally{ ReleaseDC(IntPtr.Zero,sdc); g.ReleaseHdc(dc); } if(!ok){ b.Dispose(); return "-1\t\t\t\t\t\tbitblt"; } }
  string s=Stats(b); Kept.Add(b);
  return (Kept.Count-1)+"\t"+s+"\t"+ours+"\t"+o.x+","+o.y+","+w+","+ht;
 }
}
'@
}
# Opt-in continuous screen recording (env SWIFTRIGHT_SCREEN_RECORD=gdigrab or wgc; 1 = gdigrab; the wgc path is Start-WgcRecord). Per run: ffmpeg gdigrab of the whole virtual screen at 60 fps, ffv1 (lossless), started after the
# initial settle and before the first input step, stopped in the run's finally after the last settle. It takes no focus, injects no input and opens no console window.
# The sidecar record-NN.json holds the host client rect, the virtual screen, the anchors (UTC epoch seconds and QPC) and each input step's start and end, so the frames
# align to the steps (factory/tools/flicker_scan.py). -use_wallclock_as_timestamps with -copyts keeps the frame times on the UTC epoch.
$script:rec = $null; $script:stepTimes = @(); $script:anchorEpoch = 0.0; $script:anchorQpc = [long]0
function Get-Qpc { return [System.Diagnostics.Stopwatch]::GetTimestamp() }
function Epoch-Of([long]$qpc) { return $script:anchorEpoch + ([double]($qpc - $script:anchorQpc) / [double][System.Diagnostics.Stopwatch]::Frequency) }
function Start-WgcRecord([string]$dir, [string]$name, [IntPtr]$h) {
    $exe = [string]$env:SWIFTRIGHT_WGC_RECORDER
    if (-not $exe -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "screen record wgc requested but SWIFTRIGHT_WGC_RECORDER is not a file: '$exe'" }
    $frameDir = Join-Path $dir ($name + '-wgc')
    New-Item -ItemType Directory -Force -Path $frameDir | Out-Null
    $stopFile = Join-Path $dir ($name + '-wgc.stop')
    Remove-Item -LiteralPath $stopFile -Force -ErrorAction SilentlyContinue
    $wArgs = '--hwnd ' + [int64]$h + ' --out "' + $frameDir + '" --seconds 900 --stop-file "' + $stopFile + '"'
    $si = [Diagnostics.ProcessStartInfo]::new($exe, $wArgs)
    $si.UseShellExecute = $false; $si.CreateNoWindow = $true
    $si.RedirectStandardError = $true; $si.RedirectStandardOutput = $true
    $script:anchorEpoch = ([DateTime]::UtcNow - [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)).TotalSeconds
    $script:anchorQpc = Get-Qpc
    $vs = [IxNative]::Virt(); $cs = [IxNative]::ClientScreen($h)
    $p = [Diagnostics.Process]::Start($si)
    $errTask = $p.StandardError.ReadToEndAsync(); $outTask = $p.StandardOutput.ReadToEndAsync()
    $ready = Join-Path $frameDir 'ready.txt'
    $limit = [DateTime]::UtcNow.AddSeconds(10)
    while (-not (Test-Path -LiteralPath $ready)) {
        if ($p.HasExited) { [void]$errTask.Wait(2000); throw "FactoryWGCRecord exited at start code=$($p.ExitCode) stdout=$($outTask.Result) stderr=$($errTask.Result)" }
        if ([DateTime]::UtcNow -gt $limit) { try { $p.Kill() } catch { }; throw 'FactoryWGCRecord did not become ready within 10 s' }
        Start-Sleep -Milliseconds 50
    }
    $script:rec = [ordered]@{ recorder = 'wgc'; proc = $p; errTask = $errTask; outTask = $outTask; file = $frameDir; frameDir = $frameDir; stopFile = $stopFile; name = $name; ffmpeg = $exe; version = ''; args = $wArgs; virt = $vs; client = $cs; hwnd = [int64]$h }
    $script:stepTimes = @()
}
function Start-ScreenRecord([string]$dir, [string]$name, [IntPtr]$h) {
    if ($script:recMode -eq 'wgc') { Start-WgcRecord $dir $name $h; return }
    $ff = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ff) { throw 'screen record requested (SWIFTRIGHT_SCREEN_RECORD=gdigrab) but ffmpeg is not on PATH' }
    $ver = [string](& $ff.Source -hide_banner -version 2>&1 | Select-Object -First 1)
    $file = Join-Path $dir ($name + '.mkv')
    $ffArgs = '-hide_banner -loglevel warning -nostats -use_wallclock_as_timestamps 1 -f gdigrab -framerate 60 -draw_mouse 0 -i desktop -copyts -fps_mode passthrough -c:v ffv1 -level 3 -g 1 -y "' + $file + '"'
    $si = [Diagnostics.ProcessStartInfo]::new($ff.Source, $ffArgs)
    $si.UseShellExecute = $false; $si.CreateNoWindow = $true
    $si.RedirectStandardInput = $true; $si.RedirectStandardError = $true; $si.RedirectStandardOutput = $true
    $script:anchorEpoch = ([DateTime]::UtcNow - [DateTime]::new(1970, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)).TotalSeconds
    $script:anchorQpc = Get-Qpc
    $vs = [IxNative]::Virt(); $cs = [IxNative]::ClientScreen($h)
    $p = [Diagnostics.Process]::Start($si)
    $errTask = $p.StandardError.ReadToEndAsync(); $outTask = $p.StandardOutput.ReadToEndAsync()
    Start-Sleep -Milliseconds 300
    if ($p.HasExited) { throw "ffmpeg exited at start code=$($p.ExitCode)" }
    $script:rec = [ordered]@{ recorder = 'gdigrab'; proc = $p; errTask = $errTask; outTask = $outTask; file = $file; name = $name; ffmpeg = $ff.Source; version = $ver; args = $ffArgs; virt = $vs; client = $cs; hwnd = [int64]$h }
    $script:stepTimes = @()
}
function Stop-WgcRecord([string]$jsonPath) {
    $r = $script:rec; $p = $r.proc
    $stopQpc = Get-Qpc; $stopEpoch = Epoch-Of $stopQpc
    try { [IO.File]::WriteAllText($r.stopFile, 'stop') } catch { }
    $exited = [bool]$p.WaitForExit(30000)
    if (-not $exited) { try { $p.Kill() } catch { }; [void]$p.WaitForExit(10000) }
    $out = ''; $err = ''
    try { [void]$r.outTask.Wait(5000); $out = [string]$r.outTask.Result } catch { }
    try { [void]$r.errTask.Wait(5000); $err = [string]$r.errTask.Result } catch { }
    if ($err.Length -gt 2000) { $err = $err.Substring($err.Length - 2000) }
    $summary = $null
    try { $summary = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $r.frameDir 'summary.json'))) } catch { }
    $side = [ordered]@{
        schema = 'screen-record/v1'; recorder = 'wgc'; run = $r.name; record = [IO.Path]::GetFileName($r.frameDir); frameDir = [IO.Path]::GetFileName($r.frameDir)
        source = 'Windows.Graphics.Capture of the host HWND (every FrameArrived; frames only on content change)'; codec = 'png'
        recorderExe = $r.ffmpeg; recorderArgs = $r.args; recorderExited = $exited; recorderExitCode = $(if ($exited) { $p.ExitCode } else { $null }); recorderStdout = $out; recorderStderr = $err
        wgcSummary = $summary
        hostHwnd = $r.hwnd; hostClient = $r.client; virtualScreen = $r.virt
        anchorEpoch = $script:anchorEpoch; anchorQpc = $script:anchorQpc; qpcFrequency = [System.Diagnostics.Stopwatch]::Frequency
        stopEpoch = $stopEpoch; stopQpc = $stopQpc; steps = @($script:stepTimes)
    }
    [IO.File]::WriteAllText($jsonPath, (ConvertTo-Json -InputObject $side -Depth 8), (New-Object Text.UTF8Encoding($false)))
    try { Remove-Item -LiteralPath $r.stopFile -Force -ErrorAction SilentlyContinue } catch { }
    try { $p.Dispose() } catch { }
    $script:rec = $null
}
function Stop-ScreenRecord([string]$jsonPath) {
    if ($script:rec.recorder -eq 'wgc') { Stop-WgcRecord $jsonPath; return }
    $r = $script:rec; $p = $r.proc
    $stopQpc = Get-Qpc; $stopEpoch = Epoch-Of $stopQpc
    try { $p.StandardInput.WriteLine('q'); $p.StandardInput.Flush() } catch { }
    $exited = [bool]$p.WaitForExit(30000)
    if (-not $exited) { try { $p.Kill() } catch { }; [void]$p.WaitForExit(10000) }
    $err = ''; try { [void]$r.errTask.Wait(5000); $err = [string]$r.errTask.Result } catch { }
    if ($err.Length -gt 2000) { $err = $err.Substring($err.Length - 2000) }
    $side = [ordered]@{
        schema = 'screen-record/v1'; recorder = 'gdigrab'; run = $r.name; record = [IO.Path]::GetFileName($r.file); source = 'gdigrab desktop (whole virtual screen)'; codec = 'ffv1'; framerate = 60
        ffmpeg = $r.ffmpeg; ffmpegVersion = $r.version; ffmpegArgs = $r.args; ffmpegExited = $exited; ffmpegExitCode = $(if ($exited) { $p.ExitCode } else { $null }); ffmpegStderr = $err
        hostHwnd = $r.hwnd; hostClient = $r.client; virtualScreen = $r.virt
        anchorEpoch = $script:anchorEpoch; anchorQpc = $script:anchorQpc; qpcFrequency = [System.Diagnostics.Stopwatch]::Frequency
        stopEpoch = $stopEpoch; stopQpc = $stopQpc; steps = @($script:stepTimes)
    }
    [IO.File]::WriteAllText($jsonPath, (ConvertTo-Json -InputObject $side -Depth 6), (New-Object Text.UTF8Encoding($false)))
    try { $p.Dispose() } catch { }
    $script:rec = $null
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
            # CI only (GITHUB_ACTIONS is set on runner steps, not in the Sandbox guest): HWND_TOPMOST with NOACTIVATE, so no other window sits above the host while the
            # cursor moves (CI 38912970380: no WM_MOUSEMOVE reached the host). The Dell path keeps the bottom placement above.
            $ciRun = ([string]$env:GITHUB_ACTIONS -eq 'true')
            if ($ciRun -and -not [IxNative]::SetWindowPos($h, [IntPtr]::new(-1), 0, 0, 0, 0, 0x0013)) { throw 'SetWindowPos HWND_TOPMOST failed' }
            Add-Content -LiteralPath (Join-Path $out "cursor-$n.txt") -Value ("start ci=$ciRun host=$($h.ToInt64()) " + [IxNative]::ZInfo($h, [IxNative]::ClientScreen($h)))
            Start-Sleep -Milliseconds $settle
            if ($script:screenRecord) { Start-ScreenRecord $out "record-$n" $h }
            $k = 0
            foreach ($s in $steps) {
                $k++
                $r = 'ok'; $t0 = Window-Ms
                $q0 = $(if ($script:rec) { Get-Qpc } else { [long]0 })
                try { $r = Do-Step $p $h $s $out $n } catch { $r = 'ERROR: ' + $_.Exception.Message }
                $log += [ordered]@{ step = $k; op = [string]$s.op; result = $r; window_ms_start = $t0; window_ms_end = (Window-Ms) }
                if ($script:rec) { $q1 = Get-Qpc; $script:stepTimes += [ordered]@{ step = $k; op = [string]$s.op; result = $r; qpc0 = $q0; qpc1 = $q1; epoch0 = (Epoch-Of $q0); epoch1 = (Epoch-Of $q1) } }
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
            if ($script:rec) { try { Stop-ScreenRecord (Join-Path $out "record-$n.json") } catch { $status = "$status | screen record stop: " + $_.Exception.Message } }
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
