#!/usr/bin/env python3
"""Wave 1 block I2: fits the host resampling filter per Image.Interpolation level against Mac captures (docs/foundations-images-fonts.md 1.4, the measured-resampling-filter rule).
usage: i2fit.py fit  <calibration case dir>...      fit on the CALIBRATION image set; writes fit-result.json beside this script (winner per level, full candidate table)
       i2fit.py gate-model <gating case dir>...     evaluate the FITTED filters (fit-result.json) on the GATING image set (a different set); writes gate-model-result.json
Each case dir needs layout.json (make_cases.py) and runs/*/mac/run-NN.png. Needs numpy (run with the venv python). Placement model (measured): the destination rect is the frame's
unsnapped rect with every edge = floor(v + 0.5) (device pixels; edges on an exact half pixel are excluded by make_cases.py because float noise decides them); the whole source maps onto that rect (no sub-pixel phase). Error = |round(model composite over the
ground) - Mac| per channel on the whole rect; a cell's max and mean; per level the mean of cell means (the fit criterion) and the max of cell maxima (the tolerance basis)."""
import functools, json, glob, math, sys
from pathlib import Path
import numpy as np
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parent))
import i2gen, i2rects, resample_model as m
HERE = Path(__file__).resolve().parent
LEVELS = ["none", "low", "medium", "high", "default"]


def rect_px(c):
    return tuple(i2rects.cell_rects(c)["image"])


@functools.lru_cache(maxsize=None)
def load(case):
    man = json.loads((case / "layout.json").read_text())
    runs = sorted(glob.glob(str(case / "runs/*/mac")))
    return man, runs


