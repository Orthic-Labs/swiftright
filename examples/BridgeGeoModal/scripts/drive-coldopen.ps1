# SR0 T10 driver: controlled cold and warm modal opens, one fresh ColdOpen06.exe process per run. Run it INSIDE an interactive desktop
# session (one-shot scheduled task, see schedule-coldopen.ps1). Window-targeted input only (PostMessage to the host's own menu or dialog);
# no global input. Window titles are never recorded, only process names.
#
# Two measures, defined in Sources/ColdOpen06/main.swift:
#   M1 main-queue blocking during open  (host: max job delay in [req, req+150 ms), and the longest gap between job runs)
#   M2 request -> dialog visible        (driver: first window-visible stamp from SetWinEventHook, and first UIA WindowOpened/MenuOpened
#                                        stamp, minus the host's req_ns; all on the QueryPerformanceCounter clock)
# Conditions (each run is a fresh process):
#   cold   OPENS=1, the first modal of the process     (-Cold runs per kind; no UIA subscription, so M1 is not perturbed by an AT client)
#   warm   OPENS=2, read at open 2 (same kind opened and dismissed once before) (-Warm runs per kind)
#   coldat OPENS=1 with a UIA event subscription (WindowOpened, MenuOpened on the desktop's top-level windows) so M2 can be stamped at the
#          UIA event; it also shows what an accessibility client does to M1 (-ColdAt runs per kind)
param(
  [string]$Base = 'D:\Claude\sr0-r08\geomodal',
  [string]$Bin = '',
  [string]$OutDir = '',
  [string]$Result = '',
  [int]$Cold = 20,
  [int]$Warm = 20,
  [int]$ColdAt = 10,
  [int]$HoldMs = 400,
  [int]$MaxRetries = 2,
  [string[]]$Only = @(),          # run only these conditions, e.g. coldat-dialog (default: all six cond-kind sets)
  [string[]]$ReportFrom = @(),    # no runs: rebuild the report from the record.json files under these directories (first valid attempt per cond/kind/index)
  [switch]$DryRun
)
. (Join-Path $PSScriptRoot 'common.ps1')
# powershell -File passes a string[] as one comma-joined string
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ }); $ReportFrom = @($ReportFrom | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
if (-not $Bin) { $Bin = Join-Path $Base 'bin' }
if (-not $OutDir) { $OutDir = Join-Path $Base 'out\coldopen08' }
if (-not $Result) { $Result = Join-Path $Base 'result-coldopen08.txt' }
$ExeName = 'ColdOpen06.exe'
$WM_KEYDOWN = 0x0100; $WM_KEYUP = 0x0101; $TDM_CLICK_BUTTON = 0x0466; $VK_ESCAPE = 0x1B

Add-Type -ReferencedAssemblies 'UIAutomationClient', 'UIAutomationTypes', 'WindowsBase' -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Automation;
public static class ColdListen {
  public sealed class Ev { public string Src; public long Ns; public long Hwnd; public string Cls; public int Pid; }
  delegate void WinEventProc(IntPtr hook, uint ev, IntPtr hwnd, int idObj, int idChild, uint thread, uint time);
  [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam; public IntPtr lParam; public uint time; public int x; public int y; }
  [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr mod, WinEventProc proc, uint pid, uint tid, uint flags);
  [DllImport("user32.dll")] static extern bool UnhookWinEvent(IntPtr h);
  [DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr h, uint a, uint b);
  [DllImport("user32.dll")] static extern bool PostThreadMessage(uint tid, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  static readonly object L = new object();
  static List<Ev> events = new List<Ev>();
  static WinEventProc cb;
  static Thread th;
  static uint tid;
  static IntPtr hook1, hook2;
  static int hostPid;
  static AutomationEventHandler uiaHandler;
  static bool uiaOn;
  public static long Now() { return (long)((double)Stopwatch.GetTimestamp() * 1e9 / (double)Stopwatch.Frequency); }
  static string ClassOf(IntPtr h) { StringBuilder sb = new StringBuilder(256); GetClassNameW(h, sb, 256); return sb.ToString(); }
  static void Add(string src, long ns, long hwnd, string cls, int pid) { lock (L) { events.Add(new Ev { Src = src, Ns = ns, Hwnd = hwnd, Cls = cls, Pid = pid }); } }
  static void OnWin(IntPtr hook, uint ev, IntPtr hwnd, int idObj, int idChild, uint thread, uint time) {
    long ns = Now();
    try {
      if (ev == 0x8002 && (idObj != 0 || idChild != 0)) return;            // EVENT_OBJECT_SHOW of a window object only
      string cls = ClassOf(hwnd);
      if (cls != "#32768" && cls != "#32770") return;
      Add(ev == 0x0006 ? "win-menupopup" : "win-show", ns, hwnd.ToInt64(), cls, hostPid);
    } catch (Exception) { }
  }
  public static void Start(int pid, bool uia) {
    Stop();
    hostPid = pid;
    lock (L) { events = new List<Ev>(); }
    cb = new WinEventProc(OnWin);
    ManualResetEvent ready = new ManualResetEvent(false);
    th = new Thread(delegate() {
      tid = GetCurrentThreadId();
      hook1 = SetWinEventHook(0x0006, 0x0006, IntPtr.Zero, cb, (uint)pid, 0, 0);      // EVENT_SYSTEM_MENUPOPUPSTART, out of context
      hook2 = SetWinEventHook(0x8002, 0x8002, IntPtr.Zero, cb, (uint)pid, 0, 0);      // EVENT_OBJECT_SHOW
      ready.Set();
      MSG m;
      while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { }
      if (hook1 != IntPtr.Zero) UnhookWinEvent(hook1);
      if (hook2 != IntPtr.Zero) UnhookWinEvent(hook2);
    });
    th.IsBackground = true; th.Start(); ready.WaitOne(5000);
    if (uia) {
      uiaHandler = new AutomationEventHandler(delegate(object s, AutomationEventArgs e) {
        long ns = Now();
        try {
          AutomationElement el = s as AutomationElement;
          int p = el.Current.ProcessId;
          if (p != hostPid) return;
          Add(e.EventId == AutomationElement.MenuOpenedEvent ? "uia-menuopened" : "uia-windowopened", ns, el.Current.NativeWindowHandle, el.Current.ClassName, p);
        } catch (Exception) { }
      });
      Automation.AddAutomationEventHandler(WindowPattern.WindowOpenedEvent, AutomationElement.RootElement, TreeScope.Subtree, uiaHandler);   // Subtree: UIA lists an owned dialog under its owner window, not under the desktop (Children missed all 30 dialog attempts of the first pass)
      Automation.AddAutomationEventHandler(AutomationElement.MenuOpenedEvent, AutomationElement.RootElement, TreeScope.Subtree, uiaHandler);
      uiaOn = true;
    }
  }
  public static void Stop() {
    if (uiaOn) { try { Automation.RemoveAllEventHandlers(); } catch (Exception) { } uiaOn = false; }
    if (th != null) { PostThreadMessage(tid, 0x0012, IntPtr.Zero, IntPtr.Zero); th.Join(2000); th = null; }
  }
  public static Ev[] All() { lock (L) { return events.ToArray(); } }
}
'@

function Make-KeyLParam([int]$vk, [bool]$up) {
  $scan = [int64][GMWin]::MapVirtualKeyW([uint32]$vk, 0)
  $v = [int64]1 -bor ($scan -shl 16)
  if ($up) { $v = $v -bor [int64]0xC0000000L }
  return $v
}
function Send-Key([IntPtr]$h, [int]$vk) {
  [void][GMWin]::PostMessageW($h, $script:WM_KEYDOWN, [IntPtr]$vk, [IntPtr](Make-KeyLParam $vk $false))
  Start-Sleep -Milliseconds 40
  [void][GMWin]::PostMessageW($h, $script:WM_KEYUP, [IntPtr]$vk, [IntPtr](Make-KeyLParam $vk $true))
}
function Find-Modal([uint32]$ProcId, [IntPtr]$Main, [string]$Kind) {
  foreach ($h in [GMWin]::TopLevel($ProcId)) {
    if (-not [GMWin]::IsWindowVisible($h)) { continue }
    $cls = [GMWin]::ClassOf($h)
    if ($Kind -eq 'menu' -and $cls -eq '#32768') { return $h }
    if ($Kind -eq 'dialog' -and $cls -eq '#32770' -and ([GMWin]::GetWindow($h, 4) -eq $Main)) { return $h }
  }
  return [IntPtr]::Zero
}

function Get-Stat([double[]]$Xs) {
  $a = @($Xs | Sort-Object)
  if ($a.Count -eq 0) { return $null }
  $pick = { param($p) $i = [Math]::Min($a.Count - 1, [Math]::Max(0, [int][Math]::Ceiling($p * $a.Count) - 1)); $a[$i] }
  $mean = ($a | Measure-Object -Average).Average
  return [pscustomobject]@{ N = $a.Count; Min = $a[0]; Median = (& $pick 0.5); P90 = (& $pick 0.9); Max = $a[$a.Count - 1]; Mean = $mean }
}
function Fmt-Stat([string]$Name, [double[]]$Xs) {
  $s = Get-Stat $Xs
  if ($s -eq $null) { return ("{0,-34} n=0" -f $Name) }
  return ("{0,-34} n={1,-3} min={2,7:N2} median={3,7:N2} p90={4,7:N2} max={5,7:N2} mean={6,7:N2}" -f $Name, $s.N, $s.Min, $s.Median, $s.P90, $s.Max, $s.Mean)
}

# One fresh process. Returns a record with the measured open (the last open of the process) or Valid=$false and a reason.
function Invoke-OpenRun([string]$Cond, [string]$Kind, [int]$Index, [int]$Attempt) {
  $opens = if ($Cond -eq 'warm') { 2 } else { 1 }
  $uia = ($Cond -eq 'coldat')
  $runDir = Join-Path $OutDir ('{0}-{1}-{2:D2}a{3}' -f $Cond, $Kind, $Index, $Attempt)
  New-Item -ItemType Directory -Force $runDir | Out-Null
  $logPath = Join-Path $runDir 'host.log'
  $rec = [ordered]@{ cond = $Cond; kind = $Kind; index = $Index; attempt = $Attempt; valid = $false; reason = ''; fg_owner_request = ''; dismissed_by_driver = $true }
  $hp = $null
  try {
    $hp = Start-Host (Join-Path $Bin $ExeName) $Bin @{ SWR_CO_LOG = $logPath; SWR_CO_KIND = $Kind; SWR_CO_OPENS = $opens; SWR_CO_LEAD_S = '1.5'; SWR_CO_TIMEOUT = '40' }
    $proc = $hp.Proc
    $main = Wait-MainWindow $proc 30
    if ($main -eq [IntPtr]::Zero) { throw 'no main window' }
    [ColdListen]::Start([int]$proc.Id, $uia)
    $handled = @{}
    $deadline = (Get-Date).AddSeconds(60)
    $dismissAt = @{}
    while (-not $proc.HasExited -and (Get-Date) -lt $deadline) {
      $log = Read-Shared $logPath
      foreach ($m in [regex]::Matches($log, '(?m)^OPEN n=(\d+) kind=(\w+) id=(\d+) rc=(\S+) req_ns=(\d+) dismiss=(\S+)')) {
        $n = [int]$m.Groups[1].Value
        if ($handled.ContainsKey($n)) { continue }
        $handled[$n] = $true
        $req = [int64]$m.Groups[5].Value
        if ($m.Groups[4].Value -ne 'SWR_OK') { $rec.reason = "request rc=$($m.Groups[4].Value)"; continue }
        try { $rec.fg_owner_request = [FgWatch]::Sample().Owner } catch { }
        # wait for the modal window (the listener stamps it; Find-Modal is the fallback handle for the dismissal)
        $hm = [IntPtr]::Zero
        $limit = (Get-Date).AddSeconds(6)
        while ((Get-Date) -lt $limit -and $hm -eq [IntPtr]::Zero) { $hm = Find-Modal ([uint32]$proc.Id) $main $Kind; if ($hm -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 5 } }
        if ($hm -eq [IntPtr]::Zero) { $rec.reason = "open $n : modal window never visible"; continue }
        if ($uia) { Start-Sleep -Milliseconds 300 }
        Start-Sleep -Milliseconds $HoldMs
        $dismissAt[$n] = [ColdListen]::Now()
        if ($Kind -eq 'menu') { Send-Key $hm $VK_ESCAPE } else { [void][GMWin]::PostMessageW($hm, $script:TDM_CLICK_BUTTON, [IntPtr]101, [IntPtr]::Zero) }
      }
      if ($log -match '(?m)^HOSTSUMMARY ') { break }
      Start-Sleep -Milliseconds 20
    }
    if (-not $proc.WaitForExit(30000)) { try { $proc.Kill() } catch { }; $rec.reason = 'host did not exit'; }
    $proc.WaitForExit()
    $rec.exit = $proc.ExitCode
    $done = Read-Shared $logPath
    $evs = @([ColdListen]::All())
    [ColdListen]::Stop()
    $hm1 = @([regex]::Matches($done, '(?m)^M1 n=(\d+) kind=\w+ jobs=(\d+) blocking_max_ms=(-?[\d.]+) run_gap_ms=([\d.]+)'))
    $reqs = @{}; foreach ($m in [regex]::Matches($done, '(?m)^OPEN n=(\d+) .*? req_ns=(\d+)')) { $reqs[[int]$m.Groups[1].Value] = [int64]$m.Groups[2].Value }
    $ress = @{}; foreach ($m in [regex]::Matches($done, '(?m)^RESULT n=(\d+) action=(\d+) i0=(-?\d+) i1=(-?\d+) failed=(\w+) res_ns=(\d+)')) { $ress[[int]$m.Groups[1].Value] = [pscustomobject]@{ I1 = [int]$m.Groups[4].Value; Failed = $m.Groups[5].Value; ResNs = [int64]$m.Groups[6].Value } }
    $idle = [regex]::Match($done, '(?m)^IDLE n=(\d+) p99=(-?[\d.]+) max=(-?[\d.]+)'); if ($idle.Success) { $rec.idle_p99 = [double]$idle.Groups[2].Value; $rec.idle_max = [double]$idle.Groups[3].Value }
    $rec.host_pass = ($done -match '(?m)^HOSTSUMMARY PASS')
    $n = $opens
    if (-not $reqs.ContainsKey($n)) { throw "no OPEN n=$n in the host log" }
    $req = $reqs[$n]
    # valid only if the driver (not the foreground or a stray key) dismissed it: the result must arrive after the driver's dismissal
    if (-not $ress.ContainsKey($n)) { $rec.reason = 'no result'; }
    elseif ($ress[$n].ResNs -lt $dismissAt[$n]) { $rec.reason = 'result before the driver dismissed (spontaneous dismissal)'; $rec.dismissed_by_driver = $false }
    elseif ($ress[$n].Failed -ne 'false') { $rec.reason = 'modal failed' }
    elseif (-not $rec.host_pass) { $rec.reason = 'host summary FAIL' }
    else { $rec.valid = $true }
    $b = @($hm1 | Where-Object { [int]$_.Groups[1].Value -eq $n })
    if ($b.Count -eq 1) { $rec.m1_jobs = [int]$b[0].Groups[2].Value; $rec.m1_blocking_max_ms = [double]$b[0].Groups[3].Value; $rec.m1_run_gap_ms = [double]$b[0].Groups[4].Value }
    else { $rec.valid = $false; if (-not $rec.reason) { $rec.reason = 'no M1 line' } }
    # M2: first stamp of each source at or after this open's request (and before the next one, if any)
    $lo = $req - 2000000
    $evN = @($evs | Where-Object { $_.Ns -ge $lo })
    $win = @($evN | Where-Object { $_.Src -like 'win-*' } | Sort-Object Ns | Select-Object -First 1)
    $show = @($evN | Where-Object { $_.Src -eq 'win-show' } | Sort-Object Ns | Select-Object -First 1)
    $pop = @($evN | Where-Object { $_.Src -eq 'win-menupopup' } | Sort-Object Ns | Select-Object -First 1)
    $ua = @($evN | Where-Object { $_.Src -like 'uia-*' } | Sort-Object Ns | Select-Object -First 1)
    if ($win.Count -eq 1) { $rec.m2_win_ms = [Math]::Round(($win[0].Ns - $req) / 1e6, 2); $rec.m2_win_src = $win[0].Src }
    elseif ($rec.valid) { $rec.valid = $false; $rec.reason = 'no WinEvent stamp' }
    if ($show.Count -eq 1) { $rec.m2_show_ms = [Math]::Round(($show[0].Ns - $req) / 1e6, 2) }
    if ($pop.Count -eq 1) { $rec.m2_popup_ms = [Math]::Round(($pop[0].Ns - $req) / 1e6, 2) }
    if ($ua.Count -eq 1) { $rec.m2_uia_ms = [Math]::Round(($ua[0].Ns - $req) / 1e6, 2); $rec.m2_uia_src = $ua[0].Src }
    elseif ($uia -and $rec.valid) { $rec.valid = $false; $rec.reason = 'no UIA event stamp' }
    $rec.events = ($evN | Sort-Object Ns | ForEach-Object { '{0}@{1:N2}ms({2})' -f $_.Src, (($_.Ns - $req) / 1e6), $_.Cls }) -join ' '
  } catch {
    $rec.valid = $false; $rec.reason = $_.Exception.Message + ' @ ' + $_.InvocationInfo.ScriptLineNumber
  } finally {
    try { [ColdListen]::Stop() } catch { }
    if ($hp -ne $null) {
      $hp.Proc.Refresh()
      if (-not $hp.Proc.HasExited) { try { $hp.Proc.Kill() } catch { } }
      try { [System.IO.File]::WriteAllText((Join-Path $runDir 'stderr.log'), [string]$hp.Err.Result) } catch { }
    }
  }
  [System.IO.File]::WriteAllText((Join-Path $runDir 'record.json'), ([pscustomobject]$rec | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
  return [pscustomobject]$rec
}

function Invoke-Condition([string]$Cond, [string]$Kind, [int]$Count) {
  $good = @()
  for ($i = 1; $i -le $Count; $i++) {
    $r = $null
    for ($a = 1; $a -le (1 + $MaxRetries); $a++) {
      $r = Invoke-OpenRun $Cond $Kind $i $a
      $script:allAttempts += $r
      Write-Host ('{0} {1} {2:D2}a{3} valid={4} m1={5} m2win={6} m2uia={7} {8}' -f $Cond, $Kind, $i, $a, $r.valid, $r.m1_blocking_max_ms, $r.m2_win_ms, $r.m2_uia_ms, $r.reason)
      if ($r.valid) { break }
      Start-Sleep -Seconds 3
    }
    if ($r.valid) { $good += $r }
  }
  return $good
}

if ($DryRun) {
  $fails = @()
  $s = Get-Stat @(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
  if ($s.Median -ne 5 -or $s.P90 -ne 9 -or $s.Max -ne 10) { $fails += 'Get-Stat' }
  $t0 = [ColdListen]::Now(); Start-Sleep -Milliseconds 20; $t1 = [ColdListen]::Now()
  if ((($t1 - $t0) / 1e6) -lt 19 -or (($t1 - $t0) / 1e6) -gt 60) { $fails += 'clock' }
  $errs = Test-ParseFile $PSCommandPath; if ($errs.Count -gt 0) { $fails += 'parse' }
  "dryrun fails=$($fails.Count) $($fails -join ',')"; exit $fails.Count
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$exeSha = Get-Sha (Join-Path $Bin $ExeName)
$script:allAttempts = @()
$started = Get-Date
$sets = [ordered]@{}
if ($ReportFrom.Count -gt 0) {
  $recs = @()
  foreach ($dir in $ReportFrom) { foreach ($f in (Get-ChildItem -LiteralPath $dir -Recurse -Filter record.json | Sort-Object FullName)) { $recs += (Get-Content -Raw -LiteralPath $f.FullName | ConvertFrom-Json) } }
  $script:allAttempts = $recs
  foreach ($cond in 'cold', 'warm', 'coldat') { foreach ($kind in 'dialog', 'menu') {
    $g = @(); $idx = @($recs | Where-Object { $_.cond -eq $cond -and $_.kind -eq $kind } | ForEach-Object { [int]$_.index } | Sort-Object -Unique)
    foreach ($i in $idx) { $v = @($recs | Where-Object { $_.cond -eq $cond -and $_.kind -eq $kind -and [int]$_.index -eq $i -and $_.valid } | Select-Object -First 1); if ($v.Count -eq 1) { $g += $v[0] } }
    if ($g.Count -gt 0) { $sets["$cond-$kind"] = $g }
  } }
} else {
  $plan = @(); foreach ($kind in 'dialog', 'menu') { $plan += , @('cold', $kind, $Cold) }; foreach ($kind in 'dialog', 'menu') { $plan += , @('warm', $kind, $Warm) }; foreach ($kind in 'dialog', 'menu') { $plan += , @('coldat', $kind, $ColdAt) }
  foreach ($p in $plan) { if ($Only.Count -eq 0 -or $Only -contains ($p[0] + '-' + $p[1])) { $sets[$p[0] + '-' + $p[1]] = Invoke-Condition $p[0] $p[1] $p[2] } }
}
$ended = Get-Date

$L = New-Object System.Collections.ArrayList
function Out([string]$s) { [void]$L.Add($s) }
Out ("host=$env:COMPUTERNAME user=$env:USERNAME started=$($started.ToString('o')) ended=$($ended.ToString('o')) cold=$Cold warm=$Warm coldat=$ColdAt hold_ms=$HoldMs max_retries=$MaxRetries only=[$($Only -join ',')] report_from=[$($ReportFrom -join ',')]")
Out ("ARTIFACTS $ExeName=$exeSha renderer=$(Get-Sha (Join-Path $Bin 'swiftright_render.dll')) (Modal06.exe is not used; ColdOpen06 is a new host linking the same renderer)")
Out ('All times in ms. M1 = main-queue blocking during open (max producer-job delay in [req, req+150 ms); the Modal06 modal_open_one_off quantity). M1gap = longest pause between job runs in [req-10, req+300 ms].')
Out ('M2win = request -> first window-visible stamp (SetWinEventHook EVENT_OBJECT_SHOW / EVENT_SYSTEM_MENUPOPUPSTART). M2uia = request -> first UIA WindowOpened/MenuOpened event (coldat runs only).')
Out ('A run is valid only if the driver dismissed the modal (result after dismissal), the host summary passed and the stamps exist; an invalid attempt is retried (<= ' + $MaxRetries + ' retries) and kept below.')
Out ''
foreach ($k in $sets.Keys) {
  $g = @($sets[$k])
  Out "== $k : $($g.Count) valid runs"
  Out (Fmt-Stat 'M1 blocking max (ms)' @($g | ForEach-Object { [double]$_.m1_blocking_max_ms }))
  Out (Fmt-Stat 'M1gap run gap (ms)' @($g | ForEach-Object { [double]$_.m1_run_gap_ms }))
  Out (Fmt-Stat 'M2win request->visible (ms)' @($g | ForEach-Object { [double]$_.m2_win_ms }))
  if ($k -like 'coldat-*') { Out (Fmt-Stat 'M2uia request->UIA event (ms)' @($g | ForEach-Object { [double]$_.m2_uia_ms })) }
  Out (Fmt-Stat 'idle job delay max before open (ms)' @($g | ForEach-Object { [double]$_.idle_max }))
  $over = @($g | Where-Object { $_.m1_blocking_max_ms -gt 50 }).Count
  $overv = @($g | Where-Object { $_.m2_win_ms -gt 50 }).Count
  Out "  runs with M1 > 50 ms: $over / $($g.Count);  runs with M2win > 50 ms: $overv / $($g.Count)"
  Out ''
}
Out '== per run (valid attempts)'
foreach ($k in $sets.Keys) { foreach ($r in $sets[$k]) { Out ('{0,-14} #{1:D2}a{2} m1={3,6:N2} m1gap={4,6:N2} m2win={5,7} m2show={6,7} m2popup={7,7} m2uia={8,7} idle_max={9} fg_at_request={10} jobs={11}' -f $k, $r.index, $r.attempt, $r.m1_blocking_max_ms, $r.m1_run_gap_ms, $r.m2_win_ms, $r.m2_show_ms, $r.m2_popup_ms, $r.m2_uia_ms, $r.idle_max, $r.fg_owner_request, $r.m1_jobs) } }
Out ''
$bad = @($script:allAttempts | Where-Object { -not $_.valid })
Out "== invalid attempts (kept, not counted): $($bad.Count) of $(@($script:allAttempts).Count) attempts"
foreach ($r in $bad) { Out ('{0}-{1} #{2:D2}a{3}: {4} fg_at_request={5}' -f $r.cond, $r.kind, $r.index, $r.attempt, $r.reason, $r.fg_owner_request) }
Out ''
Out '== raw event stamps (first valid attempt of each run; ms after the host request; class shown)'
foreach ($k in $sets.Keys) { foreach ($r in $sets[$k]) { Out ('{0,-14} #{1:D2}: {2}' -f $k, $r.index, $r.events) } }
[System.IO.File]::WriteAllText($Result, ([string]::Join("`r`n", [string[]]$L.ToArray()) + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
"result written: $Result"
