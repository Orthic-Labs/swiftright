# ABI 0.8 DLL-pair harness (headless console; opens no window, loads no GUI). Loads ONE renderer DLL, reads every discovery view it
# exports, and (when it exports 0.8) asks the face resolver real questions. Run once per DLL and diff the outputs:
#   0.7 host on a 0.8 renderer  -> the legacy and _v07 lines of the 0.8 DLL equal the pinned 0.7 DLL's lines, and the 0.8 table
#                                  starts with the 0.7 table's pointers (TABLE_PREFIX_EQUAL).
#   0.8 host on a 0.7 renderer  -> V08_EXPORTS=none on the 0.7 DLL (the bridge then falls back to 0.7 or refuses: Swift tests).
# usage: powershell -NoProfile -ExecutionPolicy Bypass -File abi08-dll-harness.ps1 -Dll <path> [-Label <text>]
param([Parameter(Mandatory = $true)][string]$Dll, [string]$Label = "")
$ErrorActionPreference = "Stop"
trap { [Console]::WriteLine("ERROR: " + $_ + " at line " + $_.InvocationInfo.ScriptLineNumber); exit 1 }
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Swr {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr LoadLibraryW(string p);
  [DllImport("kernel32.dll", CharSet = CharSet.Ansi)] public static extern IntPtr GetProcAddress(IntPtr m, string n);
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct ACTCTX { public int cbSize; public uint flags; public string src; public ushort arch; public ushort lang; public string dir; public string res; public string app; public IntPtr mod; }
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] public static extern IntPtr CreateActCtxW(ref ACTCTX c);
  [DllImport("kernel32.dll", SetLastError = true)] public static extern bool ActivateActCtx(IntPtr h, out IntPtr cookie);
  // The renderer imports comctl32 v6 (TaskDialogIndirect): a host normally carries the manifest, this console process does not.
  public static bool ComCtl6() {
    string man = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "swr-abi08.manifest");
    System.IO.File.WriteAllText(man, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><assembly xmlns=\"urn:schemas-microsoft-com:asm.v1\" manifestVersion=\"1.0\"><dependency><dependentAssembly><assemblyIdentity type=\"win32\" name=\"Microsoft.Windows.Common-Controls\" version=\"6.0.0.0\" processorArchitecture=\"*\" publicKeyToken=\"6595b64144ccf1df\" language=\"*\"/></dependentAssembly></dependency></assembly>");
    ACTCTX ac = new ACTCTX(); ac.cbSize = Marshal.SizeOf(typeof(ACTCTX)); ac.src = man;
    IntPtr h = CreateActCtxW(ref ac); IntPtr cookie;
    return h.ToInt64() != -1 && ActivateActCtx(h, out cookie);
  }
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int Query(IntPtr o, uint size);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int FaceMetrics(byte[] fam, uint len, uint weight, uint width, uint italic, IntPtr o);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int SysInfo(IntPtr o);
  public static Query MakeQuery(IntPtr p) { return (Query)Marshal.GetDelegateForFunctionPointer(p, typeof(Query)); }
  public static FaceMetrics MakeFace(IntPtr p) { return (FaceMetrics)Marshal.GetDelegateForFunctionPointer(p, typeof(FaceMetrics)); }
  public static SysInfo MakeSys(IntPtr p) { return (SysInfo)Marshal.GetDelegateForFunctionPointer(p, typeof(SysInfo)); }
}
"@
function U32($p, $o) { [BitConverter]::ToUInt32([BitConverter]::GetBytes([System.Runtime.InteropServices.Marshal]::ReadInt32($p, $o)), 0) }
function I32($p, $o) { [System.Runtime.InteropServices.Marshal]::ReadInt32($p, $o) }
function F32($p, $o) { [BitConverter]::ToSingle([BitConverter]::GetBytes([System.Runtime.InteropServices.Marshal]::ReadInt32($p, $o)), 0) }
function CStr($p, $o, $max) {
  $b = New-Object byte[] $max; [System.Runtime.InteropServices.Marshal]::Copy([IntPtr]($p.ToInt64() + $o), $b, 0, $max)
  $n = [Array]::IndexOf($b, [byte]0); if ($n -lt 0) { $n = $max }
  [Text.Encoding]::UTF8.GetString($b, 0, $n)
}
function Out-Line($k, $v) { [Console]::WriteLine(("{0}={1}" -f $k, $v)) }
function Tag($t) { $b = [BitConverter]::GetBytes([uint32]$t); [Array]::Reverse($b); [Text.Encoding]::ASCII.GetString($b) }

