#!/usr/bin/env python3
"""Reads a capture of a text-stack case (blocks-26-34/make_cases_textstack.py): per row of solid blocks, the width in points of every coloured block, left to right.
usage: rowsegments.py <png> [--scale 2.5]"""
import sys, itertools
from PIL import Image
PAL = {"R": (255, 59, 48), "B": (0, 122, 255), "G": (52, 199, 89), "O": (255, 141, 40), "P": (203, 48, 224), "g": (142, 142, 147)}
def cls(p):
    best = min(PAL, key=lambda k: sum((a - b) ** 2 for a, b in zip(p, PAL[k])))
    return best if sum((a - b) ** 2 for a, b in zip(p, PAL[best])) < 900 else "."
def rows(path, scale=2.5):
    im = Image.open(path).convert("RGB"); W, H = im.size
    out = []; prev = None; start = 0
    for y in range(H):
        row = [cls(im.getpixel((x, y))) for x in range(W)]
        segs = [(k, round(len(list(g)) / scale, 2)) for k, g in itertools.groupby(row)]
        # leading offset
        cur = tuple(segs)
        if cur != prev:
            if prev is not None and any(k != "." for k, _ in prev): out.append((round(start / scale, 1), round(y / scale, 1), [(k, n) for k, n in prev if k != "."]))
            prev = cur; start = y
    return out
if __name__ == "__main__":
    for y0, y1, segs in rows(sys.argv[1]):
        print(f"{y0:6.1f}-{y1:6.1f}  " + " ".join(f"{k}{n:g}" for k, n in segs))
