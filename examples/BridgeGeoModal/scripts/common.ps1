# Shared helpers of the BridgeGeoModal drivers (dot-sourced by drive-textgeom.ps1, drive-modal.ps1, dryrun.ps1).
# Input policy (SR0 rule): NEVER a global keystroke or mouse event. The drivers only use UI Automation and
# PostMessage to windows owned by the host process under test (its main window, its popup menu, its task dialog).
$ErrorActionPreference = 'Continue'
$script:SwiftRuntime = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin'
$script:PinnedRendererSha = '7533963d124c066159322edf540bd45637cc294173fd9db2af95d4d4a3f149fc'

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, Accessibility
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class GMWin {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern uint MapVirtualKeyW(uint code, uint type);
  [DllImport("oleacc.dll")] public static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint objectId, ref Guid riid, out IntPtr ppv);
  public static string ClassOf(IntPtr h) { var sb = new StringBuilder(256); GetClassNameW(h, sb, 256); return sb.ToString(); }
  public static string TitleOf(IntPtr h) { var sb = new StringBuilder(512); GetWindowTextW(h, sb, 512); return sb.ToString(); }
  public static IntPtr[] TopLevel(uint pid) {
    var list = new List<IntPtr>();
    EnumWindows(delegate(IntPtr h, IntPtr l) { uint p; GetWindowThreadProcessId(h, out p); if (p == pid) list.Add(h); return true; }, IntPtr.Zero);
    return list.ToArray();
  }
}
'@

# per-monitor v2: UIA and ClientToScreen then report physical pixels, like the host's commit coordinates
$null = [GMWin]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))

function Get-Sha([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower() }

# Reads a file another process is appending to (the host flushes every line).
function Read-Shared([string]$Path) {
  try {
    $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
    $t = $sr.ReadToEnd(); $sr.Close(); $fs.Close(); return $t
  } catch { return '' }
}

# Polls the host log until a line matches the regex (multiline) or the time is up; returns the whole log either way.
function Wait-Log([string]$Path, [string]$Pattern, [double]$Seconds) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    $t = Read-Shared $Path
    if ($t -match "(?m)$Pattern") { return $t }
    Start-Sleep -Milliseconds 40
  }
  return (Read-Shared $Path)
}

function Unesc([string]$s) {
  return [regex]::Replace($s, '\\(.)', { param($m) if ($m.Groups[1].Value -eq 'n') { "`n" } else { $m.Groups[1].Value } })
}

# Starts a host exe with the environment overrides; stdout/stderr are collected asynchronously.
function Start-Host([string]$Exe, [string]$Bin, [hashtable]$EnvVars) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.WorkingDirectory = $Bin
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables['Path'] = "$($script:SwiftRuntime);$Bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
  foreach ($k in $EnvVars.Keys) { $psi.EnvironmentVariables[$k] = [string]$EnvVars[$k] }
  $p = [System.Diagnostics.Process]::Start($psi)
  return [pscustomobject]@{ Proc = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync() }
}

function Wait-MainWindow($Proc, [double]$Seconds) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    $Proc.Refresh()
    if ($Proc.HasExited) { return [IntPtr]::Zero }
    $h = $Proc.MainWindowHandle
    if ($h -ne [IntPtr]::Zero) { return $h }
    Start-Sleep -Milliseconds 100
  }
  return [IntPtr]::Zero
}

