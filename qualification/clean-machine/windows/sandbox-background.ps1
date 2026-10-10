# sandbox-background.ps1 - keeps every Windows Sandbox window in the BACKGROUND of the host desktop, so a person working on the host is not interrupted.
# Rule (host owner, 2026-10-10): never minimize it (a minimized RDP client can stop rendering the guest), change no host setting, do not activate it:
#   SetWindowPos(hwnd, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE) on every visible top-level window of WindowsSandboxClient (and the
#   remote-session host), then give the foreground back to the last window that was in front and was not a Sandbox window.
# It must run in the interactive session (session 1): a one-shot Interactive scheduled task, or the launcher that run-unelevated-task.ps1 starts.
# It reads window handles and process ids only. It never reads or records a window title and sends no input (the foreground is restored with
# SetForegroundWindow, using AttachThreadInput to the current foreground thread only when the first call is refused).
#   -Library                      define the type and functions only (dot-source it: . .\sandbox-background.ps1 -Library)
#   -Once                         one pass now, print what was done
#   -Watch [-MaxMinutes 60] [-GraceSeconds 30] [-Log <file>]   pass every 150 ms until no Sandbox process has been seen for GraceSeconds after one was
param([switch]$Library, [switch]$Once, [switch]$Watch, [int]$MaxMinutes = 60, [int]$GraceSeconds = 30, [string]$Log = '')
if (-not ('SbBack' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class SbBack {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", SetLastError = true)] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern void SwitchToThisWindow(IntPtr h, bool altTab);
  [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, System.Text.StringBuilder s, int n);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr proc, uint access, out IntPtr tok);
  [DllImport("advapi32.dll", SetLastError = true)] static extern bool GetTokenInformation(IntPtr tok, int cls, IntPtr buf, int len, out int ret);
  [DllImport("advapi32.dll")] static extern IntPtr GetSidSubAuthority(IntPtr sid, uint n);
  [DllImport("advapi32.dll")] static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] static extern int GetWindowTextLengthW(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  const uint SWP_NOSIZE = 0x1, SWP_NOMOVE = 0x2, SWP_NOACTIVATE = 0x10;
  static readonly IntPtr HWND_BOTTOM = new IntPtr(1);
  static readonly string[] Names = { "WindowsSandboxClient", "WindowsSandboxRemoteSession" };
  static readonly Dictionary<long, long> lastPush = new Dictionary<long, long>();
  static IntPtr lastOther = IntPtr.Zero;
  static long lastRestoreAttempt = 0;
  public static int Pushes, Restores, RestoreFailures, PushFailures, SandboxProcesses;
  public static string LastEvent = "";
  static HashSet<uint> SandboxPids() {
    HashSet<uint> s = new HashSet<uint>();
    foreach (string n in Names) foreach (Process p in Process.GetProcessesByName(n)) { s.Add((uint)p.Id); p.Dispose(); }
    return s;
  }
  // When no earlier foreground window is known (the watcher started after the Sandbox was already in front): the top-most ordinary window in z-order that is not a
  // Sandbox window: visible, not minimized, captioned, not a tool or no-activate window, not owned, not cloaked, with a non-empty title (only its LENGTH is read).
  static IntPtr Fallback(HashSet<uint> pids) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      if (found != IntPtr.Zero) return true;
      if (!IsWindowVisible(h) || IsIconic(h)) return true;
      uint p; GetWindowThreadProcessId(h, out p); if (pids.Contains(p)) return true;
      int ex = GetWindowLong(h, -20), st = GetWindowLong(h, -16);
      if ((ex & 0x80) != 0 || (ex & 0x08000000) != 0) return true;
      if ((st & 0xC00000) != 0xC00000) return true;
      if (GetWindow(h, 4) != IntPtr.Zero) return true;
      int cloaked; if (DwmGetWindowAttribute(h, 14, out cloaked, 4) == 0 && cloaked != 0) return true;
      if (GetWindowTextLengthW(h) == 0) return true;
      found = h; return true;
    }, IntPtr.Zero);
    return found;
  }
  public static int Step1, Step2, Step3, Step4, StepNone;
  public static string Diag = "";
  static int diagCount = 0;
  static string ClassOf(IntPtr h) { System.Text.StringBuilder sb = new System.Text.StringBuilder(128); GetClassNameW(h, sb, 128); return sb.ToString(); }
  static string ProcOf(IntPtr h) { uint pid; GetWindowThreadProcessId(h, out pid); try { using (Process p = Process.GetProcessById((int)pid)) return p.ProcessName + "#" + pid; } catch (Exception) { return "pid" + pid; } }
  // integrity RID of a process (0x1000 low, 0x2000 medium, 0x3000 high, 0x4000 system); -1 unknown
  static int IntegrityOf(uint pid) {
    IntPtr hp = OpenProcess(0x1000, false, pid); if (hp == IntPtr.Zero) return -1;   // PROCESS_QUERY_LIMITED_INFORMATION
    try {
      IntPtr tok; if (!OpenProcessToken(hp, 0x8, out tok)) return -1;
      try {
        int len; GetTokenInformation(tok, 25, IntPtr.Zero, 0, out len);              // TokenIntegrityLevel
        IntPtr buf = Marshal.AllocHGlobal(len);
        try {
          if (!GetTokenInformation(tok, 25, buf, len, out len)) return -1;
          IntPtr sid = Marshal.ReadIntPtr(buf);
          int cnt = Marshal.ReadByte(GetSidSubAuthorityCount(sid));
          return Marshal.ReadInt32(GetSidSubAuthority(sid, (uint)(cnt - 1)));
        } finally { Marshal.FreeHGlobal(buf); }
      } finally { CloseHandle(tok); }
    } finally { CloseHandle(hp); }
  }
  static bool IsSb(IntPtr h, HashSet<uint> pids) { if (h == IntPtr.Zero) return false; uint p; GetWindowThreadProcessId(h, out p); return pids.Contains(p); }
  // Escalation chain; returns the step that moved the foreground off the Sandbox (0 = none).
  static int Force(IntPtr target, HashSet<uint> pids) {
    IntPtr fg0 = GetForegroundWindow(); uint fpid0 = 0; uint ft = GetWindowThreadProcessId(fg0, out fpid0);
    bool ok1 = SetForegroundWindow(target); int e1 = Marshal.GetLastWin32Error();
    if (!IsSb(GetForegroundWindow(), pids)) return 1;
    uint me = GetCurrentThreadId(); bool att = false; int e2 = 0;
    if (ft != 0 && ft != me) { att = AttachThreadInput(me, ft, true); e2 = Marshal.GetLastWin32Error(); }
    if (att) { try { SetForegroundWindow(target); BringWindowToTop(target); } finally { AttachThreadInput(me, ft, false); } }
    if (!IsSb(GetForegroundWindow(), pids)) return 2;
    SwitchToThisWindow(target, true);
    if (!IsSb(GetForegroundWindow(), pids)) return 3;
    BringWindowToTop(target); SetForegroundWindow(target);
    if (!IsSb(GetForegroundWindow(), pids)) return 4;
    if (diagCount < 6) {
      diagCount++; uint tpid; GetWindowThreadProcessId(target, out tpid);
      Diag += "restore failed: fg=" + ProcOf(fg0) + " class=" + ClassOf(fg0) + " integrity=0x" + IntegrityOf(fpid0).ToString("X") + "; me integrity=0x" + IntegrityOf((uint)Process.GetCurrentProcess().Id).ToString("X")
        + "; target=" + ProcOf(target) + " class=" + ClassOf(target) + " integrity=0x" + IntegrityOf(tpid).ToString("X")
        + "; SetForegroundWindow ok=" + ok1 + " err=" + e1 + "; AttachThreadInput ok=" + att + " err=" + e2 + " | ";
    }
    return 0;
  }
  // One pass. Returns the number of Sandbox processes seen.
  public static int Tick() {
    HashSet<uint> pids = SandboxPids(); SandboxProcesses = pids.Count;
    IntPtr fg = GetForegroundWindow(); uint fpid = 0; if (fg != IntPtr.Zero) GetWindowThreadProcessId(fg, out fpid);
    bool fgIsSandbox = pids.Contains(fpid);
    if (!fgIsSandbox && fg != IntPtr.Zero) lastOther = fg;
    if (pids.Count == 0) return 0;
    long now = Environment.TickCount;
    List<IntPtr> wins = new List<IntPtr>();
    EnumWindows(delegate(IntPtr h, IntPtr l) { uint p; GetWindowThreadProcessId(h, out p); if (pids.Contains(p) && IsWindowVisible(h)) wins.Add(h); return true; }, IntPtr.Zero);
    foreach (IntPtr h in wins) {
      long k = h.ToInt64(); long last; bool known = lastPush.TryGetValue(k, out last);
      if (!((fgIsSandbox && now - last > 400) || !known || now - last > 3000)) continue;
      bool ok = SetWindowPos(h, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE);
      lastPush[k] = now; if (ok) Pushes++; else PushFailures++;
      LastEvent = (ok ? "pushed " : "push FAILED ") + "hwnd=" + k + (IsIconic(h) ? " (iconic)" : "") + (fgIsSandbox ? " it was the foreground window" : "");
    }
    if (fgIsSandbox && now - lastRestoreAttempt >= 400) {
      lastRestoreAttempt = now;
      IntPtr target = (lastOther != IntPtr.Zero && IsWindow(lastOther) && IsWindowVisible(lastOther) && !IsIconic(lastOther)) ? lastOther : Fallback(pids);
      if (target == IntPtr.Zero) { RestoreFailures++; return pids.Count; }
      int step = Force(target, pids);
      if (step == 0) RestoreFailures++;
      else { Restores++; if (step == 1) Step1++; else if (step == 2) Step2++; else if (step == 3) Step3++; else Step4++; LastEvent += "; foreground given back to hwnd=" + target.ToInt64() + " by step " + step; }
    }
    return pids.Count;
  }
  public static void Reset() { lastPush.Clear(); Pushes = Restores = RestoreFailures = PushFailures = 0; }
}
'@
}
function Get-SandboxBackgroundSummary { return ('pushes=' + [SbBack]::Pushes + ' push_failures=' + [SbBack]::PushFailures + ' foreground_restores=' + [SbBack]::Restores + ' (by step 1 SetForegroundWindow=' + [SbBack]::Step1 + ', 2 AttachThreadInput=' + [SbBack]::Step2 + ', 3 SwitchToThisWindow=' + [SbBack]::Step3 + ', 4 retry=' + [SbBack]::Step4 + ') restore_failures=' + [SbBack]::RestoreFailures + ' diag=[' + [SbBack]::Diag + ']') }
function Invoke-SandboxBackground([int]$MaxMinutes = 60, [int]$GraceSeconds = 30, [string]$Log = '') {
  $deadline = (Get-Date).AddMinutes($MaxMinutes); $seen = $false; $lastSeen = Get-Date; $lastLine = ''
  while ((Get-Date) -lt $deadline) {
    $n = [SbBack]::Tick()
    if ($n -gt 0) { $seen = $true; $lastSeen = Get-Date }
    elseif ($seen -and ((Get-Date) - $lastSeen).TotalSeconds -gt $GraceSeconds) { break }
    if ($Log -and [SbBack]::LastEvent -ne $lastLine) { $lastLine = [SbBack]::LastEvent; try { Add-Content -LiteralPath $Log -Value ((Get-Date -Format 'HH:mm:ss.fff') + ' ' + $lastLine + ' | pushes=' + [SbBack]::Pushes + ' push_failures=' + [SbBack]::PushFailures + ' restores=' + [SbBack]::Restores + ' restore_failures=' + [SbBack]::RestoreFailures) } catch { } }
    Start-Sleep -Milliseconds 150
  }
  if ($Log) { try { Add-Content -LiteralPath $Log -Value ((Get-Date -Format 'HH:mm:ss.fff') + ' watch ended: pushes=' + [SbBack]::Pushes + ' push_failures=' + [SbBack]::PushFailures + ' restores=' + [SbBack]::Restores + ' restore_failures=' + [SbBack]::RestoreFailures) } catch { } }
}
if ($Library) { return }
if ($Once) {
  $n = [SbBack]::Tick()
  "sandbox processes=$n pushes=$([SbBack]::Pushes) push_failures=$([SbBack]::PushFailures) restores=$([SbBack]::Restores) restore_failures=$([SbBack]::RestoreFailures) last=[$([SbBack]::LastEvent)]"
  exit 0
}
if ($Watch) { Invoke-SandboxBackground $MaxMinutes $GraceSeconds $Log; exit 0 }
'usage: -Library | -Once | -Watch'
