#!/usr/bin/env python3
"""Fit per-scale-class SF Symbol layout models from symbol-metrics measurements and record them in a
FactorySystemImageAssets.json mapping table (symbols[name].layout.scaleClasses). Replaces per-configuration
calibration: a class model predicts the Image view frame and the half-coverage ink box for ANY frame size.

usage: fit-layout.py --fit FIT.json [--holdout HOLD.json] [--table assets.json] [--check-only]
  FIT/HOLD: symbol-metrics output (many --config scale:WxH runs). FIT trains; HOLD is never used for fitting and
  reports how often the trained model reproduces the Mac box exactly.

Model (measured on macOS, ImageRenderer, resizable+scaledToFit):
  * SwiftUI fits the symbol by an intrinsic size that depends on the screen-scale CLASS only (scale < 2 uses the
    1x symbol box, scale >= 2 the 2x box), never on the frame size. View frame = aspect-fit of that box in the
    frame, each edge snapped to whole device pixels (round half up).
  * Ink box (alpha >= 128 bounding box, px relative to the snapped view frame): edge = floor(fraction * viewDim + bias).
    The fraction is the symbol's ink extent; the bias (px) absorbs how pointed tips cover pixels. The biases are
    fitted, not derived from outlines (outlines are never read or stored)."""
import argparse, json, math, sys

SPLIT = 2.0   # scale class boundary, measured: fit intrinsic sizes are identical for 1/1.25/1.5 and for 2/2.5/3/4


def cls(scale): return "1x" if scale < SPLIT else "2x"


def edge_dim(i, cfg): return cfg["viewFramePx"][2 + (i % 2)]


def fit_edge(i, cfgs):
    big = max(cfgs, key=lambda c: edge_dim(i, c))
    seed = big["inkBoxPx"][i] / edge_dim(i, big)
    best = None
    steps = range(-100, 101)
    for k in steps:
        fx = seed + k * 0.0001
        for ci in range(-100, 101):
            c = ci * 0.01
            viol, margin = 0, 9.0
            for cfg in cfgs:
                v = fx * edge_dim(i, cfg) + c
                obs = cfg["inkBoxPx"][i]
                m = min(v - obs, obs + 1 - v)
                if m < 0: viol += 1
                margin = min(margin, m)
            key = (-viol, margin)
            if best is None or key > best[0]: best = (key, fx, c)
    (nv, margin), fx, c = best
    return round(fx, 4), round(c, 2), -nv, round(margin, 3)


def predict(model, cfg):
    fr, bias = model["inkFractions"], model["inkBias"]
    w, h = cfg["viewFramePx"][2], cfg["viewFramePx"][3]
    dims = [w, h, w, h]
    return [math.floor(fr[i] * dims[i] + bias[i]) for i in range(4)]


def collect(path):
    out = {}
    for name, v in json.load(open(path))["symbols"].items():
        if "error" in v: sys.exit(f"{name}: {v['error']}")
        for d in v["deviceInk"]: out.setdefault(name, {}).setdefault(cls(d["scale"]), []).append(d)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fit", required=True); ap.add_argument("--holdout"); ap.add_argument("--table"); ap.add_argument("--check-only", action="store_true")
    a = ap.parse_args()
    fit = collect(a.fit); hold = collect(a.holdout) if a.holdout else {}
    meta = json.load(open(a.fit))
    models = {}
    for name, classes in fit.items():
        models[name] = {}
        for k, cfgs in sorted(classes.items()):
            sizes = {tuple(c["fitIntrinsicSize"]) for c in cfgs}
            if len(sizes) != 1: sys.exit(f"{name} {k}: fit intrinsic size varies with the frame {sizes}; the class model does not apply")
            fr, bias, viol, margins = [], [], [], []
            for i in range(4):
                fx, c, v, m = fit_edge(i, cfgs); fr.append(fx); bias.append(c); viol.append(v); margins.append(m)
            model = {"scaleClass": k, "minScale": 0 if k == "1x" else SPLIT, "maxScaleExclusive": SPLIT if k == "1x" else None,
                     "fitIntrinsicSize": list(next(iter(sizes))), "inkFractions": fr, "inkBias": bias}
            h = hold.get(name, {}).get(k, [])
            miss = [0] * 4; boxmiss = 0; fitbox = 0
            for cfg in cfgs:
                if predict(model, cfg) != cfg["inkBoxPx"]: fitbox += 1
            for cfg in h:
                p = predict(model, cfg)
                bad = [p[i] != cfg["inkBoxPx"][i] for i in range(4)]
                for i in range(4): miss[i] += bad[i]
                boxmiss += any(bad)
            model["fit"] = {"trainConfigs": len(cfgs), "trainEdgeViolations": viol, "trainBoxMismatches": fitbox, "trainMinMarginPx": margins,
                            "holdoutConfigs": len(h), "holdoutEdgeMismatches": miss, "holdoutBoxMismatches": boxmiss}
            overrides = [{"scale": c["scale"], "viewFramePx": c["viewFramePx"], "inkBoxPx": c["inkBoxPx"]}
                         for c in cfgs + h if predict(model, c) != c["inkBoxPx"]]
            seen = set(); uniq = []
            for o in overrides:
                key = (o["scale"], tuple(o["viewFramePx"]))
                if key not in seen: seen.add(key); uniq.append(o)
            model["_overrides"] = uniq
            models[name][k] = model
            print(f"{name} {k}: aspect={model['fitIntrinsicSize']} fractions={fr} bias={bias}\n   train {len(cfgs)} cfgs: box mismatches {fitbox}, edge violations {viol}; holdout {len(h)} cfgs: box mismatches {boxmiss}, edge mismatches {miss}")
            for cfg in h:
                p = predict(model, cfg)
                if p != cfg["inkBoxPx"]: print("     holdout miss", cfg["scale"], cfg["containerPt"], "view", cfg["viewFramePx"], "pred", p, "meas", cfg["inkBoxPx"])
    if a.table and not a.check_only:
        table = json.load(open(a.table))
        for name, ms in models.items():
            lay = table["symbols"][name]["layout"]
            lay["scaleClasses"] = [{k2: v for k2, v in ms[k].items() if k2 != "_overrides"} for k in sorted(ms)]
            lay.pop("deviceInk", None)
            # Measured boxes the class model mispredicts (sharp-tip phase, see predictedInkBox). Applied only on an
            # exact (scale, view frame px) match; every other frame uses the formula.
            lay["inkOverrides"] = [o for k in sorted(ms) for o in ms[k]["_overrides"]]
            lay["classModel"] = "factory/tools/symbol-metrics/fit-layout.py"
        json.dump(table, open(a.table, "w"), indent=2); open(a.table, "a").write("\n")
        print("table updated:", a.table)


if __name__ == "__main__":
    main()
