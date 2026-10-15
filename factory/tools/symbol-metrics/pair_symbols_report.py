#!/usr/bin/env python3
"""Semantic gate for a grid of font-sized (non-resizable) Image(systemName:) cells (round 5 block 29; docs/sr1-decisions.md items 3 and F5-F8).
usage: pair_symbols_report.py <case-dir> <runs/<ts> dir> [--mac-only]     (after factory/tools/pair.py produced mac/ and windows/)
<case>/pair.json "symbolGate": {"assets", "scale", "outsetPx", "tolerancePx", "tintTolerance", "cells": [{"name", "size", "cellPx": [x0,y0,x1,y1], "tint": [r,g,b]}]}.
Per cell the Image view frame expected in the 800x600 capture is the table's Mac-measured frame for (symbol, point size, scale class) centred in the cell and
snapped half up; the cell region is that frame outset by outsetPx (symbols overflow their frame). Per run it reports and GATES, per cell:
  frame  the Windows host's logged SYSTEM_IMAGE_FRAME of that cell is within frameTolerancePx (default 1: a half-pixel centring offset snaps either way) of the expected frame;
  ink    the half-coverage (>= 50 % of the tint over white) bounding box, relative to the frame origin, is within inkTolerancePx (default 1: the Mac capture moves a symbol's
         ink by up to 1 px with the sub-pixel phase of the cell origin) on Windows of the Mac capture's, and the Mac capture is within that of the table's measurement
         (otherwise a table defect, reported as such); the exact-equality counts are reported;
  tint   the colour of the covered pixels (coverage >= 70 %, estimated per pixel over white) is the cell's tint within tintTolerance on both sides;
  outside every pixel outside all cell regions is identical on both sides.
The glyph SHAPE (all pixels inside a cell region) is excluded from the exact gate: the differing pixel count is reported, never gated.
tolerancePx > 0 (interpolated sizes) compares frame and ink edges within that many pixels and says so: such a case is not evidence of generalisation."""
import json, re, sys
from pathlib import Path
from PIL import Image

BG = (255, 255, 255)


