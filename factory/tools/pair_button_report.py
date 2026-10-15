#!/usr/bin/env python3
"""Control gate for a paired Mac/Windows run of a push BUTTON with a text label. The button is as wide as its label plus 24 pt, so by decision 2
(Segoe UI vs SF: a different advance width) it is narrower on Windows. usage: pair_button_report.py <case-dir> <runs/<ts> dir>

<case>/pair.json supplies {"buttonGate": {"capPx": 28, "yTolerancePx": 0, "labelCentreTolerancePx": 3, "labelColourTolerance": 40, "edgeAA": 32}}. Per run it GATES:
 1. the button (the bounding box of non-white pixels) has the same height and the same y on both sides;
 2. the left cap (capPx columns aligned at the left edge) and the right cap (aligned at the right edge) pass the factory edge gate against the Mac
    (flat fill exact, edges within edgeAA/255): the button artwork is the same, only the straight middle is shorter or longer;
 3. the straight top and bottom bands between the caps are the flat fill colour of the Mac button;
 4. the label is centred in the button (vertically and horizontally within labelCentreTolerancePx) and its darkest ink is within labelColourTolerance
    of the Mac's darkest ink (the label colour: dark when enabled, grey when disabled).
It REPORTS, never gates: the button width on each side and their difference (the label advance difference), both label ink boxes, the label pixels that differ.
`.borderedProminent` and the default button (accent fill, white label) use the same gate: the fill is read from the Mac button, the label ink is the luminance farthest from it."""
import json, sys
from pathlib import Path
from PIL import Image, ImageChops

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pair import edge_gate
from pair_control_report import bbox_nonwhite


def label_ink(img, button, fill, cap, thresh=40):
    """bbox and extreme luminance (the label colour) of the pixels in the button's label region that differ from the fill by at least thresh."""
    x0, y0, x1, y1 = button
    rect = (x0 + cap - 4, y0 + 4, x1 - cap + 4, y1 - 4)
    crop = img.crop(rect)
    lum = crop.convert("L")
    f = int(0.299 * fill[0] + 0.587 * fill[1] + 0.114 * fill[2])     # the luminance the 'L' conversion gives
    mask = lum.point(lambda v: 255 if abs(v - f) >= thresh else 0)
    b = mask.getbbox()
    if b is None: return None, None
    # the label's ink colour: the luminance farthest from the fill's (darkest on a light fill, brightest on the prominent accent fill)
    return [b[0] + rect[0], b[1] + rect[1], b[2] + rect[0], b[3] + rect[1]], max(lum.getdata(), key=lambda v: abs(v - f))


def bbox_nonbg(img, rect, bg):
    """bbox of the pixels in rect that differ from the background colour bg (white: the light cases; the dark ground of round 5)"""
    m = ImageChops.difference(img.crop(rect), Image.new("RGB", (rect[2] - rect[0], rect[3] - rect[1]), tuple(bg)))
    m = ImageChops.lighter(ImageChops.lighter(*m.split()[:2]), m.split()[2]).point(lambda v: 255 if v >= 6 else 0)
    b = m.getbbox()
    return None if b is None else [b[0] + rect[0], b[1] + rect[1], b[2] + rect[0], b[3] + rect[1]]


