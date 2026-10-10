# SR0 T4 driver: rendered-output (pixel) assertions on a live GPUI window of the final tuple. Run INSIDE an interactive desktop session
# (one-shot scheduled task, see schedule-pixels.ps1); the Dell desktop lock must be held. Input is window-targeted only: UIA Invoke and
# PostMessage to the app's own window. Capture is read-only: PrintWindow(PW_CLIENTONLY | PW_RENDERFULLCONTENT) of the HWND and a copy of the
# window's client rectangle from the composed desktop (CopyFromScreen, which sees what DWM shows, including a DirectComposition swap chain).
#
#   -Target Smoke   the UNCHANGED tuple BridgeSmoke.exe, driven as drive-smoke.ps1 does (UIA Invoke + posted 'a'), then its final frame:
#                   background, label glyphs, button fill / rounded corner / label, edit box fill and border, and the underline node
#                   (20,440 DIP, 120 DIP long, max(1, 2s) px thick, D97706) with its exact extent and neighbouring rows.
#   -Target Pixels  BridgePixels.exe (Sources/BridgePixels, a separate exe: BridgeSmoke commits its image and removes it in the same turn
#                   and never clips, so its final frame has neither): rounded and square image with all 16 cell colors, corners, three clips,
#                   a translate, and text with its underline.
# Every assertion is evaluated on each capture method that yields a non-uniform frame. The first such method is the primary (the verdict);
# the other is reported beside it.
param(
  [ValidateSet('Smoke', 'Pixels')][string]$Target = 'Smoke',
  [string]$Bin = 'D:\Claude\sr0-r08\smoke\scratch\out\Products\Release-windows-x86_64',
  [string]$Out = '',
  [string]$OutDir = '',
  [int]$Runs = 10,
  [int]$MaxRetries = 2,
  [string]$AssertPng = '',   # offline: run the assertions of -Target on a saved PNG of a client area (no window, no desktop); geometry defaults are the scale-2.5 values of the real runs
  [double]$Scale = 2.5,
  [switch]$DryRun
)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -ReferencedAssemblies 'System.Drawing' -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
public static class PixWin {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint f);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern uint MapVirtualKeyW(uint code, uint type);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  public static string Describe(IntPtr h) {
    if (h == IntPtr.Zero) return "hwnd=0";
    StringBuilder sb = new StringBuilder(256); GetClassNameW(h, sb, 256);
    RECT r; GetWindowRect(h, out r); RECT c; GetClientRect(h, out c);
    return "hwnd=" + h.ToInt64() + " class=" + sb + " visible=" + IsWindowVisible(h) + " iconic=" + IsIconic(h) + " rect=" + r.left + "," + r.top + "," + r.right + "," + r.bottom + " client=" + c.right + "x" + c.bottom;
  }
  // visible top-level windows of a process whose client area is non-empty (largest first): the app window, not a helper
  public static IntPtr BestWindow(uint pid) {
    IntPtr best = IntPtr.Zero; long area = 0;
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p); if (p != pid) return true;
      if (!IsWindowVisible(h)) return true;
      RECT c; GetClientRect(h, out c); long a = (long)c.right * c.bottom; if (a > area) { area = a; best = h; }
      return true;
    }, IntPtr.Zero);
    return best;
  }
  public static bool Occluded(IntPtr h, int w, int hh) {
    // WindowFromPoint at a grid of client points: every one must resolve to this window (or a child of it)
    POINT o = new POINT(); ClientToScreen(h, ref o);
    int[] fx = { 8, w / 4, w / 2, 3 * w / 4, w - 8 }; int[] fy = { 8, hh / 4, hh / 2, 3 * hh / 4, hh - 8 };
    foreach (int x in fx) foreach (int y in fy) {
      POINT p = new POINT(); p.x = o.x + x; p.y = o.y + y;
      IntPtr t = WindowFromPoint(p);
      if (t == IntPtr.Zero) return true;
      IntPtr top = GetAncestor(t, 2);
      if (t != h && top != h) return true;
    }
    return false;
  }
  public sealed class ProcLines {
    readonly object L = new object(); readonly StringBuilder sb = new StringBuilder(); Thread th;
    public ProcLines(StreamReaderHolder r) { th = new Thread(delegate() { string s; while ((s = r.Reader.ReadLine()) != null) { lock (L) { sb.AppendLine(s); } } }); th.IsBackground = true; th.Start(); }
    public string Text() { lock (L) { return sb.ToString(); } }
    public void Join() { th.Join(5000); }
  }
  public sealed class StreamReaderHolder { public System.IO.StreamReader Reader; public StreamReaderHolder(System.IO.StreamReader r) { Reader = r; } }
}
public sealed class Cap {
  public int W, H; public byte[] D; public string Mode;   // BGRA, row-major
  public static Cap FromBitmap(Bitmap bmp, string mode) {
    Cap c = new Cap(); c.W = bmp.Width; c.H = bmp.Height; c.Mode = mode;
    BitmapData bd = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    c.D = new byte[bd.Stride * bmp.Height]; System.Runtime.InteropServices.Marshal.Copy(bd.Scan0, c.D, 0, c.D.Length);
    int stride = bd.Stride; bmp.UnlockBits(bd);
    if (stride != c.W * 4) { byte[] t = new byte[c.W * 4 * c.H]; for (int y = 0; y < c.H; y++) Buffer.BlockCopy(c.D, y * stride, t, y * c.W * 4, c.W * 4); c.D = t; }
    return c;
  }
  public static Cap Print(IntPtr hwnd, int w, int h) {
    using (Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
      using (Graphics g = Graphics.FromImage(bmp)) { g.Clear(Color.Magenta); IntPtr hdc = g.GetHdc(); try { PixWin.PrintWindow(hwnd, hdc, 3); } finally { g.ReleaseHdc(hdc); } }
      return FromBitmap(bmp, "printwindow");
    }
  }
  public static Cap Screen(IntPtr hwnd, int w, int h) {
    PixWin.POINT o = new PixWin.POINT(); PixWin.ClientToScreen(hwnd, ref o);
    using (Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
      using (Graphics g = Graphics.FromImage(bmp)) { g.CopyFromScreen(o.x, o.y, 0, 0, new Size(w, h), CopyPixelOperation.SourceCopy); }
      return FromBitmap(bmp, "screen");
    }
  }
  public void SavePng(string path) {
    using (Bitmap b = new Bitmap(W, H, PixelFormat.Format32bppArgb)) {
      BitmapData bd = b.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
      System.Runtime.InteropServices.Marshal.Copy(D, 0, bd.Scan0, D.Length); b.UnlockBits(bd); b.Save(path, ImageFormat.Png);
    }
  }
  public int[] At(int x, int y) { if (x < 0 || y < 0 || x >= W || y >= H) return new int[] { -1, -1, -1 }; int i = (y * W + x) * 4; return new int[] { D[i + 2], D[i + 1], D[i] }; }
  public static bool Near(int[] p, int r, int g, int b, int tol) { return Math.Abs(p[0] - r) <= tol && Math.Abs(p[1] - g) <= tol && Math.Abs(p[2] - b) <= tol; }
  public bool Is(int x, int y, int r, int g, int b, int tol) { return Near(At(x, y), r, g, b, tol); }
  // fraction of pixels in [x0,x1) x [y0,y1) within tol of the color
  public double Frac(int x0, int y0, int x1, int y1, int r, int g, int b, int tol) {
    int n = 0, m = 0; for (int y = y0; y < y1; y++) for (int x = x0; x < x1; x++) { n++; if (Is(x, y, r, g, b, tol)) m++; }
    return n == 0 ? 0.0 : (double)m / n;
  }
  public int Count(int x0, int y0, int x1, int y1, int r, int g, int b, int tol) {
    int m = 0; for (int y = y0; y < y1; y++) for (int x = x0; x < x1; x++) if (Is(x, y, r, g, b, tol)) m++; return m;
  }
  // number of pixels with luminance below lim in the region; also the bounding box of them: returns {count, minX, minY, maxX, maxY}
  public int[] Dark(int x0, int y0, int x1, int y1, int lim) {
    int n = 0, mnx = int.MaxValue, mny = int.MaxValue, mxx = -1, mxy = -1;
    for (int y = Math.Max(0, y0); y < Math.Min(H, y1); y++) for (int x = Math.Max(0, x0); x < Math.Min(W, x1); x++) {
      int[] p = At(x, y); int lum = (p[0] * 3 + p[1] * 6 + p[2]) / 10;
      if (lum < lim) { n++; if (x < mnx) mnx = x; if (x > mxx) mxx = x; if (y < mny) mny = y; if (y > mxy) mxy = y; }
    }
    return new int[] { n, mnx, mny, mxx, mxy };
  }
  public int Light(int x0, int y0, int x1, int y1, int lim) {
    int n = 0; for (int y = y0; y < y1; y++) for (int x = x0; x < x1; x++) { int[] p = At(x, y); int lum = (p[0] * 3 + p[1] * 6 + p[2]) / 10; if (lum > lim) n++; } return n;
  }
  // columns of the first and last pixel within tol of the color on row y (-1 if none)
  public int[] Extent(int y, int x0, int x1, int r, int g, int b, int tol) {
    int a = -1, z = -1; for (int x = Math.Max(0, x0); x < Math.Min(W, x1); x++) if (Is(x, y, r, g, b, tol)) { if (a < 0) a = x; z = x; } return new int[] { a, z };
  }
  public int Distinct() { HashSet<int> s = new HashSet<int>(); for (int i = 0; i < D.Length; i += 4 * 97) { s.Add(D[i] | (D[i + 1] << 8) | (D[i + 2] << 16)); if (s.Count > 6) break; } return s.Count; }
}
'@
if (-not [PixWin]::SetProcessDpiAwarenessContext([IntPtr]-4)) { [void][PixWin]::SetProcessDPIAware() }

