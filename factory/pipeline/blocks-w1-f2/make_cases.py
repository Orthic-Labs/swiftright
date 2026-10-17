#!/usr/bin/env python3
"""Wave 1 / F2 block cases (docs/foundations-images-fonts.md F2; decisions G70+ in docs/sr1-decisions.md): system font mapping, Mac vs Windows.
Stamped through new-case.py (ScalePin-pinned Mac host, byte-identical Witness). usage: make_cases.py [case-substring ...]

Case families (directory `swiftui.system-font-f2/`):
  styles-regular-v1, styles-emphasized-v1   the eleven text styles, regular and `.bold()` (the style's emphasized weight, G25), stacked with no spacing and no fixed frames
  grid-<size>-v1                            Font.system(size: S, weight: w) for the nine weights at S in 9, 11, 13, 16, 20, 24, 32 pt (63 combinations), a 3 x 3 grid
  design-monospaced-v1, design-serif-v1, design-rounded-v1   the three designs at 13 regular, 13 bold, 20 regular, 28 light
  baseline-hstack-v1                        HStack(alignment: .firstTextBaseline) mixing sizes, text styles and designs
  hub-theme-v1                              the hub's theme fonts (F15)
  digits-v1                                 monospacedDigit() (tnum; width reported)
Texts have no descenders (HIEFLT Hxz, HIH, Hub Total 82%): rows touch (no spacing), and a descender of the row above bled 1-2 px into the next row's region, so the first N=20 pass measured
the bleed (first ink y -12 px in hub-theme) and failed the exact gate outside the excluded regions (grid-13/24/32).

Gates (pair.json): (1) semantic tree: Text elements' y and height within 0.05 pt of the Mac's ("boundsY") and x ("boundsX"): the Text FRAME and, in the baseline HStack, the
baseline placement (a child's y is the difference of baselines) are exact in points; (2) the text-colour gate with the position gate of decision 19 per text region (first glyph top,
baseline, mid-point, first ink column), tolerances re-measured at 13 DIP (decision G7x); the glyph pixels themselves are excluded by name (decision 2); (3) the baseline relation for the
baseline HStack (decision F3). Width is semantic: reported (ink right edge, text-colour report), never gated.

The witness is a W x 200 pt frame top-leading in the 320 x 240 pt viewport: origin ((320 - W) / 2, 20) pt = client pixel (2.5 x) at scale 2.5."""
import json, subprocess, sys, tempfile
from pathlib import Path
H = Path(__file__).resolve().parent
ROOT = H.parents[2]
SCALE = 2.5
BLOCK = "swiftui.system-font-f2"
HEADER_NOTE = "F2"

_s = (ROOT / "packages/SwiftRightHost/Sources/SwiftRightHost/FontMetricTableData.swift").read_text()
TABLE = json.loads(_s[_s.index('#"""') + 5:_s.rindex('"""#')])
STYLES = ["largeTitle", "title", "title2", "title3", "headline", "body", "callout", "subheadline", "footnote", "caption", "caption2"]
WEIGHTS = ["ultraLight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black"]
EMPH = {"largeTitle": "bold", "title": "bold", "title2": "bold", "title3": "semibold", "headline": "heavy", "subheadline": "semibold", "body": "semibold",
        "callout": "semibold", "footnote": "semibold", "caption": "medium", "caption2": "semibold"}


def fmt(n):
    return ("%g" % n)


def sys_line(size, design="default"):
    return TABLE["swiftUISystem"][f"{design}|regular|{fmt(size)}|{fmt(SCALE)}"]


def style_line(style, design="default"):
    return TABLE["swiftUIStyles"][f"{style}|{'default' if design == 'default' else 'design-' + design}|{fmt(SCALE)}"]


def rect(ox, oy, x0, y0, x1, y1):
    return [round((ox + x0) * SCALE), round((oy + y0) * SCALE), round((ox + x1) * SCALE), round((oy + y1) * SCALE)]


# first-pass tolerances (px): wide, to be replaced by the measured ones (decision G7x). "reason" names the pass.
FIRST_PASS = {"firstInkYTolerancePx": 8, "baselineTolerancePx": 8, "inkCentreYTolerancePx": 8, "firstInkXTolerancePx": 4}