Out-Line "ACTCTX" ([Swr]::ComCtl6())
$m = [Swr]::LoadLibraryW($Dll)
if ($m -eq [IntPtr]::Zero) { Out-Line "LOAD" ("failed win32=" + [Runtime.InteropServices.Marshal]::GetLastWin32Error()); exit 2 }
Out-Line "DLL" ((Split-Path $Dll -Leaf) + " sha256=" + (Get-FileHash $Dll -Algorithm SHA256).Hash.ToLower())
Out-Line "LABEL" $Label
$exports = @("swr_bootstrap_query", "swr_get_api", "swr_bootstrap_query_v07", "swr_get_api_v07", "swr_bootstrap_query_v08", "swr_get_api_v08",
             "swr_measure_text_v08", "swr_text_run_faces", "swr_font_face_metrics", "swr_system_font_info")
$p = @{}
foreach ($e in $exports) { $p[$e] = [Swr]::GetProcAddress($m, $e); Out-Line ("EXPORT " + $e) ($p[$e] -ne [IntPtr]::Zero) }
$has08 = ($p["swr_bootstrap_query_v08"] -ne [IntPtr]::Zero) -and ($p["swr_get_api_v08"] -ne [IntPtr]::Zero)
Out-Line "V08_EXPORTS" $(if ($has08) { "both" } elseif (($p["swr_bootstrap_query_v08"] -ne [IntPtr]::Zero) -or ($p["swr_get_api_v08"] -ne [IntPtr]::Zero)) { "HALF" } else { "none" })

function Dump-Boot($name, $size) {
  $buf = [Runtime.InteropServices.Marshal]::AllocHGlobal($size + 64)
  for ($i = 0; $i -lt $size + 64; $i += 4) { [Runtime.InteropServices.Marshal]::WriteInt32($buf, $i, 0) }
  $rc = ([Swr]::MakeQuery($p[$name])).Invoke($buf, [uint32]$size)
  $words = @(); for ($i = 0; $i -lt $size; $i += 4) { $words += (U32 $buf $i) }
  Out-Line ("BOOT " + $name + " rc") $rc
  Out-Line ("BOOT " + $name + " words") ($words -join ",")
  Out-Line ("BOOT " + $name + " abi_minor") $words[2]
  Out-Line ("BOOT " + $name + " api_table_size") $words[(4 + 4 + 1) + 0]
  return $buf
}
# legacy view: 88 bytes; _v07: 96; _v08: 120
$null = Dump-Boot "swr_bootstrap_query" 88
if ($p["swr_bootstrap_query_v07"] -ne [IntPtr]::Zero) { $null = Dump-Boot "swr_bootstrap_query_v07" 96 }
if ($has08) { $b8 = Dump-Boot "swr_bootstrap_query_v08" 120 }

