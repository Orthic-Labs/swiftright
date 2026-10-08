# SR0-B frame-clock probe: runs SwiftHost.exe in an interactive desktop session.
# Needed because SSH sessions (session 0) have no DirectX-capable desktop (DXGI_ERROR_NOT_CURRENTLY_AVAILABLE).
# Variants are interleaved per round: base (no timeBeginPeriod) and tbp (timeBeginPeriod(1) via --timer-res-1).
# Each run writes events.csv, dwm.csv, meta.txt, jobs.csv and ticks.csv into its own directory under $base\runs\<stamp>\.
# Once the probe window exists, it is brought to the foreground (SetForegroundWindow, then AllowSetForegroundWindow,
# then an AttachThreadInput fallback); the outcome is logged per run as fg_attempt.
# While each run is alive, samples every 50 ms: foreground HWND, its title and process, whether the probe is
# foreground, and whether any visible top-level window above the probe in z-order intersects the probe rect.
# Output is one line per change (not per sample) plus per-run counts; see the summary lines below.
# Outputs are compatible with the previous version: the focus_samples line keeps its format.
param(
    [int]$Runs = 5,
    [string]$OutFile = ''
)

$ErrorActionPreference = 'Continue'
$base = 'D:\Claude\sr0b-frame-clock'
$bin = "$base\scratch-1\out\Products\Release-windows-x86_64"
$exe = Join-Path $bin 'SwiftHost.exe'
$swiftBin = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $OutFile) { $OutFile = "$base\result-$stamp.txt" }
$runRoot = "$base\runs\$stamp"
New-Item -ItemType Directory -Force $runRoot | Out-Null

$probeSrc = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

public class SR0Snap {
    public IntPtr Fg;
    public string FgTitle;
    public string FgProc;
    public bool ProbeFg;
    public bool ProbeVisible;
    public string[] Occluders;
}

public static class SR0Probe {
    public delegate bool EnumWinProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int dwProcessId);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWinProc callback, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hWnd, int attribute, out int value, int size);

    static string Title(IntPtr h) {
        int n = GetWindowTextLength(h);
        if (n <= 0) return "";
        StringBuilder sb = new StringBuilder(n + 1);
        GetWindowText(h, sb, sb.Capacity);
        return sb.ToString().Replace("\r", " ").Replace("\n", " ");
    }

    static string Proc(IntPtr h) {
        uint pid;
        GetWindowThreadProcessId(h, out pid);
        if (pid == 0) return "?";
        try { return Process.GetProcessById((int)pid).ProcessName; }
        catch (Exception) { return "pid" + pid; }
    }

    static bool Cloaked(IntPtr h) {
        int cloaked;
        // DWMWA_CLOAKED = 14 (UWP and virtual-desktop-hidden windows report visible but are not drawn)
        if (DwmGetWindowAttribute(h, 14, out cloaked, 4) != 0) return false;
        return cloaked != 0;
    }

    // Brings hwnd to the foreground. Returns the method that worked, or "failed".
    public static string Foreground(IntPtr hwnd, int pid) {
        if (hwnd == IntPtr.Zero) return "no-hwnd";
        if (IsIconic(hwnd)) ShowWindow(hwnd, 9); // SW_RESTORE
        if (GetForegroundWindow() == hwnd) return "already";
        if (SetForegroundWindow(hwnd) && GetForegroundWindow() == hwnd) return "direct";
        AllowSetForegroundWindow(pid);
        if (SetForegroundWindow(hwnd) && GetForegroundWindow() == hwnd) return "allow";
        uint fgPid;
        uint fgThread = GetWindowThreadProcessId(GetForegroundWindow(), out fgPid);
        uint me = GetCurrentThreadId();
        bool attached = fgThread != 0 && fgThread != me && AttachThreadInput(me, fgThread, true);
        try {
            BringWindowToTop(hwnd);
            SetForegroundWindow(hwnd);
        } finally {
            if (attached) AttachThreadInput(me, fgThread, false);
        }
        return GetForegroundWindow() == hwnd ? "attach" : "failed";
    }

    // One sample: foreground window, probe visibility, and visible top-level windows above the probe that
    // intersect its rectangle. EnumWindows walks top-down in z-order, so the walk stops at the probe.
    public static SR0Snap Take(IntPtr probe) {
        SR0Snap s = new SR0Snap();
        s.Fg = GetForegroundWindow();
        s.FgTitle = s.Fg == IntPtr.Zero ? "" : Title(s.Fg);
        s.FgProc = s.Fg == IntPtr.Zero ? "" : Proc(s.Fg);
        s.ProbeFg = probe != IntPtr.Zero && s.Fg == probe;
        s.ProbeVisible = probe != IntPtr.Zero && IsWindowVisible(probe) && !IsIconic(probe);
        List<string> occ = new List<string>();
        s.Occluders = occ.ToArray();
        if (!s.ProbeVisible) return s;

        RECT pr;
        if (!GetWindowRect(probe, out pr)) return s;
        uint probePid;
        GetWindowThreadProcessId(probe, out probePid);

        List<IntPtr> above = new List<IntPtr>();
        bool found = false;
        EnumWindows((h, l) => {
            if (h == probe) { found = true; return false; }
            above.Add(h);
            return true;
        }, IntPtr.Zero);
        if (!found) return s;

        foreach (IntPtr h in above) {
            if (!IsWindowVisible(h) || IsIconic(h) || Cloaked(h)) continue;
            RECT r;
            if (!GetWindowRect(h, out r)) continue;
            if (r.Right <= pr.Left || r.Left >= pr.Right || r.Bottom <= pr.Top || r.Top >= pr.Bottom) continue;
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            if (pid == probePid) continue; // the probe's own helper windows are not interrupters
            occ.Add(Proc(h) + "|" + Title(h));
        }
        s.Occluders = occ.ToArray();
        return s;
    }
}
'@
if (-not ('SR0Probe' -as [type])) { Add-Type -TypeDefinition $probeSrc -Language CSharp }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) started=$(Get-Date -Format o)")
$lines.Add("exe=$exe exists=$(Test-Path $exe) runs_per_variant=$Runs runRoot=$runRoot")

