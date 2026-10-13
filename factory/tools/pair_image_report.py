#!/usr/bin/env python3
"""Semantic gate for an Image(systemName:) pair run (SF Symbols cannot ship on Windows; docs/sr1-decisions.md item 3).
usage: pair_image_report.py <case-dir> <runs/<ts> dir>   (after factory/tools/pair.py produced mac/ and windows/)
Case <case>/pair.json supplies {"imageFrame": {"name","tint":[r,g,b],"assets":<mapping json>,"symbol","scale","containerPx":[x0,y0,x1,y1],
"shapeOutsetPx"}}: the expected Image view frame is containerPx origin + the Mac-measured viewFramePx for (symbol, scale) in the mapping table;
the shape region is that frame outset by shapeOutsetPx (symbols overflow their frame). Pixels are in the 800x600 capture on white.
Per run it reports and GATES: frame (the host's logged image frame equals the expected rect; everything outside the frame is
pixel-identical), ink bbox (half-coverage bounding boxes equal on both sides), tint (the fully covered colour equals the expected
tint on both sides). The glyph SHAPE (all pixels inside the frame rect) is a named exclusion from the exact gate: its differing
pixel count and any-coverage ink bboxes are reported, never gated. Any frame/bbox/tint mismatch is a real defect (exit 1)."""
import json, re, sys
from collections import Counter
from pathlib import Path
from PIL import Image

BG = (255, 255, 255)


def alpha_of(px, tint):
    """Coverage estimate of a pixel over white for a solid tint (max over channels with contrast)."""
    best = 0.0
    for p, t, b in zip(px, tint, BG):
        if b != t:
            best = max(best, (b - p) / (b - t))
    return max(0.0, min(1.0, best))


def analyse(img, rect, tint):
    x0, y0, x1, y1 = rect
    px = img.load()
    any_box = half_box = None
    full = Counter()
    for y in range(img.height):
        for x in range(img.width):
            p = px[x, y]
            if p == BG:
                continue
            inside = x0 <= x < x1 and y0 <= y < y1
            a = alpha_of(p, tint)
            def grow(box):
                return (x, y, x + 1, y + 1) if box is None else (min(box[0], x), min(box[1], y), max(box[2], x + 1), max(box[3], y + 1))
            any_box = grow(any_box)
            if a >= 0.5:
                half_box = grow(half_box)
            if a >= 0.999:
                full[p] += 1
    rel = lambda b: None if b is None else [b[0] - x0, b[1] - y0, b[2] - x0, b[3] - y0]
    return dict(inkBBoxHalfCoverage=rel(half_box), inkBBoxAnyCoverage=rel(any_box),
                fullCoverageColour=(list(full.most_common(1)[0][0]) if full else None),
                fullCoveragePixels=sum(full.values()))


