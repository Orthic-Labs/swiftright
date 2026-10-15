#!/usr/bin/env python3
"""Adds the Pulse hub symbols (segoe-map.json glyph mapping + symbol-sizes.sh Mac measurements) to
packages/SwiftRightHost/Assets/SystemImageAssets.json, then run packages/SwiftRightHost/scripts/embed-assets.py.
Existing entries keep every field they have; star.fill only gains layout.fontSizes.

usage: merge-symbol-table.py --sizes SIZES.json   (SIZES: symbol-sizes.sh output at scales 1 and 2.5)
Class model: the 1x class (screen scale < 2) is measured at scale 1, the 2x class (scale >= 2) at scale 2.5."""
import argparse, json
from pathlib import Path
here = Path(__file__).resolve().parent
table_path = here.parent.parent.parent / "packages/SwiftRightHost/Assets/SystemImageAssets.json"
ap = argparse.ArgumentParser(); ap.add_argument("--sizes", required=True, nargs="+", help="one or more symbol-sizes outputs (a file carries one weight)"); a = ap.parse_args()
files = [json.load(open(f)) for f in a.sizes]; meas = files[0]; smap = json.load(open(here / "segoe-map.json"))
table = json.load(open(table_path))
REF = {"1x": 1.0, "2x": 2.5}

def font_sizes(name):
    rows = []
    for f in files:
        per = f["symbols"].get(name)
        if per is None: continue
        weight = f.get("weight", "regular")
        for size in sorted({float(k.split("@")[0]) for k in per}):
            label = str(int(size)) if size == int(size) else str(size)
            classes = []
            for cls, ref in REF.items():
                m = per[f"{label}@{ref}"]
                classes.append({"scaleClass": cls, "refScale": ref, "framePx": m["viewFramePx"][2:4], "inkPx": m["inkBoxPx"]})
            rows.append({"size": size, "weight": weight, "classes": classes})
    rows.sort(key=lambda r: (r["weight"] != "regular", r["weight"], r["size"]))
    return rows

names = []
for f in files:
    names += [n for n in f["symbols"] if n not in names]
for name in names:
    fs = font_sizes(name)
    base = next(e for e in fs if e["size"] == 13 and e["weight"] == "regular")["classes"][0]   # 1x class, body size 13
    w, h = base["framePx"]; ink = base["inkPx"]
    if name in table["symbols"]:
        table["symbols"][name]["layout"]["fontSizes"] = fs
        table["symbols"][name]["layout"]["fontSizesSource"] = meas["method"] + "; weights regular, semibold, bold; macOS " + meas["macOS"]
        continue
    g = smap["symbols"][name]
    table["symbols"][name] = {
        "provider": "Segoe Fluent Icons", "providerVersion": "SegoeFluentIcons", "glyph": g["glyph"],
        "foregroundSemantic": "label", "width": w, "height": h, "status": "provider-live-declared",
        "rasterization": {"kind": "gdi-glyph-outline", "textureType": "GGO_GRAY8_BITMAP", "fontEmSize": None, "source": "live-gdi-getglyphoutlinew"},
        "mapping": {"segoeName": g["segoeName"], "fit": g["fit"], "note": g["note"], "source": smap["source"]},
        "layout": {"source": "factory/tools/symbol-metrics/symbol-sizes.sh --capture-path (NSHostingView in an offscreen pinned-scale window drawn into a bitmap as the capture host does; non-resizable Image(systemName:).font(.system(size:)); half-coverage ink)",
                   "macOS": meas["macOS"], "referencePointSize": 13, "aspect": w / h,
                   "inkRect": [ink[0] / w, ink[1] / h, ink[2] / w, ink[3] / h], "intrinsicSize": [w, h],
                   "sourceOversample": 8, "fontSizes": fs},
    }
assert len(table["symbols"]) <= table["providerPolicy"]["maxSymbols"]
import re
text = json.dumps(table, indent=2)
text = re.sub(r"\[\s*(-?[\d.eE+-]+(?:,\s*-?[\d.eE+-]+)*)\s*\]", lambda m: "[" + re.sub(r",\s+", ", ", m.group(1)) + "]", text)   # numeric arrays on one line
text = re.sub(r'\{\s*("scaleClass": "[^"]*",\s*"refScale": [\d.]+,\s*"framePx": \[[^\]]*\],\s*"inkPx": \[[^\]]*\])\s*\}', lambda m: "{" + re.sub(r",\s+", ", ", m.group(1)) + "}", text)
table_path.write_text(text + "\n")
print("symbols", len(table["symbols"]))