@functools.lru_cache(maxsize=None)
def _mac_image(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(float)


def mac_images(runs):
    out = []
    for r in runs:
        for p in sorted(glob.glob(r + "/run-*.png")):
            out.append((p, _mac_image(p)))
    return out


@functools.lru_cache(maxsize=None)
def _source(family, sw, sh, seed):
    return np.array(i2gen.make(family, sw, sh, seed), dtype=np.uint8).reshape(sh, sw, 4)


def source(c):
    return _source(c["family"], c["sw"], c["sh"], c["seed"])


STRUCTS = ["area", "point", "mip"]   # area: kernel widened by the reduction (a filtered reduction); point: kernel NOT widened (point-sampled); mip: 2 x 2 box halvings while the reduction is >= 2:1, then point
CUBIC = {}                            # name -> (B, C) of a parametric Mitchell-Netravali cubic registered by fit_cubic


def kfull(structure, kernel):
    return kernel if structure == "area" else kernel + "@1"


def model(src, W, H, cand, ground, frame):
    kind, structure, kernel, space = cand
    if kind == "nearest":
        return m.composite(m.nearest(src, W, H, frame), ground)
    k = kfull(structure, kernel)
    if structure == "mip":
        return m.composite(m.resample_mip(src, W, H, kernel, space, frame=frame), ground)
    return m.composite(m.resample(src, W, H, k, space, straight=(kind == "straight"), frame=frame), ground)


def candidates(level, extras=True):
    out = []
    if level == "none":
        out.append(("nearest", "point", "nearest", "gamma"))      # the measured rule; the named filters are tried against it so that the table shows it wins
    for st in STRUCTS:
        for k in m.KERNELS + (m.EXTRA_KERNELS if extras else []) + list(CUBIC):
            for sp in m.SPACES:
                if st == "area" and k.startswith("box") is False and False: continue
                out.append(("filter", st, k, sp))
    return out


def cname(c):
    return "nearest" if c[0] == "nearest" else f"{c[2]}/{c[3]}/{c[1]}" + ("-STRAIGHT" if c[0] == "straight" else "")


def odd_reduction(c):
    """A source with an odd side reduced by more than 2:1 on that axis: the Mac's mip chain for odd sizes is NOT fitted (measured: no tested variant reproduces it; docs/sr1-decisions.md G52)."""
    fw, fh = c["framePx"]
    return (c["sw"] % 2 == 1 and c["sw"] / fw > 2) or (c["sh"] % 2 == 1 and c["sh"] / fh > 2)


def has_tie(c):
    """True when some destination pixel centre maps exactly onto a source pixel boundary (a nearest-neighbour tie): on the Mac the float noise of the layout decides which side
    (measured: the same exact tie went up at one origin and down at another), so such cells are not gateable and are listed as unfitted."""
    fw, fh = c["framePx"]
    def ax(sn, f):
        return any(abs(((t + 0.5) * sn / f) - round((t + 0.5) * sn / f)) < 1e-9 for t in range(int(round(f))))
    return ax(c["sw"], fw) or ax(c["sh"], fh)


def evaluate(cases, levels=LEVELS, cand_filter=None, skip_odd=True):
    """-> {level: {cand: {cells: [...], mean, max, down: {...}, up: {...}}}}; cells with an odd-size reduction > 2:1 are excluded (listed under unfitted)."""
    res = {lv: {} for lv in levels}
    unfitted = []
    for case in cases:
        man, runs = load(case)
        imgs = mac_images(runs)
        if not imgs: raise SystemExit(f"no Mac captures in {case}")
        img = imgs[0][1]
        ground = man["groundRGB"]
        for c in man["cells"]:
            if c.get("mode") or c["level"] not in levels: continue
            if skip_odd and c["level"] in ("medium", "high") and odd_reduction(c):
                unfitted.append(dict(case=case.name, family=c["family"], level=c["level"], ratio=c["ratio"], src=[c["sw"], c["sh"]])); continue
            if c["level"] == "none" and has_tie(c):
                unfitted.append(dict(case=case.name, family=c["family"], level="none", ratio=c["ratio"], src=[c["sw"], c["sh"]], why="nearest tie")); continue
            x0, y0, x1, y1 = rect_px(c); W, H = x1 - x0, y1 - y0
            crop = img[y0:y1, x0:x1]
            src = source(c)
            for cand in (cand_filter or candidates)(c["level"]):
                out = model(src, W, H, cand, ground, c["framePx"])
                e = np.abs(crop - out)
                r = res[c["level"]].setdefault(cname(cand), dict(cells=[], cand=list(cand)))
                r["cells"].append(dict(case=case.name, family=c["family"], ratio=c["ratio"], rectPx=[x0, y0, x1, y1], max=float(e.max()), mean=float(e.mean())))
    for lv in res:
        for k, r in res[lv].items():
            cs = r["cells"]
            r["mean"] = float(np.mean([x["mean"] for x in cs])); r["max"] = float(max(x["max"] for x in cs))
            for nm, sel in (("down", lambda x: x["ratio"] < 1), ("up", lambda x: x["ratio"] > 1)):
                sub = [x for x in cs if sel(x)]
                if sub: r[nm] = dict(mean=float(np.mean([x["mean"] for x in sub])), max=float(max(x["max"] for x in sub)))
    res["_unfitted"] = unfitted
    return res


def table(res, n=6):
    for lv, d in res.items():
        if lv.startswith("_"): continue
        print(f"== level {lv}")
        for k, r in sorted(d.items(), key=lambda kv: (kv[1]["mean"], kv[1]["max"]))[:n]:
            print(f"   {k:34s} mean {r['mean']:7.3f} max {r['max']:5.0f} | down mean {r.get('down', {}).get('mean', float('nan')):7.3f} max {r.get('down', {}).get('max', float('nan')):5.0f} | up mean {r.get('up', {}).get('mean', float('nan')):7.3f} max {r.get('up', {}).get('max', float('nan')):5.0f}")


def fit_cubic(cases, level, structure="mip", span=(0.0, 1.0), step=0.02, lo=-0.1, hi=0.5):
    """Parametric Mitchell-Netravali cubic (B, C) grid for one level (an EXTRA family beyond the five named candidates: recorded as such)."""
    best = []
    Bs = np.arange(span[0], span[1] + 1e-9, step); Cs = np.arange(lo, hi + 1e-9, step)
    for B in Bs:
        for C in Cs:
            m.FN["cubic-fit"] = m._cubic(float(B), float(C)); m.SUPPORT["cubic-fit"] = 2.0; m.weights.cache_clear()
            CUBIC["cubic-fit"] = (float(B), float(C))
            res = evaluate(cases, [level], cand_filter=lambda lv: [("filter", structure, "cubic-fit", "gamma")])
            r = res[level][cname(("filter", structure, "cubic-fit", "gamma"))]
            best.append((r["mean"], r["max"], round(float(B), 3), round(float(C), 3)))
    best.sort()
    CUBIC.clear()
    return best


def host_output(src, W, H, level, frame, B, C):
    """The product's output for one case as straight 8-bit RGBA (what ImageResampler.swift registers); used for the Swift test vectors."""
    if level == "none":
        out = m.nearest(src, W, H, frame)
    else:
        kernel, struct = {"low": ("triangle", "point"), "default": ("triangle", "point"), "medium": ("triangle", "mip"), "high": ("cubic-fit", "mip")}[level]
        m.register_cubic("cubic-fit", B, C)
        out = m.resample_mip(src, W, H, kernel, "gamma", frame=frame) if struct == "mip" else m.resample(src, W, H, kernel + "@1", "gamma", frame=frame)
    return np.clip(np.floor(out + 0.5), 0, 255).astype(np.uint8)


def emit_vectors(path, B, C):
    import base64
    cases = [("photo", 48, 36, 11, 24, 18, 24.0, 18.0, lv) for lv in ("none", "low", "medium", "high")] + \
            [("photo", 48, 36, 11, 16, 12, 16.0, 12.0, lv) for lv in ("medium", "high")] + \
            [("photo", 48, 36, 11, 60, 45, 60.0, 45.0, lv) for lv in ("none", "low", "high")] + \
            [("alpha", 40, 30, 41, 53, 39, 53.0, 39.0, lv) for lv in ("low", "medium", "high")] + \
            [("lineart", 44, 32, 21, 19, 14, 19.0, 14.0, lv) for lv in ("none", "low", "medium", "high")] + \
            [("checker", 32, 24, 52, 32, 24, 32.0, 24.0, "high")]
    out = []
    for fam, sw, sh, seed, W, H, fw, fh, lv in cases:
        src = _source(fam, sw, sh, seed)
        res = host_output(src, W, H, lv, (fw, fh), B, C)
        out.append(dict(family=fam, sw=sw, sh=sh, seed=seed, width=W, height=H, frameW=fw, frameH=fh, level=lv,
                        source=base64.b64encode(src.tobytes()).decode(), expected=base64.b64encode(res.tobytes()).decode()))
    Path(path).write_text(json.dumps(dict(note="generated by factory/pipeline/blocks-w1-i2/i2fit.py vectors; resample_model.py is the reference model", cubic=[B, C], cases=out), indent=0))
    print("wrote", path, len(out), "cases")


def final(dirs, B, C):
    """The recorded fit (fit-result.json): per level the best of the five NAMED candidates, the best of the extras (including the parametric cubic for `high`) and the filter the host implements."""
    m.register_cubic("cubic-fit", B, C); CUBIC["cubic-fit"] = (B, C)
    res = evaluate(dirs)
    named = {f"{k}/{sp}/{st}" for k in m.KERNELS for sp in m.SPACES for st in STRUCTS}
    out = dict(calibrationSet=[d.name for d in dirs], unfitted=res.pop("_unfitted"), cubicBC=[B, C], levels={})
    chosen = {"none": "nearest", "low": "triangle/gamma/point", "default": "triangle/gamma/point", "medium": "triangle/gamma/mip", "high": "cubic-fit/gamma/mip"}
    for lv, d in res.items():
        def entry(k):
            r = d[k]; return dict(candidate=k, mean=round(r["mean"], 4), max=r["max"], down=r.get("down"), up=r.get("up"), cells=len(r["cells"]))
        nm = sorted((k for k in d if k in named), key=lambda k: (d[k]["mean"], d[k]["max"]))
        ex = sorted((k for k in d if k not in named), key=lambda k: (d[k]["mean"], d[k]["max"]))
        out["levels"][lv] = dict(bestNamed=entry(nm[0]) if nm else None, bestNamedRunnersUp=[entry(k) for k in nm[1:4]], bestExtra=entry(ex[0]), chosen=entry(chosen[lv]),
                                 namedCandidatesTried=len(nm), extraCandidatesTried=len(ex))
    (HERE / "fit-result.json").write_text(json.dumps(out, indent=1))
    for lv, d in out["levels"].items():
        bn = d["bestNamed"]
        print(f"{lv:8s} chosen {d['chosen']['candidate']:24s} mean {d['chosen']['mean']:7.4f} max {d['chosen']['max']:5.0f} | best named {bn['candidate'] if bn else '-':26s} mean {bn['mean'] if bn else float('nan'):7.4f} max {bn['max'] if bn else float('nan'):5.0f} | best extra {d['bestExtra']['candidate']} {d['bestExtra']['mean']}")


def gate_model(dirs, B, C):
    """The FITTED filters (not refitted) against the Mac captures of the GATING set: the model's own error before any Windows run (gate-model-result.json)."""
    m.register_cubic("cubic-fit", B, C); CUBIC["cubic-fit"] = (B, C)
    pick = {"none": ("nearest", "point", "nearest", "gamma"), "low": ("filter", "point", "triangle", "gamma"), "default": ("filter", "point", "triangle", "gamma"),
            "medium": ("filter", "mip", "triangle", "gamma"), "high": ("filter", "mip", "cubic-fit", "gamma")}
    res = evaluate(dirs, cand_filter=lambda lv: [pick[lv]])
    unf = res.pop("_unfitted")
    out = dict(gatingSet=[d.name for d in dirs], unfitted=unf, levels={})
    for lv, d in res.items():
        for k, r in d.items():
            worst = sorted(r["cells"], key=lambda x: -x["max"])[:3]
            out["levels"][lv] = dict(candidate=k, cells=len(r["cells"]), mean=round(r["mean"], 4), max=r["max"], worstCells=[dict(case=w["case"], family=w["family"], ratio=w["ratio"], max=w["max"], mean=round(w["mean"], 3)) for w in worst])
    (HERE / "gate-model-result.json").write_text(json.dumps(out, indent=1))
    for lv, d in out["levels"].items(): print(f"{lv:8s} {d['candidate']:24s} cells {d['cells']:3d} mean {d['mean']:7.4f} max {d['max']:5.0f}  worst {d['worstCells'][0]}")
    print("unfitted (excluded):", len(unf))


def main():
    mode = sys.argv[1]
    dirs = [Path(a) for a in sys.argv[2:] if not a.startswith("--bc=")] if mode != "vectors" else []
    if mode == "fit":
        res = evaluate(dirs); table(res)
        (HERE / "fit-raw.json").write_text(json.dumps(res, indent=0))
    elif mode == "gate-model":
        bc = next((a[5:] for a in sys.argv if a.startswith("--bc=")), "0.72,0.12"); B, C = (float(x) for x in bc.split(","))
        gate_model(dirs, B, C)
    elif mode == "final":
        bc = next((a[5:] for a in sys.argv if a.startswith("--bc=")), "0.72,0.12"); B, C = (float(x) for x in bc.split(","))
        final(dirs, B, C)
    elif mode == "vectors":
        emit_vectors(sys.argv[2], float(sys.argv[3]), float(sys.argv[4]))
    elif mode == "cubic":
        for lv in ("high",):
            b = fit_cubic(dirs, lv, step=0.04)
            print(lv, b[:5])
            b2 = fit_cubic(dirs, lv, span=(b[0][2] - 0.04, b[0][2] + 0.04), lo=b[0][3] - 0.04, hi=b[0][3] + 0.04, step=0.01)
            print(lv, "refined", b2[:5])
    else:
        raise SystemExit("unknown mode")


if __name__ == "__main__":
    main()
