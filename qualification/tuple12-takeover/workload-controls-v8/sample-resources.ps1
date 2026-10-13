# SR0 resource sampler (Windows). One instance per timed run, started by task-workload.ps1 right after it launches WorkloadWin.exe.
# Writes <OutDir>\resources.csv (about 1 row/s, QPC-stamped like every other SR0 clock) and <OutDir>\resources-meta.json.
#   powershell -NoProfile -ExecutionPolicy Bypass -File sample-resources.ps1 -TargetPid <pid> -OutDir <run dir> [-RunId r1] [-StopFile <path>]
#
# What a row holds (analyze_workload.py reads it; every value is informational, the only flag that can fail a run is a private-bytes
# leak slope > 5 MB/min):
#   total_cpu_pct        whole machine, 0-100, from NtQuerySystemInformation(SystemProcessorPerformanceInformation) deltas over the row's wall interval
#   max_core_pct/max_core busiest logical processor of the machine in that interval
#   proc_cpu_core_pct    our process, percent of ONE core (100 = one core busy; sums over threads, can exceed 100); proc_cpu_pct = same / logical CPUs
#   top_threads          top 5 threads of our process by CPU in the interval: "tid[name]:pct;..." (pct of one core). The OS charges thread time
#                        by clock tick, so single-second values are noisy for a thread that runs a few ms per frame; a thread that is pinned is not
#   pinned_tid/pinned_pct the busiest thread when it used >= 90% of one core (pinned core), else empty / 0
#   working_set_bytes, private_bytes, handles, threads   our process (private_bytes = PrivateMemorySize64, the commit charge)
#   gpu<i>_{3d,compute,copy,video,other}_pct   GPU Engine utilisation of OUR process on DXGI adapter i, summed per engine type
#                        (video = VideoDecode/VideoEncode/VideoProcessing; other = anything else), from \GPU Engine(pid_<ours>_*)\Utilization Percentage
#   gpu<i>_ded_bytes/gpu<i>_shared_bytes       \GPU Process Memory(pid_<ours>_*): dedicated / shared usage of our process on adapter i
#   gpux_*               the same for a LUID that is not in the DXGI adapter list
#   gpu_n                number of GPU counter instances returned (0 = counters unavailable that second, not "0% load")
#   gpu_engines          every engine instance with utilisation > 0: "a<adapter>.<type>#<engine>=<pct>;..."
#   sampler_cpu_pct      this sampler's own CPU (percent of one core): the measurement overhead
# resources-meta.json maps adapter index -> LUID -> name (DXGI), so a run states which adapter its process rendered on.
param(
  [Parameter(Mandatory = $true)][int]$TargetPid,
  [Parameter(Mandatory = $true)][string]$OutDir,
  [string]$RunId = '',
  [string]$StopFile = '',
  [double]$IntervalS = 1.0,           # minimum time per row (Get-Counter itself blocks 1 s when the process has GPU instances)
  [double]$MaxSeconds = 1200
)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force $OutDir | Out-Null

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class ResProbe {
    [DllImport("ntdll.dll")] static extern int NtQuerySystemInformation(int cls, IntPtr buf, int len, out int ret);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenThread(uint access, bool inherit, uint tid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] static extern int GetThreadDescription(IntPtr h, out IntPtr desc);
    [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);

    // Per logical processor: [idle0, busy+idle0, idle1, busy+idle1, ...] in 100 ns units (kernel time includes idle time). null on failure.
    public static long[] CpuTimes() {
        int n = Environment.ProcessorCount;
        int size = 64 * n + 64;
        IntPtr buf = Marshal.AllocHGlobal(size);
        try {
            int ret;
            int st = NtQuerySystemInformation(8, buf, size, out ret);   // SystemProcessorPerformanceInformation
            if (st != 0 || ret < n * 24) return null;
            int stride = ret / n;
            long[] v = new long[n * 2];
            for (int i = 0; i < n; i++) {
                long idle = Marshal.ReadInt64(buf, i * stride);
                long kernel = Marshal.ReadInt64(buf, i * stride + 8);
                long user = Marshal.ReadInt64(buf, i * stride + 16);
                v[2 * i] = idle;
                v[2 * i + 1] = kernel + user;
            }
            return v;
        } finally { Marshal.FreeHGlobal(buf); }
    }

    public static string ThreadName(uint tid) {
        IntPtr h = OpenThread(0x0800, false, tid);   // THREAD_QUERY_LIMITED_INFORMATION
        if (h == IntPtr.Zero) return "";
        try {
            IntPtr d;
            if (GetThreadDescription(h, out d) != 0 || d == IntPtr.Zero) return "";
            string s = Marshal.PtrToStringUni(d);
            LocalFree(d);
            return s ?? "";
        } catch (Exception) { return ""; }
        finally { CloseHandle(h); }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DXGI_ADAPTER_DESC1 {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
        public uint VendorId, DeviceId, SubSysId, Revision;
        public UIntPtr DedicatedVideoMemory, DedicatedSystemMemory, SharedSystemMemory;
        public uint LuidLow;
        public int LuidHigh;
        public uint Flags;
    }

    [ComImport, Guid("770aae78-f26f-4dba-a829-253c83d1b387"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDXGIFactory1 {
        void SetPrivateData(); void SetPrivateDataInterface(); void GetPrivateData(); void GetParent();
        [PreserveSig] int EnumAdapters(uint i, out IntPtr a);
        void MakeWindowAssociation(); void GetWindowAssociation(); void CreateSwapChain(); void CreateSoftwareAdapter();
        [PreserveSig] int EnumAdapters1(uint i, out IDXGIAdapter1 a);
        [PreserveSig] int IsCurrent();
    }

    [ComImport, Guid("29038f61-3839-4626-91fd-086879011a05"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDXGIAdapter1 {
        void SetPrivateData(); void SetPrivateDataInterface(); void GetPrivateData(); void GetParent();
        void EnumOutputs(); void GetDesc(); void CheckInterfaceSupport();
        [PreserveSig] int GetDesc1(out DXGI_ADAPTER_DESC1 d);
    }

    [DllImport("dxgi.dll")] static extern int CreateDXGIFactory1(ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IDXGIFactory1 f);

    // "index|0xHHHHHHHH_0xLLLLLLLL|description|dedicated_video_mb|vendor_id|flags" per DXGI adapter, in enumeration order (the LUID text is the
    // form used by the GPU Engine / GPU Process Memory counter instance names). Empty list when DXGI is unavailable.
    public static List<string> Adapters() {
        List<string> res = new List<string>();
        Guid iid = new Guid("770aae78-f26f-4dba-a829-253c83d1b387");
        IDXGIFactory1 f;
        if (CreateDXGIFactory1(ref iid, out f) != 0 || f == null) return res;
        try {
            for (uint i = 0; i < 16; i++) {
                IDXGIAdapter1 a;
                if (f.EnumAdapters1(i, out a) != 0 || a == null) break;
                try {
                    DXGI_ADAPTER_DESC1 d;
                    if (a.GetDesc1(out d) != 0) continue;
                    res.Add(i + "|0x" + ((uint)d.LuidHigh).ToString("x8") + "_0x" + d.LuidLow.ToString("x8") + "|" + d.Description + "|"
                        + (d.DedicatedVideoMemory.ToUInt64() / (1024UL * 1024UL)) + "|" + d.VendorId + "|" + d.Flags);
                } finally { Marshal.ReleaseComObject(a); }
            }
        } finally { Marshal.ReleaseComObject(f); }
        return res;
    }
}
'@

$qHz = [double][Diagnostics.Stopwatch]::Frequency
$logical = [Environment]::ProcessorCount
$adapters = @()
try {
  foreach ($line in [ResProbe]::Adapters()) {
    $f = $line.Split('|')
    $adapters += [pscustomobject]@{ index = [int]$f[0]; luid = $f[1]; name = $f[2]; dedicated_mb = [int64]$f[3]; vendor_id = [int]$f[4]; flags = [int]$f[5] }
  }
} catch { $adapters = @() }
$luidIndex = @{}
foreach ($a in $adapters) { $luidIndex[$a.luid.ToLowerInvariant()] = $a.index }
$nAd = $adapters.Count

$meta = [ordered]@{
  run_id = $RunId; target_pid = $TargetPid; started = (Get-Date -Format o); qpc_hz = $qHz; logical_cpus = $logical
  sampler_pid = $PID; powershell = $PSVersionTable.PSVersion.ToString(); adapters = $adapters
  adapter_enumeration = $(if ($nAd) { 'dxgi' } else { 'failed' })
}
($meta | ConvertTo-Json -Depth 4) | Set-Content -Path "$OutDir\resources-meta.json" -Encoding ascii

$cols = @('t_s', 'qpc', 'dt_s', 'total_cpu_pct', 'max_core_pct', 'max_core', 'proc_cpu_pct', 'proc_cpu_core_pct', 'top_threads', 'pinned_tid', 'pinned_pct',
          'working_set_bytes', 'private_bytes', 'handles', 'threads')
$adIdx = @(0..([math]::Max($nAd, 1) - 1) | ForEach-Object { "$_" }) + @('x')
if ($nAd -eq 0) { $adIdx = @('x') }
foreach ($i in $adIdx) { foreach ($k in '3d_pct', 'compute_pct', 'copy_pct', 'video_pct', 'other_pct', 'ded_bytes', 'shared_bytes') { $cols += "gpu${i}_$k" } }
$cols += @('gpu_n', 'gpu_engines', 'sampler_cpu_pct')
$fs = [IO.File]::Open("$OutDir\resources.csv", [IO.FileMode]::Create, [IO.FileAccess]::Write, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
$wr = New-Object IO.StreamWriter($fs, [Text.Encoding]::ASCII)
$wr.WriteLine(($cols -join ','))
$wr.Flush()

function Q([string]$s) { '"' + $s.Replace('"', '') + '"' }
function Snap-Threads($p) {
  $m = @{}
  try { foreach ($t in $p.Threads) { try { $m[[int]$t.Id] = $t.TotalProcessorTime.Ticks } catch { } } } catch { }
  return $m
}

$self = [Diagnostics.Process]::GetCurrentProcess()
$nameCache = @{}
$paths = @("\GPU Engine(pid_${TargetPid}_*)\Utilization Percentage",
           "\GPU Process Memory(pid_${TargetPid}_*)\Dedicated Usage",
           "\GPU Process Memory(pid_${TargetPid}_*)\Shared Usage")
$t00 = [Diagnostics.Stopwatch]::GetTimestamp()
$deadline = $t00 + [long]($MaxSeconds * $qHz)
try { $p = [Diagnostics.Process]::GetProcessById($TargetPid) } catch { $p = $null }
if (-not $p) { exit 3 }

# baselines for the first interval
$prevQ = [Diagnostics.Stopwatch]::GetTimestamp()
$prevSys = [ResProbe]::CpuTimes()
$p.Refresh()
$prevProc = try { $p.TotalProcessorTime.Ticks } catch { 0 }
$prevThr = Snap-Threads $p
$self.Refresh(); $prevSelf = $self.TotalProcessorTime.Ticks
$rows = 0
while ($true) {
  if ($StopFile -and (Test-Path -LiteralPath $StopFile)) { break }
  if ([Diagnostics.Stopwatch]::GetTimestamp() -gt $deadline) { break }
  try { if ($p.HasExited) { break } } catch { break }

  # GPU counters for our pid only: Get-Counter blocks one SampleInterval, so this call also paces the loop (about 1 row/s). Instance names are
  # expanded on every call, so engines the process starts using later are picked up.
  $gpuN = 0; $eng = @{}; $mem = @{}
  $iterStart = [Diagnostics.Stopwatch]::GetTimestamp()
  try {
    $c = Get-Counter -Counter $paths -SampleInterval 1 -MaxSamples 1 -ErrorAction SilentlyContinue
    if ($c) {
      foreach ($s in $c.CounterSamples) {
        $inst = [string]$s.InstanceName
        if ($inst -notmatch '^pid_(\d+)_luid_(0x[0-9a-f]+_0x[0-9a-f]+)_phys_\d+(?:_eng_(\d+)_engtype_(.*))?$') { continue }
        if ([int]$Matches[1] -ne $TargetPid) { continue }
        $gpuN++
        $luid = $Matches[2]; $engIdx = $Matches[3]; $ty = $Matches[4]   # captured before the -match below overwrites $Matches
        $ai = if ($luidIndex.ContainsKey($luid)) { "$($luidIndex[$luid])" } else { 'x' }
        if ($s.Path -match 'gpu engine') {
          $grp = if ($ty -eq '3d') { '3d' } elseif ($ty -like 'compute*') { 'compute' } elseif ($ty -eq 'copy') { 'copy' } elseif ($ty -like 'video*') { 'video' } else { 'other' }
          $key = "$ai.$grp"
          if (-not $eng.ContainsKey($key)) { $eng[$key] = 0.0 }
          $eng[$key] += [double]$s.CookedValue
          if ($s.CookedValue -gt 0) { $eng["detail:a$ai.$ty#$engIdx"] = [double]$s.CookedValue }
        } elseif ($s.Path -match 'dedicated usage') {
          $mem["$ai.ded"] = [double]$mem["$ai.ded"] + [double]$s.CookedValue
        } elseif ($s.Path -match 'shared usage') {
          $mem["$ai.shared"] = [double]$mem["$ai.shared"] + [double]$s.CookedValue
        }
      }
    }
  } catch { }
  # Get-Counter returns at once when the process has no GPU counter instances (yet): hold the row period at IntervalS so the loop never spins.
  $spent = ([Diagnostics.Stopwatch]::GetTimestamp() - $iterStart) / $qHz
  if ($spent -lt $IntervalS) { Start-Sleep -Milliseconds ([int](($IntervalS - $spent) * 1000)) }

  $nowQ = [Diagnostics.Stopwatch]::GetTimestamp()
  $dt = ($nowQ - $prevQ) / $qHz
  if ($dt -le 0) { $dt = 1e-6 }
  $sys = [ResProbe]::CpuTimes()
  $total = ''; $maxCore = ''; $maxCoreIdx = ''
  if ($sys -and $prevSys -and $sys.Length -eq $prevSys.Length) {
    $sumIdle = 0.0; $sumAll = 0.0; $mx = -1.0; $mi = -1
    for ($i = 0; $i -lt $sys.Length; $i += 2) {
      $di = [double]($sys[$i] - $prevSys[$i]); $da = [double]($sys[$i + 1] - $prevSys[$i + 1])
      $sumIdle += $di; $sumAll += $da
      if ($da -gt 0) { $u = 100.0 * (1.0 - $di / $da); if ($u -gt $mx) { $mx = $u; $mi = $i / 2 } }
    }
    if ($sumAll -gt 0) { $total = [math]::Round(100.0 * (1.0 - $sumIdle / $sumAll), 2) }
    if ($mi -ge 0) { $maxCore = [math]::Round($mx, 2); $maxCoreIdx = $mi }
  }
  $procCore = ''; $procTot = ''; $topTxt = ''; $pinTid = ''; $pinPct = 0; $ws = ''; $priv = ''; $hnd = ''; $thr = ''
  try {
    $p.Refresh()
    $cpu = $p.TotalProcessorTime.Ticks
    $procCore = [math]::Round(100.0 * ($cpu - $prevProc) / ($dt * 1e7), 2)
    $procTot = [math]::Round($procCore / $logical, 3)
    $prevProc = $cpu
    $ws = $p.WorkingSet64; $priv = $p.PrivateMemorySize64; $hnd = $p.HandleCount
    $curThr = Snap-Threads $p
    $thr = $curThr.Count
    $list = foreach ($k in $curThr.Keys) {
      $old = if ($prevThr.ContainsKey($k)) { $prevThr[$k] } else { 0 }
      [pscustomobject]@{ Tid = $k; Pct = 100.0 * ($curThr[$k] - $old) / ($dt * 1e7) }
    }
    $top = @($list | Sort-Object Pct -Descending | Select-Object -First 5)
    $parts = foreach ($t in $top) {
      if (-not $nameCache.ContainsKey($t.Tid)) { $nameCache[$t.Tid] = ([ResProbe]::ThreadName([uint32]$t.Tid) -replace '[^A-Za-z0-9_.-]', '_') }
      $nm = $nameCache[$t.Tid]
      "$($t.Tid)$(if ($nm) { "[$nm]" }):$([math]::Round($t.Pct, 1))"
    }
    $topTxt = $parts -join ';'
    if ($top.Count -and $top[0].Pct -ge 90) { $pinTid = $top[0].Tid; $pinPct = [math]::Round($top[0].Pct, 1) }
    $prevThr = $curThr
  } catch { if ($p.HasExited) { break } }
  $self.Refresh(); $selfT = $self.TotalProcessorTime.Ticks
  $selfPct = [math]::Round(100.0 * ($selfT - $prevSelf) / ($dt * 1e7), 2)
  $prevSelf = $selfT; $prevSys = $sys; $prevQ = $nowQ

  $f = New-Object System.Collections.Generic.List[string]
  $f.Add([string][math]::Round(($nowQ - $t00) / $qHz, 3)); $f.Add([string]$nowQ); $f.Add([string][math]::Round($dt, 4))
  $f.Add([string]$total); $f.Add([string]$maxCore); $f.Add([string]$maxCoreIdx); $f.Add([string]$procTot); $f.Add([string]$procCore)
  $f.Add((Q $topTxt)); $f.Add([string]$pinTid); $f.Add([string]$pinPct); $f.Add([string]$ws); $f.Add([string]$priv); $f.Add([string]$hnd); $f.Add([string]$thr)
  foreach ($i in $adIdx) {
    foreach ($g in '3d', 'compute', 'copy', 'video', 'other') { $v = $eng["$i.$g"]; $f.Add($(if ($null -ne $v) { [string][math]::Round($v, 3) } else { '0' })) }
    foreach ($g in 'ded', 'shared') { $v = $mem["$i.$g"]; $f.Add($(if ($null -ne $v) { [string][int64]$v } else { '0' })) }
  }
  $f.Add([string]$gpuN)
  $detail = ($eng.Keys | Where-Object { $_ -like 'detail:*' } | Sort-Object | ForEach-Object { "$($_.Substring(7))=$([math]::Round($eng[$_], 3))" }) -join ';'
  $f.Add((Q $detail)); $f.Add([string]$selfPct)
  $wr.WriteLine(($f -join ','))
  $wr.Flush()
  $rows++
}
$wr.Dispose(); $fs.Dispose()
exit 0