def snap(v):
    return int(v + 0.5 // 1) if False else int((v + 0.5) // 1)


def table_layout(sym, size, scale, weight="regular"):
    """(framePx [w,h], inkPx [l,t,r,b], measured) mirroring SystemImageTable.Layout.fontLayout at the class reference scale."""
    cls = "1x" if scale < 2 else "2x"
    rows = []
    for r in sym["layout"]["fontSizes"]:
        if r.get("weight", "regular") != weight: continue
        c = next(c for c in r["classes"] if c["scaleClass"] == cls)
        w, h = c["framePx"]; ink = c["inkPx"]
        rows.append((r["size"], [w / c["refScale"] * scale, h / c["refScale"] * scale], [ink[0] / w, ink[1] / h, ink[2] / w, ink[3] / h], c))
    rows.sort(key=lambda r: r[0])
    for s, fp, fr, c in rows:
        if abs(s - size) < 1e-9:
            return [round(fp[0]), round(fp[1])] if abs(c["refScale"] - scale) < 1e-6 else fp, c["inkPx"] if abs(c["refScale"] - scale) < 1e-6 else None, fr, True
    lo = max((r for r in rows if r[0] < size), key=lambda r: r[0], default=None); hi = min((r for r in rows if r[0] > size), key=lambda r: r[0], default=None)
    t = (size - lo[0]) / (hi[0] - lo[0])
    fp = [a + (b - a) * t for a, b in zip(lo[1], hi[1])]; fr = [a + (b - a) * t for a, b in zip(lo[2], hi[2])]
    return fp, None, fr, False


def coverage(p, tint):
    ch = max(range(3), key=lambda i: BG[i] - tint[i])
    d = BG[ch] - tint[ch]
    return max(0.0, min(1.2, (BG[ch] - p[ch]) / d)) if d > 0 else 0.0


def analyse(img, rect, tint):
    x0, y0, x1, y1 = rect
    px = img.load()
    box = None; samples = []
    for y in range(max(0, y0), min(img.height, y1)):
        for x in range(max(0, x0), min(img.width, x1)):
            p = px[x, y]
            if p == BG: continue
            a = coverage(p, tint)
            if a >= 0.5:
                box = (x, y, x + 1, y + 1) if box is None else (min(box[0], x), min(box[1], y), max(box[2], x + 1), max(box[3], y + 1))
            if 0.7 <= a <= 1.05:
                samples.append([(p[i] - (1 - a) * 255) / a for i in range(3)])
    est = None
    if samples:
        est = [sorted(s[i] for s in samples)[len(samples) // 2] for i in range(3)]
    return (None if box is None else [box[0], box[1], box[2], box[3]]), est, len(samples)


rect_origin = (0, 0)


def main():
    global rect_origin
    case, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    mac_only = "--mac-only" in sys.argv
    cfg = json.loads((case / "pair.json").read_text())["symbolGate"]
    table = json.loads((Path(__file__).resolve().parents[3] / cfg["assets"]).read_text())["symbols"]
    scale, outset, tol, ttol = cfg["scale"], cfg["outsetPx"], cfg.get("tolerancePx", 0), cfg.get("tintTolerance", 3)
    itol = max(tol, cfg.get("inkTolerancePx", 1)); ftol = cfg.get("frameTolerancePx", 1)
    plan = []
    for c in cfg["cells"]:
        fp, ink, fr, measured = table_layout(table[c["name"]], c["size"], scale, c.get("weight", "regular"))
        cx0, cy0, cx1, cy1 = c["cellPx"]
        fw, fh = fp
        l = snap(cx0 + ((cx1 - cx0) - fw) / 2); t = snap(cy0 + ((cy1 - cy0) - fh) / 2)
        r = snap(cx0 + ((cx1 - cx0) + fw) / 2); b = snap(cy0 + ((cy1 - cy0) + fh) / 2)
        vw, vh = r - l, b - t
        model_ink = ink if ink is not None and [vw, vh] == [round(fw), round(fh)] else [int((fr[0] * vw + 0.5) // 1), int((fr[1] * vh + 0.5) // 1), int((fr[2] * vw + 0.5) // 1), int((fr[3] * vh + 0.5) // 1)]
        plan.append(dict(cell=c, frame=[l, t, r, b], modelInk=model_ink, measuredSize=measured, region=[l - outset, t - outset, r + outset, b + outset]))
    rows = []
    for mac in sorted((out / "mac").glob("run-[0-9][0-9].png")):
        n = mac.stem.split("-")[1]
        win = out / "windows" / f"native-{n}.png"
        row = dict(run=int(n), cells=[])
        im = Image.open(mac).convert("RGB")
        iw = Image.open(win).convert("RGB") if win.is_file() and not mac_only else None
        if not mac_only and (iw is None or im.size != iw.size):
            row.update(ok=False, error="missing or differently sized windows capture"); rows.append(row); continue
        logtext = ""
        log = out / "windows" / f"host-{n}.stdout.txt"
        if log.is_file(): logtext = log.read_text(errors="replace")
        logged = [(m.group(1), int(m.group(2)), int(m.group(3)), int(m.group(4)), int(m.group(5))) for m in
                  re.finditer(r"(?:FACTORY_)?SYSTEM_IMAGE_FRAME name=(\S+) xPX=(-?\d+) yPX=(-?\d+) widthPX=(\d+) heightPX=(\d+)", logtext)]
        masked_a, masked_b = im.copy(), (iw.copy() if iw else None)
        shape_px = 0
        all_ok = True
        for p in plan:
            c, fr = p["cell"], p["frame"]
            rect_origin = (fr[0], fr[1])
            mi, mt, mn = analyse(im, p["region"], c["tint"])
            wi, wt, wn = analyse(iw, p["region"], c["tint"]) if iw else (None, None, 0)
            cx0, cy0, cx1, cy1 = c["cellPx"]
            hit = [e for e in logged if e[0] == c["name"] and cx0 - 30 <= e[1] + e[3] / 2 <= cx1 + 30 and cy0 - 30 <= e[2] + e[4] / 2 <= cy1 + 30]
            lg = hit[-1] if hit else None
            logged_frame = [lg[1], lg[2], lg[1] + lg[3], lg[2] + lg[4]] if lg else None
            near = lambda a, b, t=tol: a is not None and b is not None and all(abs(x - y) <= t for x, y in zip(a, b))
            frame_ok = True if mac_only else near(logged_frame, fr, max(tol, ftol))
            rel = lambda b, o: None if b is None else [b[0] - o[0], b[1] - o[1], b[2] - o[0], b[3] - o[1]]
            mi_rel = rel(mi, fr)
            ink_table_ok = near(mi_rel, p["modelInk"], itol)     # reported (is the table's measurement what the Mac capture drew?)
            ink_ok = True if mac_only else near(wi, mi, itol)     # gated: the ink box in capture pixels, Windows against the Mac capture
            tint_ok = (mt is not None and all(abs(a - b) <= ttol for a, b in zip(mt, c["tint"]))) and (True if mac_only else (wt is not None and all(abs(a - b) <= ttol for a, b in zip(wt, c["tint"]))))
            cell_ok = frame_ok and ink_ok and tint_ok and (ink_table_ok or not cfg.get("gateTable", False))
            all_ok &= cell_ok
            if iw:
                a, b = im.crop(p["region"]), iw.crop(p["region"])
                shape_px += sum(1 for u, v in zip(a.get_flattened_data(), b.get_flattened_data()) if u != v)
                masked_a.paste(BG, p["region"]); masked_b.paste(BG, p["region"])
            row["cells"].append(dict(name=c["name"], size=c["size"], ok=cell_ok, expectedFrame=fr, loggedFrame=logged_frame, frameOk=frame_ok,
                                     modelInk=p["modelInk"], macInk=mi_rel, windowsInk=rel(wi, fr), macInkAbs=mi, windowsInkAbs=wi, macInkExact=(mi_rel == p["modelInk"]), inkExactMacWindows=(None if iw is None else wi == mi), frameExact=(None if mac_only else logged_frame == fr), inkOk=ink_ok, macMatchesTable=ink_table_ok, measuredSize=p["measuredSize"],
                                     expectedTint=c["tint"], macTint=mt and [round(v) for v in mt], windowsTint=wt and [round(v) for v in wt], tintOk=tint_ok))
        outside = 0 if not iw else sum(1 for u, v in zip(masked_a.get_flattened_data(), masked_b.get_flattened_data()) if u != v)
        row.update(ok=all_ok and outside == 0, differingPixelsOutsideCells=outside, glyphShapeDiffPixels=shape_px)
        rows.append(row)
    passed = sum(1 for r in rows if r.get("ok"))
    bad = [(r["run"], c["name"], c["size"], {k: c[k] for k in ("frameOk", "inkOk", "macMatchesTable", "tintOk")}, c["expectedFrame"], c["loggedFrame"], c["modelInk"], c["macInk"], c["windowsInk"])
           for r in rows for c in r.get("cells", []) if not c["ok"]]
    rep = dict(case=case.name, run=out.name, macOnly=mac_only, pairs=len(rows), gatePassed=passed, tolerancePx=tol, note=cfg.get("note", ""),
               gate="per cell: logged frame, half-coverage ink box (Mac == Windows == table), tint; pixels outside the cell regions identical; glyph shape reported only",
               cellsTotal=len(plan), inkTolerancePx=itol, frameTolerancePx=max(tol, ftol), frameExactCells=sum(1 for r in rows for c in r.get("cells", []) if c.get("frameExact")), macInkEqualsTableCells=sum(1 for r in rows for c in r.get("cells", []) if c["macInkExact"]), windowsInkEqualsMacCells=sum(1 for r in rows for c in r.get("cells", []) if c["inkExactMacWindows"]), cellsFailing=len(bad), failing=bad[:60], rows=rows)
    (out / "symbols-report.json").write_text(json.dumps(rep, indent=1))
    print(f"{case.name}: pairs={len(rows)} gate={passed}/{len(rows)} cells={len(plan)} failing={len(bad)}" + (" [mac only]" if mac_only else "") + (f" [tolerance {tol}px: not generalisation evidence]" if tol else ""))
    for b in bad[:12]:
        print("  FAIL", b)
    sys.exit(0 if rows and passed == len(rows) else 1)


if __name__ == "__main__":
    main()
