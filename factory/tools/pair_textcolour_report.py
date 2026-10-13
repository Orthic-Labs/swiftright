#!/usr/bin/env python3
"""Text-colour gate for a paired Mac/Windows run: text pixels differ by decision 2 (Segoe UI vs SF), but the COLOUR must match.
usage: pair_textcolour_report.py <case-dir> <runs/<ts> dir>   (after factory/tools/pair.py produced mac/ and windows/)
<case>/pair.json supplies {"textColourGate": {"tolerance": 24, "regions": [{"name": ..., "rect": [x0,y0,x1,y1]}]}} (800x600 capture px, one text line each).
Per run and region it GATES that the strongest ink pixel (the pixel farthest from white, a full-coverage glyph pixel) is within `tolerance` per channel of the
Mac's, and that both sides have ink. Optional "background": [r,g,b] measures ink as the distance from that colour instead of from white (dark cases). Positions outside the regions are gated by the case's excludeRects pixel gate. It REPORTS the strongest pixel on each side."""
import json, sys
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
            ok &= good
            row["regions"].append(dict(name=r["name"], mac=m, windows=w, ok=good))
        row["ok"] = ok
    passed = sum(1 for r in rows if r["ok"])
    (out / "text-colour-report.json").write_text(json.dumps(dict(case=case.name, run=out.name, pairs=len(rows), gatePassed=passed, tolerance=tol, rows=rows), indent=1))
    first = rows[0]["regions"] if rows else []
    print(f"{case.name}: pairs={len(rows)} text-colour-gate={passed}/{len(rows)} (tolerance {tol}/255 per channel) first run: " + "; ".join(f"{r['name']} mac={r['mac']} win={r['windows']}" for r in first))
    for r in rows:
        if not r["ok"]: print("  run", r["run"], r.get("error") or r["regions"])
    sys.exit(0 if rows and passed == len(rows) else 1)


if __name__ == "__main__":
    main()
