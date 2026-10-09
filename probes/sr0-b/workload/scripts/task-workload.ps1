# SR0 workload harness (Windows). Runs inside the INTERACTIVE desktop session (registered as a one-shot task by
# run-workload.ps1; the renderer needs a real desktop). For each run: launch WorkloadWin.exe (release, no debugger),
# bring its window to the foreground, POST the keystroke script (WM_CHAR via PostMessage to the workload HWND only, no global
# input API) on the QPC clock (10 keys/s; foreground is kept only so the window is unoccluded for PresentMon, and a foreground
# loss that cannot be recovered aborts the script and voids the run), wait for the self-timed run to finish (10 s warm-up +
# 60 s measured + teardown), record pid / QPC start / QPC end for the PresentMon PID join.
#
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
# Result file lines (parsed by analyze_workload.py): "=== RUN <id>", "pid run=", "pid_exit run=", "inject run=", "host ...".
param(
  [string]$Base = 'D:\Claude\sr0b-workload',
  [string]$RunRoot = 'D:\Claude\sr0b-workload\runs\manual',
  [string]$ResultFile = 'D:\Claude\sr0b-workload\runs\manual\result-workload.txt',
  [int]$Runs = 3,
  [int]$Warmup = 10,
  [int]$Measure = 60,
  [string]$Instr = 'full',
  [double]$RateHz = 10,
  [string]$RunPrefix = 'r',
  [ValidateSet('char', 'all')][string]$KeyMode = 'char',   # char: WM_CHAR only; all: WM_KEYDOWN + WM_CHAR + WM_KEYUP (types every key twice)
  [int]$ForegroundSeconds = 8                               # how long to keep trying to take the foreground (inside the 10 s warm-up) before the run is voided
)
$ErrorActionPreference = 'Continue'
$swiftBin = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin'
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
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

    public static int InputSize() { return 0; } // no SendInput: keys are POSTED to the workload HWND only

    public static bool Visible(IntPtr hwnd) { return hwnd != IntPtr.Zero && IsWindow(hwnd) && IsWindowVisible(hwnd); }

    // True when the window's UI thread answers a WM_NULL within ms (SMTO_ABORTIFHUNG): it can take part in foreground changes.
    public static bool Responsive(IntPtr hwnd, uint ms) {
        IntPtr r;
        return SendMessageTimeout(hwnd, 0, IntPtr.Zero, IntPtr.Zero, 2, ms, out r) != IntPtr.Zero;
    }

    public static bool Hung(IntPtr hwnd) { return hwnd != IntPtr.Zero && IsHungAppWindow(hwnd); }

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
    // Foreground is checked before each key (validity: window must stay unoccluded). A loss is logged with who holds the
    // foreground and re-acquired (three tries, 30/60/120 ms); a key goes out only with the window in the foreground, and when
    // re-acquiring fails the script aborts (fg_lost=1). Losses are written to eventsPath and marked in the key's fg_event column.
    public static string Run(IntPtr hwnd, int pid, double rateHz, double maxSeconds, string outPath, string chars, string eventsPath, bool allMessages) {
        double hz = Stopwatch.Frequency;
        long step = (long)(hz / rateHz);
        long start = Stopwatch.GetTimestamp() + (long)(0.2 * hz);
        long limit = (long)(maxSeconds * hz);
        StringBuilder sb = new StringBuilder();
        StringBuilder ev = new StringBuilder();
        sb.Append("seq,char,qpc_before,qpc_after,sent,fg_ok,fg_event\n");
        ev.Append("seq,qpc,recovered,hung,responsive,owner\n");
        int seq = 0, fgLost = 0, sendFail = 0, events = 0, recoveredEvents = 0;
        while (true) {
            long due = start + (long)seq * step;
            if (due - start > limit) break;
            while (true) {
                long rem = due - Stopwatch.GetTimestamp();
                if (rem <= 0) break;
                if (rem > (long)(0.016 * hz)) Thread.Sleep(8); else Thread.SpinWait(40);
            }
            if (!IsWindow(hwnd)) break;
            int fgEvent = 0;
            if (GetForegroundWindow() != hwnd) {
                long lostAt = Stopwatch.GetTimestamp();
                string owner = ForegroundOwner();
                bool hung = Hung(hwnd);
                bool responsive = Responsive(hwnd, 100);
                bool recovered = false;
                int pause = 30;
                for (int i = 0; i < 3 && !recovered; i++) {
                    string how = Foreground(hwnd, pid);
                    recovered = how != "failed" && GetForegroundWindow() == hwnd;
                    if (!recovered) { Thread.Sleep(pause); pause *= 2; }
                }
                events++;
                if (recovered) recoveredEvents++;
                ev.Append(seq + "," + lostAt + "," + (recovered ? 1 : 0) + "," + (hung ? 1 : 0) + "," + (responsive ? 1 : 0) + ",\"" + owner + "\"\n");
                if (!recovered) {
                    fgLost = 1;
                    sb.Append(seq + ",,0,0,0,0,1\n");
                    break;
                }
                fgEvent = 1;
            }
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
        return "sent=" + seq + " fg_lost=" + fgLost + " send_fail=" + sendFail + " fg_events=" + events + " fg_recovered=" + recoveredEvents;
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
$lines.Add("exe=$exe exe_sha256=$($b.exe_sha256) dll_sha256=$($b.dll_sha256) instr=$Instr runs=$Runs warmup_s=$Warmup measure_s=$Measure rate_hz=$RateHz key_mode=$KeyMode foreground_s=$ForegroundSeconds")
$lines.Add("power=$((powercfg /getactivescheme) -join ' ')")
Flush-Out
$chars = 'mwqogdhbnk'
$okRuns = 0
for ($i = 1; $i -le $Runs; $i++) {
  $id = "$RunPrefix$i"
  $dir = "$RunRoot\$id"
  New-Item -ItemType Directory -Force $dir | Out-Null
  $lines.Add("=== RUN $id start=$(Get-Date -Format o)")
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  $psi.Arguments = "--run-id $id --out `"$dir`" --warmup-s $Warmup --measure-s $Measure --instr $Instr"
  $psi.WorkingDirectory = $bin
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables['Path'] = "$swiftBin;$bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $qs = [System.Diagnostics.Stopwatch]::GetTimestamp()
  $proc = [System.Diagnostics.Process]::Start($psi)
  $so = $proc.StandardOutput.ReadToEndAsync()
  $se = $proc.StandardError.ReadToEndAsync()
  $lines.Add("pid run=$id pid=$($proc.Id) start_utc=$([DateTime]::UtcNow.ToString('o')) qpc_start=$qs")
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
    $acqLog = New-Object System.Text.StringBuilder
    $fg = [Inj]::Acquire($hwnd, $proc.Id, $ForegroundSeconds * 1000, $acqLog)
    foreach ($l in ($acqLog.ToString() -split "`r?`n" | Where-Object { $_ })) { $lines.Add("fg_attempt run=$id $l") }
    $rc = New-Object Inj+RECT; [void][Inj]::GetClientRect($hwnd, [ref]$rc)
    $dpi = [Inj]::GetDpiForWindow($hwnd)
    $lines.Add("window run=$id hwnd=$($hwnd.ToInt64()) foreground=$fg dpi=$dpi client_px=$($rc.Right)x$($rc.Bottom)")
    if ($fg -eq 'failed' -or $fg -eq 'no-window') { $valid = $false; $reason = 'foreground-failed' }
    else {
      # Keys from now until the run ends (warm-up + measured + margin); the analyzer keeps those inside the measured window.
      $res = [Inj]::Run($hwnd, $proc.Id, $RateHz, $Warmup + $Measure + 6, "$dir\inject.csv", $chars, "$dir\fg_events.csv", ($KeyMode -eq 'all'))
      $lines.Add("inject run=$id $res csv=$dir\inject.csv key_mode=$KeyMode")
      foreach ($l in (Get-Content "$dir\fg_events.csv" -ErrorAction SilentlyContinue | Select-Object -Skip 1)) { $lines.Add("fg_event run=$id $l") }
      # fg_lost=1 only stops the key script. The analyzer decides validity: a loss before the measured window ends voids the run.
    }
  }
  $deadline = (Get-Date).AddSeconds($Warmup + $Measure + 40)
  while (-not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
  if (-not $proc.HasExited) { $valid = $false; $reason = 'timeout-killed'; try { $proc.Kill() } catch { } }
  $qe = [System.Diagnostics.Stopwatch]::GetTimestamp()
  $exit = if ($proc.HasExited) { $proc.ExitCode } else { -1 }
  $lines.Add("pid_exit run=$id pid=$($proc.Id) qpc_end=$qe exit=$exit")
  if ($exit -ne 0) { $valid = $false; if ($reason -eq 'ok') { $reason = "exit-$exit" } }
  [System.IO.File]::WriteAllText("$dir\stdout.txt", $so.Result)
  [System.IO.File]::WriteAllText("$dir\stderr.txt", $se.Result)
  $lines.Add("run_state id=$id valid=$([int]$valid) reason=$reason")
  if ($valid) { $okRuns++ }
  Flush-Out
  Start-Sleep -Seconds 5
}
$lines.Add("finished=$(Get-Date -Format o) runs_valid=$okRuns of $Runs")
Flush-Out
