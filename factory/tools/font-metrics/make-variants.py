#!/usr/bin/env python3
"""Writes throwaway test fonts for font-metrics' Font.custom lookup-order cases into <outdir> (a scratch dir; nothing is stored in the repo).

Each variant is Tinos Regular (factory/resources/fonts) with its name table rewritten and its ascent raised by a distinct step, so the line height of a Text set in
the font tells which file a name resolved to. Output is deterministic. Needs python3 with fontTools (already on the workspace Mac)."""
import json, sys
from pathlib import Path
from fontTools.ttLib import TTFont

SRC = Path(__file__).resolve().parents[2] / "resources/fonts/Tinos-Regular.ttf"
STEP = 300  # design units of extra ascent per id (Tinos upm 2048): ~2.9 pt per id at 20 pt

# label: (id, family, ps, full).  A name N is "collided" when it is the PostScript name of one file, the full name of another and/or the family of a third.
V = {}
def add(label, i, fam, ps, full): V[label] = (i, fam, ps, full)
add("single-family",   1, "ZqSingleFam", "ZqS1-Regular", "ZqS1 Regular")
add("single-ps",       2, "ZqS2 Family", "ZqSinglePS", "ZqS2 Regular")
add("single-full",     3, "ZqS3 Family", "ZqS3-Regular", "Zq Single Full")
for n, parts in (("1", "pfy"), ("2", "pf"), ("3", "py"), ("4", "fy")):
    name = f"ZqCollide{n}"
    for k, ch in enumerate(parts):
        i = 10 * int(n) + k + 1
        if ch == "p": add(f"c{n}-ps", i, f"ZqC{n}p Family", name, f"ZqC{n}p Regular")
        if ch == "f": add(f"c{n}-full", i, f"ZqC{n}f Family", f"ZqC{n}f-Regular", name)
        if ch == "y": add(f"c{n}-family", i, name, f"ZqC{n}y-Regular", f"ZqC{n}y Regular")

def main(out):
    out = Path(out); out.mkdir(parents=True, exist_ok=True)
    meta = {}
    for label, (i, fam, ps, full) in sorted(V.items()):
        f = TTFont(str(SRC))
        nm = f["name"]
        nm.names = [n for n in nm.names if n.nameID not in (1, 2, 3, 4, 6, 16, 17, 21, 22, 25)]
        for pid, eid, lid in ((3, 1, 0x409), (1, 0, 0)):
            for nid, s in ((1, fam), (2, "Regular"), (3, f"zq-{label}"), (4, full), (6, ps)):
                nm.setName(s, nid, pid, eid, lid)
        f["hhea"].ascent += STEP * i
        f["OS/2"].sTypoAscender += STEP * i
        f["OS/2"].usWinAscent += STEP * i
        p = out / f"{label}.ttf"
        f.save(str(p))
        meta[label] = {"id": i, "family": fam, "postScript": ps, "fullName": full, "extraAscentUnits": STEP * i}
    (out / "variants.json").write_text(json.dumps(meta, sort_keys=True, indent=1))

main(sys.argv[1])