function Write-Result([string]$Path, [string[]]$Lines) {
  [System.IO.File]::WriteAllText($Path, ([string]::Join("`r`n", $Lines) + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
}

function Get-Artifacts([string]$Bin, [string[]]$Exes) {
  $parts = @()
  foreach ($e in $Exes) { $parts += ("{0}={1}" -f $e, (Get-Sha (Join-Path $Bin $e))) }
  $parts += ("renderer={0}" -f (Get-Sha (Join-Path $Bin 'swiftright_render.dll')))
  return 'ARTIFACTS ' + ($parts -join ' ')
}

function Test-ParseFile([string]$Path) {
  $errs = $null; $tokens = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errs)
  return ,@($errs)
}

# MSAA (IAccessible) children of a window's client object. UI Automation shows the classic #32768 popup menu as one empty Pane
# (probe-menu-uia.ps1, 10 Oct), but its items are reachable through MSAA: name, state (UNAVAILABLE = disabled, CHECKED) and
# accDoDefaultAction. Returns the IAccessible and the items.
function Get-MsaaItems([IntPtr]$Hwnd) {
  $items = @()
  $acc = $null
  $dbg = ''
  try {
    $g = [Guid]'618736E0-3C3D-11CF-810C-00AA00389B71'
    $ptr = [IntPtr]::Zero
    $hr = [GMWin]::AccessibleObjectFromWindow($Hwnd, [uint32]4294967292, [ref]$g, [ref]$ptr)     # OBJID_CLIENT = -4
    $dbg = "hr=0x{0:X} ptr={1}" -f $hr, $ptr.ToInt64()
    if ($hr -eq 0 -and $ptr -ne [IntPtr]::Zero) {
      $o = [System.Runtime.InteropServices.Marshal]::GetObjectForIUnknown($ptr)
      $acc = $o      # late-bound IDispatch (a cast to Accessibility.IAccessible fails in Windows PowerShell)
      $n = [int]$acc.accChildCount
      $dbg += " children=$n"
      for ($i = 1; $i -le $n; $i++) {
        $name = $acc.accName($i); $state = [int]$acc.accState($i); $role = [int]$acc.accRole($i)
        $items += [pscustomobject]@{ Index = $i; Name = [string]$name; State = $state; Role = $role; Enabled = (($state -band 0x1) -eq 0); Checked = (($state -band 0x10) -ne 0) }
      }
    }
  } catch { $dbg += " ERR $($_.Exception.Message)" }
  return [pscustomobject]@{ Acc = $acc; Items = $items; Debug = $dbg }
}

# ---------------------------------------------------------------- foreground watch (Modal06 driver, tuple 08)
# The Dell is a laptop a person is using. TrackPopupMenu dismisses a menu when its owner loses activation, so a run that fails while another
# process held the foreground is a harness casualty, not a product failure. FgWatch polls GetForegroundWindow every 10 ms on its own thread and
# records each change (owner process, class, title); the driver also takes a direct sample at menu request, menu shown, dismissal and result.
# Nothing here opens a window or sends input.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class FgWatch {
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint ms);
  [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint ms);
  public sealed class Rec {
    public long TMs; public string Wall; public long Hwnd; public uint Pid; public string Owner; public string Class; public string Title;
    public bool IsHost; public bool HostWinAlive;
  }
  static readonly object L = new object();
  static readonly Stopwatch Clock = Stopwatch.StartNew();
  static readonly Dictionary<uint, string> Names = new Dictionary<uint, string>();
  static List<Rec> events = new List<Rec>();
  static Thread th;
  static volatile bool run;
  static bool periodSet;
  static uint hostPid;
  static long hostWin;
  static long lastHwnd = long.MinValue;
  public const int PollMs = 10;
  public static long Polls;
  public static long MaxGapMs;
  public static long NowMs() { return Clock.ElapsedMilliseconds; }
  static string NameOf(uint pid) {
    if (pid == 0) return "none";
    lock (Names) { string n; if (Names.TryGetValue(pid, out n)) return n; }
    string name = "pid" + pid;
    try { using (Process p = Process.GetProcessById((int)pid)) { name = p.ProcessName; } } catch (Exception) { }
    lock (Names) { Names[pid] = name; }
    return name;
  }
  static Rec Build(IntPtr h, long t) {
    Rec r = new Rec();
    r.TMs = t; r.Wall = DateTime.Now.ToString("HH:mm:ss.fff"); r.Hwnd = h.ToInt64();
    uint pid = 0; if (h != IntPtr.Zero) GetWindowThreadProcessId(h, out pid);
    r.Pid = pid; r.Owner = NameOf(pid); r.IsHost = (pid != 0 && pid == hostPid);
    long hw = hostWin; r.HostWinAlive = (hw != 0 && IsWindow(new IntPtr(hw)));
    StringBuilder cb = new StringBuilder(256); if (h != IntPtr.Zero) GetClassNameW(h, cb, 256); r.Class = cb.ToString();
    r.Title = "";
    // the title of a window of ANOTHER process is read without a message to it; a host window is never asked (it could be busy in its modal loop)
    if (h != IntPtr.Zero && !r.IsHost) { StringBuilder tb = new StringBuilder(512); GetWindowTextW(h, tb, 512); r.Title = tb.ToString(); }
    return r;
  }
  public static Rec Sample() { return Build(GetForegroundWindow(), Clock.ElapsedMilliseconds); }
  public static void SetHostWindow(long hwnd) { hostWin = hwnd; }
  public static void Start(uint host) {
    Stop();
    lock (L) { events = new List<Rec>(); }
    lock (Names) { Names.Clear(); }
    hostPid = host; hostWin = 0; lastHwnd = long.MinValue; Polls = 0; MaxGapMs = 0;
    run = true;
    timeBeginPeriod(1); periodSet = true;
    th = new Thread(Loop); th.IsBackground = true; th.Priority = ThreadPriority.AboveNormal; th.Start();
  }
  static void Loop() {
    long prev = Clock.ElapsedMilliseconds;
    while (run) {
      long t = Clock.ElapsedMilliseconds;
      long gap = t - prev; if (gap > MaxGapMs) MaxGapMs = gap; prev = t;
      IntPtr h = GetForegroundWindow();
      long hv = h.ToInt64();
      if (hv != lastHwnd) { Rec r = Build(h, t); lock (L) { events.Add(r); } lastHwnd = hv; }
      Polls++;
      Thread.Sleep(PollMs);
    }
  }
  public static void Stop() {
    run = false;
    if (th != null) { th.Join(1000); th = null; }
    if (periodSet) { timeEndPeriod(1); periodSet = false; }
  }
  public static Rec[] All() { lock (L) { return events.ToArray(); } }
  public static Rec[] Between(long t0, long t1) {
    List<Rec> o = new List<Rec>();
    lock (L) { foreach (Rec r in events) { if (r.TMs >= t0 && r.TMs <= t1) o.Add(r); } }
    return o.ToArray();
  }
}
'@

