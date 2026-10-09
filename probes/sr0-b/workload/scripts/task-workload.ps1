# SR0 workload harness (Windows). Runs inside the INTERACTIVE desktop session (registered as a one-shot task by
# run-workload.ps1; the renderer needs a real desktop). For each run: launch WorkloadWin.exe (release, no debugger),
# bring its window to the foreground, POST the keystroke script (WM_KEYDOWN/WM_CHAR/WM_KEYUP via PostMessage to the workload HWND only, no global
# global input API) on the QPC clock (10 keys/s; foreground is kept only so the window is unoccluded for PresentMon, and a foreground
# loss aborts the script and voids the run), wait for the self-timed run to finish (10 s warm-up +
# 60 s measured + teardown), record pid / QPC start / QPC end for the PresentMon PID join.
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
  [string]$RunPrefix = 'r'
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
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

    public static int InputSize() { return 0; } // no SendInput: keys are POSTED to the workload HWND only

    public static string Foreground(IntPtr hwnd, int pid) {
        if (hwnd == IntPtr.Zero) return "no-hwnd";
        if (IsIconic(hwnd)) ShowWindow(hwnd, 9);
        if (GetForegroundWindow() == hwnd) return "already";
        if (SetForegroundWindow(hwnd) && GetForegroundWindow() == hwnd) return "direct";
        AllowSetForegroundWindow(pid);
        if (SetForegroundWindow(hwnd) && GetForegroundWindow() == hwnd) return "allow";
        uint fgPid;
        uint fgThread = GetWindowThreadProcessId(GetForegroundWindow(), out fgPid);
        uint me = GetCurrentThreadId();
        bool attached = fgThread != 0 && fgThread != me && AttachThreadInput(me, fgThread, true);
        try { BringWindowToTop(hwnd); SetForegroundWindow(hwnd); }
        finally { if (attached) AttachThreadInput(me, fgThread, false); }
        return GetForegroundWindow() == hwnd ? "attach" : "failed";
    }

    // The three messages a physical key produces, POSTED to the workload window only (as drive-fixture.ps1 'targeted'):
    // no keystroke can reach another application whatever has focus. Returns true when all three were queued.
    static bool PostKey(IntPtr hwnd, ushort vk, char ch) {
        uint scan = MapVirtualKey(vk, 0);
        IntPtr down = (IntPtr)(1L | ((long)scan << 16));
        IntPtr up = (IntPtr)(1L | ((long)scan << 16) | 0x40000000L | 0x80000000L);
        bool a = PostMessage(hwnd, 0x0100, (IntPtr)vk, down);
        bool b = PostMessage(hwnd, 0x0102, (IntPtr)ch, down);
        bool c = PostMessage(hwnd, 0x0101, (IntPtr)vk, up);
        return a && b && c;
    }

    // Posts `chars` cyclically at rateHz for maxSeconds, each key on an absolute schedule from the first key. The QPC
    // timestamp is taken immediately BEFORE the key-down PostMessage (the event timestamp of CONTRACT section 5).
    // Foreground is checked before each key (validity: window must stay unoccluded); the first miss aborts the script (fg_lost=1).
    public static string Run(IntPtr hwnd, double rateHz, double maxSeconds, string outPath, string chars) {
        double hz = Stopwatch.Frequency;
        long step = (long)(hz / rateHz);
        long start = Stopwatch.GetTimestamp() + (long)(0.2 * hz);
        long limit = (long)(maxSeconds * hz);
        StringBuilder sb = new StringBuilder();
        sb.Append("seq,char,qpc_before,qpc_after,sent,fg_ok\n");
        int seq = 0, fgLost = 0, sendFail = 0;
        while (true) {
            long due = start + (long)seq * step;
            if (due - start > limit) break;
            while (true) {
                long rem = due - Stopwatch.GetTimestamp();
                if (rem <= 0) break;
                if (rem > (long)(0.016 * hz)) Thread.Sleep(8); else Thread.SpinWait(40);
            }
            if (!IsWindow(hwnd)) break;
            if (GetForegroundWindow() != hwnd) {
                fgLost = 1;
                sb.Append(seq + ",,0,0,0,0\n");
                break;
            }
            char c = chars[seq % chars.Length];
            ushort vk = (ushort)char.ToUpperInvariant(c);
            long before = Stopwatch.GetTimestamp();
            bool posted = PostKey(hwnd, vk, c);
            long after = Stopwatch.GetTimestamp();
            uint n = posted ? 1u : 0u;
            if (!posted) sendFail++;
            sb.Append(seq + "," + c + "," + before + "," + after + "," + n + ",1\n");
            seq++;
        }
        File.WriteAllText(outPath, sb.ToString());
        return "sent=" + seq + " fg_lost=" + fgLost + " send_fail=" + sendFail;
    }
}
'@

[void][Inj]::SetProcessDpiAwarenessContext([IntPtr]-4)
$swFreq = [System.Diagnostics.Stopwatch]::Frequency
$lines = New-Object System.Collections.Generic.List[string]
function Flush-Out { [System.IO.File]::WriteAllText($ResultFile, [string]::Join("`r`n", $lines)) }
$vc = Get-CimInstance Win32_VideoController | Select-Object -First 1
$lines.Add("harness=task-workload host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) started=$(Get-Date -Format o)")
$lines.Add("host qpc_freq=$swFreq input_struct=$([Inj]::InputSize()) gpu=$($vc.Name) driver=$($vc.DriverVersion) refresh_hz=$($vc.CurrentRefreshRate) res=$($vc.CurrentHorizontalResolution)x$($vc.CurrentVerticalResolution)")
$lines.Add("exe=$exe exe_sha256=$($b.exe_sha256) dll_sha256=$($b.dll_sha256) instr=$Instr runs=$Runs warmup_s=$Warmup measure_s=$Measure rate_hz=$RateHz")
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
    Start-Sleep -Milliseconds 1500
    $fg = [Inj]::Foreground($hwnd, $proc.Id)
    $rc = New-Object Inj+RECT; [void][Inj]::GetClientRect($hwnd, [ref]$rc)
    $dpi = [Inj]::GetDpiForWindow($hwnd)
    $lines.Add("window run=$id hwnd=$($hwnd.ToInt64()) foreground=$fg dpi=$dpi client_px=$($rc.Right)x$($rc.Bottom)")
    if ($fg -eq 'failed') { $valid = $false; $reason = 'foreground-failed' }
    else {
      # Keys from now until the run ends (warm-up + measured + margin); the analyzer keeps those inside the measured window.
      $res = [Inj]::Run($hwnd, $RateHz, $Warmup + $Measure + 6, "$dir\inject.csv", $chars)
      $lines.Add("inject run=$id $res csv=$dir\inject.csv")
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
