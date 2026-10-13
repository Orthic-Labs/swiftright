# window-shot.ps1 - interactive session. PrintWindow (flags 2 = PW_RENDERFULLCONTENT) of the Sandbox window ONLY (not the desktop) to -Out PNG; diagnostic aid.
param([Parameter(Mandatory)][string]$Out)
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Collections.Generic; using System.Diagnostics; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class WShot {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int l, t, r, b; }
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  public static string Shot(string path) {
    HashSet<uint> pids = new HashSet<uint>(); foreach (string n in new string[] { "WindowsSandboxClient", "WindowsSandboxRemoteSession" }) foreach (Process p in Process.GetProcessesByName(n)) pids.Add((uint)p.Id);
    string res = "no window";
    EnumWindows(delegate(IntPtr h, IntPtr l) { uint p; GetWindowThreadProcessId(h, out p); if (!pids.Contains(p) || !IsWindowVisible(h)) return true;
      RECT r; GetWindowRect(h, out r); int w = r.r - r.l, ht = r.b - r.t; if (w < 300 || ht < 300) return true; res = "rect " + r.l + "," + r.t + " " + w + "x" + ht;
      using (Bitmap b = new Bitmap(w, ht)) { using (Graphics g = Graphics.FromImage(b)) { IntPtr dc = g.GetHdc(); PrintWindow(h, dc, 2); g.ReleaseHdc(dc); } b.Save(path, ImageFormat.Png); res += " saved"; }
      return true; }, IntPtr.Zero);
    return res;
  }
}
'@
[IO.File]::WriteAllText($Out + '.txt', [WShot]::Shot($Out))