# One log line per observation. phase: start | request | shown | not_shown | dismiss | result | change. tag '-' = outside any modal.
function ConvertTo-FgField($s, [int]$Max) {
  $t = ([string]$s) -replace '[\x00-\x1F\x7F]', ' '
  if ($t.Length -gt $Max) { $t = $t.Substring(0, $Max) + '...' }
  return $t
}
function Format-FgRec($Rec, [int]$Id, [string]$Tag, [string]$Phase) {
  return ('FG t_ms={0} wall={1} id={2} tag={3} phase={4} hwnd={5} pid={6} host={7} hostwin={8} class=[{9}] owner=[{10}] title=[{11}]' -f `
    $Rec.TMs, $Rec.Wall, $Id, $Tag, $Phase, $Rec.Hwnd, $Rec.Pid, ([string]$Rec.IsHost).ToLower(), ([string]$Rec.HostWinAlive).ToLower(),
    (ConvertTo-FgField $Rec.Class 40), (ConvertTo-FgField $Rec.Owner 40), (ConvertTo-FgField $Rec.Title 80))
}
$script:FgLineRe = '(?m)^FG t_ms=(\d+) wall=(\S+) id=(\d+) tag=(\S+) phase=(\S+) hwnd=(\d+) pid=(\d+) host=(true|false) hostwin=(true|false) class=\[(.*?)\] owner=\[(.*?)\] title=\[(.*)\]\r?$'
function Read-FgLog([string]$Text) {
  $out = @()
  foreach ($m in [regex]::Matches($Text, $script:FgLineRe)) {
    $g = $m.Groups
    $out += [pscustomobject]@{ TMs = [int64]$g[1].Value; Wall = $g[2].Value; Id = [int]$g[3].Value; Tag = $g[4].Value; Phase = $g[5].Value; Hwnd = [int64]$g[6].Value
      Pid = [int64]$g[7].Value; IsHost = ($g[8].Value -eq 'true'); HostWin = ($g[9].Value -eq 'true'); Class = $g[10].Value; Owner = $g[11].Value; Title = $g[12].Value }
  }
  return $out
}

# Another process held the foreground during a modal: not the host, not "no foreground window" (pid 0), the host window still exists (a
# foreground change caused by the host closing its own window, scenario S6, is not a loss), and the record belongs to a modal (tag not '-').
function Test-FgForeign($r) { return ((-not $r.IsHost) -and ($r.Pid -ne 0) -and $r.HostWin -and ($r.Tag -ne '-')) }

# Which scenario a failed check belongs to. Kind: scenario (Tags) | run (a consequence of an early dismissal that has no scenario in its text) | real
# (never excused by foreground loss: stalls, ticks_during=0, idle latency, startup, teardown, exceptions, and anything not listed).
function Get-CheckScope([string]$Name, [string]$Detail) {
  $m = [regex]::Match($Name, '^(?:host: )?(S\d)\b')
  if ($m.Success) { return [pscustomobject]@{ Kind = 'scenario'; Tags = @($m.Groups[1].Value) } }
  if ($Name -like 'host: main loop keeps pumping*') {
    # per-scenario run counts in the detail ("S1=265 S2=0 ... (need >= 50 each)"): the scenarios under the bound are the ones that failed
    $need = 50
    $nm = [regex]::Match($Detail, 'need >= (\d+) each'); if ($nm.Success) { $need = [int]$nm.Groups[1].Value }
    $tags = @()
    foreach ($x in [regex]::Matches($Detail, '\b(S\d)=(\d+)')) { if ([int]$x.Groups[2].Value -lt $need) { $tags += $x.Groups[1].Value } }
    if ($tags.Count -gt 0) { return [pscustomobject]@{ Kind = 'scenario'; Tags = $tags } }
    return [pscustomobject]@{ Kind = 'real'; Tags = @() }
  }
  foreach ($p in 'host exited by itself*', 'all 6 scenarios were requested*', 'host: sequence ran without timeout*', 'renderer logged one modal line per modal*', 'host: one-off cost of opening a modal*', 'host: job latency during an open modal*') {
    if ($Name -like $p) { return [pscustomobject]@{ Kind = 'run'; Tags = @() } }
  }
  return [pscustomobject]@{ Kind = 'real'; Tags = @() }
}

# The rule (as run-matrix.sh applies it to foreground_failed): a failed attempt is `foreground_lost` only when EVERY failed check is explained:
#   - each scenario-tagged failure sits in a modal during which another process held the foreground, and
#   - the remaining failures are run-wide consequences of an early dismissal (host exit code, one-off bound, ...) and there is at least one scenario failure.
# Anything else (a failure in a modal with no foreground loss, a stall, an exception, a run-wide failure alone) is a real failure: no retry.
function Get-FailureClass($Failed, [string]$FgText) {
  $failed = @($Failed)
  if ($failed.Count -eq 0) { return [pscustomobject]@{ Class = 'pass'; Owner = ''; Title = ''; Tags = @(); Phase = ''; Wall = ''; Explained = @(); Consequences = @(); Unexplained = @() } }
  $recs = @(Read-FgLog $FgText)
  $foreign = @{}
  foreach ($r in $recs) { if (Test-FgForeign $r) { if (-not $foreign.ContainsKey($r.Tag)) { $foreign[$r.Tag] = @() }; $foreign[$r.Tag] += $r } }
  $explained = @(); $conseq = @(); $unexpl = @(); $lostTags = @()
  foreach ($f in $failed) {
    $sc = Get-CheckScope ([string]$f.name) ([string]$f.detail)
    if ($sc.Kind -eq 'scenario') {
      $ok = $true
      foreach ($t in $sc.Tags) { if ($foreign.ContainsKey($t)) { $lostTags += $t } else { $ok = $false } }
      if ($ok) { $explained += [string]$f.name } else { $unexpl += [string]$f.name }
    } elseif ($sc.Kind -eq 'run') { $conseq += [string]$f.name } else { $unexpl += [string]$f.name }
  }
  $lost = ($unexpl.Count -eq 0) -and ($explained.Count -gt 0)
  $first = $null
  foreach ($t in @($lostTags | Sort-Object -Unique)) { foreach ($r in $foreign[$t]) { if ($first -eq $null -or $r.TMs -lt $first.TMs) { $first = $r } } }
  # a run-wide failure with no scenario failure beside it has no foreground explanation: list it as unexplained
  if (-not $lost -and $explained.Count -eq 0) { $unexpl = @($unexpl) + @($conseq) }
  $o = [pscustomobject]@{ Class = 'real_failure'; Owner = ''; Title = ''; Tags = @(); Phase = ''; Wall = ''; Explained = $explained; Consequences = $conseq; Unexplained = $unexpl }
  if ($lost) {
    $o.Class = 'foreground_lost'; $o.Tags = @($lostTags | Sort-Object -Unique)
    if ($first) { $o.Owner = $first.Owner; $o.Title = $first.Title; $o.Phase = $first.Phase; $o.Wall = $first.Wall }
  }
  return $o
}

# One line per scenario: the foreground owner at request / shown / dismiss / result, the number of change records, and the first foreign owners.
function Get-FgScenarioLines([string]$FgText) {
  $recs = @(Read-FgLog $FgText | Where-Object { $_.Tag -ne '-' })
  $lines = @()
  foreach ($tag in @($recs | ForEach-Object { $_.Tag } | Sort-Object -Unique)) {
    $r = @($recs | Where-Object { $_.Tag -eq $tag })
    $ph = { param($p) $x = @($r | Where-Object { $_.Phase -eq $p } | Select-Object -First 1); if ($x.Count -eq 0) { '-' } else { $x[0].Owner } }
    $changes = @($r | Where-Object { $_.Phase -eq 'change' }).Count
    $fo = @($r | Where-Object { Test-FgForeign $_ })
    $s = "  fg $tag request=$(& $ph 'request') shown=$(& $ph 'shown') dismiss=$(& $ph 'dismiss') result=$(& $ph 'result') changes=$changes"
    if ($fo.Count -gt 0) {
      $seen = @(); foreach ($x in $fo) { $k = "$($x.Owner) [$($x.Title)] ($($x.Phase) $($x.Wall))"; if ($seen -notcontains $k) { $seen += $k } }
      $s += " FOREIGN=" + (($seen | Select-Object -First 3) -join '; ')
    }
    $lines += $s
  }
  return $lines
}

# Renderer AX counters of one run (stderr): the shutdown memory line and the re-throttle retry lines.
function Get-AxTally([string]$ErrText) {
  $m = @([regex]::Matches($ErrText, 'ax_publishes=(\d+) ax_throttled=(\d+) ax_rethrottled=(\d+)'))
  $retry = @([regex]::Matches($ErrText, '(?m)^\[swiftright-render\] ax trailing re-throttled ')).Count
  if ($m.Count -eq 0) { return [pscustomobject]@{ Seen = $false; Publishes = 0; Throttled = 0; Rethrottled = 0; RetryLines = $retry } }
  $l = $m[$m.Count - 1]
  return [pscustomobject]@{ Seen = $true; Publishes = [int]$l.Groups[1].Value; Throttled = [int]$l.Groups[2].Value; Rethrottled = [int]$l.Groups[3].Value; RetryLines = $retry }
}
