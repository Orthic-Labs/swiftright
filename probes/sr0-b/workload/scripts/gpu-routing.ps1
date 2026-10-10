# W5 step 1: GPU / output routing facts (read-only). Usage: powershell -NoProfile -File gpu-routing.ps1 -Out <dir>
param([string]$Out = 'D:\Claude\sr0-r08\workload\runs\w5\routing')
New-Item -ItemType Directory -Force $Out | Out-Null
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;
public static class Gr {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct AD1 { [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description; public uint VendorId, DeviceId, SubSysId, Revision; public UIntPtr Ded, DedSys, Shared; public uint LuidLow; public int LuidHigh; public uint Flags; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct OD { [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName; public int L, T, R, B; public int Attached; public int Rotation; public IntPtr Monitor; }
  [ComImport, Guid("770aae78-f26f-4dba-a829-253c83d1b387"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IF1 { void a(); void b(); void c(); void d(); [PreserveSig] int EnumAdapters(uint i, out IntPtr a); void e(); void f(); void g(); void h(); [PreserveSig] int EnumAdapters1(uint i, out IA1 a); [PreserveSig] int IsCurrent(); }
  [ComImport, Guid("29038f61-3839-4626-91fd-086879011a05"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IA1 { void a(); void b(); void c(); void d(); [PreserveSig] int EnumOutputs(uint i, out IO o); void GetDesc(); void Check(); [PreserveSig] int GetDesc1(out AD1 d); }
  [ComImport, Guid("ae02eedb-c735-4690-8d52-5a8dc20213aa"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IO { void a(); void b(); void c(); void d(); [PreserveSig] int GetDesc(out OD d); }
  [DllImport("dxgi.dll")] static extern int CreateDXGIFactory1(ref Guid r, [MarshalAs(UnmanagedType.Interface)] out IF1 f);
  public static List<string> Dxgi() {
    var res = new List<string>(); var g = new Guid("770aae78-f26f-4dba-a829-253c83d1b387"); IF1 f;
    if (CreateDXGIFactory1(ref g, out f) != 0) return res;
    for (uint i = 0; i < 16; i++) { IA1 a; if (f.EnumAdapters1(i, out a) != 0) break; AD1 d; a.GetDesc1(out d);
      string luid = "0x" + ((uint)d.LuidHigh).ToString("x8") + "_0x" + d.LuidLow.ToString("x8");
      res.Add("adapter " + i + " luid=" + luid + " name=" + d.Description + " vendor=0x" + d.VendorId.ToString("x4") + " device=0x" + d.DeviceId.ToString("x4") + " rev=" + d.Revision + " dedicated_mb=" + (d.Ded.ToUInt64() >> 20) + " shared_mb=" + (d.Shared.ToUInt64() >> 20) + " flags=" + d.Flags);
      for (uint j = 0; j < 16; j++) { IO o; if (a.EnumOutputs(j, out o) != 0) break; OD od; o.GetDesc(out od);
        res.Add("  output " + j + " adapter_index=" + i + " adapter_luid=" + luid + " device=" + od.DeviceName + " desktop=(" + od.L + "," + od.T + ")-(" + od.R + "," + od.B + ") attached=" + od.Attached + " rotation=" + od.Rotation); } }
    return res; }
  [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint np, out uint nm);
  [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint np, byte[] paths, ref uint nm, byte[] modes, IntPtr topo);
  public static List<string> Paths() {
    var res = new List<string>(); uint np, nm; if (GetDisplayConfigBufferSizes(2, out np, out nm) != 0) { res.Add("GetDisplayConfigBufferSizes failed"); return res; }
    var p = new byte[np * 72]; var m = new byte[nm * 64];
    int rc = QueryDisplayConfig(2, ref np, p, ref nm, m, IntPtr.Zero); if (rc != 0) { res.Add("QueryDisplayConfig rc=" + rc); return res; }
    for (int i = 0; i < np; i++) { int o = i * 72;
      Func<int, string> L = off => "0x" + BitConverter.ToUInt32(p, o + off + 4).ToString("x8") + "_0x" + BitConverter.ToUInt32(p, o + off).ToString("x8");
      res.Add("path " + i + " source_adapter_luid=" + L(0) + " source_id=" + BitConverter.ToUInt32(p, o + 8) + " target_adapter_luid=" + L(20) + " target_id=" + BitConverter.ToUInt32(p, o + 28) + " outputTechnology=" + BitConverter.ToInt32(p, o + 36) + " refresh=" + BitConverter.ToUInt32(p, o + 48) + "/" + BitConverter.ToUInt32(p, o + 52) + " targetAvailable=" + BitConverter.ToUInt32(p, o + 60) + " flags=" + BitConverter.ToUInt32(p, o + 68)); }
    return res; }
}
'@
$o = @()
$o += "# gpu-routing $(Get-Date -Format o) host=$env:COMPUTERNAME"
$o += "## DXGI adapters and outputs (default process, EnumAdapters1 order)"; $o += [Gr]::Dxgi()
$o += "## Active display paths (QueryDisplayConfig, QDC_ONLY_ACTIVE_PATHS): source adapter owns the desktop surface / output"; $o += [Gr]::Paths()
$o += "## HAGS (HKLM GraphicsDrivers)"
$gd = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -ErrorAction SilentlyContinue
$o += "HwSchMode=$($gd.HwSchMode) (1=default/off, 2=on) HwSchModeAtLastBoot? n/a; TdrDelay=$($gd.TdrDelay)"
$o += "## Win32_VideoController"
foreach ($v in Get-CimInstance Win32_VideoController) { $o += "name=$($v.Name) driver=$($v.DriverVersion) date=$($v.DriverDate) pnp=$($v.PNPDeviceID) mode=$($v.CurrentHorizontalResolution)x$($v.CurrentVerticalResolution)@$($v.CurrentRefreshRate) status=$($v.Status)" }
$o += "## Win32_DesktopMonitor / PnP monitors"
foreach ($m in Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPClass -eq 'Monitor' }) { $o += "monitor name=$($m.Name) id=$($m.PNPDeviceID) status=$($m.Status)" }
$o += "## nvidia-smi"
$smi = (Get-Command nvidia-smi -ErrorAction SilentlyContinue).Source; if (-not $smi) { $smi = 'C:\Windows\System32\nvidia-smi.exe' }
if (Test-Path $smi) { $o += (& $smi --query-gpu=name,driver_version,pci.bus_id,display_mode,display_active,vbios_version,power.management,clocks.max.graphics --format=csv 2>&1); $o += (& $smi -q -d PERFORMANCE,CLOCK 2>&1 | Select-String -Pattern 'Performance State|Display|MUX|Mode' | ForEach-Object { $_.Line }) } else { $o += 'nvidia-smi not found' }
$o += "## Per-app GPU preferences (HKCU\Software\Microsoft\DirectX\UserGpuPreferences)"
$up = Get-ItemProperty 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' -ErrorAction SilentlyContinue
if ($up) { $up.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { $o += "$($_.Name) = $($_.Value)" } } else { $o += '(key absent)' }
$o += "## Global default GPU preference (DirectX\GraphicsSettings)"
$gs = Get-ItemProperty 'HKCU:\Software\Microsoft\DirectX\GraphicsSettings' -ErrorAction SilentlyContinue
if ($gs) { $gs.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object { $o += "$($_.Name) = $($_.Value)" } } else { $o += '(key absent)' }
$o += "## Battery / power"
foreach ($b in Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue) { $o += "battery status=$($b.BatteryStatus) charge=$($b.EstimatedChargeRemaining)" }
$o += "powercfg scheme: $((powercfg /getactivescheme) -join ' ')"
$o | Set-Content -Encoding utf8 "$Out\routing.txt"
Start-Process dxdiag -ArgumentList "/t","$Out\dxdiag.txt" -Wait -WindowStyle Hidden
$o
