#!/usr/bin/env python3
"""Text-colour gate for a paired Mac/Windows run: text pixels differ by decision 2 (Segoe UI vs SF), but the COLOUR must match.
usage: pair_textcolour_report.py <case-dir> <runs/<ts> dir>   (after factory/tools/pair.py produced mac/ and windows/)
<case>/pair.json supplies {"textColourGate": {"tolerance": 24, "regions": [{"name": ..., "rect": [x0,y0,x1,y1]}]}} (800x600 capture px, one text line each).
Per run and region it GATES that the strongest ink pixel (the pixel farthest from white, a full-coverage glyph pixel) is within `tolerance` per channel of the
Mac's, and that both sides have ink. Optional "background": [r,g,b] measures ink as the distance from that colour instead of from white (dark cases). Positions outside the regions are gated by the case's excludeRects pixel gate. It REPORTS the strongest pixel on each side.
POSITION (sr1-decisions #19): the glyph pixels stay excluded (decision 2) but where the line sits is gated, as decision 12 does for a TextField. With
  "position": {"align": "centre" | "leading", "firstInkYTolerancePx": 2, "baselineTolerancePx": 2, "inkCentreYTolerancePx": 0.5, "inkCentreXTolerancePx": 1, "firstInkXTolerancePx": 0, "reason": "..."}
each region measures, on both sides, the ink (a pixel whose luminance is at least "coverage" (default 0.15) of the strongest ink's distance away from the region's background colour, the most
common colour in the region or "background": relative, so an ink colour that moves within its own 24/255 tolerance never moves the edge it is measured at),
its first glyph (the run of consecutive ink columns from the first ink column), and compares: firstInkY (top of the first glyph), baseline (bottom of the first glyph) and the
mid-point of the two (the line is centred on both sides, Windows draws the 12 pt body font and the Mac 13 pt, so the top sits lower and the baseline higher by a measured
amount), plus x: for "leading" text the first ink column (firstInkXTolerancePx, default 0), for "centre" text the centre of the ink bbox (inkCentreXTolerancePx, default 0;
the advance differs, the centring does not). A region can override "align". Every tolerance defaults to 0; a non-zero one is measured and carries "reason"."""
import json, sys
from collections import Counter
from pathlib import Path
from PIL import Image


def strongest(img, rect, background=None):
    """the pixel farthest from white (default) or, for a dark case, from `background` (the window colour the ink sits on)"""
    best, bp = -1, None
    crop = img.crop(rect)
    for p in crop.getdata():
        d = sum(255 - c for c in p) if background is None else sum(abs(c - b) for c, b in zip(p, background))
        if d > best: best, bp = d, p
    return None if best <= 0 else list(bp)


def lum(p):
    return (299 * p[0] + 587 * p[1] + 114 * p[2]) / 1000


def position(img, rect, background=None, coverage=0.15):
    """ink geometry of one text region: first ink x, first glyph top and bottom (baseline), ink bbox centre x; None when the region has no ink"""
    x0, y0, x1, y1 = rect
    px = img.load()
    pts = [(x, y, px[x, y]) for y in range(y0, y1) for x in range(x0, x1)]
    bg = tuple(background) if background else Counter(p for _, _, p in pts).most_common(1)[0][0]
    top = max(abs(lum(p) - lum(bg)) for _, _, p in pts)
    if top < 8:
        return None
    ink = [(x, y) for x, y, p in pts if abs(lum(p) - lum(bg)) >= coverage * top]
    cols = sorted({x for x, _ in ink})
    run = {cols[0]}
    for c in cols[1:]:
        if c != max(run) + 1:
            break
        run.add(c)
    xs = [x for x, _ in ink]
    rows = sorted({y for _, y in ink})
    bands = 1 + sum(1 for a, b in zip(rows, rows[1:]) if b != a + 1)
    return dict(firstInkX=cols[0], firstInkY=min(y for x, y in ink if x in run), baselineY=max(y for x, y in ink if x in run), inkCentreX=(min(xs) + max(xs) + 1) / 2,
                inkRightX=max(xs) + 1, inkHeight=max(rows) - min(rows) + 1, lineBands=bands)


def position_why(m, w, pos, align):
    """-> list of reasons the line's position differs beyond its tolerances (empty: ok)"""
    if m is None or w is None:
        return [f"no ink to place: mac={m} windows={w}"]
    t = lambda k: float(pos.get(k, 0))
    why = []
    dy, db = w["firstInkY"] - m["firstInkY"], w["baselineY"] - m["baselineY"]
    if abs(dy) > t("firstInkYTolerancePx"): why.append(f"first ink y differs by {dy} px (tolerance {t('firstInkYTolerancePx'):g})")
    if abs(db) > t("baselineTolerancePx"): why.append(f"baseline differs by {db} px (tolerance {t('baselineTolerancePx'):g})")
    if abs((dy + db) / 2) > t("inkCentreYTolerancePx"): why.append(f"ink vertical centre differs by {(dy + db) / 2:g} px (tolerance {t('inkCentreYTolerancePx'):g})")
    if align == "leading":
        dx = w["firstInkX"] - m["firstInkX"]
        if abs(dx) > t("firstInkXTolerancePx"): why.append(f"first ink x differs by {dx} px (tolerance {t('firstInkXTolerancePx'):g})")
    else:
        dx = w["inkCentreX"] - m["inkCentreX"]
        if abs(dx) > t("inkCentreXTolerancePx"): why.append(f"ink centre x differs by {dx:g} px (tolerance {t('inkCentreXTolerancePx'):g})")
    # ROUND 5 (decision F1): a text row may also gate the number of lines (ink bands separated by a blank pixel row; both sides must show the same count, within
    # "lineBandsTolerance", default 0) and where the ink ends ("maxInkRightPx": neither side's ink bbox right edge may pass it, a truncated or wrapped line stays in its frame).
    if "lineBands" in pos or pos.get("lines"):
        db_ = w["lineBands"] - m["lineBands"]
        if abs(db_) > t("lineBandsTolerance"): why.append(f"line count differs: mac {m['lineBands']} windows {w['lineBands']}")
    if "maxInkRightPx" in pos:
        for side, v in (("mac", m), ("windows", w)):
            if v["inkRightX"] > float(pos["maxInkRightPx"]): why.append(f"{side} ink ends at {v['inkRightX']} px, past {pos['maxInkRightPx']}")
    return why