function RGB([string]$hex) { return @([Convert]::ToInt32($hex.Substring(0, 2), 16), [Convert]::ToInt32($hex.Substring(2, 2), 16), [Convert]::ToInt32($hex.Substring(4, 2), 16)) }
function Rn([double]$v) { return [int][Math]::Round($v, [MidpointRounding]::AwayFromZero) }

$script:checks = $null
function Chk([string]$name, [bool]$ok, [string]$detail) { [void]$script:checks.Add([pscustomobject]@{ name = $name; ok = $ok; detail = $detail }) }
function F2([double]$x) { return $x.ToString('0.000', [Globalization.CultureInfo]::InvariantCulture) }

# ---------------------------------------------------------------- assertions per target
# $c = Cap, $s = scale (px per DIP), $g = hashtable of geometry
function Assert-Common($c, [string]$lab) {
  $bg = $c.At($c.W - 12, 12)
  Chk "$lab frame is not blank (distinct colors sampled)" ($c.Distinct() -ge 3) ("distinct>=" + $c.Distinct())
  $pts = @($c.At(12, 12), $c.At($c.W - 12, 12), $c.At(12, $c.H - 12), $c.At($c.W - 12, $c.H - 12), $c.At([int]($c.W / 2), $c.H - 12))
  $same = $true; foreach ($p in $pts) { if (-not [Cap]::Near($p, $bg[0], $bg[1], $bg[2], 2)) { $same = $false } }
  return [pscustomobject]@{ Bg = $bg; Uniform = $same }
}

