# SR0-B frame-clock probe, harness v3 (batch 4). run-desktop.ps1 (v2) is kept unchanged.
# Runs SwiftHost.exe in an interactive desktop session (SSH sessions have no DirectX desktop).
# Changes from v2 (INVESTIGATION.md, "Harness diffs"):
#  - pid, QPC start and QPC end per run (pid / pid_exit lines); analysis joins on pid, not on time.
#  - per-monitor-v2 DPI awareness, set once before any geometry read.
#  - per-sample probe state: own DWMWA_CLOAKED mask, IVirtualDesktopManager current-desktop flag,
#    7x5 WindowFromPoint hit grid, foreground-window geometry (physical rect | ex-style | extended frame bounds).
#    Every change of state is logged, even when rect overlap stays zero.
#  - skips a launch while an rk2* process is alive (waits up to -RkWaitSeconds, then logs skip_run).
#  - per-sample trace in <run>\harness-samples.csv on the QPC clock the probe uses (window_ticks).
#  - run_state line per run: valid=1|0 and reasons, from samples inside the probe's workload window.
#  - variants base, tbp (--timer-res-1), nosamp (--no-dwm-sampler), interleaved per round.
# Disturbed runs are logged with valid=0 and are never removed from the result file.
param(
    [int]$Runs = 10,
    [string]$Bin = 'D:\Claude\sr0b-frame-clock\b4\scratch-b4m\out\Products\Release-windows-x86_64',
    [string]$OutFile = '',
    [int]$RkWaitSeconds = 60
)

$ErrorActionPreference = 'Continue'
$base = 'D:\Claude\sr0b-frame-clock'
$exe = Join-Path $Bin 'SwiftHost.exe'
$swiftBin = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if (-not $OutFile) { $OutFile = "$base\result-desktop-v3-$stamp.txt" }
$runRoot = "$base\runs-b4\$stamp"
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
    public int ProbeCloaked;
    public int OnCurrentDesktop;
    public int HitPct;
    public string FgGeom;
    public string[] Occluders;
}

