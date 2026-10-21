#!/usr/bin/env python3
"""Text gate for a paired Mac/Windows run of a Text case (same font bytes both sides; CoreText vs DirectWrite rasterizer).
usage: pair_text_report.py <case-dir> <runs/<ts> dir>   (after factory/tools/pair.py produced mac/ and windows/)
<case>/pair.json supplies {"textGate": {"rect":[x0,y0,x1,y1], "edgeTolerancePx":1, "ink":"half"}}: rect = the glyph region (800x600 capture px).
Per run it GATES: (1) positions/frames: every pixel OUTSIDE rect is identical on both sides; (2) glyph region: the half-coverage ink
bounding box (pixels at least 50% dark, luminance <= 127) agrees within edgeTolerancePx on each of its 4 edges. It REPORTS, never gates:
the any-coverage ink bbox on each side, and the number of pixels inside rect that differ (the anti-aliasing difference: DirectWrite
grayscale vs CoreText). Exit 1 when any run fails the gate."""
import json, sys
from pathlib import Path
from PIL import Image, ImageChops


def bbox_of(img, rect, max_lum):
    x0, y0, x1, y1 = rect
    lum = img.convert("L").crop(rect)
    m = lum.point(lambda v: 255 if v <= max_lum else 0)
    b = m.getbbox()
    return None if b is None else [b[0] + x0, b[1] + y0, b[2] + x0, b[3] + y0]


def npx(d):
    return sum(1 for p in d.get_flattened_data() if p != (0, 0, 0)) if hasattr(d, "get_flattened_data") else sum(1 for p in d.getdata() if p != (0, 0, 0))


def main():
    case, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    cfg = json.loads((case / "pair.json").read_text())["textGate"]
    # "rects" (several glyph regions, each with its own ink bbox gate; e.g. one per line, so a narrower line inside a wider one is still gated) or one "rect"
    rects = [tuple(r) for r in cfg["rects"]] if "rects" in cfg else [tuple(cfg["rect"])]
    rect, tol = rects[0], int(cfg.get("edgeTolerancePx", 1))
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
        diff = ImageChops.difference(im, iw)
        inside = diff.crop(rect)
        outside = diff.copy()
        for r in rects: outside.paste((0, 0, 0), r)
        outside_px = npx(outside)
        ma, wa = bbox_of(im, rect, 127), bbox_of(iw, rect, 127)
        deltas = None if ma is None or wa is None else [w - m for m, w in zip(ma, wa)]
        ink_ok = deltas is not None and max(abs(d) for d in deltas) <= tol
        regions = []
        for r in rects:
            m2, w2 = bbox_of(im, r, 127), bbox_of(iw, r, 127)
            d2 = None if m2 is None or w2 is None else [w - m for m, w in zip(m2, w2)]
            regions.append(dict(rect=list(r), mac=m2, windows=w2, deltaWindowsMinusMac=d2, match=d2 is not None and max(abs(d) for d in d2) <= tol))
        if len(rects) > 1:
            ink_ok = all(g["match"] for g in regions)
            row.update(regions=regions)
        row.update(ok=outside_px == 0 and ink_ok,
                   outsideGlyphRegionDifferingPixels=outside_px,
                   inkBBoxHalfCoverage=dict(mac=ma, windows=wa, deltaWindowsMinusMac=deltas, tolerancePx=tol, match=ink_ok),
                   inkBBoxAnyCoverageReported=dict(mac=bbox_of(im, rect, 254), windows=bbox_of(iw, rect, 254)),
                   aaDifferingPixelsInGlyphRegion=npx(inside), aaMaxChannelDiff=max(e[1] for e in inside.getextrema()))
        rows.append(row)
    ok = sum(1 for r in rows if r.get("ok"))
    rep = dict(case=case.name, run=out.name, pairs=len(rows), gatePassed=ok, glyphRegion=list(rect),
               gate="exact outside glyph region; half-coverage ink bbox within %d px per edge; AA diff pixels reported only" % tol, rows=rows)
    (out / "text-report.json").write_text(json.dumps(rep, indent=1))
    aa = sorted({r.get("aaDifferingPixelsInGlyphRegion") for r in rows})
    print(f"{case.name}: pairs={len(rows)} gate={ok}/{len(rows)} outside-diff={sorted({r.get('outsideGlyphRegionDifferingPixels') for r in rows})} aaDiffPx min={aa[0] if aa else None} max={aa[-1] if aa else None}")
    for g in (rows[0].get("regions") or []) if rows else []:
        print(f"  region {g['rect']}: mac={g['mac']} windows={g['windows']} delta={g['deltaWindowsMinusMac']}")
    if rows and rows[0].get("inkBBoxHalfCoverage") and not rows[0].get("regions"):
        b = rows[0]["inkBBoxHalfCoverage"]
        print(f"  half-coverage ink bbox mac={b['mac']} windows={b['windows']} delta={b['deltaWindowsMinusMac']}")
    sys.exit(0 if rows and ok == len(rows) else 1)


if __name__ == "__main__":
    main()