function Assert-Smoke($c, [double]$s, $g, [string]$lab) {
  $cm = Assert-Common $c $lab
  $bg = $cm.Bg
  Chk "$lab background is one uniform color in the four corners and bottom edge" $cm.Uniform ("bg=#{0:X2}{1:X2}{2:X2}" -f $bg[0], $bg[1], $bg[2])
  # label glyphs (node 1 at 20,20 DIP): dark pixels inside the text box
  $lx = Rn (20 * $s); $ly = Rn (20 * $s)
  $dk = $c.Dark($lx, $ly, $lx + (Rn (300 * $s)), $ly + (Rn (24 * $s)), 128)
  Chk "$lab label glyphs painted at (20,20) DIP" ($dk[0] -ge 40 -and $dk[1] -ge $lx - 2 -and $dk[2] -ge $ly - 2) ("dark_px=$($dk[0]) bbox=($($dk[1]),$($dk[2]))-($($dk[3]),$($dk[4])) expect origin ($lx,$ly)")
  # underline node 6: (20,440) DIP, 120 DIP long, thickness max(1, 2s) px, D97706
  $u = RGB 'D97706'
  $ux = Rn (20 * $s); $uw = Rn (120 * $s); $uy = Rn (440 * $s); $ut = [Math]::Max(1, (Rn (2 * $s)))
  $fi = $c.Frac($ux + 3, $uy + 1, $ux + $uw - 3, $uy + $ut - 1, $u[0], $u[1], $u[2], 6)
  Chk "$lab underline interior is D97706 (>= 99% of $($uw - 6) x $($ut - 2) px)" ($fi -ge 0.99) ("fraction=" + (F2 $fi) + " region=($($ux + 3),$($uy + 1))-($($ux + $uw - 3),$($uy + $ut - 1))")
  $ex = $c.Extent($uy + [int]($ut / 2), $ux - 20, $ux + $uw + 20, $u[0], $u[1], $u[2], 10)
  Chk "$lab underline starts at x=$ux and ends at x=$($ux + $uw - 1) (+-1 px)" ([Math]::Abs($ex[0] - $ux) -le 1 -and [Math]::Abs($ex[1] - ($ux + $uw - 1)) -le 1) ("first=$($ex[0]) last=$($ex[1])")
  $above = $c.Frac($ux + 3, $uy - 4, $ux + $uw - 3, $uy - 1, $bg[0], $bg[1], $bg[2], 6)
  $below = $c.Frac($ux + 3, $uy + $ut + 1, $ux + $uw - 3, $uy + $ut + 4, $bg[0], $bg[1], $bg[2], 6)
  $leak = $c.Count($ux + 3, $uy - 4, $ux + $uw - 3, $uy - 1, $u[0], $u[1], $u[2], 14) + $c.Count($ux + 3, $uy + $ut + 1, $ux + $uw - 3, $uy + $ut + 4, $u[0], $u[1], $u[2], 14)
  Chk "$lab underline is $ut px thick: the 3 rows above and below are background" ($above -ge 0.99 -and $below -ge 0.99 -and $leak -eq 0) ("above=" + (F2 $above) + " below=" + (F2 $below) + " underline_colored_outside=$leak")
  # button (UIA rect in client px): fill 2563EB, radius 6s corners, white label
  $b = $g.button; $f = RGB '2563EB'
  $bfill = $c.Frac($b.x + 4, $b.y + [int]($b.h / 2) - 4, $b.x + 12, $b.y + [int]($b.h / 2) + 4, $f[0], $f[1], $f[2], 6)
  Chk "$lab button fill is 2563EB (left padding strip)" ($bfill -ge 0.99) ("fraction=" + (F2 $bfill) + " button=($($b.x),$($b.y)) $($b.w)x$($b.h) px")
  $rad = Rn (6 * $s)
  $corner = $c.Is($b.x, $b.y, $bg[0], $bg[1], $bg[2], 10)
  $edge = $c.Frac($b.x + $rad + 3, $b.y + 2, $b.x + $b.w - $rad - 3, $b.y + 4, $f[0], $f[1], $f[2], 14)
  Chk "$lab button corner is rounded (corner pixel is background, top edge past the radius is fill)" ($corner -and $edge -ge 0.98) ("corner_is_bg=$corner top_edge_fill=" + (F2 $edge) + " radius=$rad")
  $lt = $c.Light($b.x + 10, $b.y + 4, $b.x + $b.w - 10, $b.y + $b.h - 4, 200)
  Chk "$lab button label glyphs (white) painted inside the button" ($lt -ge 40) ("light_px=$lt")
  # edit box (UIA rect): white fill, 888888 border, radius 4s
  $e = $g.edit; $bd = RGB '888888'
  $efill = $c.Frac($e.x + $e.w - 60, $e.y + [int]($e.h / 2) - 4, $e.x + $e.w - 10, $e.y + [int]($e.h / 2) + 4, 255, 255, 255, 4)
  Chk "$lab edit box interior is white" ($efill -ge 0.99) ("fraction=" + (F2 $efill) + " edit=($($e.x),$($e.y)) $($e.w)x$($e.h) px")
  $bn = $c.Count($e.x, $e.y + [int]($e.h / 2) - 1, $e.x + 4, $e.y + [int]($e.h / 2) + 2, $bd[0], $bd[1], $bd[2], 28)
  $outside = $c.Frac($e.x - 6, $e.y + [int]($e.h / 2) - 3, $e.x - 3, $e.y + [int]($e.h / 2) + 3, $bg[0], $bg[1], $bg[2], 6)
  Chk "$lab edit box has a 888888 border on its left edge and background outside it" ($bn -ge 2 -and $outside -ge 0.99) ("border_px=$bn outside_bg=" + (F2 $outside))
}

