# SR0 tuple12 read-only display-context probe.
# Captures targeted HWND/client/work-area/foreground/session facts; no UI, input, lock, or process mutation.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][int]$TargetPid,
  [Parameter(Mandatory)][IntPtr]$TargetHwnd,
  [Parameter(Mandatory)][string]$Out
)
$ErrorActionPreference = 'Stop'
if ($TargetPid -le 0 -or ($TargetHwnd -eq [IntPtr]::Zero)) { throw 'positive target PID/HWND required' }
if (Test-Path -LiteralPath $Out) { throw "output already exists: $Out" }
$parent = Split-Path -Parent ([IO.Path]::GetFullPath($Out))
if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw "output parent missing: $parent" }
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Sr0DisplayContextV1 {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] public struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint flags);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool GetMonitorInfo(IntPtr h, ref MONITORINFO i);
  [DllImport("kernel32.dll")] public static extern uint WTSGetActiveConsoleSessionId();
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool ProcessIdToSessionId(uint pid, out uint session);
}
'@
function Rect-Object($r) { [ordered]@{ left=$r.left; top=$r.top; right=$r.right; bottom=$r.bottom; width=($r.right-$r.left); height=($r.bottom-$r.top) } }
function Window-Object([IntPtr]$h) {
  $r = New-Object Sr0DisplayContextV1+RECT; $client = New-Object Sr0DisplayContextV1+RECT; $owner = [uint32]0
  $valid = [Sr0DisplayContextV1]::IsWindow($h)
  $windowOk = $valid -and [Sr0DisplayContextV1]::GetWindowRect($h, [ref]$r)
  $clientOk = $valid -and [Sr0DisplayContextV1]::GetClientRect($h, [ref]$client)
  $p = New-Object Sr0DisplayContextV1+POINT; $screenOk = $clientOk -and [Sr0DisplayContextV1]::ClientToScreen($h, [ref]$p)
  [Sr0DisplayContextV1]::GetWindowThreadProcessId($h, [ref]$owner) | Out-Null
  $windowValue = if ($windowOk) { Rect-Object $r } else { $null }
  $clientValue = if ($clientOk) { Rect-Object $client } else { $null }
  $originValue = if ($screenOk) { [ordered]@{ x=$p.x; y=$p.y } } else { $null }
  [ordered]@{ hwnd=$h.ToInt64(); valid=$valid; visible=($valid -and [Sr0DisplayContextV1]::IsWindowVisible($h)); owner_pid=$owner; window_ok=$windowOk; window=$windowValue; client_ok=$clientOk; client=$clientValue; client_screen_ok=$screenOk; client_origin=$originValue }
}
$targetSession = [uint32]0; $targetSessionOk = [Sr0DisplayContextV1]::ProcessIdToSessionId([uint32]$TargetPid, [ref]$targetSession)
$fg = [Sr0DisplayContextV1]::GetForegroundWindow(); $fgPid = [uint32]0
[Sr0DisplayContextV1]::GetWindowThreadProcessId($fg, [ref]$fgPid) | Out-Null
$target = Window-Object $TargetHwnd
$foreground = Window-Object $fg
$monitor = [Sr0DisplayContextV1]::MonitorFromWindow($TargetHwnd, 2)
$mi = New-Object Sr0DisplayContextV1+MONITORINFO; $mi.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($mi)
$monitorOk = ($monitor -ne [IntPtr]::Zero) -and [Sr0DisplayContextV1]::GetMonitorInfo($monitor, [ref]$mi)
$monitorRect = if ($monitorOk) { Rect-Object $mi.rcMonitor } else { $null }
$workRect = if ($monitorOk) { Rect-Object $mi.rcWork } else { $null }
$outObject = [ordered]@{
  kind='sr0-tuple12-readonly-display-context-v1'; captured_utc=[DateTimeOffset]::UtcNow.ToString('o'); target_pid=$TargetPid; target_hwnd=$TargetHwnd.ToInt64()
  target_session_ok=$targetSessionOk; target_session=$targetSession; active_console_session=[Sr0DisplayContextV1]::WTSGetActiveConsoleSessionId()
  foreground_hwnd=$fg.ToInt64(); foreground_pid=$fgPid; foreground_is_target=($fgPid -eq $TargetPid); target=$target; foreground=$foreground
  monitor_ok=$monitorOk; monitor=$monitorRect; work_area=$workRect
  observation='single read-only snapshot; no conclusion about historical PresentMon rows'
}
$json = $outObject | ConvertTo-Json -Depth 12
$bytes = [Text.Encoding]::UTF8.GetBytes($json + [Environment]::NewLine)
$s = [IO.File]::Open($Out, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try { $s.Write($bytes, 0, $bytes.Length) } finally { $s.Dispose() }
"display context=$Out foreground_pid=$fgPid target_session=$targetSession monitor_ok=$monitorOk"