def gate(regions, ox, oy, extra_pos=None, align_items=None, name=""):
    pos = {"align": "leading", "reason": "F2 first pass: wide tolerances to record the Windows minus Mac deltas at body 13 DIP; replaced by the re-measured values (decision G7x)", **FIRST_PASS}
    if extra_pos: pos.update(extra_pos)
    tcg = {"tolerance": 40, "regions": regions, "position": pos}
    if align_items: tcg["baselineAlign"] = align_items
    ex = [{"name": f"{r['name']} glyph region (Segoe UI vs SF, decision 2); gated by the position gate of decision 19 and the semantic frame gate", "rect": r["rect"]} for r in regions]
    return {"textColourGate": tcg, "excludeRects": ex,
            "semanticGate": {"fields": ["role", "name", "count", "order", "boundsY", "boundsX"], "scope": "main", "phases": [""]}}


CASES = {}


def witness_src(t, body, w):
    return f"""#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct {t}_inner: View {{
    var body: some View {{
{body}
    }}
}}

struct {t}: View {{
    var body: some View {{ {t}_inner().frame(width: {w}, height: 200, alignment: .topLeading) }}
}}
"""


def stack_case(name, rows, w=240):
    """rows: [(font expr, text, line (height, firstBaseline, ...))]: a VStack, leading, spacing 0, the text natural height (no fixed frames)."""
    ox, oy = (320 - w) / 2, 20
    lines = "\n".join(f'            Text("{t}").font({f})' for f, t, _ in rows)
    body = f"        VStack(alignment: .leading, spacing: 0) {{\n{lines}\n        }}"
    y, regions = 0.0, []
    for i, (f, t, ln) in enumerate(rows):
        regions.append({"name": f"row {i} {f}", "rect": rect(ox, oy, 0, y, w, y + ln[0]), "align": "leading"})
        y += ln[0]
    assert y <= 200.0001, (name, y)
    CASES[name] = (body, w, gate(regions, ox, oy))


def grid_case(size):
    w, ox, oy = 300, 10, 20
    ln = sys_line(size)
    rows = [WEIGHTS[0:3], WEIGHTS[3:6], WEIGHTS[6:9]]
    vs = "\n".join("            HStack(alignment: .top, spacing: 0) {\n" + "\n".join(
        f'                Text("HIH").font(.system(size: {fmt(size)}, weight: .{wt})).frame(width: 100, alignment: .leading)' for wt in r) + "\n            }" for r in rows)
    body = f"        VStack(alignment: .leading, spacing: 0) {{\n{vs}\n        }}"
    regions = []
    for ri, r in enumerate(rows):
        for ci, wt in enumerate(r):
            regions.append({"name": f"{size}pt {wt}", "rect": rect(ox, oy, ci * 100, ri * ln[0], ci * 100 + 100, (ri + 1) * ln[0]), "align": "leading"})
    g = gate(regions, ox, oy)
    if size <= 11:
        # SF ultraLight/thin at 11 pt never reaches a full-coverage pixel (strongest ink (91,91,91) on the Mac, measured, decision G7x), Segoe Light does ((31,31,31)): the colour gate allows the measured 60 levels here
        g["textColourGate"]["tolerance"] = 64
    CASES[f"grid-{fmt(size)}-v1"] = (body, w, g)


def design_case(design):
    rows = [(f"Font.system(size: 13, weight: .regular, design: .{design})", "HIEFLT Hxz 0123", sys_line(13, design)),
            (f"Font.system(size: 13, weight: .bold, design: .{design})", "HIEFLT Hxz 0123", sys_line(13, design)),
            (f"Font.system(size: 20, weight: .regular, design: .{design})", "HIEFLT Hxz", sys_line(20, design)),
            (f"Font.system(size: 28, weight: .light, design: .{design})", "HIEFLT", sys_line(28, design))]
    stack_case(f"design-{design}-v1", rows)