function Assert-Pixels($c, [double]$s, $g, [string]$lab) {
  $cm = Assert-Common $c $lab
  $bg = RGB 'F5F5F5'
  Chk "$lab background rect painted F5F5F5 (corners, bottom edge)" ($cm.Uniform -and [Cap]::Near($cm.Bg, $bg[0], $bg[1], $bg[2], 2)) ("observed=#{0:X2}{1:X2}{2:X2}" -f $cm.Bg[0], $cm.Bg[1], $cm.Bg[2])
  # images: 4x4 cells of 16 DIP; cell i = (i*16, 255-i*16, 128)
  foreach ($im in @(@{ n = 'A rounded'; x = 20; rad = 8 }, @{ n = 'B square'; x = 120; rad = 0 })) {
    $ox = $im.x * $s; $oy = 20 * $s; $bad = @()
    for ($i = 0; $i -lt 16; $i++) {
      $cx = $i % 4; $cy = [int][Math]::Floor($i / 4)
      $px = Rn ($ox + ($cx + 0.5) * 16 * $s); $py = Rn ($oy + ($cy + 0.5) * 16 * $s)
      $p = $c.At($px, $py); $exp = @(($i * 16), (255 - $i * 16), 128)
      if (-not [Cap]::Near($p, $exp[0], $exp[1], $exp[2], 12)) { $bad += ("cell{0}@({1},{2}) got=#{3:X2}{4:X2}{5:X2} want=#{6:X2}{7:X2}{8:X2}" -f $i, $px, $py, $p[0], $p[1], $p[2], $exp[0], $exp[1], $exp[2]) }
    }
    Chk "$lab image $($im.n): all 16 cell centers have the source colors (+-12)" ($bad.Count -eq 0) $(if ($bad.Count -eq 0) { '16/16' } else { ($bad | Select-Object -First 4) -join '; ' })
    $x0 = Rn $ox; $y0 = Rn $oy; $w = Rn (64 * $s)
    $outl = $c.Frac($x0 - 4, $y0 + 4, $x0 - 1, $y0 + $w - 4, $bg[0], $bg[1], $bg[2], 6)
    $outr = $c.Frac($x0 + $w + 1, $y0 + 4, $x0 + $w + 4, $y0 + $w - 4, $bg[0], $bg[1], $bg[2], 6)
    Chk "$lab image $($im.n): extent is 64 DIP ($w px): background just left and right of it" ($outl -ge 0.99 -and $outr -ge 0.99) ("left=" + (F2 $outl) + " right=" + (F2 $outr))
    # corner shape, geometrically. The renderer samples the 4x4 image with smoothing, so the outermost half texel blends toward its neighbours and is not
    # a pure cell color (observed on tuple 08); the cell-center colors above pin the colors. Here: along each corner's diagonal, the first pixel that is not
    # background. A circle of radius r crosses the diagonal at r(1 - 1/sqrt 2) = 0.293 r from each side; a square corner is image from the first pixel.
    $diag = @(); $badDiag = @()
    foreach ($cn in @(@('TL', $x0, $y0, 1, 1), @('TR', ($x0 + $w - 1), $y0, -1, 1), @('BL', $x0, ($y0 + $w - 1), 1, -1), @('BR', ($x0 + $w - 1), ($y0 + $w - 1), -1, -1))) {
      $k = 0; while ($k -lt 40 -and $c.Is($cn[1] + $k * $cn[3], $cn[2] + $k * $cn[4], $bg[0], $bg[1], $bg[2], 8)) { $k++ }
      $diag += ($cn[0] + '=' + $k)
      if ($im.rad -gt 0) { $rr = Rn ($im.rad * $s); $want = $rr * (1 - 1 / [Math]::Sqrt(2)); if ([Math]::Abs($k - $want) -gt 2.5) { $badDiag += ($cn[0] + ' first_image_px=' + $k + ' want~' + (F2 $want)) } }
      else { if ($k -gt 1) { $badDiag += ($cn[0] + ' first_image_px=' + $k + ' want<=1') } }
    }
    $mid = @($c.Is($x0 + [int]($w / 2), $y0, $bg[0], $bg[1], $bg[2], 8), $c.Is($x0 + [int]($w / 2), $y0 + $w - 1, $bg[0], $bg[1], $bg[2], 8), $c.Is($x0, $y0 + [int]($w / 2), $bg[0], $bg[1], $bg[2], 8), $c.Is($x0 + $w - 1, $y0 + [int]($w / 2), $bg[0], $bg[1], $bg[2], 8))
    $midBg = @($mid | Where-Object { $_ }).Count
    $shape = $(if ($im.rad -gt 0) { "rounded (radius $(Rn ($im.rad * $s)) px)" } else { 'square' })
    Chk "$lab image $($im.n): corners are $shape (first image pixel on each diagonal) and all four edge midpoints are image" ($badDiag.Count -eq 0 -and $midBg -eq 0) ("diagonals " + ($diag -join ' ') + $(if ($badDiag.Count) { ' BAD: ' + ($badDiag -join '; ') } else { '' }) + " edge_midpoints_background=$midBg")
  }
  # text + underline
  $t = $g.text; $u = RGB 'D97706'
  $tx = Rn $t.x; $ty = Rn $t.y; $tw = Rn $t.w; $th = Rn $t.h; $uy = Rn $t.uy; $ut = [Math]::Max(1, (Rn $t.ut))
  $dk = $c.Dark($tx - 4, $ty, $tx + $tw + 8, $uy - 1, 120)
  Chk "$lab text run painted: glyph pixels inside its measured box ($tw x $th px)" ($dk[0] -ge 60 -and $dk[1] -ge $tx - 2 -and $dk[3] -le $tx + $tw + 2 -and $dk[4] -lt $uy) ("dark_px=$($dk[0]) bbox=($($dk[1]),$($dk[2]))-($($dk[3]),$($dk[4])) box x=[$tx,$($tx + $tw)) y=[$ty,$uy)")
  $fi = $c.Frac($tx + 2, $uy, $tx + $tw - 2, $uy + $ut, $u[0], $u[1], $u[2], 8)
  $ex = $c.Extent($uy + [int]($ut / 2), $tx - 20, $tx + $tw + 20, $u[0], $u[1], $u[2], 10)
  Chk "$lab underline sits directly under the text run, spans its measured width ($tw px) and is $ut px thick" ($fi -ge 0.98 -and [Math]::Abs($ex[0] - $tx) -le 1 -and [Math]::Abs($ex[1] - ($tx + $tw - 1)) -le 1) ("interior=" + (F2 $fi) + " first=$($ex[0]) last=$($ex[1]) want=[$tx,$($tx + $tw - 1)] rows=[$uy,$($uy + $ut))")
  $leak = $c.Count($tx - 4, $ty, $tx + $tw + 8, $uy - 1, $u[0], $u[1], $u[2], 14) + $c.Count($tx - 4, $uy + $ut + 1, $tx + $tw + 8, $uy + $ut + 6, $u[0], $u[1], $u[2], 14)
  Chk "$lab underline color appears only in its own rows (not in the glyph box, not below)" ($leak -eq 0) ("outside_px=$leak")
  # clips
  $c1 = RGB 'C0392B'
  $x0 = Rn (20 * $s); $y0 = Rn (220 * $s); $cw = Rn (100 * $s); $ch = Rn (40 * $s)
  $in1 = $c.Frac($x0 + 2, $y0 + 2, $x0 + $cw - 2, $y0 + $ch - 2, $c1[0], $c1[1], $c1[2], 6)
  $out1 = $c.Count($x0 + $cw + 2, $y0, $x0 + (Rn (300 * $s)) - 2, $y0 + $ch, $c1[0], $c1[1], $c1[2], 20)
  $ed1 = $c.Extent($y0 + [int]($ch / 2), $x0 - 10, $x0 + (Rn (320 * $s)) + 10, $c1[0], $c1[1], $c1[2], 20)
  Chk "$lab clip 1 (horizontal): the 300 DIP rect shows only inside the 100 DIP clip" ($in1 -ge 0.99 -and $out1 -eq 0 -and [Math]::Abs($ed1[1] - ($x0 + $cw - 1)) -le 1 -and [Math]::Abs($ed1[0] - $x0) -le 1) ("inside=" + (F2 $in1) + " colored_outside_clip=$out1 first=$($ed1[0]) last=$($ed1[1]) want=[$x0,$($x0 + $cw - 1)]")
  $c2 = RGB '2E86C1'
  $x0 = Rn (200 * $s); $cw = Rn (100 * $s); $y1 = Rn (230 * $s); $y2 = Rn (250 * $s)
  $in2 = $c.Frac($x0 + 2, $y1 + 2, $x0 + $cw - 2, $y2 - 2, $c2[0], $c2[1], $c2[2], 6)
  $out2 = $c.Count($x0, (Rn (210 * $s)) + 1, $x0 + $cw, $y1 - 1, $c2[0], $c2[1], $c2[2], 20) + $c.Count($x0, $y2 + 1, $x0 + $cw, (Rn (290 * $s)) - 1, $c2[0], $c2[1], $c2[2], 20)
  Chk "$lab clip 2 (vertical band): the 80 DIP tall rect shows only the 20 DIP band" ($in2 -ge 0.99 -and $out2 -eq 0) ("inside=" + (F2 $in2) + " colored_above_or_below=$out2 band_rows=[$y1,$y2)")
  # clip 3: image C at (340,20), 64 DIP wide, clipped to the left 32 DIP
  $x0 = Rn (340 * $s); $y0 = Rn (20 * $s); $half = Rn (32 * $s); $w = Rn (64 * $s)
  $bad = @()
  foreach ($i in 0, 1, 4, 5, 8, 9, 12, 13) {
    $cx = $i % 4; $cy = [int][Math]::Floor($i / 4); $px = Rn ((340 + ($cx + 0.5) * 16) * $s); $py = Rn ((20 + ($cy + 0.5) * 16) * $s)
    $p = $c.At($px, $py); $exp = @(($i * 16), (255 - $i * 16), 128)
    if (-not [Cap]::Near($p, $exp[0], $exp[1], $exp[2], 12)) { $bad += "cell$i" }
  }
  $rightBg = $c.Frac($x0 + $half + 3, $y0 + 2, $x0 + $w - 2, $y0 + $w - 2, $bg[0], $bg[1], $bg[2], 6)
  Chk "$lab clip 3 (image): the left half of the image shows its cells, the right half is background" ($bad.Count -eq 0 -and $rightBg -ge 0.99) ("left_cells_bad=$($bad.Count) right_half_bg=" + (F2 $rightBg))
  # translate
  $c3 = RGB '27AE60'
  $x0 = Rn (400 * $s); $y0 = Rn (220 * $s); $tw2 = Rn (60 * $s); $th2 = Rn (40 * $s)
  $in3 = $c.Frac($x0 + 2, $y0 + 2, $x0 + $tw2 - 2, $y0 + $th2 - 2, $c3[0], $c3[1], $c3[2], 6)
  $at0 = $c.Count(0, 0, $tw2, $th2, $c3[0], $c3[1], $c3[2], 20)
  $ed3 = $c.Extent($y0 + [int]($th2 / 2), $x0 - 10, $x0 + $tw2 + 10, $c3[0], $c3[1], $c3[2], 20)
  Chk "$lab translate: the rect drawn at (0,0) after translatePush(400,220) DIP lands at ($x0,$y0), not at the origin" ($in3 -ge 0.99 -and $at0 -eq 0 -and [Math]::Abs($ed3[0] - $x0) -le 1 -and [Math]::Abs($ed3[1] - ($x0 + $tw2 - 1)) -le 1) ("inside=" + (F2 $in3) + " colored_at_origin=$at0 first=$($ed3[0]) last=$($ed3[1])")
}