def main():
    case, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    cfg = json.loads((case / "pair.json").read_text())["buttonGate"]
    cap, ytol = int(cfg.get("capPx", 28)), int(cfg.get("yTolerancePx", 0))
    ctol, coltol, aa = int(cfg.get("labelCentreTolerancePx", 3)), int(cfg.get("labelColourTolerance", 40)), int(cfg.get("edgeAA", 32))
    # ROUND 5 (decision F13): "background": [r,g,b] (the dark ground) and "regions": [{"name", "rect"}] (several buttons in one capture, one gate each, on a canvas of the capture's size)
    bg = tuple(cfg.get("background", (255, 255, 255)))
    regions = cfg.get("regions") or [None]
    rows = []
    for mac in sorted((out / "mac").glob("run-*.png")):
      for reg in regions:
        n = mac.stem.split("-")[1]
        win = out / "windows" / f"native-{n}.png"
        row = dict(run=int(n), ok=False, **({"region": reg["name"]} if reg else {}))
        rows.append(row)
        if not win.is_file(): row["error"] = "missing windows capture"; continue
        im, iw = Image.open(mac).convert("RGB"), Image.open(win).convert("RGB")
        if im.size != iw.size: row["error"] = f"size mac={im.size} win={iw.size}"; continue
        if reg:
            def cut(img):
                c = Image.new("RGB", img.size, bg); r = reg["rect"]; c.paste(img.crop(tuple(r)), (0, 0)); return c
            im, iw = cut(im), cut(iw)
        mb, wb = bbox_nonbg(im, (0, 0) + im.size, bg), bbox_nonbg(iw, (0, 0) + iw.size, bg)
        if mb is None or wb is None: row["error"] = f"no button ink mac={mb} windows={wb}"; continue
        mh, wh = mb[3] - mb[1], wb[3] - wb[1]
        same_h = mh == wh and abs(mb[1] - wb[1]) <= ytol
        if mb[2] - mb[0] < 2 * cap or wb[2] - wb[0] < 2 * cap: row["error"] = f"button narrower than two caps (mac={mb} windows={wb})"; continue
        fill = im.getpixel((mb[0] + cap // 2, (mb[1] + mb[3]) // 2))
        # caps through the edge gate, each aligned at its own end
        def canvas(img, box, side):
            c = Image.new("RGB", im.size, bg)
            if side == "L": c.paste(img.crop((box[0], mb[1], box[0] + cap, mb[3])), (0, 0))
            else: c.paste(img.crop((box[2] - cap, mb[1], box[2], mb[3])), (0, 0))
            return c
        gl = edge_gate(canvas(im, mb, "L"), canvas(iw, wb, "L")); gr = edge_gate(canvas(im, mb, "R"), canvas(iw, wb, "R"))
        caps_ok = all(g["verdict"] in ("exact", "edge-aa<=32") and g["maxInBand"] <= aa for g in (gl, gr))
        # straight bands between the caps: flat fill
        bands_ok, band_px = True, 0
        for y in list(range(wb[1] + 1, wb[1] + 9)) + list(range(wb[3] - 9, wb[3] - 1)):
            for x in range(wb[0] + cap, wb[2] - cap):
                band_px += 1
                if iw.getpixel((x, y)) != fill: bands_ok = False
        lm, dm = label_ink(im, mb, fill, cap); lw, dw = label_ink(iw, wb, fill, cap)
        if lm is None or lw is None: row["error"] = f"no label ink inside the button (mac={lm} windows={lw})"; continue
        cy_ok = abs((lw[1] + lw[3]) / 2 - (wb[1] + wb[3]) / 2) <= ctol and abs((lm[1] + lm[3]) / 2 - (mb[1] + mb[3]) / 2) <= ctol
        cx_ok = abs((lw[0] + lw[2]) / 2 - (wb[0] + wb[2]) / 2) <= ctol
        colour_ok = abs(dw - dm) <= coltol
        row.update(ok=same_h and caps_ok and bands_ok and cy_ok and cx_ok and colour_ok,
                   buttonBBox=dict(mac=mb, windows=wb, widthDifferencePx=(wb[2] - wb[0]) - (mb[2] - mb[0])), sameHeightAndY=same_h,
                   fill=list(fill), capGates=dict(left=gl, right=gr), flatBandsExact=bands_ok, flatBandPixels=band_px,
                   labelInk=dict(mac=lm, windows=lw, darkestMac=dm, darkestWindows=dw, centredVertically=cy_ok, centredHorizontally=cx_ok, colourOk=colour_ok))
    ok = sum(1 for r in rows if r.get("ok"))
    rep = dict(case=case.name, run=out.name, pairs=len(rows), gatePassed=ok,
               gate="button height equal and y within %d px; both %d px caps exact with edge-aa<=%d; straight bands flat fill; label centred within %d px, darkest ink within %d of the Mac; widths reported" % (ytol, cap, aa, ctol, coltol), rows=rows)
    (out / "button-report.json").write_text(json.dumps(rep, indent=1))
    ws = sorted({r["buttonBBox"]["widthDifferencePx"] for r in rows if "buttonBBox" in r})
    worst = max((max(r["capGates"]["left"]["maxInBand"], r["capGates"]["right"]["maxInBand"]) for r in rows if "capGates" in r), default=None)
    print(f"{case.name}: pairs={len(rows)} button-gate={ok}/{len(rows)} width difference (label advance, Segoe vs SF)={ws} cap max-in-band={worst}")
    for r in rows:
        if not r.get("ok"): print("  run", r["run"], {k: v for k, v in r.items() if k in ("error", "sameHeightAndY", "flatBandsExact", "labelInk")})
    sys.exit(0 if rows and ok == len(rows) else 1)


if __name__ == "__main__":
    main()
