#!/usr/bin/env python3
"""Resampling gate (wave 1 block I2, docs/foundations-images-fonts.md 1.4): Windows against the Mac for image cells drawn at other sizes.
usage: pair_resample_report.py <case-dir> <runs/<ts> dir> [--calibrate]   (after factory/tools/pair.py produced mac/ and windows/)
<case-dir>/layout.json lists the cells (factory/pipeline/blocks-w1-i2/make_cases.py); <case-dir>/pair.json "resampleGate":
  {"groundRGB": 128,
   "resampleTolerance": {"<level>": {"resampleMaxPerChannel": n, "resampleMeanPerChannel": x}},      # level in none, low, medium, high; 'default' uses low
   "resampleToleranceReason": "...", "resampleFilter": {...},
   "excludeRects": [{"name": "...", "rect": [x0,y0,x1,y1], "reason": "..."}]}                                         # the fit that the host implements (informational here)
Per run (800x600 captures) it GATES:
  frame      outside every cell's visible rect both captures equal the ground exactly, and on the one-pixel ring around each rect and on its outermost pixels a pixel that is exactly
             the ground in one capture is not more than 16 levels from it in the other (the image covers the same pixels: exact frame and edge positions)
  exact      (alpha family: at most 1 level, partial-alpha rounding) a cell at 1:1 (not .high: the Mac blurs .high at 1:1, measured) or `.none` at an integer ratio: Windows == Mac, every pixel
  resampled  every other cell: per pixel per channel <= resampleMaxPerChannel[level] and the cell's per-channel mean <= resampleMeanPerChannel[level]
--calibrate: report only (the per-level maxima over the run: the basis of the tolerance), exit 0.  Exit 1 on any violation."""
import json, sys
from pathlib import Path
from PIL import Image, ImageChops, ImageStat

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "pipeline/blocks-w1-i2"))
import i2rects

W, H = 800, 600
EDGE_MARGIN = 16      # levels: an edge pixel is a coverage mismatch when one capture is exactly the ground and the other is further than this from it


def cell_class(c):
    lv = c["level"]
    if "mode" in c:
        return "resampled"
    if (lv in ("none", "low", "medium", "default") and c["ratio"] == 1) or (lv == "none" and c["ratio"] in (1, 2, 3)):
        return "exact"
    return "resampled"


def tol_level(c):
    return "low" if c["level"] == "default" else c["level"]


def stats(a, b, rect):
    ca, cb = a.crop(tuple(rect)), b.crop(tuple(rect))
    d = ImageChops.difference(ca, cb)
    ex = d.getextrema()
    mean = ImageStat.Stat(d).mean
    return max(e[1] for e in ex), max(mean)


def ground_mask_equal(a, b, rect, ground):
    """The ring of 1 px around rect plus the outermost pixel rows/columns inside it: the sets of ground-coloured pixels must be equal."""
    x0, y0, x1, y1 = rect
    pts = set()
    for x in range(x0 - 1, x1 + 1):
        for y in (y0 - 1, y0, y1 - 1, y1):
            pts.add((x, y))
    for y in range(y0 - 1, y1 + 1):
        for x in (x0 - 1, x0, x1 - 1, x1):
            pts.add((x, y))
    pa, pb = a.load(), b.load()
    def dist(p): return max(abs(p[0] - ground[0]), abs(p[1] - ground[1]), abs(p[2] - ground[2]))
    # covered in one capture, plainly ground in the other: a blend can land on the ground colour by chance, so "plainly" is more than EDGE_MARGIN levels away
    bad = [(x, y) for (x, y) in pts if 0 <= x < W and 0 <= y < H and ((dist(pa[x, y]) == 0 and dist(pb[x, y]) > EDGE_MARGIN) or (dist(pb[x, y]) == 0 and dist(pa[x, y]) > EDGE_MARGIN))]
    return bad


