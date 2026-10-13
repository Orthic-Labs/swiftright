#!/usr/bin/env python3
"""Control gate for a paired Mac/Windows run of a LABELLED control (Toggle with its label), where the label text differs by decision 2
(Segoe UI vs SF: a different advance width) and the control therefore sits at a different x. usage: pair_control_report.py <case-dir> <runs/<ts> dir>

<case>/pair.json supplies {"controlGate": {"minControlHeightPx": 50, "controlYTolerancePx": 0, "labelCentreTolerancePx": 3, "edgeAA": 32}}. Per run it GATES:
 1. the control (the columns whose ink spans at least minControlHeightPx rows, i.e. the switch or box, never a text line) has the same width and
    height on both sides and the same y (within controlYTolerancePx);
 2. the control, translated by the measured dx, passes the factory edge gate against the Mac (flat colours exact, edges within edgeAA/255);
 3. the label is one line of ink left of the control (right of it for a checkbox) whose vertical centre agrees within labelCentreTolerancePx.
It REPORTS, never gates: dx (the label advance difference), both label ink boxes, and the number of label pixels that differ."""
import json, sys
from pathlib import Path
from PIL import Image, ImageChops

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pair import edge_gate


INK = 8      # a pixel is ink when some channel is at least this far from white (ignores the 1-2 level shadow haze around a control)


def is_ink(p):
    return p[0] < 255 - INK or p[1] < 255 - INK or p[2] < 255 - INK


def ink_columns(img, min_h):
    """x ranges (list of (x0,x1)) where the non-white vertical extent of a column is at least min_h rows."""
    w, h = img.size
    px = img.load()
    cols = []
    for x in range(w):
        ys = [y for y in range(h) if is_ink(px[x, y])]
        cols.append(bool(ys) and ys[-1] - ys[0] + 1 >= min_h)
    out, start = [], None
    for x, c in enumerate(cols + [False]):
        if c and start is None: start = x
        if not c and start is not None: out.append((start, x)); start = None
    return out


def grow_to_gap(img, x0, x1):
    """Widen [x0, x1) over adjacent columns that still have any non-white pixel (the control's rounded ends), up to the next blank column."""
    w, h = img.size
    px = img.load()
    inked = lambda x: any(is_ink(px[x, y]) for y in range(h))
    while x0 > 0 and inked(x0 - 1): x0 -= 1
    while x1 < w and inked(x1): x1 += 1
    return x0, x1


def bbox_nonwhite(img, rect):
    m = ImageChops.difference(img.crop(rect), Image.new("RGB", (rect[2] - rect[0], rect[3] - rect[1]), (255, 255, 255)))
    m = ImageChops.lighter(ImageChops.lighter(*m.split()[:2]), m.split()[2]).point(lambda v: 255 if v >= INK else 0)
    b = m.getbbox()
    return None if b is None else [b[0] + rect[0], b[1] + rect[1], b[2] + rect[0], b[3] + rect[1]]


MIN_STRIP = 4   # a label strip narrower than this cannot hold a glyph, so it is not searched


def label_box(img, c):
    """Ink bbox of the label beside the control span c=(x0,x1): searches BOTH sides (a strip must be at least MIN_STRIP wide, and excludes the
    control's own columns plus a 2 px guard) and returns the box on the side that holds the most ink, or None when neither side has any."""
    w, h = img.size
    cands = []
    if c[0] - 2 >= MIN_STRIP: cands.append((0, 0, c[0] - 2, h))
    if w - (c[1] + 2) >= MIN_STRIP: cands.append((c[1] + 2, 0, w, h))
    best = None
    for r in cands:
        b = bbox_nonwhite(img, r)
        if b is None: continue
        area = (b[2] - b[0]) * (b[3] - b[1])
        if best is None or area > best[0]: best = (area, b)
    return None if best is None else best[1]


