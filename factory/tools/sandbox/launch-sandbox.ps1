# launch-sandbox.ps1 - runs in the INTERACTIVE session (hidden scheduled task from start-worker.ps1). Starts Windows Sandbox ONCE and keeps its window out of the way and
# out of the foreground while it boots (-WatchSeconds), reading handles and pids only, sending no input:
#   -Hide bottom     (default for the boot phase) z-order bottom with SWP_NOACTIVATE, no move: the guest logon needs a normal, visible, non-minimised client (offscreen and minimised clients
#                    were observed to break the connection: 'Error: the remote environment is logging off' / logon never ran). start-worker.ps1 then hides the window AFTER the
#                    worker heartbeat is up (window-set.ps1).
#   -Hide offscreen the window is moved to (-30000,-30000) with SWP_NOACTIVATE and z-order bottom: it is NOT minimised, so the RDP-style client keeps rendering and
#                    the guest logon proceeds (a minimised client stalled the guest logon in the 2026-10-13 tests), and nothing is ever visible on the desktop.
#   -Hide min        SW_SHOWMINNOACTIVE on every pass.
# If a Sandbox process owns the foreground window, the previously active window is restored (escalation: SetForegroundWindow, AttachThreadInput, SwitchToThisWindow,
# retry; the same chain as sandbox-background.ps1). Log: <StateDir>\launch.log.
param([Parameter(Mandatory)][string]$Wsb, [Parameter(Mandatory)][string]$StateDir, [int]$WatchSeconds = 150, [ValidateSet('offscreen', 'min', 'bottom')][string]$Hide = 'bottom')
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Diagnostics; using System.Runtime.InteropServices;
public static class SbMin {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int l, t, r, b; }
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr h, int cmd);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] static extern void SwitchToThisWindow(IntPtr h, bool alt);
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  static readonly string[] Names = { "WindowsSandbox", "WindowsSandboxClient", "WindowsSandboxRemoteSession", "WindowsSandboxServer" };
  public static IntPtr Prior = IntPtr.Zero; static int lastBottom = 0;
  public static int Moves = 0, FgSamples = 0, FgSandbox = 0, Restores = 0, RestoreFailures = 0, MainWindows = 0, StillVisibleOnScreen = 0;
  public static long FirstWindowMs = -1, FirstHiddenMs = -1;
  public static string Owners = "";
  static HashSet<uint> Pids() { HashSet<uint> s = new HashSet<uint>(); foreach (string n in Names) foreach (Process p in Process.GetProcessesByName(n)) { s.Add((uint)p.Id); p.Dispose(); } return s; }
  public static void Snapshot() { IntPtr f = GetForegroundWindow(); if (f != IntPtr.Zero) Prior = f; }
  static bool Force(IntPtr t, HashSet<uint> pids) {
    IntPtr fg0 = GetForegroundWindow(); uint fp0; uint ft = GetWindowThreadProcessId(fg0, out fp0);
    SetForegroundWindow(t); if (!Is(pids)) return true;
    uint me = GetCurrentThreadId();
    if (ft != 0 && ft != me && AttachThreadInput(me, ft, true)) { try { SetForegroundWindow(t); BringWindowToTop(t); } finally { AttachThreadInput(me, ft, false); } }
    if (!Is(pids)) return true;
    SwitchToThisWindow(t, true); if (!Is(pids)) return true;
    BringWindowToTop(t); SetForegroundWindow(t); return !Is(pids);
  }
  static bool Is(HashSet<uint> pids) { IntPtr f = GetForegroundWindow(); if (f == IntPtr.Zero) return false; uint p; GetWindowThreadProcessId(f, out p); return pids.Contains(p); }
  public static void Tick(long ms, string mode) {
    HashSet<uint> pids = Pids();
    IntPtr fg = GetForegroundWindow(); uint fp = 0; if (fg != IntPtr.Zero) GetWindowThreadProcessId(fg, out fp);
    FgSamples++;
    if (fg != IntPtr.Zero && pids.Contains(fp)) { FgSandbox++; if (Prior != IntPtr.Zero && IsWindow(Prior)) { if (Force(Prior, pids)) Restores++; else RestoreFailures++; } }
    else if (fg != IntPtr.Zero) Prior = fg;
    if (pids.Count == 0) return;
    int main = 0, shown = 0;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p); if (!pids.Contains(p) || !IsWindowVisible(h)) return true;
      RECT r; GetWindowRect(h, out r); bool iconic = IsIconic(h);
      if (!iconic && (r.r - r.l < 300 || r.b - r.t < 300)) return true;   // small helper windows (timer, IME) are not the client window
      main++; string o = p.ToString(); try { using (Process q = Process.GetProcessById((int)p)) o = q.ProcessName + "#" + p; } catch (Exception) { }
      if (Owners.IndexOf(o) < 0) Owners += o + " ";
      if (mode == "bottom") { if (Environment.TickCount - lastBottom > 1000) { SetWindowPos(h, new IntPtr(1), 0, 0, 0, 0, 0x1 | 0x2 | 0x10); Moves++; lastBottom = Environment.TickCount; } shown++; }
      else if (mode == "offscreen") { if (r.l > -20000) { SetWindowPos(h, new IntPtr(1), -30000, -30000, 0, 0, 0x1 | 0x10); Moves++; shown++; } }
      else { if (!iconic) { ShowWindowAsync(h, 7); Moves++; shown++; } }
      return true; }, IntPtr.Zero);
    MainWindows = main; StillVisibleOnScreen = shown;
    if (main > 0 && FirstWindowMs < 0) FirstWindowMs = ms;
    if (main > 0 && shown == 0 && FirstHiddenMs < 0) FirstHiddenMs = ms;
  }
}
'@
$log = Join-Path $StateDir 'launch.log'
function W([string]$s) { Add-Content -LiteralPath $log -Value ((Get-Date -Format 'o') + ' ' + $s) }
[SbMin]::Snapshot()
W ('launch: hide=' + $Hide + ' wsb=' + $Wsb)
$sw = [Diagnostics.Stopwatch]::StartNew()
Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsSandbox.exe') -ArgumentList ('"' + $Wsb + '"') -WindowStyle Minimized | Out-Null
while ($sw.Elapsed.TotalSeconds -lt $WatchSeconds) { [SbMin]::Tick($sw.ElapsedMilliseconds, $Hide); Start-Sleep -Milliseconds 10 }
W ('watch ended: window_owners=[' + [SbMin]::Owners + '] first_window_ms=' + [SbMin]::FirstWindowMs + ' first_hidden_ms=' + [SbMin]::FirstHiddenMs + ' moves=' + [SbMin]::Moves +
    ' fg_samples=' + [SbMin]::FgSamples + ' fg_was_sandbox=' + [SbMin]::FgSandbox + ' fg_restored=' + [SbMin]::Restores + ' fg_restore_failures=' + [SbMin]::RestoreFailures + ' main_windows=' + [SbMin]::MainWindows)
