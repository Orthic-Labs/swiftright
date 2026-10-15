#!/usr/bin/env python3
"""Wave 1 block I2 (docs/foundations-images-fonts.md 1.3, 1.4): image layout, scaling and interpolation. Creates
  CAL  cases (group swiftui.image-calibration, Mac-only captures that feed the filter fit; the CALIBRATION image set: seeds/dimensions below) and
  GATE cases (group swiftui.image-layout, Mac/Windows pairs; the GATING image set: other seeds and other source dimensions),
each with a layout.json manifest (every cell: family, seed, source size, level, ratio, destination size, the intended origin in px) next to the witness.
Pages are 320 x 240 pt (800 x 600 px at scale 2.5) on a mid-grey ground (128) so that no image colour equals the ground; each page holds rows of cells.
A cell is Image(decorative: pixels, scale: 2.5).resizable().interpolation(level).frame(W pt, H pt) with a leading pad of `lead` pt (fractional origins:
0.1 pt = 0.25 px). Source pixels come from i2gen (integer-only, byte-identical Swift and Python).
usage: make_cases.py [substring ...]   (re-stamps the matching cases)"""
import json, math, subprocess, sys, shutil
from fractions import Fraction as F
from pathlib import Path
import i2gen
H = Path(__file__).resolve().parent
S = 2.5
FAMS = ["photo", "lineart", "text", "alpha", "checker"]
RATIOS = [0.33, 0.5, 0.66, 0.8, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0]    # the eight 1.4 calibration ratios plus 1:1 and 2x (a (B, C) cubic blurs at 1:1 unless the Mac draws it directly: measured)
LEVELS = ["none", "low", "medium", "high", "default"]
GROUND = 128
CAL_SEEDS = {"photo": 11, "lineart": 21, "text": 31, "alpha": 41, "checker": 52}      # checker seed 52: 3 px cells; sizes 48 x 36
GATE_SEEDS = {"photo": 111, "lineart": 121, "text": 131, "alpha": 143, "checker": 150}  # checker seed 150: 1 px cells; sizes 45 x 34
CAL_SRC, GATE_SRC = (48, 36), (57, 41)       # the gating set differs in seeds AND sizes. Odd sides make every `.none` cell tie-free (G51); the Mac's mip chain for an odd side reduced > 2:1 is not fitted (G53), so the
# 0.33 ratio of `.medium` / `.high` is gated on the even-sided mip page instead (mip-v1) and left out of the odd-sided ratio pages
LEADS = [0.1, 0.0, 0.3, 0.4, 0.2]      # pt, tried in this order starting at the cell's own index: 0.25, 0, 0.75, 1, 0.5 px. A lead is refused when it puts ANY edge of the cell on an exact half pixel:
# there a Mac edge depends on floating-point noise of the layout sum (measured: 16.5 + 24 gave a right edge of 40, not 41), which is not a rule a gate can pin (docs/sr1-decisions.md G51).

HEADER = """#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import ImageIO
import CoreGraphics
#endif

"""
HELPER = i2gen.SWIFT_GEN + """
/// Straight-alpha RGBA8 pixels of one synthetic family (i2gen.py) as an Image at scale 2.5 (W px = W / 2.5 pt). Windows: RGBAImage; Mac: CGImage, alpha last, not premultiplied.
@MainActor func i2Image(_ family: String, _ w: Int, _ h: Int, _ seed: Int) -> Image {
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h { for x in 0..<w { let p = i2Pixel(family, w, h, seed, x, y); let i = (y * w + x) * 4; bytes[i] = p.0; bytes[i + 1] = p.1; bytes[i + 2] = p.2; bytes[i + 3] = p.3 } }
#if os(Windows)
    return Image(decorative: RGBAImage(width: w, height: h, rgba: bytes)!, scale: 2.5)
#else
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    return Image(decorative: cg, scale: 2.5)
#endif
}
"""


def lvl(expr, level):
    return expr if level == "default" else f"{expr}.interpolation(.{level})"


def pt(px):
    return f"{px / S!r}"


def grid_cell(c):
    """c: family, seed, sw, sh, level, wpx, hpx, lead (pt) -> Swift source."""
    img = f"i2Image(\"{c['family']}\", {c['sw']}, {c['sh']}, {c['seed']}).resizable()"
    img = lvl(img, c["level"])
    if c.get("aa") is not None: img += f".antialiased({'true' if c['aa'] else 'false'})"
    return f"{img}.frame(width: {pt(c['wpx'])}, height: {pt(c['hpx'])}).padding(.leading, {c['lead']})"