function Table($name, $size) {
  $buf = [Runtime.InteropServices.Marshal]::AllocHGlobal($size)
  for ($i = 0; $i -lt $size; $i += 4) { [Runtime.InteropServices.Marshal]::WriteInt32($buf, $i, 0) }
  $rc = ([Swr]::MakeQuery($p[$name])).Invoke($buf, [uint32]$size)
  Out-Line ("TABLE " + $name + " rc") $rc
  Out-Line ("TABLE " + $name + " struct_size") (U32 $buf 0)
  return $buf
}
$t6 = Table "swr_get_api" 136
$t7 = $null
if ($p["swr_get_api_v07"] -ne [IntPtr]::Zero) { $t7 = Table "swr_get_api_v07" 152 }
if ($has08) {
  $t8 = Table "swr_get_api_v08" 184
  # the 0.8 table keeps the 0.7 table's 18 pointers at the same offsets (8 + 8*i), and the 0.7 table keeps the 0.6 table's 16.
  $eq7 = $true; for ($i = 0; $i -lt 18; $i++) { if ([Runtime.InteropServices.Marshal]::ReadInt64($t8, 8 + 8 * $i) -ne [Runtime.InteropServices.Marshal]::ReadInt64($t7, 8 + 8 * $i)) { $eq7 = $false } }
  Out-Line "TABLE_PREFIX_EQUAL v08==v07 (18 pointers)" $eq7
  $eq6 = $true; for ($i = 0; $i -lt 16; $i++) { if ([Runtime.InteropServices.Marshal]::ReadInt64($t7, 8 + 8 * $i) -ne [Runtime.InteropServices.Marshal]::ReadInt64($t6, 8 + 8 * $i)) { $eq6 = $false } }
  Out-Line "TABLE_PREFIX_EQUAL v07==v06 (16 pointers)" $eq6
  $mt = [Runtime.InteropServices.Marshal]::ReadInt64($t8, 152)
  Out-Line "V08_ENTRIES_NONZERO" (([Runtime.InteropServices.Marshal]::ReadInt64($t8, 152) -ne 0) -and ([Runtime.InteropServices.Marshal]::ReadInt64($t8, 160) -ne 0) -and ([Runtime.InteropServices.Marshal]::ReadInt64($t8, 168) -ne 0) -and ([Runtime.InteropServices.Marshal]::ReadInt64($t8, 176) -ne 0))
  # a too-small caller is refused whole (E_ABI = -14), nothing written
  $small = [Runtime.InteropServices.Marshal]::AllocHGlobal(183)
  Out-Line "TABLE swr_get_api_v08 caller 183 -> rc" (([Swr]::MakeQuery($p["swr_get_api_v08"])).Invoke($small, 183))

  # face resolver: needs no window and no UI thread
  $fm = [Swr]::MakeFace($p["swr_font_face_metrics"])
  function Face($family, $weight, $italic) {
    $o = [Runtime.InteropServices.Marshal]::AllocHGlobal(456)
    for ($i = 0; $i -lt 456; $i += 4) { [Runtime.InteropServices.Marshal]::WriteInt32($o, $i, 0) }
    [Runtime.InteropServices.Marshal]::WriteInt32($o, 0, 456)
    $fb = [Text.Encoding]::UTF8.GetBytes($family)
    $rc = $fm.Invoke($fb, [uint32]$fb.Length, [uint32]$weight, 0, [uint32]$italic, $o)
    $axes = @(); $n = U32 $o 68
    for ($i = 0; $i -lt $n; $i++) { $a = 72 + 16 * $i; $axes += ("{0}:{1}..{2}@{3}" -f (Tag (U32 $o $a)), (F32 $o ($a + 4)), (F32 $o ($a + 8)), (F32 $o ($a + 12))) }
    Out-Line ("FACE [" + $family + "] w" + $weight + " i" + $italic) ("rc=$rc flags=" + (U32 $o 4) + " weight=" + (U32 $o 8) + " style=" + (U32 $o 12) + " sims=" + (U32 $o 16) + " source=" + (U32 $o 20) +
      " upem=" + (U32 $o 24) + " hhea=" + (I32 $o 28) + "/" + (I32 $o 32) + "/" + (I32 $o 36) + " cap=" + (U32 $o 60) + " xh=" + (U32 $o 64) +
      " axes=[" + ($axes -join ";") + "] ps=" + (CStr $o 296 64) + " ver=" + (CStr $o 360 32) + " file=" + (CStr $o 392 64))
    [Runtime.InteropServices.Marshal]::FreeHGlobal($o)
  }
  foreach ($c in @(@("Segoe UI Variable Text", 400, 0), @("Segoe UI Variable Text", 500, 0), @("Segoe UI Variable Text", 100, 0), @("Segoe UI Variable Text", 900, 0),
                   @("Segoe UI Variable Display", 400, 0), @("Segoe UI Variable Small", 400, 0), @("Segoe UI Variable", 400, 0),
                   @("Segoe UI", 400, 0), @("Segoe UI", 900, 0), @("Segoe UI", 400, 1), @("Cascadia Mono", 400, 0), @("Sitka Text", 400, 0),
                   @("Tinos", 400, 0), @("No Such Family SRProbe", 400, 0))) { Face $c[0] $c[1] $c[2] }
  $si = [Swr]::MakeSys($p["swr_system_font_info"])
  $o = [Runtime.InteropServices.Marshal]::AllocHGlobal(720)
  for ($i = 0; $i -lt 720; $i += 4) { [Runtime.InteropServices.Marshal]::WriteInt32($o, $i, 0) }
  [Runtime.InteropServices.Marshal]::WriteInt32($o, 0, 720)
  $rc = $si.Invoke($o)
  Out-Line "SYSINFO" ("rc=$rc flags=" + (U32 $o 4) + " families=" + (U32 $o 8))
  for ($i = 0; $i -lt 8; $i++) { $e = 16 + 88 * $i; Out-Line ("SYSINFO entry " + $i) ((CStr $o $e 48) + " present=" + (U32 $o ($e + 80)) + " faces=" + (U32 $o ($e + 84)) + " version=" + (CStr $o ($e + 48) 32)) }
}