# ---------------------------------------------------------------- one run
function Get-ElementRect($root, [string]$id, [int]$ox, [int]$oy) {
  $AE = [System.Windows.Automation.AutomationElement]
  $cond = New-Object System.Windows.Automation.PropertyCondition($AE::AutomationIdProperty, $id)
  $el = $null
  for ($k = 0; $k -lt 20 -and $el -eq $null; $k++) { $el = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond); if ($el -eq $null) { Start-Sleep -Milliseconds 250 } }
  if ($el -eq $null) { return $null }
  $r = $el.Current.BoundingRectangle
  return @{ x = [int][Math]::Round($r.X) - $ox; y = [int][Math]::Round($r.Y) - $oy; w = [int][Math]::Round($r.Width); h = [int][Math]::Round($r.Height); el = $el }
}

function Invoke-PixelRun([int]$n, [int]$attempt) {
  $script:checks = New-Object System.Collections.ArrayList
  $info = [ordered]@{ run = $n; attempt = $attempt; target = $Target; started = (Get-Date).ToString('o') }
  $exeName = if ($Target -eq 'Smoke') { 'BridgeSmoke.exe' } else { 'BridgePixels.exe' }
  $exe = Join-Path $Bin $exeName
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe; $psi.WorkingDirectory = $Bin; $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables['Path'] = "C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;$Bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
  if ($Target -eq 'Smoke') { $psi.EnvironmentVariables['SWR_SMOKE_LINGER_TICKS'] = '900' } else { $psi.EnvironmentVariables['SWR_PIX_HOLD_S'] = '14' }
  $proc = [System.Diagnostics.Process]::Start($psi)
  $lines = New-Object PixWin+ProcLines((New-Object PixWin+StreamReaderHolder($proc.StandardOutput)))
  $err = $proc.StandardError.ReadToEndAsync()
  $caps = @()
  try {
    $hwnd = [IntPtr]::Zero
    for ($i = 0; $i -lt 120 -and $hwnd -eq [IntPtr]::Zero -and -not $proc.HasExited; $i++) { Start-Sleep -Milliseconds 250; $hwnd = [PixWin]::BestWindow([uint32]$proc.Id) }
    if ($hwnd -eq [IntPtr]::Zero) { throw 'no window with a client area' }
    $info.window = [PixWin]::Describe($hwnd)
    $info.hwnd = $hwnd.ToInt64()
    Start-Sleep -Milliseconds 1500
    [void][PixWin]::SetForegroundWindow($hwnd)
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
    if ($Target -eq 'Smoke') {
      # the same two window-targeted inputs drive-smoke.ps1 sends so the unchanged exe completes normally: UIA Invoke on the button, posted 'a'
      $AE = [System.Windows.Automation.AutomationElement]
      $btnCond = New-Object System.Windows.Automation.AndCondition((New-Object System.Windows.Automation.PropertyCondition($AE::NameProperty, 'Press me')), (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)))
      $btn = $null; for ($k = 0; $k -lt 40 -and $btn -eq $null; $k++) { $btn = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $btnCond); if ($btn -eq $null) { Start-Sleep -Milliseconds 250 } }
      if ($btn -ne $null) { try { $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $info.uia_invoke = 'ok' } catch { $info.uia_invoke = 'ERR ' + $_.Exception.Message } } else { $info.uia_invoke = 'NOT_FOUND' }
      Start-Sleep -Milliseconds 500
      $scanA = [PixWin]::MapVirtualKeyW(0x41, 0)
      $kd = [IntPtr]([int64]1 -bor ([int64]$scanA -shl 16)); $ku = [IntPtr]([int64]1 -bor ([int64]$scanA -shl 16) -bor 0x40000000 -bor 0x80000000)
      [void][PixWin]::PostMessageW($hwnd, 0x0100, [IntPtr]0x41, $kd); [void][PixWin]::PostMessageW($hwnd, 0x0102, [IntPtr]0x61, $kd); [void][PixWin]::PostMessageW($hwnd, 0x0101, [IntPtr]0x41, $ku)
      Start-Sleep -Milliseconds 800
    } else {
      $dl = (Get-Date).AddSeconds(20); while ((Get-Date) -lt $dl -and ($lines.Text() -notmatch 'COMMIT rc=SWR_OK')) { Start-Sleep -Milliseconds 100 }
      Start-Sleep -Milliseconds 1200
    }
    [void][PixWin]::SetForegroundWindow($hwnd); Start-Sleep -Milliseconds 400
    $cr = New-Object PixWin+RECT; [void][PixWin]::GetClientRect($hwnd, [ref]$cr)
    $org = New-Object PixWin+POINT; [void][PixWin]::ClientToScreen($hwnd, [ref]$org)
    $dpi = [PixWin]::GetDpiForWindow($hwnd); $s = $dpi / 96.0
    $info.client = "$($cr.right)x$($cr.bottom)"; $info.scale = $s; $info.origin = "$($org.x),$($org.y)"
    $info.occluded = [PixWin]::Occluded($hwnd, $cr.right, $cr.bottom)
    $info.foreground_is_target = ([PixWin]::GetForegroundWindow() -eq $hwnd)
    $g = @{}
    if ($Target -eq 'Smoke') {
      $b = Get-ElementRect $root 'toolbar/press' $org.x $org.y; $e = Get-ElementRect $root 'field/edit' $org.x $org.y
      if ($b -eq $null -or $e -eq $null) { throw 'button or edit node not found through UIA' }
      $g.button = $b; $g.edit = $e
    } else {
      $m = [regex]::Match($lines.Text(), 'GEOM text x=([\d.]+) y=([\d.]+) w=([\d.]+) h=([\d.]+) underline_y=([\d.]+) underline_h=([\d.]+)')
      if (-not $m.Success) { throw 'no GEOM line from the host' }
      $ci = [Globalization.CultureInfo]::InvariantCulture
      $g.text = @{ x = [double]::Parse($m.Groups[1].Value, $ci); y = [double]::Parse($m.Groups[2].Value, $ci); w = [double]::Parse($m.Groups[3].Value, $ci); h = [double]::Parse($m.Groups[4].Value, $ci); uy = [double]::Parse($m.Groups[5].Value, $ci); ut = [double]::Parse($m.Groups[6].Value, $ci) }
      $sm = [regex]::Match($lines.Text(), 'ready: .* scale=([\d.]+)'); if ($sm.Success) { $info.host_scale = $sm.Groups[1].Value }
    }
    $pw = [Cap]::Print($hwnd, $cr.right, $cr.bottom)
    $sc = [Cap]::Screen($hwnd, $cr.right, $cr.bottom)
    $caps = @($pw, $sc)
    $info.printwindow_distinct = $pw.Distinct(); $info.screen_distinct = $sc.Distinct()
    $primary = $null
    foreach ($c in $caps) { if ($c.Distinct() -ge 3 -and $primary -eq $null) { $primary = $c } }
    $info.primary = if ($primary -ne $null) { $primary.Mode } else { 'none' }
    foreach ($c in $caps) {
      $before = $script:checks.Count
      if ($Target -eq 'Smoke') { Assert-Smoke $c $s $g $c.Mode } else { Assert-Pixels $c $s $g $c.Mode }
      $info[$c.Mode + '_pass'] = (@($script:checks | Select-Object -Skip $before | Where-Object { -not $_.ok }).Count -eq 0)
    }
    if ($n -eq 1 -and $attempt -eq 1 -or $script:keepPng) { foreach ($c in $caps) { try { $c.SavePng((Join-Path $script:OutDir ('{0}-run{1:D2}a{2}-{3}.png' -f $Target.ToLower(), $n, $attempt, $c.Mode))) } catch { } } }
    if ($info.occluded) { Chk 'window not occluded (WindowFromPoint grid is the target)' $false 'another window covers the client area' }
    # let the host finish normally
    if (-not $proc.WaitForExit(60000)) { try { $proc.Kill() } catch { }; $info.killed = $true }
    $proc.WaitForExit(); $lines.Join()
    $info.exit = $proc.ExitCode
    $txt = $lines.Text()
    if ($Target -eq 'Smoke') {
      $sm2 = [regex]::Match($txt, '(?m)^SMOKE (PASS|FAIL) \((\d+)/(\d+)\)'); $info.smoke = if ($sm2.Success) { $sm2.Value } else { 'no summary' }
      Chk 'the unchanged BridgeSmoke.exe still passes its own checks in this run (exit 0, SMOKE PASS)' ($proc.ExitCode -eq 0 -and $sm2.Success -and $sm2.Groups[1].Value -eq 'PASS') ("exit=$($proc.ExitCode) $($info.smoke)")
    } else {
      Chk 'BridgePixels host reports PIXELS-HOST PASS (scene committed, no rejection)' ($proc.ExitCode -eq 0 -and $txt -match 'PIXELS-HOST PASS') ("exit=$($proc.ExitCode)")
    }
    $info.host_scale_matches = if ($Target -eq 'Smoke') { ([regex]::Match($txt, 'ready: .* scale=([\d.]+)').Groups[1].Value -eq ([string]$s)) } else { ($info.host_scale -eq [string]$s) }
    Chk "host-reported window scale equals the scale used for the pixel positions ($s)" $info.host_scale_matches ("host=" + [regex]::Match($txt, 'ready: .* scale=([\d.]+)').Groups[1].Value)
  } catch {
    $hostText = ''; try { $hostText = ($lines.Text() -replace '\s+', ' ') } catch { }
    Chk 'run completed without exception' $false ($_.Exception.Message + ' @ ' + $_.InvocationInfo.ScriptLineNumber + ' | window: ' + $info.window + ' | exited=' + $proc.HasExited + ' | host: ' + $hostText.Substring(0, [Math]::Min(500, $hostText.Length)))
  } finally {
    if (-not $proc.HasExited) { try { $proc.Kill() } catch { } }
  }
  $primaryMode = $info.primary
  # the verdict: all checks of the primary capture + the run-wide checks (names without a capture prefix)
  $verdictChecks = @($script:checks | Where-Object { $_.name -like "$primaryMode *" -or ($_.name -notlike 'printwindow *' -and $_.name -notlike 'screen *') })
  $failed = @($verdictChecks | Where-Object { -not $_.ok })
  $valid = (-not $info.occluded) -and ($primaryMode -ne 'none') -and ($info.foreground_is_target -ne $false)
  return [pscustomobject]@{ Info = $info; Checks = @($script:checks); Verdict = $(if ($valid -and $failed.Count -eq 0) { 'PASS' } elseif (-not $valid) { 'INVALID' } else { 'FAIL' }); Failed = $failed; Caps = $caps }
}