$variants = @(
    @{ name = 'base'; extra = @() },
    @{ name = 'tbp';  extra = @('--timer-res-1') }
)
$inv = [Globalization.CultureInfo]::InvariantCulture

for ($r = 1; $r -le $Runs; $r++) {
    foreach ($v in $variants) {
        $id = "$($v.name)-$r"
        $outDir = "$runRoot\$id"
        New-Item -ItemType Directory -Force $outDir | Out-Null
        $lines.Add("=== RUN $id start=$(Get-Date -Format o)")

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exe
        $psi.Arguments = (@("--out=$outDir") + $v.extra) -join ' '
        $psi.WorkingDirectory = $bin
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.EnvironmentVariables['Path'] = "$swiftBin;$bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $proc = [System.Diagnostics.Process]::Start($psi)
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()

        $clock = [Diagnostics.Stopwatch]::StartNew()
        $samples = 0; $visible = 0; $foreground = 0
        $occludedN = 0; $probeFgN = 0
        $fgTried = $false
        $prevKey = $null
        $interrupters = @{}
        $deadline = (Get-Date).AddSeconds(120)
        while (-not $proc.HasExited -and (Get-Date) -lt $deadline) {
            $proc.Refresh()
            $hwnd = $proc.MainWindowHandle
            $samples++
            if ($hwnd -ne [IntPtr]::Zero) {
                $visible++
                if (-not $fgTried) {
                    $fgTried = $true
                    $method = [SR0Probe]::Foreground($hwnd, $proc.Id)
                    $ok = ($method -ne 'failed' -and $method -ne 'no-hwnd')
                    $t = $clock.Elapsed.TotalSeconds.ToString('0.000', $inv)
                    $lines.Add("fg_attempt run=$id t=+${t}s method=$method ok=$ok hwnd=0x$($hwnd.ToInt64().ToString('X'))")
                }
            }
            $snap = [SR0Probe]::Take($hwnd)
            if ($snap.ProbeFg) { $foreground++; $probeFgN++ }
            if ($snap.Occluders.Count -gt 0) { $occludedN++ }
            if ($snap.Fg -ne [IntPtr]::Zero -and -not $snap.ProbeFg) {
                $fgKey = "$($snap.FgProc)|$($snap.FgTitle)"
                $interrupters[$fgKey] = 1 + [int]$interrupters[$fgKey]
            }
            foreach ($o in $snap.Occluders) {
                $interrupters[$o] = 1 + [int]$interrupters[$o]
            }

            $key = "{0}|{1}|{2}|{3}|{4}|{5}" -f $snap.Fg.ToInt64(), $snap.FgProc, $snap.FgTitle,
                [int]$snap.ProbeFg, [int]$snap.ProbeVisible, ($snap.Occluders -join ' ; ')
            if ($key -ne $prevKey) {
                $prevKey = $key
                $t = $clock.Elapsed.TotalSeconds.ToString('0.000', $inv)
                $occText = if ($snap.Occluders.Count -gt 0) { $snap.Occluders -join ' ; ' } else { '-' }
                $lines.Add("change run=$id t=+${t}s fg=$($snap.FgProc)|$($snap.FgTitle) probe_fg=$([int]$snap.ProbeFg) probe_visible=$([int]$snap.ProbeVisible) occluded_by=$occText")
            }
            Start-Sleep -Milliseconds 50
        }
        if (-not $proc.HasExited) { $proc.Kill(); $lines.Add('TIMEOUT: killed after 120 s') }
        $proc.WaitForExit()
        $lines.Add("focus_samples: total=$samples window_visible=$visible window_foreground=$foreground")
        $lines.Add("fg_samples=$samples probe_fg_samples=$probeFgN occluded_samples=$occludedN distinct_interrupters=$($interrupters.Count)")
        foreach ($k in ($interrupters.Keys | Sort-Object { -[int]$interrupters[$_] } | Select-Object -First 20)) {
            $lines.Add("  interrupter samples=$($interrupters[$k]) $k")
        }
        $lines.Add([string]$stdout.Result)
        $lines.Add([string]$stderr.Result)
        $lines.Add("exit=$($proc.ExitCode) end=$(Get-Date -Format o)")
    }
}

$lines.Add("finished=$(Get-Date -Format o)")
[System.IO.File]::WriteAllText($OutFile, [string]::Join("`r`n", $lines))
Write-Host "wrote $OutFile"
