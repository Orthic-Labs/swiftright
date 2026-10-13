# SR0 tuple12 one-run display diagnostic. Read-only HWND/session/occlusion sampling.
# It never activates, moves, resizes, posts input, registers tasks, changes permissions, or launches processes.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$TargetPid,
  [Parameter(Mandatory)][IntPtr]$TargetHwnd,
  [Parameter(Mandatory)][string]$Out,
  [Parameter(Mandatory)][string]$Summary,
  [ValidateRange(1,120)][int]$DurationSeconds = 30,
  [ValidateRange(100,2000)][int]$SampleMilliseconds = 250
)
$ErrorActionPreference = 'Stop'
if ($TargetHwnd -eq [IntPtr]::Zero) { throw 'positive target HWND required' }
$outFull = [IO.Path]::GetFullPath($Out); $summaryFull = [IO.Path]::GetFullPath($Summary)
foreach ($path in @($outFull,$summaryFull)) {
  if (Test-Path -LiteralPath $path) { throw "output exists: $path" }
  $parent = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "output parent missing: $parent" }
  $item = Get-Item -LiteralPath $parent -Force
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "output parent is reparse point: $parent" }
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class Sr0DisplayDiagnosticV1 {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct MONITORINFO { public int CbSize; public RECT Monitor, Work; public uint Flags; }
  [DllImport("user32.dll", EntryPoint="GetForegroundWindow")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", EntryPoint="IsWindow")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll", EntryPoint="IsWindowVisible")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", EntryPoint="IsIconic")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll", EntryPoint="GetWindowRect")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", EntryPoint="GetClientRect")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", EntryPoint="ClientToScreen")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll", EntryPoint="GetWindowThreadProcessId")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", EntryPoint="GetAncestor")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll", EntryPoint="WindowFromPoint")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll", EntryPoint="MonitorFromWindow")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
  [DllImport("user32.dll", EntryPoint="GetMonitorInfo", CharSet=CharSet.Unicode)] public static extern bool GetMonitorInfo(IntPtr h, ref MONITORINFO i);
  [DllImport("user32.dll", EntryPoint="IsWindowEnabled")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("dwmapi.dll", EntryPoint="DwmGetWindowAttribute")] public static extern int DwmGetWindowAttribute(IntPtr h, uint attr, out uint value, uint size);
  [DllImport("kernel32.dll", EntryPoint="WTSGetActiveConsoleSessionId")] public static extern uint WTSGetActiveConsoleSessionId();
  [DllImport("kernel32.dll", EntryPoint="ProcessIdToSessionId", SetLastError=true)] public static extern bool ProcessIdToSessionId(uint pid, out uint session);
  public static IntPtr Root(IntPtr h) { var r = GetAncestor(h, 2); return r == IntPtr.Zero ? h : r; }
  public static int Pid(IntPtr h) { uint p = 0; GetWindowThreadProcessId(h, out p); return unchecked((int)p); }
  public static bool Cloaked(IntPtr h) { uint value = 0; return DwmGetWindowAttribute(h, 14, out value, 4) == 0 && value != 0; }
  public static string SessionClass(int pid, out uint session, out uint active) {
    session = 0; active = WTSGetActiveConsoleSessionId();
    bool ok = ProcessIdToSessionId((uint)pid, out session);
    if (!ok) return "target-session-unreadable";
    return session == active ? "active-console-session" : "non-console-session";
  }
}
'@
function Rect-Value($r) { [ordered]@{ left=$r.Left; top=$r.Top; right=$r.Right; bottom=$r.Bottom; width=($r.Right-$r.Left); height=($r.Bottom-$r.Top) } }
function Window-RootPid([IntPtr]$h) { if ($h -eq [IntPtr]::Zero) { return 0 }; return [Sr0DisplayDiagnosticV1]::Pid([Sr0DisplayDiagnosticV1]::Root($h)) }
function Point-Owners([IntPtr]$root,[int]$left,[int]$top,[int]$width,[int]$height) {
  $owners = @(); $targetPoints = 0; $coveredPoints = 0
  foreach ($fx in @(0.15,0.5,0.85)) { foreach ($fy in @(0.15,0.5,0.85)) {
    $point = New-Object Sr0DisplayDiagnosticV1+POINT; $point.X = $left + [int]($width*$fx); $point.Y = $top + [int]($height*$fy)
    $hit = [Sr0DisplayDiagnosticV1]::WindowFromPoint($point); $hitRoot = [Sr0DisplayDiagnosticV1]::Root($hit); $hitPid = Window-RootPid $hit
    $owners += [ordered]@{ x=$point.X; y=$point.Y; hwnd=$hitRoot.ToInt64(); pid=$hitPid; target=($hitRoot -eq $root); covered=($hitRoot -ne [IntPtr]::Zero -and $hitRoot -ne $root) }
    if ($hitRoot -eq $root) { $targetPoints++ } elseif ($hitRoot -ne [IntPtr]::Zero) { $coveredPoints++ }
  }}
  [ordered]@{ points=$owners; target_points=$targetPoints; covered_points=$coveredPoints; unoccluded=($targetPoints -eq 9) }
}
function Snapshot([IntPtr]$target,[int]$pid,[uint32]$targetSession,[uint32]$activeSession) {
  $root = [Sr0DisplayDiagnosticV1]::Root($target); $window = New-Object Sr0DisplayDiagnosticV1+RECT; $client = New-Object Sr0DisplayDiagnosticV1+RECT
  $valid = [Sr0DisplayDiagnosticV1]::IsWindow($target); $windowOk = $valid -and [Sr0DisplayDiagnosticV1]::GetWindowRect($target,[ref]$window); $clientOk = $valid -and [Sr0DisplayDiagnosticV1]::GetClientRect($target,[ref]$client)
  $origin = New-Object Sr0DisplayDiagnosticV1+POINT; $originOk = $clientOk -and [Sr0DisplayDiagnosticV1]::ClientToScreen($target,[ref]$origin)
  $fg = [Sr0DisplayDiagnosticV1]::Root([Sr0DisplayDiagnosticV1]::GetForegroundWindow()); $monitor = [Sr0DisplayDiagnosticV1]::MonitorFromWindow($target,2); $mi = New-Object Sr0DisplayDiagnosticV1+MONITORINFO; $mi.CbSize=[Runtime.InteropServices.Marshal]::SizeOf($mi); $monitorOk=($monitor -ne [IntPtr]::Zero)-and [Sr0DisplayDiagnosticV1]::GetMonitorInfo($monitor,[ref]$mi)
  $occlusion = if ($originOk -and $client.Right -gt 0 -and $client.Bottom -gt 0) { Point-Owners $root $origin.X $origin.Y $client.Right $client.Bottom } else { [ordered]@{ points=@(); target_points=0; covered_points=0; unoccluded=$false } }
  [ordered]@{ utc=[DateTimeOffset]::UtcNow.ToString('o'); target_pid=$pid; target_hwnd=$target.ToInt64(); target_root_hwnd=$root.ToInt64(); owner_pid=(Window-RootPid $target); valid=$valid; visible=($valid -and [Sr0DisplayDiagnosticV1]::IsWindowVisible($target)); minimized=($valid -and [Sr0DisplayDiagnosticV1]::IsIconic($target)); cloaked=($valid -and [Sr0DisplayDiagnosticV1]::Cloaked($target)); enabled=($valid -and [Sr0DisplayDiagnosticV1]::IsWindowEnabled($target)); window_ok=$windowOk; window=$(if($windowOk){Rect-Value $window}else{$null}); client_ok=$clientOk; client=$(if($clientOk){Rect-Value $client}else{$null}); client_screen_ok=$originOk; client_origin=$(if($originOk){[ordered]@{x=$origin.X;y=$origin.Y}}else{$null}); foreground_hwnd=$fg.ToInt64(); foreground_pid=(Window-RootPid $fg); foreground_is_target=($fg -eq $root); monitor_ok=$monitorOk; monitor=$(if($monitorOk){Rect-Value $mi.Monitor}else{$null}); work_area=$(if($monitorOk){Rect-Value $mi.Work}else{$null}); target_session=$targetSession; active_console_session=$activeSession; session_match=($targetSession -eq $activeSession); occlusion=$occlusion }
}
$session = [uint32]0; $active = [uint32]0; $sessionClass = [Sr0DisplayDiagnosticV1]::SessionClass($TargetPid,[ref]$session,[ref]$active)
$processName=''; $processPath=''; try { $process = Get-Process -Id $TargetPid -ErrorAction Stop; $processName=$process.ProcessName; try { $processPath=$process.Path } catch {} } catch { $process=$null }
$maxSamples = [int][math]::Ceiling(($DurationSeconds * 1000.0) / $SampleMilliseconds) + 1
$writer = [IO.File]::Open($outFull,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read); $sw = New-Object IO.StreamWriter($writer,[Text.Encoding]::UTF8); $sw.AutoFlush=$true
$snapshots=@(); $started=[DateTimeOffset]::UtcNow; $stopReason='duration-complete'
try {
  for ($i=0; $i -lt $maxSamples; $i++) {
    $snap = Snapshot $TargetHwnd $TargetPid $session $active; $snap.index=$i; $snapshots += $snap; $sw.WriteLine(($snap | ConvertTo-Json -Depth 12 -Compress))
    if (-not $snap.valid) { $stopReason='target-window-invalid'; break }
    if ((([DateTimeOffset]::UtcNow)-$started).TotalSeconds -ge $DurationSeconds) { break }
    Start-Sleep -Milliseconds $SampleMilliseconds
  }
} finally { $sw.Dispose(); $writer.Dispose() }
$validSnaps=@($snapshots | Where-Object { $_.valid -eq $true }); $unoccluded=@($validSnaps | Where-Object { $_.occlusion.unoccluded -eq $true }).Count; $occluded=$validSnaps.Count-$unoccluded
$classification = if ($sessionClass -notin @('active-console-session')) { 'interactive-session-unavailable' } elseif ($validSnaps.Count -eq 0) { 'target-not-observed' } elseif ($occluded -eq 0) { 'unoccluded-observation' } else { 'background-or-occluded-observation' }
$summaryObject=[ordered]@{ kind='sr0-tuple12-workload-display-diagnostic-v1'; status='observed'; captured_utc=$started.ToString('o'); target_pid=$TargetPid; target_hwnd=$TargetHwnd.ToInt64(); process_name=$processName; process_path=$processPath; target_session=$session; active_console_session=$active; session_class=$sessionClass; duration_seconds=$DurationSeconds; sample_milliseconds=$SampleMilliseconds; max_samples=$maxSamples; samples=$snapshots.Count; valid_samples=$validSnaps.Count; unoccluded_samples=$unoccluded; occluded_samples=$occluded; stop_reason=$stopReason; classification=$classification; raw_jsonl=$outFull; strictCauseConclusion='presentmon_display_rows_not_inferred'; desktop_mutation=$false; permission_change=$false; process_launch=$false }
$bytes=[Text.Encoding]::UTF8.GetBytes(($summaryObject | ConvertTo-Json -Depth 12) + [Environment]::NewLine); $s=[IO.File]::Open($summaryFull,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read); try { $s.Write($bytes,0,$bytes.Length); $s.Flush($true) } finally { $s.Dispose() }
"display diagnostic classification=$classification samples=$($snapshots.Count) unoccluded=$unoccluded occluded=$occluded summary=$summaryFull"