def fit_cell(c):
    img = f"i2Image(\"{c['family']}\", {c['sw']}, {c['sh']}, {c['seed']}).resizable()"
    img = lvl(img, c["level"])
    if c.get("ar"):      # the explicit spelling: .aspectRatio(contentMode:)
        img += f".aspectRatio(contentMode: .{c['mode']})"
    else:
        img += ".scaledToFit()" if c["mode"] == "fit" else ".scaledToFill()"
    img += f".frame(width: {c['fw']}, height: {c['fh']})"
    if c["mode"] == "fill": img += ".clipped()"
    return img + f".padding(.leading, {c['lead']})"


def half(v):
    """True when the (exact) pixel position v sits on a half pixel."""
    return v % 1 == F(1, 2)


def cell_edges(c, x_pt, lead):
    """Exact left/right and image-rect edges (px) for cell c at accumulated x (Fractions, pt)."""
    if c.get("mode"):
        fw, fh = F(c["fw"]), F(c["fh"])
        sw, sh = F(c["sw"], 1) / F(5, 2), F(c["sh"], 1) / F(5, 2)
        k = min(fw / sw, fh / sh) if c["mode"] == "fit" else max(fw / sw, fh / sh)
        iw, ih = sw * k, sh * k
        ox = (x_pt + lead + (fw - iw) / 2) * F(5, 2)
        oy = ((fh - ih) / 2) * F(5, 2)
        fx = (x_pt + lead) * F(5, 2)      # the frame's own edges are the clip edges of a fill
        return [ox, ox + iw * F(5, 2), oy, oy + ih * F(5, 2)] + ([fx, fx + fw * F(5, 2)] if c["mode"] == "fill" else [])
    ox = (x_pt + lead) * F(5, 2)
    return [ox, ox + c["wpx"], F(0), F(c["hpx"])]


def pick_leads(cells):
    """Fix each cell's lead (pt, Fractions of tenths) so that no edge sits on an exact half pixel; returns the leads and mutates the cells."""
    x = F(0)
    for i, c in enumerate(cells):
        order = LEADS[i % len(LEADS):] + LEADS[:i % len(LEADS)]
        want = c.get("lead")
        for L in ([want] if want is not None else []) + order:
            lead = F(str(L))
            e = cell_edges(c, x, lead)
            if not any(half(v) for v in e[:2] + e[4:]):
                break
        else:
            raise SystemExit(f"no lead avoids a half-pixel edge for {c}")
        c["lead"] = float(lead)
        w_pt = F(c["fw"]) if c.get("mode") else F(c["wpx"], 1) / F(5, 2)
        x += lead + w_pt


def page(name, rows, row_h, extra=None):
    """rows: list of (rowHeightPt, [cell...]) -> (swift source, manifest)."""
    lines, man, y = [], [], 0
    for rh, cells in rows:
        pick_leads(cells)
        parts, x = [], 0.0
        for c in cells:
            src = fit_cell(c) if c.get("mode") else grid_cell(c)
            parts.append(src)
            lead = c["lead"]
            if c.get("mode"):
                w_pt, h_pt = c["fw"], c["fh"]
            else:
                w_pt, h_pt = c["wpx"] / S, c["hpx"] / S
            m = dict(c); m.update(originPx=[(x + lead) * S, y * S], framePx=[w_pt * S, h_pt * S], rowTopPt=y)
            man.append(m)
            x += lead + w_pt
        lines.append("                HStack(alignment: .top, spacing: 0) { " + "; ".join(parts) + " }.frame(width: 320, height: %s, alignment: .topLeading)" % rh)
        y += rh
    src = HEADER + HELPER + f"""
struct {name}: View {{
    var body: some View {{
        ZStack(alignment: .topLeading) {{
            Rectangle().fill(Color(red: {GROUND}.0 / 255, green: {GROUND}.0 / 255, blue: {GROUND}.0 / 255))
            VStack(alignment: .leading, spacing: 0) {{
{chr(10).join(lines)}
            }}
        }}.frame(width: 320, height: 240, alignment: .topLeading)
    }}
}}
"""
    return src, dict(page=name, scale=S, groundRGB=GROUND, cells=man, **(extra or {}))


def has_tie(sn, f):
    """Some destination pixel centre maps exactly onto a source pixel boundary (a nearest-neighbour tie): the Mac decides it by float noise (G51), so a `.none` cell avoids it."""
    return any((2 * t + 1) * sn % (2 * f) == 0 for t in range(f))


