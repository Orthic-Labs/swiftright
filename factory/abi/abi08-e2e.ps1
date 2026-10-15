# ABI 0.8 end-to-end check on a REAL window (run it in the Windows Sandbox, never on a user desktop):
#   python3 factory/tools/sandbox/cmdjob.py factory/abi/abi08-e2e.ps1   (after copying the DLL/font to the mapped inputs folder)
# The mapped inputs folder is read-only in the Sandbox: the PNG goes to $env:TEMP and is returned as PNG_B64=<base64> on stdout.
# Loads the 0.8 renderer, opens its window, and from `loop_ready` (UI thread) registers bundled Tinos, measures with swr_measure_text_v08
# (kern, tracking, baseline offset, simulation policy, weight snapping), reads swr_text_run_faces, paints three tracked/untracked lines
# through the real gpui paint path and captures the window. Prints KEY=VALUE lines. It opens one window for about four seconds.
param([string]$Dll = "D:\Claude\swiftright\.factory-work\inputs\renderer-0.8\swiftright_render_v08.dll",
      [string]$Font = "D:\Claude\swiftright\.factory-work\inputs\renderer-0.8\Tinos-Regular.ttf",
      [string]$Out = "$env:TEMP\abi08-e2e-out")
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force $Out | Out-Null
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class E2E {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr LoadLibraryW(string p);
  [DllImport("kernel32.dll", CharSet = CharSet.Ansi)] static extern IntPtr GetProcAddress(IntPtr m, string n);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateEventW(IntPtr a, bool manual, bool initial, string name);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindowW(string cls, string title);
  [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr hwnd, out RECT r);
  [StructLayout(LayoutKind.Sequential)] struct RECT { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct ACTCTX { public int cbSize; public uint flags; public string src; public ushort arch; public ushort lang; public string dir; public string res; public string app; public IntPtr mod; }
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateActCtxW(ref ACTCTX c);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool ActivateActCtx(IntPtr h, out IntPtr cookie);

  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Run(IntPtr o, IntPtr cb);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Fn0();
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FnPtr(IntPtr a);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FnPtr2(IntPtr a, IntPtr b);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Reg(IntPtr bytes, ulong len, IntPtr info);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Faces(ulong run, IntPtr o, uint cap, IntPtr count);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Cells(ulong run, IntPtr o, uint cap, IntPtr count);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Metrics(ulong win, IntPtr o);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Rel(ulong run);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void LoopReady(IntPtr ctx, ulong window);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void Drain(IntPtr ctx);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate void Closed(IntPtr ctx, ulong window);

  static IntPtr mod;
  static Run run; static Fn0 quit, shutdownComplete; static Reg reg; static FnPtr2 measure8; static Faces faces; static Cells cells;
  static Metrics winMetrics; static FnPtr commit;
  static string fontPath, outDir; static List<string> log = new List<string>();
  static LoopReady cbReady; static Drain cbDrain; static Closed cbClosed;   // kept alive
  static void L(string k, object v) { string s = k + "=" + v; log.Add(s); Console.WriteLine(s); }

  static T Bind<T>(string name) where T : class {
    IntPtr p = GetProcAddress(mod, name);
    if (p == IntPtr.Zero) throw new Exception("missing export " + name);
    return (T)(object)Marshal.GetDelegateForFunctionPointer(p, typeof(T));
  }
  static IntPtr Utf8(string s) { byte[] b = Encoding.UTF8.GetBytes(s); IntPtr p = Marshal.AllocHGlobal(b.Length + 1); Marshal.Copy(b, 0, p, b.Length); Marshal.WriteByte(p, b.Length, 0); return p; }
  static IntPtr Zero(int n) { IntPtr p = Marshal.AllocHGlobal(n); for (int i = 0; i < n; i++) Marshal.WriteByte(p, i, 0); return p; }
  static void F(IntPtr p, int o, float v) { Marshal.WriteInt32(p, o, BitConverter.ToInt32(BitConverter.GetBytes(v), 0)); }
  static float Rf(IntPtr p, int o) { return BitConverter.ToSingle(BitConverter.GetBytes(Marshal.ReadInt32(p, o)), 0); }
  static uint Ru(IntPtr p, int o) { return (uint)Marshal.ReadInt32(p, o); }
  static string Cs(IntPtr p, int o, int max) { byte[] b = new byte[max]; Marshal.Copy(new IntPtr(p.ToInt64() + o), b, 0, max); int n = Array.IndexOf(b, (byte)0); if (n < 0) n = max; return Encoding.UTF8.GetString(b, 0, n); }

  public class M { public ulong run; public float width, height, firstBaseline; public uint lines, applied, ignored, sims, italic; public float resolvedWeight; public int rc; }
  public class Opt { public float weightF, tracking, kerning, baseline = -1, scale = 1; public uint italic, simulations; public string[] features = new string[0]; public string[] fallbacks = new string[0]; public float size = 18, lh = 22; }

  static M Measure(string text, string family, uint weight, Opt o) {
    IntPtr req = Zero(160), res = Zero(88);
    Marshal.WriteInt32(req, 0, 160);
    uint flags = o.baseline >= 0 ? 1u : 0u; Marshal.WriteInt32(req, 4, (int)flags);
    Marshal.WriteInt32(req, 8, 88);
    byte[] tb = Encoding.UTF8.GetBytes(text);
    Marshal.WriteIntPtr(req, 16, Utf8(text)); Marshal.WriteIntPtr(req, 24, Utf8(family)); Marshal.WriteIntPtr(req, 32, Utf8("en-US"));
    Marshal.WriteInt32(req, 48, tb.Length); Marshal.WriteInt32(req, 52, Encoding.UTF8.GetByteCount(family)); Marshal.WriteInt32(req, 56, 5);
    Marshal.WriteInt32(req, 60, (int)weight); Marshal.WriteInt32(req, 68, unchecked((int)0x000000FF));
    F(req, 72, o.size); F(req, 76, o.lh); F(req, 80, o.scale); F(req, 84, 0);
    F(req, 96, o.weightF); F(req, 112, o.tracking); F(req, 116, o.kerning); F(req, 120, o.baseline < 0 ? 0 : o.baseline);
    Marshal.WriteInt32(req, 124, (int)o.italic); Marshal.WriteInt32(req, 128, (int)o.simulations);
    IntPtr fe = Zero(8 * 16);
    for (int i = 0; i < o.features.Length; i++) {
      string t = o.features[i].Substring(0, 4); uint v = uint.Parse(o.features[i].Substring(5));
      uint tag = ((uint)t[0] << 24) | ((uint)t[1] << 16) | ((uint)t[2] << 8) | (uint)t[3];
      Marshal.WriteInt32(fe, 8 * i, unchecked((int)tag)); Marshal.WriteInt32(fe, 8 * i + 4, (int)v);
    }
    Marshal.WriteInt32(req, 132, o.features.Length); Marshal.WriteIntPtr(req, 136, fe);
    IntPtr fb = Zero(16 * 8);
    for (int i = 0; i < o.fallbacks.Length; i++) { Marshal.WriteIntPtr(fb, 16 * i, Utf8(o.fallbacks[i])); Marshal.WriteInt32(fb, 16 * i + 8, Encoding.UTF8.GetByteCount(o.fallbacks[i])); }
    Marshal.WriteIntPtr(req, 144, fb); Marshal.WriteInt32(req, 152, o.fallbacks.Length);
    Marshal.WriteInt32(res, 0, 88);
    M m = new M();
    m.rc = measure8(req, res);
    m.run = (ulong)Marshal.ReadInt64(res, 16); m.width = Rf(res, 24); m.height = Rf(res, 28); m.firstBaseline = Rf(res, 32);
    m.lines = Ru(res, 40); m.applied = Ru(res, 64); m.ignored = Ru(res, 68); m.resolvedWeight = Rf(res, 72); m.italic = Ru(res, 76); m.sims = Ru(res, 80);
    return m;
  }
  static string Dump(string tag, M m) {
    return tag + " rc=" + m.rc + " width=" + m.width.ToString("F3") + " height=" + m.height.ToString("F3") + " firstBaseline=" + m.firstBaseline.ToString("F3") +
      " lines=" + m.lines + " applied=0x" + m.applied.ToString("x") + " ignored=0x" + m.ignored.ToString("x") + " resolvedWeight=" + m.resolvedWeight + " italic=" + m.italic + " sims=" + m.sims;
  }
  static void DumpFaces(string tag, ulong runHandle) {
    IntPtr count = Zero(8);
    int rc = faces(runHandle, IntPtr.Zero, 0, count);
    uint n = Ru(count, 0);
    IntPtr buf = Zero((int)(296 * Math.Max(n, 1)));
    rc = faces(runHandle, buf, n, count);
    L(tag + " runs", "rc=" + rc + " count=" + n);
    for (uint i = 0; i < n; i++) {
      int b = (int)(296 * i);
      StringBuilder sha = new StringBuilder(); for (int k = 0; k < 32; k++) sha.Append(Marshal.ReadByte(buf, b + 40 + k).ToString("x2"));
      L(tag + " run" + i, "utf8=" + Ru(buf, b) + "+" + Ru(buf, b + 4) + " glyphs=" + Ru(buf, b + 8) + " notdef=" + Ru(buf, b + 12) + " flags=0x" + Ru(buf, b + 16).ToString("x") + " weight=" + Ru(buf, b + 20) +
        " asc=" + Rf(buf, b + 24).ToString("F2") + " desc=" + Rf(buf, b + 28).ToString("F2") + " adv=" + Rf(buf, b + 32).ToString("F2") + " sha256=" + sha + " family=[" + Cs(buf, b + 72, 64) + "] ps=[" + Cs(buf, b + 136, 64) +
        "] ver=[" + Cs(buf, b + 200, 32) + "] file=[" + Cs(buf, b + 232, 64) + "]");
    }
  }
  static float LastCellX1(ulong runHandle, out uint count) {
    IntPtr c = Zero(8); cells(runHandle, IntPtr.Zero, 0, c); count = Ru(c, 0);
    IntPtr buf = Zero((int)(24 * Math.Max(count, 1))); cells(runHandle, buf, count, c);
    return count == 0 ? 0 : Rf(buf, (int)(24 * (count - 1) + 20));
  }

  static ulong win; static float scale = 1; static ulong[] paintRuns = new ulong[3]; static int[] paintY = new int[] { 30, 110, 190 };
  static void Ready(IntPtr ctx, ulong window) {
    try { ReadyInner(window); } catch (Exception e) { L("READY_EXCEPTION", e.ToString().Replace("\n", " | ")); }
    new Thread(Finish).Start();
  }
  static void ReadyInner(ulong window) {
    win = window;
    IntPtr wm = Zero(24); Marshal.WriteInt32(wm, 0, 24); winMetrics(window, wm);
    scale = Rf(wm, 12); uint wpx = Ru(wm, 4), hpx = Ru(wm, 8);
    L("WINDOW", "px=" + wpx + "x" + hpx + " scale=" + scale);
    byte[] fb = System.IO.File.ReadAllBytes(fontPath);
    IntPtr fp = Marshal.AllocHGlobal(fb.Length); Marshal.Copy(fb, 0, fp, fb.Length);
    IntPtr info = Zero(128); Marshal.WriteInt32(info, 0, 128);
    int rrc = reg(fp, (ulong)fb.Length, info);
    StringBuilder sha = new StringBuilder(); for (int k = 0; k < 32; k++) sha.Append(Marshal.ReadByte(info, 32 + k).ToString("x2"));
    L("REGISTER", "rc=" + rrc + " flags=" + Ru(info, 4) + " family=[" + Cs(info, 64, 64) + "] sha256=" + sha);

    Opt o = new Opt(); o.scale = scale;
    // 1. kerning: gpui leaves it off; kern=1 must change the width (G15)
    string kt = "AVAWAY To Wa";
    M plain = Measure(kt, "Tinos", 400, o); L("KERN default", Dump("m", plain));
    Opt ok = new Opt(); ok.scale = scale; ok.features = new string[] { "kern=1" };
    M kern = Measure(kt, "Tinos", 400, ok); L("KERN kern=1", Dump("m", kern));
    Opt ok0 = new Opt(); ok0.scale = scale; ok0.features = new string[] { "kern=0" };
    M kern0 = Measure(kt, "Tinos", 400, ok0); L("KERN kern=0", Dump("m", kern0));
    L("KERN narrower_with_kern1", kern.width < plain.width && Math.Abs(kern0.width - plain.width) < 0.01);
    // 2. tracking: +4 DIP per cluster adds 4*scale per character to the width, and the cell geometry follows
    string tt = "Tracking";
    Opt ot = new Opt(); ot.scale = scale; M t0 = Measure(tt, "Tinos", 400, ot);
    ot.tracking = 4; M t4 = Measure(tt, "Tinos", 400, ot);
    ot.tracking = -1; M tm = Measure(tt, "Tinos", 400, ot);
    uint c0, c4; float x0 = LastCellX1(t0.run, out c0), x4 = LastCellX1(t4.run, out c4);
    L("TRACK 0", Dump("m", t0)); L("TRACK +4", Dump("m", t4)); L("TRACK -1", Dump("m", tm));
    L("TRACK widthDelta", (t4.width - t0.width).ToString("F3") + " expected=" + (4 * scale * 8).ToString("F3") + " lastCellDelta=" + (x4 - x0).ToString("F3"));
    // 3. baseline offset: the face baseline lies exactly the given DIP below the line top
    Opt ob = new Opt(); ob.scale = scale; ob.baseline = 15.5f; M bl = Measure("Hxg", "Tinos", 400, ob);
    L("BASELINE 15.5", Dump("m", bl) + " expectedPx=" + (15.5f * scale).ToString("F3"));
    // 4. simulation policy and weight snapping
    Opt os = new Opt(); os.scale = scale; os.weightF = 700;
    M bold = Measure("Bold?", "Tinos", 400, os); L("SIM allow bold", Dump("m", bold));
    os.simulations = 1; M nob = Measure("Bold?", "Tinos", 400, os); L("SIM forbid bold", Dump("m", nob));
    Opt oi = new Opt(); oi.scale = scale; oi.italic = 1; M it = Measure("Obl?", "Tinos", 400, oi); L("SIM allow oblique", Dump("m", it));
    oi.simulations = 2; M noi = Measure("Obl?", "Tinos", 400, oi); L("SIM forbid oblique", Dump("m", noi));
    Opt ow = new Opt(); ow.scale = scale; ow.weightF = 500; M w500 = Measure("Weight", "Segoe UI Variable Text", 400, ow); L("WEIGHT 500 Segoe UI Variable Text", Dump("m", w500));
    ow.weightF = 100; M w100 = Measure("Weight", "Segoe UI Variable Text", 400, ow); L("WEIGHT 100 Segoe UI Variable Text", Dump("m", w100));
    Opt oa = new Opt(); oa.scale = scale; M wd = Measure("Weight", "Segoe UI Variable Text", 400, oa); L("WEIGHT 400", Dump("m", wd));
    // axes gpui cannot honour are reported, never faked
    Opt ox = new Opt(); ox.scale = scale; M ig = Measure("Axes", "Segoe UI", 400, ox);
    L("IGNORED none", Dump("m", ig));
    // 5. fallback: a private (bundled) family is reported and ignored; a system family is applied
    Opt of = new Opt(); of.scale = scale; of.fallbacks = new string[] { "Tinos", "Segoe UI Emoji" }; M fbm = Measure("Fallback", "Segoe UI", 400, of); L("FALLBACK private+system", Dump("m", fbm));
    // 6. run faces: bundled Tinos names the registered hash; U+0378 is .notdef (negative control)
    M th = Measure("Hello", "Tinos", 400, o); DumpFaces("FACES Tinos Hello", th.run);
    M tn = Measure("A\u0378B", "Tinos", 400, o); DumpFaces("FACES Tinos A+U+0378+B", tn.run);
    M sg = Measure("Hello", "Segoe UI", 400, o); DumpFaces("FACES Segoe UI Hello", sg.run);
    M mix = Measure("A \u65E5\u672C \u03A9 \uD83D\uDE00 B", "Segoe UI", 400, o); DumpFaces("FACES Segoe UI mixed", mix.run);
    M mixt = Measure("A \u65E5\u672C \u03A9 \uD83D\uDE00 B", "Tinos", 400, o); DumpFaces("FACES Tinos mixed", mixt.run);
    // 7. paint through the real path: line 1 plain, line 2 kern=1, line 3 tracking +4 DIP (paint_glyph path)
    Opt p1 = new Opt(); p1.scale = scale; p1.size = 28; p1.lh = 34;
    Opt p2 = new Opt(); p2.scale = scale; p2.size = 28; p2.lh = 34; p2.tracking = 4;
    Opt p3 = new Opt(); p3.scale = scale; p3.size = 28; p3.lh = 34; p3.features = new string[] { "kern=1" };
    string pt = "AVAWAY Hamburg";
    M a = Measure(pt, "Tinos", 400, p1), b = Measure(pt, "Tinos", 400, p3), c = Measure(pt, "Tinos", 400, p2);
    paintRuns[0] = a.run; paintRuns[1] = b.run; paintRuns[2] = c.run;
    L("PAINT plain", Dump("m", a)); L("PAINT kern1", Dump("m", b)); L("PAINT track4", Dump("m", c));
    // transaction: one node, 4 primitives (white background, three text runs); coordinates are physical px
    int np = 4;
    IntPtr prims = Zero(80 * np);
    Marshal.WriteInt32(prims, 0, 1); Marshal.WriteInt32(prims, 4, unchecked((int)0xFFFFFFFF)); F(prims, 8, 0); F(prims, 12, 0); F(prims, 16, wpx); F(prims, 20, hpx);
    for (int i = 0; i < 3; i++) {
      int o8 = 80 * (i + 1);
      Marshal.WriteInt32(prims, o8, 2); Marshal.WriteInt64(prims, o8 + 40, (long)paintRuns[i]);
      F(prims, o8 + 8, 20 * scale); F(prims, o8 + 12, paintY[i] * scale);
    }
    IntPtr node = Zero(144);
    Marshal.WriteInt64(node, 0, 1); Marshal.WriteInt64(node, 8, 0); F(node, 16, 0); F(node, 20, 0); F(node, 24, wpx); F(node, 28, hpx);
    Marshal.WriteInt32(node, 32, 0); Marshal.WriteInt32(node, 36, 0); Marshal.WriteInt32(node, 40, 0); Marshal.WriteInt32(node, 44, np);
    IntPtr tx = Zero(72);
    Marshal.WriteInt32(tx, 0, 72); Marshal.WriteInt64(tx, 8, (long)window); Marshal.WriteInt64(tx, 16, 1); Marshal.WriteInt64(tx, 24, 0);
    Marshal.WriteIntPtr(tx, 32, node); Marshal.WriteIntPtr(tx, 48, prims);
    Marshal.WriteInt32(tx, 56, 1); Marshal.WriteInt32(tx, 64, np);
    L("COMMIT", commit(tx));
  }
  static void Finish() {
    try {
      Thread.Sleep(2500);
      IntPtr h = FindWindowW(null, "SwiftRight ABI 0.8 e2e");
      L("HWND", h != IntPtr.Zero);
      if (h != IntPtr.Zero) {
        RECT r; GetClientRect(h, out r); int w = r.r - r.l, hh = r.b - r.t;
        using (Bitmap bmp = new Bitmap(w, hh)) {
          using (Graphics g = Graphics.FromImage(bmp)) { IntPtr dc = g.GetHdc(); PrintWindow(h, dc, 3); g.ReleaseHdc(dc); }
          string png = System.IO.Path.Combine(outDir, "e2e.png"); bmp.Save(png, ImageFormat.Png); L("PNG", png + " " + w + "x" + hh);
          for (int i = 0; i < 3; i++) {
            int y0 = (int)(paintY[i] * scale), y1 = (int)((paintY[i] + 34) * scale);
            int minx = int.MaxValue, maxx = -1, miny = int.MaxValue, maxy = -1; long ink = 0;
            for (int y = Math.Max(0, y0); y < Math.Min(hh, y1); y++) for (int x = 0; x < w; x++) {
              Color p = bmp.GetPixel(x, y); int lum = (p.R * 299 + p.G * 587 + p.B * 114) / 1000;
              if (lum < 128) { ink++; if (x < minx) minx = x; if (x > maxx) maxx = x; if (y < miny) miny = y; if (y > maxy) maxy = y; }
            }
            L("INK line" + i, "left=" + minx + " right=" + maxx + " width=" + (maxx - minx + 1) + " top=" + miny + " bottom=" + maxy + " pixels=" + ink);
          }
        }
      }
    } catch (Exception e) { L("FINISH_EXCEPTION", e.ToString().Replace("\n", " | ")); }
    quit();
  }
  static void Closed_(IntPtr ctx, ulong w) { shutdownComplete(); }

  public static int Main2(string dll, string font, string outd) {
    fontPath = font; outDir = outd;
    // comctl32 v6 for the renderer's TaskDialog import (the host manifest normally supplies it)
    string man = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "swr-e2e.manifest");
    System.IO.File.WriteAllText(man, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><assembly xmlns=\"urn:schemas-microsoft-com:asm.v1\" manifestVersion=\"1.0\"><dependency><dependentAssembly><assemblyIdentity type=\"win32\" name=\"Microsoft.Windows.Common-Controls\" version=\"6.0.0.0\" processorArchitecture=\"*\" publicKeyToken=\"6595b64144ccf1df\" language=\"*\"/></dependentAssembly></dependency></assembly>");
    ACTCTX ac = new ACTCTX(); ac.cbSize = Marshal.SizeOf(typeof(ACTCTX)); ac.src = man;
    IntPtr hctx = CreateActCtxW(ref ac); IntPtr cookie;
    L("ACTCTX", hctx.ToInt64() != -1 && ActivateActCtx(hctx, out cookie));
    mod = LoadLibraryW(dll);
    if (mod == IntPtr.Zero) { L("LOAD", "failed " + Marshal.GetLastWin32Error()); return 2; }
    run = Bind<Run>("swr_run"); quit = Bind<Fn0>("swr_request_quit"); shutdownComplete = Bind<Fn0>("swr_shutdown_complete");
    reg = Bind<Reg>("swr_font_register"); measure8 = Bind<FnPtr2>("swr_measure_text_v08"); faces = Bind<Faces>("swr_text_run_faces");
    cells = Bind<Cells>("swr_text_run_cells"); winMetrics = Bind<Metrics>("swr_window_get_metrics"); commit = Bind<FnPtr>("swr_commit");
    cbReady = new LoopReady(Ready); cbDrain = new Drain(delegate(IntPtr c) { }); cbClosed = new Closed(Closed_);
    IntPtr cb = Zero(112);
    Marshal.WriteInt32(cb, 0, 112);
    Marshal.WriteIntPtr(cb, 16, Marshal.GetFunctionPointerForDelegate(cbReady));
    Marshal.WriteIntPtr(cb, 24, Marshal.GetFunctionPointerForDelegate(cbDrain));
    Marshal.WriteIntPtr(cb, 48, Marshal.GetFunctionPointerForDelegate(cbClosed));
    IntPtr opts = Zero(40); IntPtr title = Utf8("SwiftRight ABI 0.8 e2e");
    Marshal.WriteInt32(opts, 0, 40); Marshal.WriteIntPtr(opts, 8, title); Marshal.WriteIntPtr(opts, 16, CreateEventW(IntPtr.Zero, false, false, null));
    Marshal.WriteInt32(opts, 24, 22); Marshal.WriteInt32(opts, 28, 640); Marshal.WriteInt32(opts, 32, 320);
    int rc = run(opts, cb);
    L("RUN_RETURNED", rc);
    System.IO.File.WriteAllLines(System.IO.Path.Combine(outDir, "e2e.txt"), log.ToArray());
    return rc;
  }
}
"@
Write-Output ("DLL=" + (Split-Path $Dll -Leaf) + " sha256=" + (Get-FileHash $Dll -Algorithm SHA256).Hash.ToLower())
[void][E2E]::Main2($Dll, $Font, $Out)
if (Test-Path "$Out\e2e.png") { [Console]::WriteLine("PNG_B64=" + [Convert]::ToBase64String([IO.File]::ReadAllBytes("$Out\e2e.png"))) }
