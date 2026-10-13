# window-state.ps1 - runs in the INTERACTIVE session (via Invoke-Interactive). Reads Win32 state only: no input, no activation, no window titles.
# Writes JSON to -Out: every top-level window owned by a Windows Sandbox process (pid, process, class, visible, IsIconic), the current foreground window's
# owning process, and a SampleSeconds sampling run (every 50 ms) counting how often the foreground window belonged to a Sandbox process.
param([Parameter(Mandatory)][string]$Out, [double]$SampleSeconds = 3)
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class WS {
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  public static uint FgPid() { uint p = 0; IntPtr f = GetForegroundWindow(); if (f != IntPtr.Zero) GetWindowThreadProcessId(f, out p); return p; }
  public static bool HasFg() { return GetForegroundWindow() != IntPtr.Zero; }
  public static List<string> Windows(HashSet<uint> pids) {
    List<string> r = new List<string>();
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p); if (!pids.Contains(p)) return true;
      StringBuilder sb = new StringBuilder(128); GetClassNameW(h, sb, 128);
      r.Add(p + "|" + sb + "|visible=" + IsWindowVisible(h) + "|iconic=" + IsIconic(h) + "|hwnd=" + h.ToInt64());
      return true; }, IntPtr.Zero);
    return r;
  }
}
'@
$names = 'WindowsSandbox', 'WindowsSandboxClient', 'WindowsSandboxRemoteSession', 'WindowsSandboxServer'
$procs = @(Get-Process | Where-Object { $names -contains $_.ProcessName })
$pids = New-Object 'System.Collections.Generic.HashSet[uint32]'
foreach ($p in $procs) { [void]$pids.Add([uint32]$p.Id) }
$wins = @([WS]::Windows($pids))
$fgPid = [WS]::FgPid()
$fgName = ''; try { if ($fgPid) { $fgName = (Get-Process -Id $fgPid -ErrorAction Stop).ProcessName } } catch { }
$samples = 0; $sbFg = 0; $swn = [Diagnostics.Stopwatch]::StartNew()
while ($swn.Elapsed.TotalSeconds -lt $SampleSeconds) { $samples++; $f = [WS]::FgPid(); if ($f -and $pids.Contains([uint32]$f)) { $sbFg++ }; Start-Sleep -Milliseconds 50 }
$o = [ordered]@{
    utc = (Get-Date).ToUniversalTime().ToString('o'); sandbox_processes = @($procs | ForEach-Object { $_.ProcessName + '#' + $_.Id })
    sandbox_windows = $wins; all_sandbox_windows_iconic = [bool](@($wins | Where-Object { $_ -match '\|visible=True\|iconic=False' }).Count -eq 0 -and $wins.Count -gt 0)
    foreground_process = $fgName; foreground_is_sandbox = [bool]($fgPid -and $pids.Contains([uint32]$fgPid)); foreground_window_exists = [WS]::HasFg()
    samples = $samples; samples_with_sandbox_foreground = $sbFg
}
[IO.File]::WriteAllText($Out, ($o | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