def tie_free(sn, f):
    """A tie is absent iff v2(dest) >= v2(source): an odd source never ties. Even sources are left as they are (the fit excludes tie cells)."""
    return f


def gate_set(seeds):
    return seeds is GATE_SEEDS


def ratio_cells(family, seeds, srcdim, level, aa=None, ratios=RATIOS):
    sw, sh = srcdim
    out = []
    for i, r in enumerate(ratios):
        w, h = max(1, round(sw * r)), max(1, round(sh * r))
        if level == "none" and gate_set(seeds):
            assert not has_tie(sw, w) and not has_tie(sh, h), f"a gated .none cell must be tie-free: {sw}x{sh} -> {w}x{h}"
        out.append(dict(family=family, seed=seeds[family], sw=sw, sh=sh, level=level, ratio=r, wpx=w, hpx=h, lead=LEADS[i % len(LEADS)], aa=aa))
    return out


def ratio_page(tag, family, seeds, srcdim, levels=LEVELS):
    rows = []
    for lv in levels:
        cells = ratio_cells(family, seeds, srcdim, lv)
        if gate_set(seeds) and lv in ("medium", "high"):
            cells = [c for c in cells if not ((srcdim[0] % 2 and srcdim[0] / c["wpx"] > 2) or (srcdim[1] % 2 and srcdim[1] / c["hpx"] > 2))]    # odd side reduced > 2:1: not fitted (G53), gated on the even mip page
        rows.append(cells)
    # a row is as tall as its tallest cell plus a pixel, in EVEN points (a row top on a whole device pixel at scale 2.5); the page must fit 240 pt
    rh = int(2 * math.ceil((max(c["hpx"] for r in rows for c in r) / S + 1) / 2))
    assert rh * len(rows) <= 240, f"{len(rows)} rows of {rh} pt do not fit the 240 pt page"
    return page(f"Witness_i2_{tag}_{family}", [(rh, r) for r in rows], rh)


def mip_page(tag, seeds):
    """Even-sided sources (56 x 40) reduced MORE than 2:1 at `.medium` and `.high` (the Mac's mip chain), ratios 0.33, 0.4, 0.45, 0.5 (exactly 2:1: sampled directly)."""
    rows = []
    for fam, lv in (("photo", "medium"), ("photo", "high"), ("lineart", "medium"), ("lineart", "high"), ("alpha", "high")):
        rows.append((46, ratio_cells(fam, seeds, (56, 40), lv, ratios=[0.33, 0.4, 0.45, 0.5])))
    return page(f"Witness_i2_{tag}", rows, 46)


def unit_page(tag, family_list, seeds, srcdim):
    """1:1 and .none at 2x / 3x: two rows (integer origin, fractional origin)."""
    sw, sh = srcdim
    rows = []
    for ri, lead in enumerate([0.0, 0.2]):
        cells = []
        for k, (fam, ratio) in enumerate([(f, r) for f in family_list for r in (1, 2, 3)]):
            pass
    rows = []
    combos = [(f, r) for f in family_list for r in (1, 2, 3)]
    # 5 families x 3 ratios = 15 cells; one row of 3 per family would need 5 rows x up to 108 px: 5 rows of 44 pt
    for f in family_list:
        cells = [dict(family=f, seed=seeds[f], sw=sw, sh=sh, level="none", ratio=r, wpx=sw * r, hpx=sh * r, lead=[0.0, 0.2, 0.4][j], aa=None) for j, r in enumerate((1, 2, 3))]
        rows.append((46, cells))
    return page(f"Witness_i2_{tag}", rows, 46)


def fitfill_page(tag, mode, seeds, wide=(60, 40), tall=(40, 60), ar=False):
    """A wide and a tall image (default 60 x 40 and 40 x 60) of several families in wide and tall frames, levels high / low / default / none."""
    ww, wh = wide; tw, th = tall
    def c(family, sw, sh, fw, fh, level, lead):
        return dict(family=family, seed=seeds[family], sw=sw, sh=sh, level=level, mode=mode, fw=fw, fh=fh, lead=lead, aa=None, ar=ar and family in ("photo", "text"))
    rows = [(46, [c("photo", ww, wh, 80, 44, "high", 0.0), c("photo", tw, th, 80, 44, "high", 0.2), c("alpha", ww, wh, 60, 44, "default", 0.4), c("lineart", tw, th, 60, 44, "low", 0.1)]),
            (114, [c("photo", ww, wh, 44, 110, "high", 0.0), c("photo", tw, th, 44, 110, "high", 0.2), c("text", ww, wh, 60, 110, "default", 0.4), c("checker", tw, th, 60, 110, "medium", 0.1), c("alpha", tw, th, 44, 110, "low", 0.3)])]
    return page(f"Witness_i2_{tag}", rows, 46)


