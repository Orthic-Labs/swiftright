"""Multi-line text placement (issue #7, G76): the text-colour gate of a wrapped text row places it by its FIRST line band (pair_textcolour_report.py position()).
The seeded faults move one whole line band of the Windows capture of line-limit-v1 run 01 (scale 2.5 px per pt):

  line2-down-3px   line 2 (second band) of row 0 moved 3 px down (1.2 pt, past the 1 pt the brief names): line 2 is not the first band, so the first-band
                   metric cannot see it; only a line-level metric can (inkHeight, lineBands, bandBottoms; see FACTS.md for which one decides)
  line2-up-3px     the same, 3 px up
  line2-row1-down-3px  line 2 of row 1 (three lines) moved 3 px down
  line1-down-3px   line 1 (the first band) of row 0 moved 3 px down: the first-band firstInkY and baseline move, so the existing row gate must catch it
  line2-down-2px   probe: 2 px (0.8 pt) down, reported only (the sensitivity of a line-level metric)
"""
from core import M
from mutlib import *
import pair_textcolour_report as TC

MUTATIONS = []
add = lambda gate, *a, **k: MUTATIONS.append(M(gate, *a, **k))
GC = "text-colour"
BASE = "line-limit-ml"


def bands(im, rect):
    """the line bands of a region on this image (ink rows separated by a blank row), as (first_row, last_row) pairs; the same ink threshold as the gate"""
    x0, y0, x1, y1 = rect
    px = im.load()
    pts = [(x, y, px[x, y]) for y in range(y0, y1) for x in range(x0, x1)]
    bg = Counter(p for _, _, p in pts).most_common(1)[0][0]
    top = max(abs(TC.lum(p) - TC.lum(bg)) for _, _, p in pts)
    rows = sorted({y for x, y, p in pts if abs(TC.lum(p) - TC.lum(bg)) >= 0.15 * top})
    out, start = [], rows[0]
    for a, b in zip(rows, rows[1:]):
        if b != a + 1:
            out.append((start, a)); start = b
    out.append((start, rows[-1]))
    return out, bg


def move_band(ctx, region, band, dy):
    """move band `band` (0-based) of the region's Windows ink by dy rows; the vacated rows take the region's background"""
    def f(ctx):
        rect = tuple(ctx.cfg["textColourGate"]["regions"][region]["rect"])
        im = load(ctx.p("windows/native-01.png"))
        bs, bg = bands(im, rect)
        (ya, yb) = bs[band]
        box = (rect[0], ya, rect[2], yb + 1)
        crop = im.crop(box)
        out = im.copy()
        out.paste(bg, box)
        out.paste(crop, (rect[0], ya + dy))
        save(out, ctx.p("windows/native-01.png"))
        return f"region {region} band {band + 1} (rows {ya}..{yb}) moved {dy:+d} px on the Windows side; bands before: {bs}"
    return f


add("text-colour", BASE, "line2-down-3px", "catch", move_band(None, 0, 1, +3), "line 2 of a two-line row moved 3 px (1.2 pt) down: the first-band metric cannot see it")
add("text-colour", BASE, "line2-up-3px", "catch", move_band(None, 0, 1, -3), "line 2 of a two-line row moved 3 px (1.2 pt) up")
add("text-colour", BASE, "line2-row1-down-3px", "catch", move_band(None, 1, 1, +3), "line 2 of a three-line row moved 3 px (1.2 pt) down")
add("text-colour", BASE, "line1-down-3px", "catch", move_band(None, 0, 0, +3), "line 1 of a two-line row moved 3 px (1.2 pt) down: the first-band firstInkY and baseline move")
add("text-colour", BASE, "line2-down-2px", "probe", move_band(None, 0, 1, +2), "sensitivity: line 2 moved 2 px (0.8 pt) down")
