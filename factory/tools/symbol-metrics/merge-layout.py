#!/usr/bin/env python3
"""Merge symbol-metrics output into a FactorySystemImageAssets.json mapping table (symbols[name].layout).
usage: symbol-metrics.sh name... | merge-layout.py <FactorySystemImageAssets.json>"""
import json, sys
path = sys.argv[1]
m = json.load(sys.stdin)
table = json.load(open(path))
for name, v in m["symbols"].items():
    if "error" in v or name not in table["symbols"]:
        sys.exit(f"{name}: {v.get('error', 'not in mapping table')}")
    verr = v["verification"]["worstErrorPxAtLargeFrames"]
    if verr > 1.0:
        sys.exit(f"{name}: SwiftUI layout model error {verr:.2f}px at large frames; refusing to record")
    table["symbols"][name]["layout"] = {
        "source": "factory/tools/symbol-metrics (SwiftUI ImageRenderer, resizable+scaledToFit, alpha>=128 ink)",
        "macOS": m["macOS"], "referencePointSize": m["referencePointSize"],
        "aspect": v["aspect"], "inkRect": v["inkRect"], "intrinsicSize": v["intrinsicSize"], "fitIntrinsicSize": v["fitIntrinsicSize"],
        "nsImage": v["nsImage"], "deviceInk": v["deviceInk"], "modelWorstErrorPx": round(verr, 3), "sourceOversample": 8,
    }
json.dump(table, open(path, "w"), indent=2); open(path, "a").write("\n")