def main():
    case, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    cfg = json.loads((case / "pair.json").read_text())["controlGate"]
    min_h, tol, aa = int(cfg.get("minControlHeightPx", 50)), int(cfg.get("labelCentreTolerancePx", 3)), int(cfg.get("edgeAA", 32))
    ytol = int(cfg.get("controlYTolerancePx", 0))
    rows = []
    for mac in sorted((out / "mac").glob("run-*.png")):
        n = mac.stem.split("-")[1]
        win = out / "windows" / f"native-{n}.png"
        row = dict(run=int(n), ok=False)
        rows.append(row)
        if not win.is_file(): row["error"] = "missing windows capture"; continue
        im, iw = Image.open(mac).convert("RGB"), Image.open(win).convert("RGB")
        if im.size != iw.size: row["error"] = f"size mac={im.size} win={iw.size}"; continue
        cm, cw = ink_columns(im, min_h), ink_columns(iw, min_h)
        if len(cm) != 1 or len(cw) != 1: row["error"] = f"control columns mac={cm} win={cw}"; continue
        (mx0, mx1), (wx0, wx1) = grow_to_gap(im, *cm[0]), grow_to_gap(iw, *cw[0])
        mrect, wrect = (mx0, 0, mx1, im.size[1]), (wx0, 0, wx1, iw.size[1])
        mb, wb = bbox_nonwhite(im, mrect), bbox_nonwhite(iw, wrect)
        dx = wb[0] - mb[0]
        same_size = (mb[2] - mb[0], mb[3] - mb[1]) == (wb[2] - wb[0], wb[3] - wb[1]) and abs(mb[1] - wb[1]) <= ytol
        # control crops side by side on an 800x600 white canvas, aligned at the Mac position, through the factory edge gate
        A = Image.new("RGB", im.size, (255, 255, 255)); B = Image.new("RGB", im.size, (255, 255, 255))
        A.paste(im.crop(mb), (mb[0], mb[1])); B.paste(iw.crop(wb), (mb[0], mb[1]))
        gate = edge_gate(A, B)
        gate_ok = gate["verdict"] in ("exact", "edge-aa<=32") and gate["maxInBand"] <= aa
        # label: ink beside the control (left for a switch, right for a checkbox): see label_box
        lm, lw = label_box(im, (mx0, mx1)), label_box(iw, (wx0, wx1))
        if lm is None or lw is None:   # the case declares a label: finding none fails loudly, never passes
            row["error"] = f"no label ink beside the control (mac={lm} windows={lw})"
        label_ok = lm is not None and lw is not None and abs((lm[1] + lm[3]) / 2 - (lw[1] + lw[3]) / 2) <= tol
        diff_px = None
        if lm and lw:
            x0, y0, x1, y1 = min(lm[0], lw[0]), min(lm[1], lw[1]), max(lm[2], lw[2]), max(lm[3], lw[3])
            d = ImageChops.difference(im.crop((x0, y0, x1, y1)), iw.crop((x0, y0, x1, y1))).convert("L").point(lambda v: 255 if v else 0)
            diff_px = sum(1 for p in d.getdata() if p) if not hasattr(d, "get_flattened_data") else sum(1 for p in d.get_flattened_data() if p)
        row.update(ok=same_size and gate_ok and label_ok and 'error' not in row, controlBBox=dict(mac=mb, windows=wb, dxWindowsMinusMac=dx, dyWindowsMinusMac=wb[1] - mb[1]), sameSizeAndY=same_size,
                   controlGate=gate, labelInkBBox=dict(mac=lm, windows=lw, centreToleranceOk=label_ok), labelDifferingPixelsReported=diff_px)
    ok = sum(1 for r in rows if r.get("ok"))
    rep = dict(case=case.name, run=out.name, pairs=len(rows), gatePassed=ok, gate="control size equal, y within %d px; control (translated by dx) exact with edge-aa<=%d; label vertical centre within %d px; label pixels reported only" % (ytol, aa, tol), rows=rows)
    (out / "control-report.json").write_text(json.dumps(rep, indent=1))
    dxs = sorted({r["controlBBox"]["dxWindowsMinusMac"] for r in rows if "controlBBox" in r})
    worst = max((r["controlGate"]["maxInBand"] for r in rows if "controlGate" in r), default=None)
    print(f"{case.name}: pairs={len(rows)} control-gate={ok}/{len(rows)} dx(label advance difference)={dxs} control max-in-band={worst} out-of-band={sorted({r['controlGate']['outOfBandDiff'] for r in rows if 'controlGate' in r})}")
    for r in rows:
        if not r.get("ok"): print("  run", r["run"], {k: v for k, v in r.items() if k in ("error", "sameSizeAndY", "labelInkBBox")})
    sys.exit(0 if rows and ok == len(rows) else 1)


if __name__ == "__main__":
    main()