if ($DryRun) {
  $fails = @()
  $bmp = New-Object System.Drawing.Bitmap(40, 30, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $gx = [System.Drawing.Graphics]::FromImage($bmp); $gx.Clear([System.Drawing.Color]::FromArgb(255, 0xF5, 0xF5, 0xF5))
  $br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 0xD9, 0x77, 0x06)); $gx.FillRectangle($br, 5, 10, 20, 3); $gx.Dispose()
  $c = [Cap]::FromBitmap($bmp, 'synthetic')
  if (-not $c.Is(6, 11, 0xD9, 0x77, 0x06, 0)) { $fails += 'Is' }
  if ($c.Frac(5, 10, 25, 13, 0xD9, 0x77, 0x06, 0) -ne 1.0) { $fails += 'Frac' }
  $ex = $c.Extent(11, 0, 40, 0xD9, 0x77, 0x06, 0); if ($ex[0] -ne 5 -or $ex[1] -ne 24) { $fails += "Extent $($ex -join ',')" }
  if ($c.Count(0, 0, 40, 30, 0xD9, 0x77, 0x06, 0) -ne 60) { $fails += 'Count' }
  if ($c.Distinct() -lt 2) { $fails += 'Distinct' }
  $script:checks = New-Object System.Collections.ArrayList
  # run the assertion code on a synthetic Smoke frame: a mostly-blank frame must FAIL the underline checks
  Assert-Smoke $c 2.5 @{ button = @{ x = 50; y = 10; w = 20; h = 10 }; edit = @{ x = 5; y = 5; w = 20; h = 10 } } 'synthetic'
  if (@($script:checks | Where-Object { $_.ok }).Count -eq $script:checks.Count) { $fails += 'assertions accepted a blank frame' }
  # the Pixels assertions must run to the end on a synthetic frame without an exception, and reject it
  $bmp2 = New-Object System.Drawing.Bitmap(1600, 1200, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g2 = [System.Drawing.Graphics]::FromImage($bmp2); $g2.Clear([System.Drawing.Color]::White); $g2.Dispose()
  $c2 = [Cap]::FromBitmap($bmp2, 'synthetic')
  $script:checks = New-Object System.Collections.ArrayList
  try { Assert-Pixels $c2 2.5 @{ text = @{ x = 50.0; y = 300.0; w = 211.875; h = 60.0; uy = 360.0; ut = 5.0 } } 'synthetic' } catch { $fails += ('Assert-Pixels threw: ' + $_.Exception.Message) }
  if ($script:checks.Count -lt 15) { $fails += ('Assert-Pixels produced only ' + $script:checks.Count + ' checks') }
  if (@($script:checks | Where-Object { $_.ok }).Count -eq $script:checks.Count) { $fails += 'Pixels assertions accepted a blank frame' }
  $errs = $null; $tokens = $null; [void][System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$tokens, [ref]$errs); if ($errs.Count -gt 0) { $fails += 'parse' }
  "dryrun fails=$($fails.Count) $($fails -join ' | ')"; exit $fails.Count
}