def main():
    case, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    cfg = json.loads((case / "pair.json").read_text())["imageFrame"]
    tint, name = tuple(cfg["tint"]), cfg["name"]
    layout = json.loads((case / cfg["assets"]).read_text())["symbols"][cfg["symbol"]]["layout"]
    cal = next(d for d in layout["deviceInk"] if abs(d["scale"] - cfg["scale"]) < 1e-6)
    ox, oy = cfg["containerPx"][0], cfg["containerPx"][1]
    fx, fy, exp_w, exp_h = cal["viewFramePx"]
    frame = [ox + fx, oy + fy, ox + fx + exp_w, oy + fy + exp_h]            # expected Image view frame in the capture
    o = cfg["shapeOutsetPx"]
    rect = (frame[0] - o, frame[1] - o, frame[2] + o, frame[3] + o)         # shape region (frame + overflow margin)
    table_ink = cal["inkBoxPx"]
    rows = []
    for mac in sorted((out / "mac").glob("run-*.png")):
        n = mac.stem.split("-")[1]
        win = out / "windows" / f"native-{n}.png"
        row = dict(run=int(n))
        if not win.is_file():
            row.update(error="missing windows capture", ok=False); rows.append(row); continue
        im, iw = Image.open(mac).convert("RGB"), Image.open(win).convert("RGB")
        if im.size != iw.size:
            row.update(error=f"size mac={im.size} win={iw.size}", ok=False); rows.append(row); continue
        # frame: host-logged frame and identity outside the frame
        log = out / "windows" / f"host-{n}.stdout.txt"
        m = re.search(r"FACTORY_SYSTEM_IMAGE_FRAME name=\S+ xPX=(-?\d+) yPX=(-?\d+) widthPX=(\d+) heightPX=(\d+)", log.read_text(errors="replace")) if log.is_file() else None
        logged = [int(m.group(1)), int(m.group(2)), int(m.group(1)) + int(m.group(3)), int(m.group(2)) + int(m.group(4))] if m else None
        a, b = im.copy(), iw.copy()
        shape_a, shape_b = im.crop(rect), iw.crop(rect)
        for img in (a, b):
            img.paste(BG, rect)
        outside = sum(1 for p, q in zip(a.get_flattened_data(), b.get_flattened_data()) if p != q)
        shape = sum(1 for p, q in zip(shape_a.get_flattened_data(), shape_b.get_flattened_data()) if p != q)
        ma, wa = analyse(im, frame, tint), analyse(iw, frame, tint)
        frame_ok = logged == frame and outside == 0
        bbox_ok = ma["inkBBoxHalfCoverage"] is not None and ma["inkBBoxHalfCoverage"] == wa["inkBBoxHalfCoverage"]
        table_ok = ma["inkBBoxHalfCoverage"] == table_ink      # the Mac capture agrees with the table calibration
        tint_ok = ma["fullCoverageColour"] == list(tint) == wa["fullCoverageColour"]
        row.update(ok=frame_ok and bbox_ok and tint_ok and table_ok,
                   frame=dict(match=frame_ok, expectedRectPx=frame, windowsLoggedRectPx=logged, differingPixelsOutsideShapeRegion=outside),
                   inkBBox=dict(match=bbox_ok, macCaptureEqualsTableCalibration=table_ok, tableInkBoxPx=table_ink, rule="half-coverage (>=50% of tint) bounding box, px relative to the frame origin", mac=ma["inkBBoxHalfCoverage"], windows=wa["inkBBoxHalfCoverage"],
                                anyCoverageMac=ma["inkBBoxAnyCoverage"], anyCoverageWindows=wa["inkBBoxAnyCoverage"]),
                   tint=dict(match=tint_ok, expectedRGB=list(tint), macFullCoverageRGB=ma["fullCoverageColour"], windowsFullCoverageRGB=wa["fullCoverageColour"],
                             macFullCoveragePixels=ma["fullCoveragePixels"], windowsFullCoveragePixels=wa["fullCoveragePixels"]),
                   glyphShape=dict(excludedFromExactGate=True, region=name, rect=list(rect), differingPixels=shape))
        rows.append(row)
    ok = sum(1 for r in rows if r.get("ok"))
    rep = dict(case=case.name, run=out.name, pairs=len(rows), gatePassed=ok,
               gate="frame (logged frame + exact outside frame), half-coverage ink bbox, tint colour; glyph shape reported only",
               shapeExclusion=dict(name=name, rect=list(rect), reason="SF Symbols cannot ship on Windows; provider maps to Segoe Fluent Icons (docs/sr1-decisions.md item 3)"),
               summary=dict(frameMatches=sum(1 for r in rows if r.get("frame", {}).get("match")),
                            inkBBoxMatches=sum(1 for r in rows if r.get("inkBBox", {}).get("match")),
                            tintMatches=sum(1 for r in rows if r.get("tint", {}).get("match")),
                            glyphShapeDiffPixels=sorted({r["glyphShape"]["differingPixels"] for r in rows if "glyphShape" in r})),
               rows=rows)
    (out / "image-report.json").write_text(json.dumps(rep, indent=1))
    s = rep["summary"]
    print(f"{name}: pairs={len(rows)} gate={ok}/{len(rows)} frame={s['frameMatches']} inkBBox={s['inkBBoxMatches']} tint={s['tintMatches']} shapeDiffPx={s['glyphShapeDiffPixels']} (shape excluded from exact gate)")
    if rows and rows[0].get("inkBBox"):
        r = rows[0]; print(f"  ink bbox mac={r['inkBBox']['mac']} windows={r['inkBBox']['windows']}  any-coverage mac={r['inkBBox']['anyCoverageMac']} windows={r['inkBBox']['anyCoverageWindows']}")
    sys.exit(0 if ok == len(rows) and rows else 1)


if __name__ == "__main__":
    main()
