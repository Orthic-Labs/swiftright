# SR0 workload harness (Windows). Runs inside the INTERACTIVE desktop session (registered as a one-shot task by
# run-workload.ps1; the renderer needs a real desktop). For each run: launch WorkloadWin.exe (release, no debugger),
# bring its window to the foreground, POST the keystroke script (WM_CHAR via PostMessage to the workload HWND only, no global
# input API) on the QPC clock (10 keys/s; foreground is kept only so the window is unoccluded for PresentMon, and a foreground
# loss that cannot be recovered aborts the script and voids the run), wait for the self-timed run to finish (10 s warm-up +
# 60 s measured + teardown), record pid / QPC start / QPC end for the PresentMon PID join.
#
# R10 (normal-use host): the foreground is no longer required, taken or fought for (see Run() and the acquire block below); foreground owners, user
#   input (GetLastInputInfo), a minimized window, overlay hooks in the workload process and the host's CPU by process are recorded as CONTEXT lines
#   (`fg_event`, `activity`/activity.csv, `context`, `host_top`); no run is voided for them.
# R10 harness fixes (first real run, 20261009-212322-full):
#   * Keys: a physical key is three messages (WM_KEYDOWN, WM_CHAR, WM_KEYUP) but the renderer's loop translates WM_KEYDOWN into a
#     WM_CHAR itself, so posting all three typed every key twice (injected 47, typed 94). Only WM_CHAR is posted by default
#     (-KeyMode char), the mode the SR0-S fixture matrix validated (probes/sr0-s/fresh-on-bridge/RESULT.md, "Targeted key delivery").
#   * Foreground: acquired by a retry loop with backoff, only once the window is visible and answering messages (a window whose UI
#     thread is blocked cannot take the foreground and, after 5 s of silence, Windows replaces it with a "Not Responding" ghost,
#     which is what took the foreground from r1 at 4.7 s). Every failed attempt and every loss records who holds the foreground
#     (pid, process, class, title) and whether the workload window was hung. A loss during the key script is re-acquired within
#     ~200 ms before the next key; if that fails the script aborts as before (fg_lost=1). Recovered losses are written to
#     fg_events.csv, the `fg_event` result lines, and the fg_event column of inject.csv (the analyzer ignores the extra column).
#   * Window-targeted input only: the foreground calls below never inject input; keys only ever go to the workload HWND.
# R10 stress + resource additions:
#   * -Rows N (default 200) is passed to the app as `--rows N` (the app reports the row count it ran with in meta.json total_rows; the analyzer
#     voids a run whose app did not honour it). -KeyRate K (default 10, alias -RateHz) is the PostMessage rate; it is the harness's, the app has no key-rate arg.
#   * Keys stop at process start + warm-up + measured - KeyTailS (default 0.5 s). The app's t0 follows its launch by ~0.57 s and it requests its own
#     window close on the first tick after t0 + 70 s, so the last key lands ~1.1 s before the close. Before this, r2 of 20261009-224605-full posted its
#     694th key 21.9 ms AFTER the app had asked to close (it was never delivered to the app: renderer events_pushed 695 = 693 typed + 2 setup events).
#   * One resource sampler process per run (sample-resources.ps1: CPU, per-thread CPU, memory, GPU engines per adapter) writes <run>\resources.csv.
#     -NoResources skips it (overhead A/B baseline). The sampler runs at BelowNormal priority with no window and reports its own CPU in every row.
# Result file lines (parsed by analyze_workload.py): "=== RUN <id>", "pid run=", "pid_exit run=", "inject run=", "host ...", "exe= ... rows= rate_hz=".
param(
  [string]$Base = 'D:\Claude\sr0b-workload',
  [string]$ControlRoot = '',
  [Parameter(Mandatory)][string]$DrainHelperPath,
  [Parameter(Mandatory)][string]$DrainHelperSha256,
  [string]$RunRoot = 'D:\Claude\sr0b-workload\runs\manual',
  [string]$ResultFile = 'D:\Claude\sr0b-workload\runs\manual\result-workload.txt',
  [int]$Runs = 3,
  [int]$Warmup = 10,
  [int]$Measure = 60,
  [string]$Instr = 'full',
  [Alias('RateHz')][double]$KeyRate = 10,                   # keys per second posted to the workload window (10 default; stress series also 30)
  [int]$Rows = 200,                                         # total editable rows the app runs with (200 default; stress series also 1000, 5000)
  [double]$KeyTailS = 0.5,                                  # keys stop this long before the nominal run end (process start + warm-up + measured)
  [switch]$NoResources,                                     # skip the resource sampler (overhead A/B)
  [string]$PaintPhaseMs = '',                               # R10: SWR_PAINT_PHASE_MS for the renderer (A/B: 0 = pacing off); '' leaves the renderer default
  [switch]$MemDeep,                                         # R10 memory diagnosis: SWR_MEM_DEEP=1 (the renderer also walks the process heaps and address space every 5th memory sample; slow, never a gated run)
  [string]$RunPrefix = 'r',
  [ValidateSet('char', 'all')][string]$KeyMode = 'char',   # char: WM_CHAR only; all: WM_KEYDOWN + WM_CHAR + WM_KEYUP (types every key twice)
  [int]$ForegroundSeconds = 8,                              # how long to keep trying to take the foreground (inside the 10 s warm-up) before the run is voided
  [switch]$LifecycleProof,                                      # tuple12 opt-in: retain process/sampler terminal proof
  [switch]$NoActivate                                           # tuple12 v5: require startup guard + HWND_BOTTOM/SWP_NOACTIVATE
)
$ErrorActionPreference = 'Continue'
$sha256Pattern='^[0-9a-fA-F]{64}$';if($DrainHelperSha256 -notmatch $sha256Pattern){throw 'drain helper SHA-256 required'};if(-not(Test-Path -LiteralPath $DrainHelperPath -PathType Leaf)){throw 'drain helper missing'};$drainHelperFull=[IO.Path]::GetFullPath($DrainHelperPath);$drainHelperItem=Get-Item -LiteralPath $drainHelperFull -Force;if(($drainHelperItem.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $drainHelperItem.Length -gt 131072){throw 'drain helper must be bounded non-reparse file'};if((Get-FileHash -LiteralPath $drainHelperFull -Algorithm SHA256).Hash.ToLowerInvariant() -cne $DrainHelperSha256.ToLowerInvariant()){throw 'drain helper hash mismatch'};. $drainHelperFull
$swiftBin = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin'
$controlRoot = if ($ControlRoot) { [IO.Path]::GetFullPath($ControlRoot) } else { $PSScriptRoot }
$b = Get-Content -Raw "$Base\build.json" | ConvertFrom-Json
$bin = Split-Path $b.exe
$exe = "$bin\WorkloadWin.exe"
New-Item -ItemType Directory -Force $RunRoot | Out-Null

Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class Inj {
    [DllImport("user32.dll", SetLastError = true)] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern uint MapVirtualKey(uint code, uint type);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll", SetLastError = true)] static extern bool SetWindowPos(IntPtr h, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool AllowSetForegroundWindow(int pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsHungAppWindow(IntPtr h);
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SendMessageTimeout(IntPtr h, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    public static int WindowPid(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return (int)p; }
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    public static long SignedDword(uint code) { return unchecked((int)code); }
    public static bool Terminal(IntPtr h, Process p, out uint code) { code = 259; try { p.Refresh(); if (!p.HasExited) return false; if (!GetExitCodeProcess(h, out code)) return false; return code != 259; } catch { return false; } }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
    [DllImport("kernel32.dll")] static extern uint GetTickCount();
    [StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    public static long IdleMs() { uint li = LastInputTick(); return li == 0 ? -1 : (long)unchecked(GetTickCount() - li); }
    static uint LastInputTick() { LASTINPUTINFO i = new LASTINPUTINFO(); i.cbSize = 8; return GetLastInputInfo(ref i) ? i.dwTime : 0; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

    public static int InputSize() { return 0; } // no SendInput: keys are POSTED to the workload HWND only

    public static bool Visible(IntPtr hwnd) { return hwnd != IntPtr.Zero && IsWindow(hwnd) && IsWindowVisible(hwnd); }

    // True when the window's UI thread answers a WM_NULL within ms (SMTO_ABORTIFHUNG): it can take part in foreground changes.
    public static bool Responsive(IntPtr hwnd, uint ms) {
        IntPtr r;
        return SendMessageTimeout(hwnd, 0, IntPtr.Zero, IntPtr.Zero, 2, ms, out r) != IntPtr.Zero;
    }

    public static bool Hung(IntPtr hwnd) { return hwnd != IntPtr.Zero && IsHungAppWindow(hwnd); }

    // HWND_BOTTOM + SWP_NOACTIVATE keeps this workload behind other windows without synthesizing input.
    // This is a post-HWND guard; caller records startup activation as unproven until a host CBT guard is bound.
    public static bool BottomNoActivate(IntPtr hwnd, out RECT client) {
        client = new RECT();
        if (!Visible(hwnd) || !GetClientRect(hwnd, out client) || client.Right <= 0 || client.Bottom <= 0) return false;
        const uint SWP_NOSIZE = 0x0001, SWP_NOMOVE = 0x0002, SWP_NOACTIVATE = 0x0010, SWP_SHOWWINDOW = 0x0040;
        ShowWindow(hwnd, 4); // SW_SHOWNOACTIVATE; return value is previous visibility, not success.
        return SetWindowPos(hwnd, (IntPtr)1, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }

    // Who holds a window: "hwnd=.. pid=.. name=.. class=.. title='..'" (the foreground owner when a take-over fails or a loss happens).
    public static string Owner(IntPtr h) {
        if (h == IntPtr.Zero) return "none";
        uint pid;
        GetWindowThreadProcessId(h, out pid);
        string name = "?";
        try { name = Process.GetProcessById((int)pid).ProcessName; } catch (Exception) { }
        StringBuilder cls = new StringBuilder(128);
        StringBuilder title = new StringBuilder(128);
        GetClassName(h, cls, 128);
        GetWindowText(h, title, 128);
        return "hwnd=" + h.ToInt64() + " pid=" + pid + " name=" + name + " class=" + cls + " title='" + title.ToString().Replace("'", "") + "'";
    }

    public static string ForegroundOwner() { return Owner(GetForegroundWindow()); }

    // One take-over attempt, strongest strategy last. Returns the strategy that worked or "failed". Never injects input.
    public static string Foreground(IntPtr hwnd, int pid) {
        if (hwnd == IntPtr.Zero) return "no-hwnd";
        if (IsIconic(hwnd)) ShowWindow(hwnd, 9);
        if (GetForegroundWindow() == hwnd) return "already";
        if (SetForegroundWindow(hwnd) && GetForegroundWindow() == hwnd) return "direct";
        AllowSetForegroundWindow(pid);
        if (SetForegroundWindow(hwnd) && GetForegroundWindow() == hwnd) return "allow";
        uint me = GetCurrentThreadId();
        uint fgPid;
        uint fgThread = GetWindowThreadProcessId(GetForegroundWindow(), out fgPid);
        uint tgtPid;
        uint tgtThread = GetWindowThreadProcessId(hwnd, out tgtPid);
        // Share input state with the current foreground thread (and the target's own) for the duration of the call.
        bool attachedFg = fgThread != 0 && fgThread != me && AttachThreadInput(me, fgThread, true);
        bool attachedTgt = tgtThread != 0 && tgtThread != me && tgtThread != fgThread && AttachThreadInput(me, tgtThread, true);
        try { BringWindowToTop(hwnd); SetForegroundWindow(hwnd); }
        finally {
            if (attachedTgt) AttachThreadInput(me, tgtThread, false);
            if (attachedFg) AttachThreadInput(me, fgThread, false);
        }
        if (GetForegroundWindow() == hwnd) return "attach";
        // Minimise and restore: restoring activates the window through the same take-over rules but from the window's own state.
        ShowWindow(hwnd, 6);
        ShowWindow(hwnd, 9);
        SetForegroundWindow(hwnd);
        return GetForegroundWindow() == hwnd ? "restore" : "failed";
    }

    // Takes the foreground with retries and backoff (50 ms doubling to 1 s) for at most totalMs. Waits for the window to be
    // visible and answering messages before each try. Appends one line per attempt to `log` (including who holds the foreground
    // when it fails) and returns the strategy that worked, or "failed".
    public static string Acquire(IntPtr hwnd, int pid, int totalMs, StringBuilder log) {
        long t0 = Stopwatch.GetTimestamp();
        double hz = Stopwatch.Frequency;
        int wait = 50;
        int attempt = 0;
        while (true) {
            attempt++;
            double ms = (Stopwatch.GetTimestamp() - t0) * 1000.0 / hz;
            bool visible = Visible(hwnd);
            bool responsive = visible && Responsive(hwnd, 300);
            string how = "skipped-unresponsive";
            if (!IsWindow(hwnd)) { log.AppendLine("attempt=" + attempt + " t_ms=" + (long)ms + " window=gone"); return "no-window"; }
            if (visible && responsive) how = Foreground(hwnd, pid);
            log.AppendLine("attempt=" + attempt + " t_ms=" + (long)ms + " visible=" + (visible ? 1 : 0) + " responsive=" + (responsive ? 1 : 0)
                + " hung=" + (Hung(hwnd) ? 1 : 0) + " result=" + how + (how == "failed" || how.StartsWith("skipped") ? " fg=[" + ForegroundOwner() + "]" : ""));
            if (how != "failed" && !how.StartsWith("skipped")) return how;
            if ((Stopwatch.GetTimestamp() - t0) * 1000.0 / hz + wait > totalMs) return "failed";
            Thread.Sleep(wait);
            wait = Math.Min(wait * 2, 1000);
        }
    }

    // The three messages a physical key produces, POSTED to the workload window only (as drive-fixture.ps1 'targeted'):
    // no keystroke can reach another application whatever has focus. Returns true when all three were queued.
    // mode "char" posts WM_CHAR only (one text-store replace per key); "all" posts the three messages of a physical key, which the
    // renderer's loop turns into two characters.
    static bool PostKey(IntPtr hwnd, ushort vk, char ch, bool all) {
        uint scan = MapVirtualKey(vk, 0);
        IntPtr down = (IntPtr)(1L | ((long)scan << 16));
        IntPtr up = (IntPtr)(1L | ((long)scan << 16) | 0x40000000L | 0x80000000L);
        bool a = !all || PostMessage(hwnd, 0x0100, (IntPtr)vk, down);
        bool b = PostMessage(hwnd, 0x0102, (IntPtr)ch, down);
        bool c = !all || PostMessage(hwnd, 0x0101, (IntPtr)vk, up);
        return a && b && c;
    }

    // Posts `chars` cyclically at rateHz for maxSeconds, each key on an absolute schedule from the first key. The QPC
    // timestamp is taken immediately BEFORE the key's PostMessage (the event timestamp of CONTRACT section 5).
    // Keys are window-targeted, so the foreground is NOT required and is never fought for here (the machine is in normal use: the user's own
    // windows come and go). Foreground changes, user input (GetLastInputInfo; our PostMessage keys do not count as input) and a minimized window
    // are RECORDED as context at every key: eventsPath (foreground owner changes), activityPath (one row per key). Nothing here aborts the script.
    // deadlineQpc > 0: no key is posted whose due time is after it (keys never reach a window the app is already closing).
    public static string Run(IntPtr hwnd, int pid, double rateHz, double maxSeconds, string outPath, string chars, string eventsPath, bool allMessages, long deadlineQpc, string activityPath) {
        if (WindowPid(hwnd) != pid) return "sent=0 fg_lost=0 send_fail=0 fg_events=0 fg_recovered=0 stop=window-owner-mismatch user_input_events=0 min_idle_ms=-1 minimized_samples=0";
        double hz = Stopwatch.Frequency;
        long step = (long)(hz / rateHz);
        long start = Stopwatch.GetTimestamp() + (long)(0.2 * hz);
        long limit = (long)(maxSeconds * hz);
        StringBuilder sb = new StringBuilder();
        StringBuilder ev = new StringBuilder();
        StringBuilder act = new StringBuilder();
        sb.Append("seq,char,qpc_before,qpc_after,sent,fg_ok,fg_event\n");
        ev.Append("seq,qpc,recovered,hung,responsive,owner\n");
        act.Append("seq,qpc,idle_ms,fg_ours,iconic\n");
        int seq = 0, sendFail = 0, events = 0, userInput = 0, minimized = 0;
        uint minIdle = uint.MaxValue;
        uint lastInput = LastInputTick();
        IntPtr lastFg = GetForegroundWindow();
        string stop = "limit";
        while (true) {
            long due = start + (long)seq * step;
            if (due - start > limit) break;
            if (deadlineQpc > 0 && due > deadlineQpc) { stop = "deadline"; break; }
            while (true) {
                long rem = due - Stopwatch.GetTimestamp();
                if (rem <= 0) break;
                if (rem > (long)(0.016 * hz)) Thread.Sleep(8); else Thread.SpinWait(40);
            }
            if (!IsWindow(hwnd)) { stop = "window-gone"; break; }
            IntPtr fg = GetForegroundWindow();
            uint li = LastInputTick();
            uint idle = unchecked(GetTickCount() - li);
            bool iconic = IsIconic(hwnd);
            if (li != lastInput) { userInput++; lastInput = li; }
            if (idle < minIdle) minIdle = idle;
            if (iconic) minimized++;
            int fgEvent = 0;
            if (fg != lastFg) {
                fgEvent = 1;
                events++;
                string owner = "?";
                try { owner = fg == hwnd ? "workload-window (regained)" : ForegroundOwner(); } catch (Exception) { }
                ev.Append(seq + "," + Stopwatch.GetTimestamp() + ",0," + (Hung(hwnd) ? 1 : 0) + ",1,\"" + owner + "\"\n");
                lastFg = fg;
            }
            act.Append(seq + "," + Stopwatch.GetTimestamp() + "," + idle + "," + (fg == hwnd ? 1 : 0) + "," + (iconic ? 1 : 0) + "\n");
            char c = chars[seq % chars.Length];
            ushort vk = (ushort)char.ToUpperInvariant(c);
            long before = Stopwatch.GetTimestamp();
            bool posted = PostKey(hwnd, vk, c, allMessages);
            long after = Stopwatch.GetTimestamp();
            uint n = posted ? 1u : 0u;
            if (!posted) sendFail++;
            sb.Append(seq + "," + c + "," + before + "," + after + "," + n + ",1," + fgEvent + "\n");
            seq++;
        }
        File.WriteAllText(outPath, sb.ToString());
        File.WriteAllText(eventsPath, ev.ToString());
        File.WriteAllText(activityPath, act.ToString());
        return "sent=" + seq + " fg_lost=0 send_fail=" + sendFail + " fg_events=" + events + " fg_recovered=0 stop=" + stop
            + " user_input_events=" + userInput + " min_idle_ms=" + (minIdle == uint.MaxValue ? -1 : (long)minIdle) + " minimized_samples=" + minimized;
    }
}
'@

[void][Inj]::SetProcessDpiAwarenessContext([IntPtr]-4)
$swFreq = [System.Diagnostics.Stopwatch]::Frequency
$lines = New-Object System.Collections.Generic.List[string]
function Flush-Out { [System.IO.File]::WriteAllText($ResultFile, [string]::Join("`r`n", $lines)) }
# The display hangs off the controller with an active mode (hybrid laptop: the first controller, the dGPU, reports no mode).
$vcs = @(Get-CimInstance Win32_VideoController)
$vc = $vcs | Where-Object { $_.CurrentRefreshRate } | Select-Object -First 1
if (-not $vc) { $vc = $vcs | Select-Object -First 1 }
$lines.Add("harness=task-workload host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) started=$(Get-Date -Format o)")
$lines.Add("host qpc_freq=$swFreq input_struct=$([Inj]::InputSize()) gpu=$($vc.Name) driver=$($vc.DriverVersion) refresh_hz=$($vc.CurrentRefreshRate) res=$($vc.CurrentHorizontalResolution)x$($vc.CurrentVerticalResolution)")
foreach ($c in $vcs) { $lines.Add("controller name=$($c.Name) driver=$($c.DriverVersion) refresh_hz=$($c.CurrentRefreshRate) res=$($c.CurrentHorizontalResolution)x$($c.CurrentVerticalResolution)") }
$lines.Add("exe=$exe exe_sha256=$($b.exe_sha256) dll_sha256=$($b.dll_sha256) instr=$Instr runs=$Runs warmup_s=$Warmup measure_s=$Measure rate_hz=$KeyRate rows=$Rows key_tail_s=$KeyTailS resources=$(if ($NoResources) { 'off' } else { 'on' }) key_mode=$KeyMode foreground_s=$ForegroundSeconds paint_phase_ms=$(if ($PaintPhaseMs -eq '') { 'default' } else { $PaintPhaseMs })")
$lines.Add("power=$((powercfg /getactivescheme) -join ' ')")
Flush-Out
$chars = 'mwqogdhbnk'
function Get-CpuMap {
  $m = @{}
  foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
    try { $m[$p.Id] = [pscustomobject]@{ Name = $p.ProcessName; Cpu = $p.TotalProcessorTime.TotalSeconds } } catch { }
  }
  return $m
}
# Overlay / capture-hook context for one process: loaded module names that match a known overlay or injection pattern, and running helper processes.
function Get-OverlayContext([int]$ProcId) {
  $mods = @()
  try { $mods = @((Get-Process -Id $ProcId -ErrorAction Stop).Modules | ForEach-Object { $_.ModuleName }) } catch { }
  $hit = @($mods | Where-Object { $_ -match 'nvspcap|nvoverlay|nvtelemetry|overlay|rtss|reshade|discord|obs-?(graphics|vulkan)|nvcamera|nvshare|nvinject|vkbasalt|steam|nvngx_update|NvCameraAllowlisting' } | Sort-Object -Unique)
  $procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'NVIDIA (Overlay|Share|app)|nvcontainer|NVDisplay\.Container|GeForceExperience|RTSS|Discord|obs64|^Steam$|MSIAfterburner' } | ForEach-Object { $_.ProcessName } | Sort-Object -Unique)
  [pscustomobject]@{ total = $mods.Count; hits = ($hit -join ','); procs = ($procs -join ','); all = $mods }
}
$okRuns = 0
$workerTerminalAll = $true
$samplerTerminalAll = $true
for ($i = 1; $i -le $Runs; $i++) {
  $id = "$RunPrefix$i"
  $dir = "$RunRoot\$id"
  New-Item -ItemType Directory -Force $dir | Out-Null
  $lines.Add("=== RUN $id start=$(Get-Date -Format o)")
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  $noActivateArgs = if ($NoActivate) { ' --sr0-noactivate' } else { '' }
  $psi.Arguments = "--run-id $id --out `"$dir`" --warmup-s $Warmup --measure-s $Measure --instr $Instr --rows $Rows$noActivateArgs"
  $psi.WorkingDirectory = $bin
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables['Path'] = "$swiftBin;$bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
  # Renderer knobs travel through the child's environment (the scheduled task does not inherit the orchestrator's). The renderer prints
  # what it read on stderr ("paint pacing on/off ...", stderr.txt); the analyzer-side receipt is the `exe=` line above.
  if ($PaintPhaseMs -ne '') { $psi.EnvironmentVariables['SWR_PAINT_PHASE_MS'] = $PaintPhaseMs } else { [void]$psi.EnvironmentVariables.Remove('SWR_PAINT_PHASE_MS') }
  $psi.EnvironmentVariables['SWR_FRAME_LOG'] = "$dir\render-frames.csv"
  if ($MemDeep) { $psi.EnvironmentVariables['SWR_MEM_DEEP'] = '1' } else { [void]$psi.EnvironmentVariables.Remove('SWR_MEM_DEEP') }
  if ($NoActivate -and $psi.Arguments -notmatch '(?i)--sr0-noactivate(?:\s|"|$)') { throw 'NoActivate startup guard argument missing' }
  $qs = [System.Diagnostics.Stopwatch]::GetTimestamp()
  $proc = [System.Diagnostics.Process]::Start($psi)
  $workerHandle = $proc.Handle
  $workerFullPath = try { $proc.MainModule.FileName } catch { $exe }
  $lines.Add("worker run=$id pid=$($proc.Id) parent_pid=$PID full_path=$workerFullPath")
  $so = $proc.StandardOutput.ReadToEndAsync()
  $se = $proc.StandardError.ReadToEndAsync()
  $lines.Add("host_startup_guard run=$id result=$(if ($NoActivate) { 'PASS' } else { 'not-requested' }) arg=$(if ($NoActivate) { '--sr0-noactivate' } else { 'none' })")
  $lines.Add("pid run=$id pid=$($proc.Id) handle=$workerHandle start_utc=$([DateTime]::UtcNow.ToString('o')) qpc_start=$qs")
  $sampler = $null; $samplerHandle = [IntPtr]::Zero; $samplerOut = $null; $samplerErr = $null
  if (-not $NoResources) {
    # No window, BelowNormal priority: it must not take the foreground or compete with the workload. Its own CPU is a column of every row.
    $ssi = New-Object System.Diagnostics.ProcessStartInfo
    $ssi.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $ssi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$controlRoot\sample-resources.ps1`" -TargetPid $($proc.Id) -OutDir `"$dir`" -RunId $id -StopFile `"$dir\sampler.stop`" -MaxSeconds $($Warmup + $Measure + 120)"
    $ssi.UseShellExecute = $false; $ssi.CreateNoWindow = $true; $ssi.RedirectStandardOutput = $true; $ssi.RedirectStandardError = $true
    $ssi.WorkingDirectory = $dir
    try {
      $sampler = [System.Diagnostics.Process]::Start($ssi)
      $samplerHandle = $sampler.Handle
      try { $sampler.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal } catch { }
      $samplerOut = $sampler.StandardOutput.ReadToEndAsync()
      $samplerErr = $sampler.StandardError.ReadToEndAsync()
      $lines.Add("sampler run=$id pid=$($sampler.Id) handle=$samplerHandle target=$($proc.Id)")
    } catch { $samplerTerminalAll = $false; $lines.Add("sampler run=$id start_failed=$($_.Exception.Message)"); $sampler = $null }
  }
  $hwnd = [IntPtr]::Zero
  for ($k = 0; $k -lt 120 -and $hwnd -eq [IntPtr]::Zero -and -not $proc.HasExited; $k++) { Start-Sleep -Milliseconds 250; $proc.Refresh(); $hwnd = $proc.MainWindowHandle }
  $valid = $true; $reason = 'ok'
  if ($hwnd -eq [IntPtr]::Zero) { $valid = $false; $reason = 'no-window' }
  else {
    # Shown and answering messages (three consecutive 300 ms probes): a window whose UI thread is blocked cannot be activated.
    $answers = 0
    for ($k = 0; $k -lt 80 -and $answers -lt 3 -and -not $proc.HasExited; $k++) {
      if ([Inj]::Visible($hwnd) -and [Inj]::Responsive($hwnd, 300)) { $answers++ } else { $answers = 0; Start-Sleep -Milliseconds 250 }
    }
    $lines.Add("window_ready run=$id visible=$([int][Inj]::Visible($hwnd)) consecutive_answers=$answers hung=$([int][Inj]::Hung($hwnd)) after_ms=$([int](([System.Diagnostics.Stopwatch]::GetTimestamp() - $qs) * 1000 / $swFreq))")
    Start-Sleep -Milliseconds 500
    # R10: the Dell is in normal use. Keys are posted to this window's HWND, so the foreground is not needed for delivery: take it ONCE, best effort
    # (2 s budget), and only when the user has not touched the keyboard or mouse in the last 2 s (a take-over would eat their next keystrokes). No
    # failure here voids the run; the foreground owner is then recorded as context (fg_event lines, activity.csv).
    $acqLog = New-Object System.Text.StringBuilder
    $idle0 = [Inj]::IdleMs()
    $rc = New-Object Inj+RECT
    $backgroundNoActivate = if ($NoActivate) { 'pending' } else { 'not-requested' }
    if ($NoActivate) {
      $backgroundNoActivate = if ([Inj]::BottomNoActivate($hwnd, [ref]$rc)) { 'PASS' } else { 'FAIL' }
      $fg = 'noactivate-background'
      $lines.Add("background_noactivate run=$id result=$backgroundNoActivate startup_activation=guarded zorder=HWND_BOTTOM")
      if ($backgroundNoActivate -ne 'PASS') { $valid = $false; $reason = 'background-noactivate-failed' }
    } else {
      $fg = if ($idle0 -ge 0 -and $idle0 -lt 2000) { 'skipped-user-active' } else { [Inj]::Acquire($hwnd, $proc.Id, 2000, $acqLog) }
      foreach ($l in ($acqLog.ToString() -split "`r?`n" | Where-Object { $_ })) { $lines.Add("fg_attempt run=$id $l") }
      [void][Inj]::GetClientRect($hwnd, [ref]$rc)
    }
    $dpi = [Inj]::GetDpiForWindow($hwnd)
    $lines.Add("window run=$id hwnd=$($hwnd.ToInt64()) foreground=$fg background_noactivate=$backgroundNoActivate dpi=$dpi client_px=$($rc.Right)x$($rc.Bottom) user_idle_ms=$idle0")
    # Context: overlay hooks in our process, overlay/capture helper processes, and the host's CPU by process over the key script.
    $ctx0 = Get-OverlayContext $proc.Id
    $lines.Add("context run=$id phase=pre overlay_modules=$(if ($ctx0.hits) { $ctx0.hits } else { 'none' }) modules_total=$($ctx0.total) overlay_procs=$(if ($ctx0.procs) { $ctx0.procs } else { 'none' })")
    $cpuA = Get-CpuMap; $tA = [System.Diagnostics.Stopwatch]::GetTimestamp()
    # Keys from now until the run ends (warm-up + measured + margin); the analyzer keeps those inside the measured window.
    $keyDeadline = $qs + [long](($Warmup + $Measure - $KeyTailS) * $swFreq)
    # A failed noactivate guard records failure & executes zero-duration Run, so no targeted input is sent.
    $runSeconds = if ($backgroundNoActivate -eq 'FAIL') { -1 } else { $Warmup + $Measure + 6 }
    $res = [Inj]::Run($hwnd, $proc.Id, [math]::Max($KeyRate, 1), $runSeconds, "$dir\inject.csv", $chars, "$dir\fg_events.csv", ($KeyMode -eq 'all'), $keyDeadline, "$dir\activity.csv")
    $lines.Add("inject run=$id $res csv=$dir\inject.csv key_mode=$KeyMode rate_hz=$KeyRate key_deadline_ms_from_start=$([int](($keyDeadline - $qs) * 1000 / $swFreq))")
    foreach ($l in (Get-Content "$dir\fg_events.csv" -ErrorAction SilentlyContinue | Select-Object -Skip 1)) { $lines.Add("fg_event run=$id $l") }
    if ($LifecycleProof -and $res -match 'window-owner-mismatch') { $valid = $false; if ($reason -eq 'ok') { $reason = 'window-owner-mismatch' } }
    $cpuB = Get-CpuMap; $spanS = ([System.Diagnostics.Stopwatch]::GetTimestamp() - $tA) / $swFreq
    $ctx1 = Get-OverlayContext $proc.Id
    $lines.Add("context run=$id phase=post overlay_modules=$(if ($ctx1.hits) { $ctx1.hits } else { 'none' }) modules_total=$($ctx1.total) overlay_procs=$(if ($ctx1.procs) { $ctx1.procs } else { 'none' })")
    try { Set-Content -Path "$dir\modules.txt" -Value $ctx1.all -Encoding ascii } catch { }
    $topRows = foreach ($k in $cpuA.Keys) {
      if ($cpuB.ContainsKey($k) -and $cpuB[$k].Name -eq $cpuA[$k].Name -and $k -ne $proc.Id) {
        [pscustomobject]@{ Name = $cpuA[$k].Name; Id = $k; Pct = [math]::Round(($cpuB[$k].Cpu - $cpuA[$k].Cpu) / ($spanS * [Environment]::ProcessorCount) * 100, 2) }
      }
    }
    $top = @($topRows | Sort-Object Pct -Descending | Select-Object -First 6 | ForEach-Object { "$($_.Name)($($_.Id)):$($_.Pct)" }) -join ';'
    $lines.Add("host_top run=$id span_s=$([math]::Round($spanS, 1)) logical_cpus=$([Environment]::ProcessorCount) pct_of_machine_excluding_workload=$top")
  }
  $deadline = (Get-Date).AddSeconds($Warmup + $Measure + 40)
  while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
  if (-not $proc.HasExited) { $valid = $false; $reason = 'timeout-killed'; try { $proc.Kill() } catch { }; $proc.Refresh() }
  $qe = [System.Diagnostics.Stopwatch]::GetTimestamp()
  $exit = if ($proc.HasExited) { [int64]$proc.ExitCode } else { -1 }
  $kernelCode = 259; $dotnetExit = if ($proc.HasExited) { [int64]$proc.ExitCode } else { [int64]259 }; $kernelTerminal = if ($LifecycleProof) { [Inj]::Terminal($workerHandle, $proc, [ref]$kernelCode) } else { $proc.HasExited }; $kernelCodeSigned=[Inj]::SignedDword($kernelCode); $workerTerminal = $kernelTerminal -and ($kernelCode -ne 259) -and ($kernelCodeSigned -eq $dotnetExit)
  if ($LifecycleProof -and -not $workerTerminal) { $workerTerminalAll = $false; $valid = $false; if ($reason -eq 'ok') { $reason = 'worker-terminal-proof-missing' } }
  $lines.Add("pid_exit run=$id pid=$($proc.Id) handle=$workerHandle qpc_end=$qe exit=$exit kernel_terminal=$([int]$workerTerminal) kernel_exit_raw=$kernelCode kernel_exit=$kernelCodeSigned dotnet_exit=$dotnetExit")
  if ($exit -ne 0) { $valid = $false; if ($reason -eq 'ok') { $reason = "exit-$exit" } }
  if ($sampler) {
    try { Set-Content -Path "$dir\sampler.stop" -Value 'stop' -Encoding ascii } catch { }
    $samplerDrain = Complete-WorkloadDrainV1 -Process $sampler -StdoutTask $samplerOut -StderrTask $samplerErr -TimeoutSeconds 15
    if (-not $samplerDrain.processTerminal) { try { $sampler.Kill() } catch { }; $sampler.Refresh() }
    $samplerOutDrained = $samplerOut -and [bool]$samplerDrain.stdoutCompleted
    $samplerErrDrained = $samplerErr -and [bool]$samplerDrain.stderrCompleted
    if ($LifecycleProof -and (-not $samplerOutDrained -or -not $samplerErrDrained)) { $samplerTerminalAll = $false; $valid = $false; if ($reason -eq 'ok') { $reason = 'sampler-stream-drain-timeout' } }
    $sOut = if ($samplerOutDrained) { $samplerOut.Result } else { '<sampler-stdout-drain-timeout>' }
    $sErr = if ($samplerErrDrained) { $samplerErr.Result } else { '<sampler-stderr-drain-timeout>' }
    [System.IO.File]::WriteAllText("$dir\sampler-stdout.txt", $sOut)
    [System.IO.File]::WriteAllText("$dir\sampler-stderr.txt", $sErr)
    $nRows = @(Get-Content "$dir\resources.csv" -ErrorAction SilentlyContinue).Count - 1
    $samplerKernelCode = 259
    $samplerDotnetExit = if ($sampler.HasExited) { [int64]$sampler.ExitCode } else { [int64]259 }; $samplerKernelTerminal = if ($LifecycleProof) { [Inj]::Terminal($samplerHandle, $sampler, [ref]$samplerKernelCode) } else { $sampler.HasExited }; $samplerKernelCodeSigned=[Inj]::SignedDword($samplerKernelCode); $samplerTerminal = $samplerKernelTerminal -and ($samplerKernelCode -ne 259) -and ($samplerKernelCodeSigned -eq $samplerDotnetExit)
    if ($LifecycleProof -and -not $samplerTerminal) { $samplerTerminalAll = $false; $valid = $false; if ($reason -eq 'ok') { $reason = 'sampler-terminal-proof-missing' } }
    $lines.Add("resources run=$id rows=$([math]::Max($nRows, 0)) sampler_exit=$(if ($samplerTerminal) { $sampler.ExitCode } else { 'running' }) sampler_kernel_terminal=$([int]$samplerTerminal) sampler_kernel_exit_raw=$samplerKernelCode sampler_kernel_exit=$samplerKernelCodeSigned sampler_dotnet_exit=$samplerDotnetExit handle=$samplerHandle stdout_drained=$([int]$samplerOutDrained) stderr_drained=$([int]$samplerErrDrained) csv=$dir\resources.csv")
  }
  $drain = Complete-WorkloadDrainV1 -Process $proc -StdoutTask $so -StderrTask $se -TimeoutSeconds 15
  $stdoutDrained = [bool]$drain.stdoutCompleted
  $stderrDrained = [bool]$drain.stderrCompleted
  if ($LifecycleProof -and (-not $stdoutDrained -or -not $stderrDrained)) { $workerTerminalAll = $false; $valid = $false; if ($reason -eq 'ok') { $reason = 'stream-drain-timeout' } }
  $stdoutText = if ($stdoutDrained) { $so.Result } else { '<stdout-drain-timeout>' }
  $stderrText = if ($stderrDrained) { $se.Result } else { '<stderr-drain-timeout>' }
  $samplerOutDrainedForLine = if ($NoResources) { $true } else { [bool]$samplerOutDrained }
  $samplerErrDrainedForLine = if ($NoResources) { $true } else { [bool]$samplerErrDrained }
  $lines.Add("stream_drains run=$id worker_stdout=$([int]$stdoutDrained) worker_stderr=$([int]$stderrDrained) sampler_stdout=$([int]$samplerOutDrainedForLine) sampler_stderr=$([int]$samplerErrDrainedForLine)")
  $lines.Add("stream_drain_diagnostics run=$id process_wait=$([int]$drain.processWaitCompleted) process_terminal=$([int]$drain.processTerminal) stdout_fault=$([int]$drain.stdoutFaulted) stderr_fault=$([int]$drain.stderrFaulted) stdout_canceled=$([int]$drain.stdoutCanceled) stderr_canceled=$([int]$drain.stderrCanceled)")
  [System.IO.File]::WriteAllText("$dir\stdout.txt", $stdoutText)
  [System.IO.File]::WriteAllText("$dir\stderr.txt", $stderrText)
  $lines.Add("run_state id=$id valid=$([int]$valid) reason=$reason")
  if ($valid) { $okRuns++ }
  Flush-Out
  Start-Sleep -Seconds 5
}
$finalText = "finished=$(Get-Date -Format o) runs_valid=$okRuns of $Runs"
if ($LifecycleProof) { $lines.Add("worker_terminal=$([int]$workerTerminalAll) sampler_terminal=$([int]$samplerTerminalAll) task_quiescent=$([int]($workerTerminalAll -and $samplerTerminalAll))") }
$lines.Add($finalText)
Flush-Out