if ($AssertPng) {
  $img = [System.Drawing.Image]::FromFile($AssertPng)
  $bm = New-Object System.Drawing.Bitmap($img); $img.Dispose()
  $c = [Cap]::FromBitmap($bm, 'png')
  $script:checks = New-Object System.Collections.ArrayList
  if ($Target -eq 'Smoke') {
    Assert-Smoke $c $Scale @{ button = @{ x = 50; y = 380; w = 400; h = 100 }; edit = @{ x = 50; y = 530; w = 1000; h = 90 } } 'png'
  } else {
    Assert-Pixels $c $Scale @{ text = @{ x = 50.0; y = 300.0; w = 211.875; h = 60.0; uy = 360.0; ut = 5.0 } } 'png'
  }
  foreach ($k in $script:checks) { ('{0} {1} [{2}]' -f $(if ($k.ok) { 'PASS' } else { 'FAIL' }), $k.name, $k.detail) }
  $nf = @($script:checks | Where-Object { -not $_.ok }).Count
  "ASSERT-PNG $(if ($nf -eq 0) { 'PASS' } else { 'FAIL' }) failed=$nf of $($script:checks.Count)"
  exit $nf
}

if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $Bin) ('pixels-' + $Target.ToLower()) }
New-Item -ItemType Directory -Force $OutDir | Out-Null
$script:OutDir = $OutDir
$script:keepPng = $false
if (-not $Out) { $Out = Join-Path $OutDir ('result-' + $Target.ToLower() + '-pixels.txt') }
$L = New-Object System.Collections.ArrayList
function Out([string]$s) { [void]$L.Add($s) }
$exeName = if ($Target -eq 'Smoke') { 'BridgeSmoke.exe' } else { 'BridgePixels.exe' }
Out "host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) started=$(Get-Date -Format o) target=$Target runs=$Runs"
Out ("ARTIFACTS $exeName=$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Bin $exeName)).Hash.ToLower()) renderer=$((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $Bin 'swiftright_render.dll')).Hash.ToLower())")
$results = @()
for ($n = 1; $n -le $Runs; $n++) {
  $r = $null
  for ($a = 1; $a -le (1 + $MaxRetries); $a++) {
    $r = Invoke-PixelRun $n $a
    $r.Info.attempt = $a
    $results += , $r
    Write-Host ("run {0:D2}a{1} {2} primary={3} failed={4}" -f $n, $a, $r.Verdict, $r.Info.primary, $r.Failed.Count)
    if ($r.Verdict -ne 'INVALID') { break }
    Start-Sleep -Seconds 3
  }
}
$final = @(); for ($n = 1; $n -le $Runs; $n++) { $final += , @($results | Where-Object { $_.Info.run -eq $n })[-1] }
Out ''
Out "RUNS: PASS=$(@($final | Where-Object { $_.Verdict -eq 'PASS' }).Count) FAIL=$(@($final | Where-Object { $_.Verdict -eq 'FAIL' }).Count) INVALID=$(@($final | Where-Object { $_.Verdict -eq 'INVALID' }).Count) of $Runs (attempts total $($results.Count))"
Out ''
Out '== assertions, primary capture (verdict), count of passing runs'
$names = @(); foreach ($r in $final) { foreach ($c in $r.Checks) { $nm = ($c.name -replace '^(printwindow|screen) ', ''); if ($names -notcontains $nm) { $names += $nm } } }
foreach ($nm in $names) {
  $np = 0; $nt = 0
  foreach ($r in $final) { $pm = $r.Info.primary; foreach ($c in $r.Checks) { if (($c.name -replace '^(printwindow|screen) ', '') -eq $nm -and ($c.name -like "$pm *" -or ($c.name -notlike 'printwindow *' -and $c.name -notlike 'screen *'))) { $nt++; if ($c.ok) { $np++ } } } }
  Out ('{0,2}/{1,-2} {2}' -f $np, $nt, $nm)
}
Out ''
Out '== capture methods: runs in which each method gave a non-uniform frame, and all-assertions-pass per method'
foreach ($mode in 'printwindow', 'screen') {
  $valid = @($final | Where-Object { $_.Info[$mode + '_distinct'] -ge 3 }).Count
  $pass = @($final | Where-Object { $_.Info[$mode + '_pass'] -eq $true }).Count
  Out ("{0,-12} non-uniform frame in {1}/{2} runs; every assertion passed in {3}/{2} runs" -f $mode, $valid, $Runs, $pass)
}
Out ''
Out '== per run'
foreach ($r in $results) {
  $i = $r.Info
  Out ("run {0:D2} a{1} {2} primary={3} client={4} scale={5} occluded={6} fg={7} exit={8} {9} pw_pass={10} screen_pass={11}" -f $i.run, $i.attempt, $r.Verdict, $i.primary, $i.client, $i.scale, $i.occluded, $i.foreground_is_target, $i.exit, $i.smoke, $i['printwindow_pass'], $i['screen_pass'])
  foreach ($c in $r.Checks) { if (-not $c.ok) { Out ("    FAIL {0} [{1}]" -f $c.name, $c.detail) } }
}
Out ''
Out '== details of run 1 (every assertion, both captures)'
$r1 = @($results | Where-Object { $_.Info.run -eq 1 })[-1]
foreach ($c in $r1.Checks) { Out ("  {0} {1} [{2}]" -f $(if ($c.ok) { 'PASS' } else { 'FAIL' }), $c.name, $c.detail) }
[System.IO.File]::WriteAllText($Out, ([string]::Join("`r`n", [string[]]$L.ToArray()) + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
"result written: $Out"