def baseline_case():
    """four HStacks(alignment: .firstTextBaseline, spacing 0) of 52 pt cells (Text 'HIH'), 6 pt apart. Row geometry from the Mac table: row top; baseline = max first baseline;
    row height = max first baseline + max (height - first baseline)."""
    w, ox, oy, cell = 240, 40, 20, 52
    mixes = [
        [("Font.system(size: 11)", sys_line(11)), ("Font.system(size: 13)", sys_line(13)), ("Font.system(size: 17)", sys_line(17)), ("Font.system(size: 22)", sys_line(22))],
        [("Font.largeTitle", style_line("largeTitle")), ("Font.body", style_line("body")), ("Font.caption", style_line("caption")), ("Font.headline", style_line("headline"))],
        [("Font.system(size: 9)", sys_line(9)), ("Font.system(size: 16, weight: .semibold)", sys_line(16)), ("Font.system(size: 24)", sys_line(24)), ("Font.system(size: 32, weight: .light)", sys_line(32))],
        [("Font.system(size: 13, design: .monospaced)", sys_line(13, "monospaced")), ("Font.system(size: 13, design: .serif)", sys_line(13, "serif")),
         ("Font.system(size: 13)", sys_line(13)), ("Font.system(size: 13, design: .rounded)", sys_line(13, "rounded"))],
    ]
    spacing = 6
    parts, regions, align, y = [], [], [], 0.0
    for ri, mix in enumerate(mixes):
        base = max(l[1] for _, l in mix); below = max(l[0] - l[1] for _, l in mix); rh = base + below
        items = "\n".join(f'                Text("HIH").font({f}).frame(width: {cell}, alignment: .leading)' for f, _ in mix)
        parts.append(f"            HStack(alignment: .firstTextBaseline, spacing: 0) {{\n{items}\n            }}")
        its = []
        for ci, (f, l) in enumerate(mix):
            r = rect(ox, oy, ci * cell, y, (ci + 1) * cell, y + rh)
            regions.append({"name": f"row {ri} item {ci} {f}", "rect": r, "align": "leading"}); its.append({"kind": "text", "rect": r})
        align.append({"name": f"row {ri} baselines", "items": its, "tolerancePx": 1})
        y += rh + spacing
    assert y - spacing <= 200.0001, y
    body = "        VStack(alignment: .leading, spacing: %d) {\n%s\n        }" % (spacing, "\n".join(parts))
    CASES["baseline-hstack-v1"] = (body, w, gate(regions, ox, oy, align_items=align))


def hub_case():
    theme = [("pageTitle", "Font.system(size: 22, weight: .semibold)", 22), ("title", "Font.system(size: 15, weight: .bold)", 15), ("lead", "Font.system(size: 13.5)", 13.5),
             ("body", "Font.system(size: 13)", 13), ("label", "Font.system(size: 12.5, weight: .semibold)", 12.5), ("caption", "Font.system(size: 12)", 12),
             ("small", "Font.system(size: 11.5)", 11.5), ("micro", "Font.system(size: 11, weight: .semibold)", 11), ("stat", "Font.system(size: 22, weight: .semibold)", 22)]
    rows = [(f, "Hub Total 82%", sys_line(s)) for n, f, s in theme]
    stack_case("hub-theme-v1", rows)


def digits_case():
    rows = [("Font.system(size: 13)", "0123456789 1111", sys_line(13)), ("Font.system(size: 13).monospacedDigit()", "0123456789 1111", sys_line(13)),
            ("Font.system(size: 22, weight: .semibold)", "10:48 1111", sys_line(22)), ("Font.system(size: 22, weight: .semibold).monospacedDigit()", "10:48 1111", sys_line(22))]
    stack_case("digits-v1", rows)


stack_case("styles-regular-v1", [(f"Font.{s}", "HIEFLT Hxz", style_line(s)) for s in STYLES])
stack_case("styles-emphasized-v1", [(f"Font.{s}.bold()", "HIEFLT Hxz", style_line(s)) for s in STYLES])
for sz in (9, 11, 13, 16, 20, 24, 32): grid_case(sz)
for d in ("monospaced", "serif", "rounded"): design_case(d)
baseline_case(); hub_case(); digits_case()


# ---- F2 fit capture for the keys block 28 uses that F2 never measured (issue #7, decision G71: "an N=20 fit capture of the missing sizes and weights on the F2 witness").
# Each row is an HStack of two cells, width 150: the PLAIN placement (natural height, in the VStack) and the FRAMED placement (frame(width: 150, height: the line height, topLeading)).
# Row order is the Swift source order of the .font(...) expressions, which position_stats.py relies on. Report-only: the block-level position carries zero tolerances,
# so the comparator measures the first-ink and baseline positions of every region and nothing is fitted or tuned from these runs.
FIT_ZERO = {"firstInkYTolerancePx": 0, "baselineTolerancePx": 0, "inkCentreYTolerancePx": 0, "firstInkXTolerancePx": 0,
            "reason": "G71 fit capture, report-only: zero tolerances so the position block is measured; no tolerance is fitted or gated by this case"}