def aa_page(tag, seeds):
    """.antialiased(true / false) at a fractional origin and ratios 1.25 / 2.5 / 0.5 for two families, levels low and high."""
    rows = []
    for fam in ("photo", "checker"):
        for lv in ("low", "high"):
            cells = []
            for aa in (True, False):
                for j, r in enumerate((0.5, 1.25, 2.5)):
                    cells.append(dict(family=fam, seed=seeds[fam], sw=48, sh=36, level=lv, ratio=r, wpx=round(48 * r), hpx=round(36 * r), lead=[0.2, 0.1, 0.3][j], aa=aa))
            rows.append((46, cells))
    return page(f"Witness_i2_{tag}", rows[:5], 46)


def build():
    cases = {}
    for f in FAMS:
        cases[("swiftui.image-calibration", f"cal-ratios-{f}-v1")] = ratio_page("cal", f, CAL_SEEDS, CAL_SRC)
        cases[("swiftui.image-layout", f"ratios-{f}-v1")] = ratio_page("gate", f, GATE_SEEDS, GATE_SRC, levels=["none", "low", "medium", "high"])
    for f in ("photo", "lineart", "alpha"):     # odd source sizes (47 x 35): `.none` is tie-free; how the Mac halves an odd size in its mip chain (not fitted: G53)
        cases[("swiftui.image-calibration", f"cal-ratios-odd-{f}-v1")] = ratio_page("calodd", f, {k: v + 1000 for k, v in CAL_SEEDS.items()}, (47, 35), levels=["none", "low", "medium", "high"])
    # 1 px checker cells (seed 60: 60 % 3 == 0 gives n = 1), calibration sizes, a seed the gating page does not use: added after the gating checker page failed medium (decision G73)
    cases[("swiftui.image-calibration", "cal-ratios-checker1-v1")] = ratio_page("cal1px", "checker", {"checker": 60}, CAL_SRC, levels=["none", "low", "medium", "high"])
    cases[("swiftui.image-calibration", "cal-aa-v1")] = aa_page("cal_aa", CAL_SEEDS)
    cases[("swiftui.image-layout", "aa-v1")] = aa_page("gate_aa", GATE_SEEDS)
    cases[("swiftui.image-layout", "mip-v1")] = mip_page("mip", GATE_SEEDS)
    cases[("swiftui.image-layout", "one-to-one-none-int-v1")] = unit_page("unit", FAMS, GATE_SEEDS, (24, 18))
    cases[("swiftui.image-layout", "fit-v1")] = fitfill_page("fit", "fit", GATE_SEEDS, (72, 48), (48, 72), ar=True)
    cases[("swiftui.image-layout", "fill-v1")] = fitfill_page("fill", "fill", GATE_SEEDS, (72, 48), (48, 72), ar=True)
    cases[("swiftui.image-calibration", "cal-fit-v1")] = fitfill_page("calfit", "fit", CAL_SEEDS)
    cases[("swiftui.image-calibration", "cal-fill-v1")] = fitfill_page("calfill", "fill", CAL_SEEDS)
    return cases


def main():
    want = sys.argv[1:]
    tmp = H / ".witness-tmp"; tmp.mkdir(exist_ok=True)
    for (group, case), (src, man) in build().items():
        if want and not any(w in case for w in want): continue
        d = H / group / case
        d.mkdir(parents=True, exist_ok=True)
        expr = man["page"] + "()"
        wf = tmp / (case + ".swift"); wf.write_text(src)
        subprocess.check_call([sys.executable, str(H / "new-case.py"), f"{group}/{case}", str(wf), expr, "--settle", "0.3"])
        (d / "layout.json").write_text(json.dumps(man, indent=1) + "\n")
        gate = dict(groundRGB=GROUND)
        tj = H / "tolerances.json"
        if group == "swiftui.image-layout" and tj.is_file():
            t = json.loads(tj.read_text())
            gate.update(resampleTolerance=t["resampleTolerance"], resampleToleranceReason=t["resampleToleranceReason"], resampleFilter=t["resampleFilter"])
        (d / "pair.json").write_text(json.dumps(dict(resampleGate=gate), indent=1) + "\n")
    shutil.rmtree(tmp)


if __name__ == "__main__":
    main()