[ComImport, Guid("a5cd92ff-29be-454c-8d04-d82879fb3f1b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IVirtualDesktopManager {
    [PreserveSig] int IsWindowOnCurrentVirtualDesktop(IntPtr h, [MarshalAs(UnmanagedType.Bool)] out bool on);
    [PreserveSig] int GetWindowDesktopId(IntPtr h, out Guid id);
    [PreserveSig] int MoveWindowToDesktop(IntPtr h, ref Guid id);
}

[ComImport, Guid("aa509086-5ca9-4c25-8f95-589d3c07b48a")]
public class VirtualDesktopManagerCls { }

public static class SR0Probe {
    public delegate bool EnumWinProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

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
    [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")] public static extern int DwmGetWindowAttributeRect(IntPtr hWnd, int attribute, out RECT rect, int size);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hWnd, uint flags);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);

    static IVirtualDesktopManager vdm;

    public static bool InitVirtualDesktops() {
        try { vdm = (IVirtualDesktopManager)new VirtualDesktopManagerCls(); return true; }
        catch (Exception) { vdm = null; return false; }
    }

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

    // DWMWA_CLOAKED mask of the probe itself; -1 when the probe is unknown or the call fails.
    public static int ProbeCloak(IntPtr probe) {
        if (probe == IntPtr.Zero) return -1;
        int c;
        if (DwmGetWindowAttribute(probe, 14, out c, 4) != 0) return -1;
        return c;
    }

    // 1 = on the current virtual desktop, 0 = not, -1 = unknown (COM unavailable or call failed).
    public static int OnCurrentDesktop(IntPtr probe) {
        if (probe == IntPtr.Zero || vdm == null) return -1;
        bool on;
        if (vdm.IsWindowOnCurrentVirtualDesktop(probe, out on) != 0) return -1;
        return on ? 1 : 0;
    }

    // Percent of a 7x5 grid over the probe window rect whose WindowFromPoint root is the probe.
    public static int HitPercent(IntPtr probe) {
        if (probe == IntPtr.Zero) return -1;
        RECT r;
        if (!GetWindowRect(probe, out r)) return -1;
        int hit = 0, tot = 0;
        for (int ix = 1; ix <= 7; ix++) {
            for (int iy = 1; iy <= 5; iy++) {
                POINT p;
                p.X = r.Left + (r.Right - r.Left) * ix / 8;
                p.Y = r.Top + (r.Bottom - r.Top) * iy / 6;
                IntPtr w = WindowFromPoint(p);
                tot++;
                if (w != IntPtr.Zero && GetAncestor(w, 2) == probe) hit++;
            }
        }
        return hit * 100 / tot;
    }

    // Foreground window geometry: physical rect | ex-style | extended frame bounds.
    public static string FgGeometry(IntPtr fg) {
        RECT r;
        string rect = "NA";
        if (GetWindowRect(fg, out r)) rect = r.Left + "," + r.Top + "," + r.Right + "," + r.Bottom;
        int ex = GetWindowLong(fg, -20);
        RECT e;
        string efb = "NA";
        if (DwmGetWindowAttributeRect(fg, 9, out e, Marshal.SizeOf(typeof(RECT))) == 0)
            efb = e.Left + "," + e.Top + "," + e.Right + "," + e.Bottom;
        return rect + "|0x" + ((uint)ex).ToString("X") + "|" + efb;
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

    // One sample. EnumWindows walks top-down in z-order, so the walk stops at the probe.
    public static SR0Snap Take(IntPtr probe) {
        SR0Snap s = new SR0Snap();
        s.Fg = GetForegroundWindow();
        s.FgTitle = s.Fg == IntPtr.Zero ? "" : Title(s.Fg);
        s.FgProc = s.Fg == IntPtr.Zero ? "" : Proc(s.Fg);
        s.ProbeFg = probe != IntPtr.Zero && s.Fg == probe;
        s.ProbeVisible = probe != IntPtr.Zero && IsWindowVisible(probe) && !IsIconic(probe);
        s.ProbeCloaked = ProbeCloak(probe);
        s.OnCurrentDesktop = OnCurrentDesktop(probe);
        s.HitPct = HitPercent(probe);
        s.FgGeom = (s.Fg == IntPtr.Zero || s.Fg == probe) ? "-" : FgGeometry(s.Fg);
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

# Per-monitor-v2 DPI awareness before any geometry read (-4 = DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2).
$dpiOk = [SR0Probe]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))
$vdmOk = [SR0Probe]::InitVirtualDesktops()
$swFreq = [System.Diagnostics.Stopwatch]::Frequency
$inv = [Globalization.CultureInfo]::InvariantCulture

# Stopwatch ticks on this host equal QPC ticks (10 MHz). Rescale only if they ever differ.
function To-Qpc([long]$sw) {
    if ($swFreq -eq 10000000) { return $sw }
    return [long]([double]$sw * 10000000.0 / [double]$swFreq)
}

$lines = New-Object System.Collections.Generic.List[string]
function Flush-Out { [System.IO.File]::WriteAllText($OutFile, [string]::Join("`r`n", $lines)) }

$sess = (Get-Process -Id $PID).SessionId
$lines.Add("harness=run-desktop-v3 host=$env:COMPUTERNAME user=$env:USERNAME session=$sess started=$(Get-Date -Format o)")
$lines.Add("exe=$exe exists=$(Test-Path $exe) dll_beside_exe=$(Test-Path (Join-Path $Bin 'swiftright_render_probe.dll')) bin=$Bin")
$lines.Add("runs_per_variant=$Runs variants=base,tbp,nosamp rk_wait_s=$RkWaitSeconds runRoot=$runRoot")
$lines.Add("dpi_awareness_per_monitor_v2=$dpiOk vdm_available=$vdmOk stopwatch_freq=$swFreq")
Flush-Out

$variants = @(
    @{ name = 'base';   extra = @() },
    @{ name = 'tbp';    extra = @('--timer-res-1') },
    @{ name = 'nosamp'; extra = @('--no-dwm-sampler') }
)

for ($r = 1; $r -le $Runs; $r++) {
    foreach ($v in $variants) {
        $id = "$($v.name)-$r"
        $outDir = "$runRoot\$id"

        # Do not measure through another desktop test: wait for rk2* to exit, then skip the launch.
        $waited = 0
        while ((Get-Process -Name 'rk2*' -ErrorAction SilentlyContinue) -and $waited -lt $RkWaitSeconds) {
            Start-Sleep -Seconds 5
            $waited += 5
        }
        if (Get-Process -Name 'rk2*' -ErrorAction SilentlyContinue) {
            $lines.Add("skip_run id=$id reason=rk2-present waited_s=$waited")
            Flush-Out
            continue
        }

        New-Item -ItemType Directory -Force $outDir | Out-Null
        $lines.Add("=== RUN $id start=$(Get-Date -Format o)")

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exe
        $psi.Arguments = (@("--out=$outDir") + $v.extra) -join ' '
        $psi.WorkingDirectory = $Bin
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.EnvironmentVariables['Path'] = "$swiftBin;$Bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
        try { $proc = [System.Diagnostics.Process]::Start($psi) } catch { $proc = $null; $startErr = $_.Exception.Message }
        if ($null -eq $proc) {
            $lines.Add("ABORT run=$id launch failed: $startErr")
            $lines | Set-Content -Encoding utf8 $OutFile
            throw "SR0-B batch aborted: probe launch failed ($startErr)"
        }
        $startQpc = To-Qpc ([System.Diagnostics.Stopwatch]::GetTimestamp())
        $creation = 'NA'
        try { $creation = $proc.StartTime.ToUniversalTime().ToString('o') } catch { }
        $lines.Add("pid run=$id pid=$($proc.Id) start_utc=$([DateTime]::UtcNow.ToString('o')) qpc_start=$startQpc creation=$creation")
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()

        $clock = [Diagnostics.Stopwatch]::StartNew()
        $samples = 0; $visible = 0; $foreground = 0
        $occludedN = 0; $probeFgN = 0
        $fgTried = $false
        $prevKey = $null
        $interrupters = @{}
        $trace = New-Object System.Collections.Generic.List[object]
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
            $qpcS = To-Qpc ([System.Diagnostics.Stopwatch]::GetTimestamp())
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
            $occText = if ($snap.Occluders.Count -gt 0) { $snap.Occluders -join ' ; ' } else { '-' }
            $trace.Add([pscustomobject]@{
                qpc = $qpcS
                t_s = $clock.Elapsed.TotalSeconds.ToString('0.000', $inv)
                probe_fg = [int]$snap.ProbeFg
                probe_visible = [int]$snap.ProbeVisible
                probe_cloaked = $snap.ProbeCloaked
                on_current_desktop = $snap.OnCurrentDesktop
                hit_pct = $snap.HitPct
                fg = "$($snap.FgProc)|$($snap.FgTitle)"
                fg_geom = $snap.FgGeom
                occluded_by = $occText
            })

            $key = "{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}" -f $snap.Fg.ToInt64(), $snap.FgProc, $snap.FgTitle,
                [int]$snap.ProbeFg, [int]$snap.ProbeVisible, ($snap.Occluders -join ' ; '),
                $snap.ProbeCloaked, $snap.OnCurrentDesktop, $snap.HitPct, $snap.FgGeom
            if ($key -ne $prevKey) {
                $prevKey = $key
                $t = $clock.Elapsed.TotalSeconds.ToString('0.000', $inv)
                $lines.Add("change run=$id t=+${t}s fg=$($snap.FgProc)|$($snap.FgTitle) probe_fg=$([int]$snap.ProbeFg) probe_visible=$([int]$snap.ProbeVisible) occluded_by=$occText cloaked=$($snap.ProbeCloaked) cur_desktop=$($snap.OnCurrentDesktop) hit_pct=$($snap.HitPct) fg_geom=$($snap.FgGeom)")
            }
            Start-Sleep -Milliseconds 50
        }
        if (-not $proc.HasExited) { $proc.Kill(); $lines.Add('TIMEOUT: killed after 120 s') }
        $proc.WaitForExit()
        $endQpc = To-Qpc ([System.Diagnostics.Stopwatch]::GetTimestamp())
        $lines.Add("pid_exit run=$id pid=$($proc.Id) qpc_end=$endQpc exit=$($proc.ExitCode)")
        $lines.Add("focus_samples: total=$samples window_visible=$visible window_foreground=$foreground")
        $lines.Add("fg_samples=$samples probe_fg_samples=$probeFgN occluded_samples=$occludedN distinct_interrupters=$($interrupters.Count)")
        foreach ($k in ($interrupters.Keys | Sort-Object { -[int]$interrupters[$_] } | Select-Object -First 20)) {
            $lines.Add("  interrupter samples=$($interrupters[$k]) $k")
        }
        $outText = [string]$stdout.Result
        $errText = [string]$stderr.Result
        $lines.Add($outText)
        $lines.Add($errText)
        $lines.Add("exit=$($proc.ExitCode) end=$(Get-Date -Format o)")
        try { $trace | Export-Csv -NoTypeInformation -Encoding UTF8 -Path "$outDir\harness-samples.csv" } catch { $lines.Add("trace_export_failed run=$id") }

        # Validity from samples inside the probe's own workload window (window_ticks, same QPC clock).
        $reasons = New-Object System.Collections.Generic.List[string]
        $ws = $null; $we = $null
        if ($outText -match 'window_ticks ws=(\d+) we=(\d+)') { $ws = [long]$Matches[1]; $we = [long]$Matches[2] }
        $wl = @()
        if ($null -ne $ws) { $wl = @($trace | Where-Object { $_.qpc -ge $ws -and $_.qpc -le $we }) }
        $nWl = $wl.Count
        $fgN = 0; $minHit = -1; $hitMin = 'NA'
        if ($null -eq $ws) { $reasons.Add('no-window-ticks') }
        elseif ($nWl -lt 80) { $reasons.Add('sparse-samples') }
        if ($nWl -gt 0) {
            $fgN = @($wl | Where-Object { $_.probe_fg -eq 1 }).Count
            if ($fgN -lt $nWl) { $reasons.Add('probe_fg<100%') }
            if (@($wl | Where-Object { $_.probe_cloaked -gt 0 }).Count -gt 0) { $reasons.Add('cloaked') }
            if (@($wl | Where-Object { $_.on_current_desktop -eq 0 }).Count -gt 0) { $reasons.Add('off_desktop') }
            if (@($wl | Where-Object { $_.on_current_desktop -lt 0 }).Count -gt 0) { $reasons.Add('vdm_unknown') }
            if (@($wl | Where-Object { $_.occluded_by -ne '-' }).Count -gt 0) { $reasons.Add('occluded') }
            $minHit = ($wl | ForEach-Object { [int]$_.hit_pct } | Measure-Object -Minimum).Minimum
            $hitMin = $minHit
            if ($minHit -lt 95) { $reasons.Add('hit<95') }
        }
        $valid = if ($reasons.Count -eq 0) { 1 } else { 0 }
        $reasonText = if ($reasons.Count -eq 0) { '-' } else { $reasons -join '+' }
        $lines.Add("run_state id=$id valid=$valid reason=$reasonText workload_samples=$nWl probe_fg_wl=$fgN hit_min_wl=$hitMin ws=$ws we=$we")
        Flush-Out
    }
}

$lines.Add("finished=$(Get-Date -Format o)")
Flush-Out
Write-Host "wrote $OutFile"