CELL_W = 150


def fit_case(name, rows, spacing, w=300):
    """rows: [(font expr, line height in pt, plain-placement text, framed-placement text)]; the line height is the Mac table's (sys_line / style_line)."""
    ox, oy = (320 - w) / 2, 20
    parts, regions, y = [], [], 0.0
    for i, (f, lh, tp, tf) in enumerate(rows):
        parts.append(f"            HStack(alignment: .top, spacing: 0) {{\n"
                     f'                Text("{tp}").font({f}).frame(width: {CELL_W}, alignment: .leading)\n'
                     f'                Text("{tf}").font({f}).frame(width: {CELL_W}, height: {fmt(lh)}, alignment: .topLeading)\n'
                     "            }")
        for c, x0 in ((0, 0), (1, CELL_W)):
            regions.append({"name": f"row {i} item {c} {f}", "rect": rect(ox, oy, x0, y, x0 + CELL_W, y + lh), "align": "leading"})
        y += lh + spacing
    assert y - spacing <= 200.0001, (name, y)
    body = "        VStack(alignment: .leading, spacing: %s) {\n%s\n        }" % (fmt(spacing), "\n".join(parts))
    CASES[name] = (body, w, gate(regions, ox, oy, extra_pos=FIT_ZERO))


def fit_size18_weights():
    """size 18 at the nine weights; per row the plain text 'HIEFLT Hxz' and the framed text 'HIH 0123' (different texts). 9 rows, no spacing (descender-free, as the other F2 stacks)."""
    rows = [(f"Font.system(size: 18, weight: .{wt})", sys_line(18)[0], "HIEFLT Hxz", "HIH 0123") for wt in WEIGHTS]
    fit_case("fit-size18-weights-v1", rows, 0)


def fit_fractional():
    """12.5 regular, 11.5 semibold, 12 regular, caption2; three texts (short, long with descenders, digits) x two placements. 2 pt between rows (descenders stay inside the gap)."""
    keys = [("Font.system(size: 12.5, weight: .regular)", sys_line(12.5)[0]), ("Font.system(size: 11.5, weight: .semibold)", sys_line(11.5)[0]),
            ("Font.system(size: 12, weight: .regular)", sys_line(12)[0]), ("Font.caption2", style_line("caption2")[0])]
    texts = ["HIH", "Hamburgefonts gjpqy", "0123456789 42"]
    rows = [(f, lh, t, t) for f, lh in keys for t in texts]
    fit_case("fit-fractional-v1", rows, 2)


def fit_sizes_large(name, keys):
    """two texts ('HIH' and 'gjpqy 42', the second with descenders) x two placements per key; 2 pt between rows."""
    rows = [(f, lh, t, t) for f, lh in keys for t in ("HIH", "gjpqy 42")]
    fit_case(name, rows, 2)


# 28 r, 15 r, 18 r: 6 rows (157 pt). headline r and title3 sb: a separate case, because all five keys (10 rows, 218 pt) exceed the 200 pt witness height.
fit_sizes_large("fit-sizes-large-v1", [("Font.system(size: 28, weight: .regular)", sys_line(28)[0]), ("Font.system(size: 15, weight: .regular)", sys_line(15)[0]),
                                       ("Font.system(size: 18, weight: .regular)", sys_line(18)[0])])
fit_sizes_large("fit-sizes-large-b-v1", [("Font.headline.weight(.regular)", style_line("headline")[0]), ("Font.title3.weight(.semibold)", style_line("title3")[0])])
fit_size18_weights(); fit_fractional()


def main():
    only = sys.argv[1:]
    for name, (body, w, pair) in CASES.items():
        if only and not any(o in name for o in only): continue
        t = "Witness_f2_" + name.replace("-", "_")
        case = f"{BLOCK}/{name}"
        (H / case).mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory() as d:
            wf = Path(d) / "Witness.swift"; wf.write_text(witness_src(t, body, w)); pj = Path(d) / "pair.json"; pj.write_text(json.dumps(pair))
            sf = Path(d) / "steps.json"; sf.write_text(json.dumps([{"op": "wait", "ms": 600}]))
            subprocess.check_call([sys.executable, str(H / "new-case.py"), case, str(wf), f"{t}()", "--settle", "0.4", "--pair-json", str(pj), "--steps", str(sf)])
    print("cases:", ", ".join(CASES))


main()
