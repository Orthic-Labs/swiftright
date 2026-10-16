# Per-monitor DPI probe for the Windows capture runner (factory-pairs.yml, before capture).
# Goal: make the runner's primary monitor report 250% (240 dpi) per monitor, so the renderer (per-monitor DPI aware: view.rs reads
# GetDpiForWindow) renders at the same 2.5 scale as the Dell. Logs every step; exits 0 only when a per-monitor-aware window reads 240.
#
# Steps: 1 log resolution and the per-monitor scale range (DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE, type -3);
#        2 if the maximum is below 250%, raise the resolution (ChangeDisplaySettingsExW, 2560x1600) and re-read;
#        3 set the scale to 250% (DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE, type -4);
#        4 read back the current scale, then create a per-monitor-aware (v2) window and log GetDpiForWindow (must be 240).
#
# Undocumented layout (NOT in the Windows SDK headers). Source: community reverse engineering of the DPI-scale device info
# (get -3, set -4; sizes 32 and 24 bytes; scale is a relative index into the table below, with the recommended scale at index -minRel).
# No authoritative URL recorded. The probe validates it by read-back: the current scale must equal the value set, or the probe fails.
# Scale table (percent): 100 125 150 175 200 225 250 300 350 400 450 500
param(
    [int]$Target = 250,
    [string]$OutFile = "$env:RUNNER_TEMP\dpi-probe.json"
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DpiNative {
    [StructLayout(LayoutKind.Sequential)] public struct LUID { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential)] public struct DeviceInfoHeader { public int type; public uint size; public LUID adapterId; public uint id; }
    [StructLayout(LayoutKind.Sequential)] public struct SourceDpiScaleGet { public DeviceInfoHeader header; public int minRel; public int curRel; public int maxRel; }
    [StructLayout(LayoutKind.Sequential)] public struct SourceDpiScaleSet { public DeviceInfoHeader header; public int scaleRel; }
    [DllImport("user32.dll")] public static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPaths, out uint numModes);
    [DllImport("user32.dll")] public static extern int QueryDisplayConfig(uint flags, ref uint numPaths, byte[] paths, ref uint numModes, IntPtr modes, IntPtr topology);
    [DllImport("user32.dll")] public static extern int DisplayConfigGetDeviceInfo(ref SourceDpiScaleGet p);
    [DllImport("user32.dll")] public static extern int DisplayConfigSetDeviceInfo(ref SourceDpiScaleSet p);
    [DllImport("user32.dll", EntryPoint = "ChangeDisplaySettingsExW", CharSet = CharSet.Unicode)] public static extern int ChangeDisplaySettingsEx(string device, byte[] devmode, IntPtr hwnd, uint flags, IntPtr param);
    [DllImport("user32.dll")] public static extern IntPtr SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll", EntryPoint = "CreateWindowExW", CharSet = CharSet.Unicode)] public static extern IntPtr CreateWindowEx(uint ex, string cls, string name, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);
    [DllImport("user32.dll")] public static extern bool DestroyWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
}
'@

$tbl = @(100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500)
$report = [ordered]@{ target = $Target; steps = @() }
function Log([string]$m) { Write-Host "[dpi-probe] $m"; $script:report.steps += $m }

function Get-Source {
    [uint32]$np = 0; [uint32]$nm = 0
    $r = [DpiNative]::GetDisplayConfigBufferSizes(2, [ref]$np, [ref]$nm)      # QDC_ONLY_ACTIVE_PATHS = 2
    if ($r -ne 0) { throw "GetDisplayConfigBufferSizes $r" }
    $paths = New-Object byte[] ($np * 72)                                       # DISPLAYCONFIG_PATH_INFO is 72 bytes
    $modes = [Runtime.InteropServices.Marshal]::AllocHGlobal([int]($nm * 64))   # DISPLAYCONFIG_MODE_INFO is 64 bytes
    try {
        $r = [DpiNative]::QueryDisplayConfig(2, [ref]$np, $paths, [ref]$nm, $modes, [IntPtr]::Zero)
    } finally { [Runtime.InteropServices.Marshal]::FreeHGlobal($modes) }
    if ($r -ne 0) { throw "QueryDisplayConfig $r" }
    # first path: sourceInfo at offset 0 = adapterId (LUID, 8 bytes) then id (uint32)
    $adapter = New-Object DpiNative+LUID
    $adapter.LowPart = [BitConverter]::ToUInt32($paths, 0)
    $adapter.HighPart = [BitConverter]::ToInt32($paths, 4)
    $id = [BitConverter]::ToUInt32($paths, 8)
    return @{ adapter = $adapter; id = $id }
}

function New-Header([int]$type, [int]$size, $src) {
    $h = New-Object DpiNative+DeviceInfoHeader
    $h.type = $type; $h.size = [uint32]$size; $h.adapterId = $src.adapter; $h.id = $src.id
    return $h
}

function Get-Range($src) {
    $g = New-Object DpiNative+SourceDpiScaleGet
    $g.header = New-Header (-3) ([Runtime.InteropServices.Marshal]::SizeOf([type][DpiNative+SourceDpiScaleGet])) $src
    $r = [DpiNative]::DisplayConfigGetDeviceInfo([ref]$g)
    if ($r -ne 0) { throw "DisplayConfigGetDeviceInfo(-3) $r" }
    $rec = -$g.minRel                                    # recommended scale index in $tbl
    $abs = { param($rel) $i = $rec + $rel; if ($i -lt 0 -or $i -ge $tbl.Count) { 'out-of-table' } else { $tbl[$i] } }
    return [ordered]@{ minRel = $g.minRel; curRel = $g.curRel; maxRel = $g.maxRel; recommendedIndex = $rec;
                       minPct = (& $abs $g.minRel); curPct = (& $abs $g.curRel); maxPct = (& $abs $g.maxRel) }
}