def bottom_of_colour(img, rect):
    """the bottom edge (y of the row below the last row) of the non-background pixels in `rect`: the bottom of a plain shape"""
    px = img.load(); x0, y0, x1, y1 = rect
    bg = Counter(px[x, y] for y in range(y0, y1) for x in range(x0, x1)).most_common(1)[0][0]
    rows = [y for y in range(y0, y1) if any(sum(abs(a - b) for a, b in zip(px[x, y], bg)) > 90 for x in range(x0, x1))]
    return None if not rows else max(rows) + 1


def baseline_align(img, items, tol):
    """ROUND 5 (decision F3): baseline alignment is gated as a RELATION on each side separately, not as a position across them (Segoe UI and SF have different ascents). items =
    [{"kind": "text" | "rect", "rect": [x0, y0, x1, y1]}]: a text's baseline is the bottom edge of its first glyph's ink, a rect's the bottom of its pixels. Every item's baseline must
    lie within `tol` px of the first item's. -> (ok, [baselines])"""
    vals = []
    for it in items:
        if it["kind"] == "text":
            p = position(img, tuple(it["rect"]))
            vals.append(None if p is None else p["baselineY"] + 1)
        else:
            vals.append(bottom_of_colour(img, tuple(it["rect"])))
    ok = all(v is not None for v in vals) and max(vals) - min(vals) <= tol
    return ok, vals


def main():
    case, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    cfg = json.loads((case / "pair.json").read_text())["textColourGate"]
    tol = int(cfg.get("tolerance", 24))
    rows = []
    for mac in sorted((out / "mac").glob("run-*.png")):
        n = mac.stem.split("-")[1]
        win = out / "windows" / f"native-{n}.png"
        row = dict(run=int(n), ok=False, regions=[])
        rows.append(row)
        if not win.is_file(): row["error"] = "missing windows capture"; continue
        im, iw = Image.open(mac).convert("RGB"), Image.open(win).convert("RGB")
        ok = True
        for r in cfg["regions"]:
            bg = cfg.get("background")
            m, w = strongest(im, tuple(r["rect"]), bg), strongest(iw, tuple(r["rect"]), bg)
            good = m is not None and w is not None and all(abs(a - b) <= tol for a, b in zip(m, w))
            reg = dict(name=r["name"], mac=m, windows=w, ok=good)
            if "position" in cfg:
                cov = float(cfg["position"].get("coverage", 0.15))
                pm, pw = position(im, tuple(r["rect"]), bg, cov), position(iw, tuple(r["rect"]), bg, cov)
                pos = {**cfg["position"], **r.get("position", {})}   # a region may carry its own measured tolerances (and "reason")
                why = position_why(pm, pw, pos, r.get("align", pos.get("align", "centre")))
                reg.update(position=dict(mac=pm, windows=pw, ok=not why, why=why)); good = good and not why; reg["ok"] = good
            ok &= good
            row["regions"].append(reg)
        for g in cfg.get("baselineAlign", []):
            tol = float(g.get("tolerancePx", 1))
            mo, mv = baseline_align(im, g["items"], tol); wo, wv = baseline_align(iw, g["items"], tol)
            row["regions"].append(dict(name=g["name"], mac=mv, windows=wv, ok=mo and wo, baselineAlign=dict(tolerancePx=tol, macOk=mo, windowsOk=wo)))
            ok &= mo and wo
        row["ok"] = ok
    passed = sum(1 for r in rows if r["ok"])
    (out / "text-colour-report.json").write_text(json.dumps(dict(case=case.name, run=out.name, pairs=len(rows), gatePassed=passed, tolerance=tol, rows=rows), indent=1))
    first = rows[0]["regions"] if rows else []
    print(f"{case.name}: pairs={len(rows)} text-colour-gate={passed}/{len(rows)} (tolerance {tol}/255 per channel{', position gated' if 'position' in cfg else ''}) first run: " + "; ".join(f"{r['name']} mac={r['mac']} win={r['windows']}" + (f" at mac={r['position']['mac']} win={r['position']['windows']}" if 'position' in r else '') for r in first))
    for r in rows:
        if not r["ok"]: print("  run", r["run"], r.get("error") or [(g["name"], g.get("position", {}).get("why"), g["mac"], g["windows"]) if not g["ok"] else g["name"] for g in r["regions"]])
    sys.exit(0 if rows and passed == len(rows) else 1)


if __name__ == "__main__":
    main()
