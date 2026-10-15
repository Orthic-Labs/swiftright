#!/usr/bin/env python3
"""E14c reader (decision G10): per row of a blocks-f0 title case, the half-coverage ink box (luminance <= 127, the text gate's rule) on the Mac and on Windows, per run.
usage: ink_rows.py <case-dir> <runs/<ts> dir> [--json out.json]
Row geometry comes from the case's Witness.swift: rows top-leading in a 260 x 200 pt frame, origin (30, 20) pt, scale 2.5, row height = the `height:` of each Text frame."""
import json, re, sys
from pathlib import Path
from PIL import Image

SCALE = 2.5
OX, OY = 30, 20
X0, X1 = round(OX * SCALE), round((OX + 240) * SCALE)


def rows_of(case):
    src = (case / "mac-source/Sources/MacHost/Witness.swift").read_text()
    out, y = [], OY
    for m in re.finditer(r'size: (\d+)\)\)\.frame\(width: 240, height: (\d+)', src):
        s, h = int(m.group(1)), int(m.group(2))
        out.append(dict(size=s, height=h, top_pt=y, y0=round(y * SCALE), y1=round((y + h) * SCALE)))
        y += h
    return out


def ink(img, x0, y0, x1, y1):
    lum = img.convert("L").crop((x0, y0, x1, y1))
    b = lum.point(lambda v: 255 if v <= 127 else 0).getbbox()
    return None if b is None else [b[0] + x0, b[1] + y0, b[2] + x0, b[3] + y0]


def main():
    case, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    rows = rows_of(case)
    res = []
    for mac in sorted((out / "mac").glob("run-*.png")):
        n = mac.stem.split("-")[1]
        win = out / "windows" / f"native-{n}.png"
        if not win.is_file():
            continue
        im, iw = Image.open(mac).convert("RGB"), Image.open(win).convert("RGB")
        for i, r in enumerate(rows):
            m, w = ink(im, X0, r["y0"], X1, r["y1"]), ink(iw, X0, r["y0"], X1, r["y1"])
            res.append(dict(run=int(n), row=i, size=r["size"], height=r["height"], top_pt=r["top_pt"], mac=m, win=w,
                            delta=None if (m is None or w is None) else [w[k] - m[k] for k in range(4)]))
    # summary: per row the distinct (mac, win) boxes over the runs
    print(f"case {case.name} runs={len({r['run'] for r in res})}")
    for i, r in enumerate(rows):
        rr = [x for x in res if x["row"] == i]
        macs = {json.dumps(x["mac"]) for x in rr}; wins = {json.dumps(x["win"]) for x in rr}; ds = {json.dumps(x["delta"]) for x in rr}
        print(f"  row {i} size {r['size']} frame {r['height']} top {r['top_pt']}pt: mac {sorted(macs)} win {sorted(wins)} delta(win-mac: l,t,r,b) {sorted(ds)}")
    if "--json" in sys.argv:
        Path(sys.argv[sys.argv.index("--json") + 1]).write_text(json.dumps(dict(case=case.name, rows=rows, runs=res), indent=1))


main()