try {
    $src = Get-Source
    Log ("primary source adapter={0:X8}:{1:X8} id={2}" -f $src.adapter.HighPart, $src.adapter.LowPart, $src.id)
    $report.resolutionBefore = "$([DpiNative]::GetSystemMetrics(0))x$([DpiNative]::GetSystemMetrics(1))"
    $r0 = Get-Range $src
    $report.rangeBefore = $r0
    Log ("resolution {0}; scale range before: min {1}% cur {2}% max {3}% (rel {4}/{5}/{6}, recommended index {7})" -f $report.resolutionBefore, $r0.minPct, $r0.curPct, $r0.maxPct, $r0.minRel, $r0.curRel, $r0.maxRel, $r0.recommendedIndex)

    $ti = [array]::IndexOf($tbl, $Target)
    if ($ti -lt 0) { throw "target $Target% is not in the scale table" }
    if ($r0.recommendedIndex + $r0.maxRel -lt $ti) {
        # step 2: the maximum allowed scale is below the target: raise the resolution, then re-read
        $dm = New-Object byte[] 220                                              # DEVMODEW, Unicode
        [BitConverter]::GetBytes([uint16]220).CopyTo($dm, 68)                    # dmSize
        [BitConverter]::GetBytes([uint32](0x80000 -bor 0x100000)).CopyTo($dm, 72) # dmFields = DM_PELSWIDTH | DM_PELSHEIGHT
        [BitConverter]::GetBytes([uint32]32).CopyTo($dm, 168)                    # dmBitsPerPel
        [BitConverter]::GetBytes([uint32]2560).CopyTo($dm, 172)                  # dmPelsWidth
        [BitConverter]::GetBytes([uint32]1600).CopyTo($dm, 176)                  # dmPelsHeight
        $c = [DpiNative]::ChangeDisplaySettingsEx($null, $dm, [IntPtr]::Zero, 0, [IntPtr]::Zero)
        Log "ChangeDisplaySettingsEx 2560x1600 returned $c (0 = DISP_CHANGE_SUCCESSFUL)"
        $report.resolutionChange = $c
        Start-Sleep -Seconds 3
        $report.resolutionAfter = "$([DpiNative]::GetSystemMetrics(0))x$([DpiNative]::GetSystemMetrics(1))"
        $r0 = Get-Range $src
        $report.rangeAfterResolution = $r0
        Log ("resolution {0}; scale range after resolution: min {1}% cur {2}% max {3}%" -f $report.resolutionAfter, $r0.minPct, $r0.curPct, $r0.maxPct)
        if ($r0.recommendedIndex + $r0.maxRel -lt $ti) { throw "maximum scale $($r0.maxPct)% is still below $Target% after the resolution change" }
    }

    # step 3: set the target scale (relative index)
    $s = New-Object DpiNative+SourceDpiScaleSet
    $s.header = New-Header (-4) ([Runtime.InteropServices.Marshal]::SizeOf([type][DpiNative+SourceDpiScaleSet])) $src
    $s.scaleRel = $ti - $r0.recommendedIndex
    $r = [DpiNative]::DisplayConfigSetDeviceInfo([ref]$s)
    Log "DisplayConfigSetDeviceInfo(-4) scaleRel=$($s.scaleRel) returned $r (0 = success)"
    $report.setReturn = $r
    if ($r -ne 0) { throw "DisplayConfigSetDeviceInfo(-4) $r" }
    Start-Sleep -Seconds 3

    # step 4: read back, then a per-monitor-aware window
    $r1 = Get-Range $src
    $report.rangeAfterSet = $r1
    Log ("scale range after set: cur {0}% (rel {1})" -f $r1.curPct, $r1.curRel)
    if ($r1.curPct -ne $Target) { throw "read-back scale $($r1.curPct)% is not $Target%" }

    $prev = [DpiNative]::SetProcessDpiAwarenessContext([IntPtr](-4))            # DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
    $hwnd = [DpiNative]::CreateWindowEx(0, 'STATIC', 'dpi-probe', 0x80000000, 0, 0, 200, 200, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero, [IntPtr]::Zero)  # WS_POPUP
    if ($hwnd -eq [IntPtr]::Zero) { throw 'CreateWindowEx failed' }
    $dpi = [DpiNative]::GetDpiForWindow($hwnd)
    [void][DpiNative]::DestroyWindow($hwnd)
    $report.windowDpi = $dpi
    $report.windowPct = [math]::Round($dpi / 96 * 100)
    Log "per-monitor-aware window GetDpiForWindow = $dpi ($($report.windowPct)%)"
    if ($dpi -ne 240) { throw "GetDpiForWindow is $dpi, not 240" }
    $report.ok = $true
    $code = 0
}
catch {
    $report.ok = $false
    $report.error = $_.Exception.Message
    Log "FAILED: $($_.Exception.Message)"
    $code = 1
}
$report | ConvertTo-Json -Depth 6 | Set-Content -Path $OutFile -Encoding utf8
Write-Host "[dpi-probe] wrote $OutFile (ok=$($report.ok))"
exit $code
