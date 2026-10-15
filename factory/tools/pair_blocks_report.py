#!/usr/bin/env python3
"""Block gate for stack-distribution cases (layout rules lane, decisions L1-L8): rows of solid colour blocks, each block the frame a stack gave one (hidden) Text.
usage: pair_blocks_report.py <case-dir> <runs/<ts> dir>   (after factory/tools/pair.py produced mac/run-NN.png and windows/native-NN.png)
Text advances differ in subpixels between the sides (the Mac reports fractional widths, the Windows host snaps to device pixels), so equal pixels are not the gate:
per run and per row band (consecutive scanlines holding palette pixels, read at the band's middle scanline) it gates that
  - both sides have the same rows, and in each row the same sequence of block colours;
  - every block's left edge and width are within `tolerancePx` (default 1.5 px = 0.6 pt at 2.5) of the Mac's;
  - a block that is narrower on the Mac than its text's natural width (blockGate "naturals": per row, per block in order, pt; null = a marker; -1 = always tolerant) is a cut Text and
    gets "cutTolerancePt" (reason in "cutReason": the Windows host cuts at the longest prefix + ellipsis that fits, the Mac at its own break, so the width differs by up to a
    character); the x of the blocks after it may move by the same allowance;
  - no ink: no pixel of the band that is neither white, nor a palette colour, nor within 2 px of a block edge (the glyphs are hidden under opaque overlays and a Text is clipped to
    its frame, so overflowing glyph ink is a failure).
<case>/pair.json "blockGate": {"tolerancePx": 1.5, "cutTolerancePt": 9, "cutReason": "...", "naturals": [[90.4, 67.6], ...]}. Exit 1 on any failure."""
import json, sys
from pathlib import Path
from PIL import Image

PAL = {"R": (255, 59, 48), "B": (0, 122, 255), "G": (52, 199, 89), "O": (255, 141, 40), "P": (203, 48, 224), "g": (142, 142, 147)}
SCALE = 2.5


def classify(p):
    best = min(PAL, key=lambda k: sum((a - b) ** 2 for a, b in zip(p, PAL[k])))
    if sum((a - b) ** 2 for a, b in zip(p, PAL[best])) < 900: return best
    if min(p) > 245: return "."
    return "k" if sum(p) < 330 else "x"   # k: dark (glyph ink), x: anything else (anti-aliased block edges)


def bands(img):
    w, h = img.size; px = img.load(); out = []; cur = None
    lines = []
    for y in range(h):
        row = [classify(px[x, y]) for x in range(w)]
        lines.append(row)
        has = any(c in PAL for c in row)
        if has and cur is None: cur = [y, y]
        elif has: cur[1] = y
        elif cur is not None: out.append(tuple(cur)); cur = None
    if cur is not None: out.append(tuple(cur))
    return lines, out


def blocks(row):
    res = []; x = 0; n = len(row)
    while x < n:
        c = row[x]
        if c in PAL:
            x0 = x
            while x < n and row[x] == c: x += 1
            if x - x0 >= 8: res.append((c, x0, x - x0))   # a block under 8 px (3.2 pt) is a sliver: a frame the stack gave almost nothing, drawn or not by either side
        else: x += 1
    return res


def analyse(path):
    lines, bs = bands(Image.open(path).convert("RGB"))
    rows = []
    for (y0, y1) in bs:
        mid = lines[(y0 + y1) // 2]
        bl = blocks(mid)
        ink = 0
        edges = [(x0 - 2, x0 + w + 2) for _, x0, w in bl]
        for y in range(y0, y1 + 1):
            for x, c in enumerate(lines[y]):
                if c == "k" and not any(a <= x < b for a, b in edges): ink += 1
        rows.append(dict(y=(y0, y1), blocks=bl, ink=ink))
    return rows


def main():
    case, out = Path(sys.argv[1]), Path(sys.argv[2])
    cfg = json.loads((case / "pair.json").read_text())["blockGate"]
    tol_px = float(cfg.get("tolerancePx", 1.5)); cut_px = float(cfg.get("cutTolerancePt", 9)) * SCALE; naturals = cfg.get("naturals", [])
    ok_all = True; runs = sorted((out / "mac").glob("run-*.png"))
    for mac in runs:
        idx = mac.stem.split("-")[1]; win = out / "windows" / f"native-{idx}.png"
        if not win.is_file():
            print(f"  block run {idx} FAIL: no windows capture"); ok_all = False; continue
        m, w = analyse(mac), analyse(win)
        problems = []
        if len(m) != len(w): problems.append(f"rows mac={len(m)} windows={len(w)}")
        for i, (a, b) in enumerate(zip(m, w)):
            if [c for c, _, _ in a["blocks"]] != [c for c, _, _ in b["blocks"]]:
                problems.append(f"row {i} blocks mac={''.join(c for c,_,_ in a['blocks'])} windows={''.join(c for c,_,_ in b['blocks'])}"); continue
            nat = naturals[i] if i < len(naturals) else []
            allow_x = 0.0
            for k, ((c, ax, aw), (_, bx, bw)) in enumerate(zip(a["blocks"], b["blocks"])):
                n = nat[k] if k < len(nat) else None
                cut = n is not None and (n < 0 or aw / SCALE < n - 1.5)
                tol_w = cut_px if cut else tol_px
                if abs(aw - bw) > tol_w or abs(ax - bx) > tol_px + allow_x:
                    problems.append(f"row {i} block {c}: mac x={ax / SCALE:g} w={aw / SCALE:g} pt, windows x={bx / SCALE:g} w={bw / SCALE:g} pt (width tol {tol_w / SCALE:g} pt{', cut' if cut else ''}, x tol {(tol_px + allow_x) / SCALE:g} pt)")
                if cut: allow_x += cut_px
            if b["ink"]: problems.append(f"row {i}: {b['ink']} windows ink pixels outside the blocks")
            if a["ink"]: problems.append(f"row {i}: {a['ink']} mac ink pixels outside the blocks (reported)")
        ok = not [p for p in problems if "(reported)" not in p]
        print(f"  block run {idx} {'ok' if ok else 'FAIL'} rows={len(m)}/{len(w)}" + ("" if not problems else " " + "; ".join(problems[:6])))
        ok_all = ok_all and ok
    print(f"blockGate runs={len(runs)} {'pass' if ok_all else 'FAIL'}")
    sys.exit(0 if ok_all else 1)


main()
