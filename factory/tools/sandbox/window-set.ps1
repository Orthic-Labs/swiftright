# window-set.ps1 - runs in the INTERACTIVE session (Invoke-Interactive). Puts the Sandbox client window into -Mode min (SW_SHOWMINNOACTIVE), bottom (z-order bottom,
# no activation) or offscreen (moved to -30000,-30000, not minimised: the guest keeps rendering and UIA-driven jobs such as W08 work) for -Seconds. Whenever a Sandbox
# process owns the foreground window, the foreground is handed back to the previously active window, or else the top-most ordinary window that is not a Sandbox window
# (escalation: SetForegroundWindow, AttachThreadInput, SwitchToThisWindow, retry, then SW_MINIMIZE of the Sandbox window as the last resort). Handles/pids only; no input.
param([ValidateSet('min', 'bottom', 'offscreen')][string]$Mode = 'min', [double]$Seconds = 2, [Parameter(Mandatory)][string]$Out)
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Diagnostics; using System.Runtime.InteropServices;
public static class WSet {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int l, t, r, b; }
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr h, int cmd);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] static extern void SwitchToThisWindow(IntPtr h, bool alt);
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] static extern int GetWindowTextLengthW(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int val, int size);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  public static int Calls = 0, FgSandbox = 0, Samples = 0, Restores = 0, RestoreFailures = 0, MinimiseFallbacks = 0; static IntPtr prior = IntPtr.Zero;
  static HashSet<uint> Pids() { HashSet<uint> s = new HashSet<uint>(); foreach (string n in new string[] { "WindowsSandbox", "WindowsSandboxClient", "WindowsSandboxRemoteSession", "WindowsSandboxServer" }) foreach (Process p in Process.GetProcessesByName(n)) { s.Add((uint)p.Id); p.Dispose(); } return s; }
  static bool Is(HashSet<uint> pids) { IntPtr f = GetForegroundWindow(); if (f == IntPtr.Zero) return false; uint p; GetWindowThreadProcessId(f, out p); return pids.Contains(p); }
  static IntPtr Fallback(HashSet<uint> pids) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      if (found != IntPtr.Zero) return true; if (!IsWindowVisible(h) || IsIconic(h)) return true;
      uint p; GetWindowThreadProcessId(h, out p); if (pids.Contains(p)) return true;
      int ex = GetWindowLong(h, -20), st = GetWindowLong(h, -16);
      if ((ex & 0x80) != 0 || (ex & 0x08000000) != 0) return true; if ((st & 0xC00000) != 0xC00000) return true;
      if (GetWindow(h, 4) != IntPtr.Zero) return true;
      int cl; if (DwmGetWindowAttribute(h, 14, out cl, 4) == 0 && cl != 0) return true;
      if (GetWindowTextLengthW(h) == 0) return true; found = h; return true; }, IntPtr.Zero);
    return found;
  }
  static bool Force(IntPtr t, HashSet<uint> pids) {
    IntPtr fg0 = GetForegroundWindow(); uint fp0; uint ft = GetWindowThreadProcessId(fg0, out fp0);
    SetForegroundWindow(t); if (!Is(pids)) return true;
    uint me = GetCurrentThreadId();
    if (ft != 0 && ft != me && AttachThreadInput(me, ft, true)) { try { SetForegroundWindow(t); BringWindowToTop(t); } finally { AttachThreadInput(me, ft, false); } }
    if (!Is(pids)) return true;
    SwitchToThisWindow(t, true); if (!Is(pids)) return true;
    BringWindowToTop(t); SetForegroundWindow(t); return !Is(pids);
  }
  public static void Tick(string mode) {
    HashSet<uint> pids = Pids(); IntPtr fg = GetForegroundWindow(); uint fp = 0; if (fg != IntPtr.Zero) GetWindowThreadProcessId(fg, out fp);
    Samples++;
    IntPtr mainWin = IntPtr.Zero;
    EnumWindows(delegate(IntPtr h, IntPtr l) { uint p; GetWindowThreadProcessId(h, out p); if (!pids.Contains(p) || !IsWindowVisible(h)) return true;
      RECT r; GetWindowRect(h, out r); bool ic = IsIconic(h);
      if (!ic && (r.r - r.l < 300 || r.b - r.t < 300)) return true;
      mainWin = h;
      if (mode == "min") { if (!ic) { ShowWindowAsync(h, 7); Calls++; } }
      else if (mode == "offscreen") { if (ic) { ShowWindowAsync(h, 4); Calls++; } else if (r.l > -20000) { SetWindowPos(h, new IntPtr(1), -30000, -30000, 0, 0, 0x11); Calls++; } }
      else if (!ic) { SetWindowPos(h, new IntPtr(1), 0, 0, 0, 0, 0x13); Calls++; }
      return true; }, IntPtr.Zero);
    if (fg != IntPtr.Zero && pids.Contains(fp)) {
      FgSandbox++;
      IntPtr t = (prior != IntPtr.Zero && IsWindow(prior) && IsWindowVisible(prior) && !IsIconic(prior)) ? prior : Fallback(pids);
      if (t != IntPtr.Zero && Force(t, pids)) Restores++;
      else { RestoreFailures++; if (mainWin != IntPtr.Zero) { ShowWindow(mainWin, 6); MinimiseFallbacks++; } }
    } else if (fg != IntPtr.Zero) prior = fg;
  }
}
'@
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $Seconds) { [WSet]::Tick($Mode); Start-Sleep -Milliseconds 20 }
[IO.File]::WriteAllText($Out, ('mode=' + $Mode + ' calls=' + [WSet]::Calls + ' fg_samples=' + [WSet]::Samples + ' fg_was_sandbox=' + [WSet]::FgSandbox + ' fg_restored=' + [WSet]::Restores + ' fg_restore_failures=' + [WSet]::RestoreFailures + ' minimise_fallbacks=' + [WSet]::MinimiseFallbacks))