def judge(win, mac, cells, tol, ground, exclude=()):
    g = (ground, ground, ground)
    for e in exclude:      # named exclusions (pair.json resampleGate.excludeRects): both captures are set to the ground there, and the report says so
        win, mac = win.copy(), mac.copy()
        for im in (win, mac): im.paste(Image.new("RGB", (e["rect"][2] - e["rect"][0], e["rect"][3] - e["rect"][1]), g), tuple(e["rect"][:2]))
    out = dict(frame=dict(outsideDiff=0, outsideNotGround=0, edgeMismatch=0), cells=[], violations=[])
    allv = Image.new("RGB", (W, H), g)
    spill = []
    mac = mac.copy()
    # Mac corner spill (G55): at a fractional x origin (also an integer one that the Mac's float layout sees as inexact: 9.6 pt x 2.5) the ImageRenderer blends ONE extra pixel just above the top-left corner of the image, outside its snapped rect, in every run. It is named, counted and
    # allowed only as that: the row above the rect, exactly the ground on Windows, within 60 levels of the ground on the Mac. Anything else outside a rect is a frame defect.
    pw, pm = win.load(), mac.load()
    for c in cells:
        r = i2rects.cell_rects(c)["visible"]
        y = r[1] - 1
        if y < 0: continue
        for x in range(r[0] - 1, r[0] + 1):
            if 0 <= x < W and pw[x, y] == g and 0 < max(abs(v - ground) for v in pm[x, y]) <= 60:
                spill.append((x, y)); pm[x, y] = g
    out["macCornerSpill"] = spill
    wcopy, mcopy = win.copy(), mac.copy()
    for c in cells:
        r = i2rects.cell_rects(c)["visible"]
        wcopy.paste(Image.new("RGB", (r[2] - r[0], r[3] - r[1]), g), tuple(r[:2]))
        mcopy.paste(Image.new("RGB", (r[2] - r[0], r[3] - r[1]), g), tuple(r[:2]))
    for nm, im in (("windows", wcopy), ("mac", mcopy)):
        ex = ImageChops.difference(im, allv).getextrema()
        n = sum(1 for p in im.getdata() if p != g)
        out["frame"]["outsideNotGround"] += n
        if n: out["violations"].append(f"{nm}: {n} pixels outside every cell are not the ground")
    for c in cells:
        r = i2rects.cell_rects(c)["visible"]
        bad = ground_mask_equal(win, mac, r, g)
        out["frame"]["edgeMismatch"] += len(bad)
        if bad: out["violations"].append(f"edge: cell {c['family']} {c['level']} ratio {c.get('ratio', c.get('mode'))}: {len(bad)} edge pixels differ in coverage, first {bad[:3]}")
        mx, mean = stats(win, mac, r)
        cl = cell_class(c)
        tol0 = 1 if c["family"] == "alpha" else 0     # exact cells: byte-equal, except a partial-alpha pixel may differ by one level (8-bit source-over rounding; T0, G3)
        row = dict(family=c["family"], level=c["level"], ratio=c.get("ratio"), mode=c.get("mode"), rect=r, cls=cl, max=mx, mean=round(mean, 4))
        if cl == "exact":
            if mx > tol0: out["violations"].append(f"exact: {c['family']} {c['level']} ratio {c.get('ratio')}: max {mx} (must be {tol0})")
        elif tol:
            t = tol[tol_level(c)]
            row.update(tolMax=t["resampleMaxPerChannel"], tolMean=t["resampleMeanPerChannel"])
            if mx > t["resampleMaxPerChannel"]: out["violations"].append(f"resampled: {c['family']} {c['level']} ratio {c.get('ratio', c.get('mode'))}: max {mx} > {t['resampleMaxPerChannel']}")
            if mean > t["resampleMeanPerChannel"]: out["violations"].append(f"resampled: {c['family']} {c['level']} ratio {c.get('ratio', c.get('mode'))}: mean {mean:.3f} > {t['resampleMeanPerChannel']}")
        out["cells"].append(row)
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    calibrate = "--calibrate" in sys.argv
    case, out = Path(args[0]).resolve(), Path(args[1]).resolve()
    man = json.loads((case / "layout.json").read_text())
    pj = json.loads((case / "pair.json").read_text()) if (case / "pair.json").is_file() else {}
    gate = pj.get("resampleGate", {})
    ground = gate.get("groundRGB", man.get("groundRGB", 128))
    tol = gate.get("resampleTolerance")
    if not calibrate:
        assert tol and gate.get("resampleToleranceReason"), "resampleGate needs resampleTolerance per level and resampleToleranceReason (decision 5: a tolerance is measured and named)"
    runs = sorted({q.name[4:6] for q in (out / "mac").glob("run-*.png") if q.name[4:6].isdigit()})
    allok = True
    per_level = {}
    rows_all = []
    for n in runs:
        mac, win = out / f"mac/run-{n}.png", out / f"windows/native-{n}.png"
        if not (mac.is_file() and win.is_file()):
            print(f"run {n}: missing capture  FAIL"); allok = False; continue
        im, iw = Image.open(mac).convert("RGB"), Image.open(win).convert("RGB")
        if im.size != (W, H) or iw.size != (W, H):
            print(f"run {n}: size mac={im.size} win={iw.size}  FAIL"); allok = False; continue
        j = judge(iw, im, man["cells"], tol, ground, gate.get("excludeRects", []))
        ok = not j["violations"]
        allok &= ok
        for r in j["cells"]:
            if r["cls"] == "resampled":
                lv = tol_level(r); d = per_level.setdefault(lv, dict(max=0, meanMax=0.0, cells=0))
                d["max"] = max(d["max"], r["max"]); d["meanMax"] = max(d["meanMax"], r["mean"]); d["cells"] += 1
        rows_all.append(dict(cornerSpill=len(j["macCornerSpill"]), run=n, ok=ok, frame=j["frame"], violations=j["violations"][:12], cells=j["cells"]))
        worst = max((r["max"] for r in j["cells"] if r["cls"] == "resampled"), default=0)
        ex = sum(1 for r in j["cells"] if r["cls"] == "exact")
        print(f"run {n}: cells {len(j['cells'])} (exact {ex}) frame outside-not-ground {j['frame']['outsideNotGround']} edge-mismatch {j['frame']['edgeMismatch']} worst resampled max {worst}  {'PASS' if ok else 'FAIL'}")
        if not ok:
            for v in j["violations"][:8]: print("   ", v)
    rep = dict(excluded=gate.get("excludeRects", []), case=case.name, run=out.name, runs=len(runs), calibrate=calibrate, perLevel=per_level, gate=dict(tolerance=tol, reason=gate.get("resampleToleranceReason")), rows=rows_all)
    (out / "resample-report.json").write_text(json.dumps(rep, indent=1))
    print("per level (resampled cells): " + "; ".join(f"{k}: max {v['max']} meanMax {v['meanMax']:.3f} ({v['cells']} cells)" for k, v in sorted(per_level.items())))
    print("resample gate:", "REPORT ONLY" if calibrate else ("PASS" if allok and runs else "FAIL"))
    sys.exit(0 if calibrate else (0 if allok and runs else 1))


main()
