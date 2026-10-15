#!/usr/bin/env python3
"""Alpha gate (wave 0 block T0, docs/foundations-images-fonts.md 1.2): composites compared with the ANALYTIC value, not with the Mac.
usage: pair_alpha_report.py <case-dir> <runs/<ts> dir>   (after factory/tools/pair.py produced mac/ and windows/)
<case>/pair.json "alphaGate": {"toleranceReason": str,
  "ground": [{"name", "rect": [x0,y0,x1,y1], "rgb": [r,g,b]}],           # opaque background bands, painted first, always exact (tolerance 0)
  "regions": [{"name", "rect": [x0,y0,x1,y1], "tol": 0|1,                 # tolerance in 8-bit levels per channel against the analytic float value
               "expect": [r,g,b]                                           # uniform: bg*(1-a)+fg*a, computed by the case generator (floats)
               | "pattern": {"kind": "checker", "cellPx": n, "even": [..], "odd": [..]}   # (x//n + y//n) parity, from the region's top-left
               | {"kind": "split", "axis": "x", "atPx": n, "first": [..], "second": [..]}}]}
Pixels are the 800x600 captures. Gate: every Windows pixel is within `tol` of its analytic value in every channel (ground and alpha-0 and alpha-255 regions
tol 0 = exact), and no pixel lies outside every ground and region rect (the frame is fully specified). The Mac capture is judged by the same model and reported
(it is the reference for what Apple does, not part of the verdict); the Windows-versus-Mac difference is reported. Exit 1 on any Windows violation."""
import json, sys
from pathlib import Path
from PIL import Image

W, H = 800, 600


def expected(gate):
    """Per pixel: (r, g, b) analytic floats or None, tolerance, region index (-1 ground)."""
    exp = [None] * (W * H); tol = [-1] * (W * H); reg = [-2] * (W * H)
    for g in gate.get("ground", []):
        x0, y0, x1, y1 = g["rect"]; rgb = tuple(float(c) for c in g["rgb"])
        for y in range(y0, y1):
            for x in range(x0, x1):
                i = y * W + x; exp[i] = rgb; tol[i] = 0; reg[i] = -1
    for k, r in enumerate(gate["regions"]):
        x0, y0, x1, y1 = r["rect"]
        p = r.get("pattern")
        uni = tuple(float(c) for c in r["expect"]) if "expect" in r else None
        for y in range(y0, y1):
            for x in range(x0, x1):
                if uni is not None: v = uni
                elif p["kind"] == "checker": v = tuple(float(c) for c in (p["odd"] if (((x - x0) // p["cellPx"]) + ((y - y0) // p["cellPx"])) % 2 == 1 else p["even"]))
                elif p["kind"] == "split": v = tuple(float(c) for c in (p["second"] if (x - x0) >= p["atPx"] else p["first"]))
                else: raise SystemExit("unknown pattern " + p["kind"])
                i = y * W + x; exp[i] = v; tol[i] = int(r["tol"]); reg[i] = k
    return exp, tol, reg


def judge(img, exp, tol, reg, regs):
    data = img.convert("RGB").tobytes()
    worst = {r["name"]: [0.0, 0, r["tol"]] for r in regs}
    unspecified = outside = ground_out = 0; max_all = 0.0
    for i in range(W * H):
        e = exp[i]
        if e is None:
            unspecified += 1; continue
        j = i * 3
        err = max(abs(data[j] - e[0]), abs(data[j + 1] - e[1]), abs(data[j + 2] - e[2]))
        if err > max_all: max_all = err
        bad = err > tol[i] + 1e-9
        k = reg[i]
        if k >= 0:
            w = worst[regs[k]["name"]]
            if err > w[0]: w[0] = err
            if bad: w[1] += 1
        if bad:
            outside += 1
            if k < 0: ground_out += 1
    return dict(unspecifiedPixels=unspecified, outsideTolerance=outside, groundOutside=ground_out, maxErrAll=round(max_all, 3),
                regions={n: dict(maxErr=round(v[0], 3), outside=v[1], tol=v[2]) for n, v in worst.items()})


def main():
    case, out = Path(sys.argv[1]), Path(sys.argv[2])
    gate = json.loads((case / "pair.json").read_text())["alphaGate"]
    assert gate.get("toleranceReason"), "alphaGate needs toleranceReason (decision 5: a tolerance is measured and named)"
    runs = sorted({q.name[4:6] for q in (out / "mac").glob("run-*.png") if q.name[4:6].isdigit()})
    exp, tol, reg = expected(gate)
    allok = True
    for n in runs:
        mac, win = out / f"mac/run-{n}.png", out / f"windows/native-{n}.png"
        if not (mac.is_file() and win.is_file()):
            print(f"run {n}: missing capture  FAIL"); allok = False; continue
        iw, im = Image.open(win), Image.open(mac)
        if iw.size != (W, H) or im.size != (W, H):
            print(f"run {n}: size win={iw.size} mac={im.size}  FAIL"); allok = False; continue
        jw, jm = judge(iw, exp, tol, reg, gate["regions"]), judge(im, exp, tol, reg, gate["regions"])
        bw, bm = iw.convert("RGB").tobytes(), im.convert("RGB").tobytes()
        diffs = [max(abs(bw[i] - bm[i]), abs(bw[i + 1] - bm[i + 1]), abs(bw[i + 2] - bm[i + 2])) for i in range(0, len(bw), 3)]
        ok = jw["outsideTolerance"] == 0 and jw["unspecifiedPixels"] == 0
        allok &= ok
        print(f"run {n}: windows-vs-analytic maxErr {jw['maxErrAll']} outside-tolerance {jw['outsideTolerance']} (ground {jw['groundOutside']}) unspecified {jw['unspecifiedPixels']} | "
              f"mac-vs-analytic maxErr {jm['maxErrAll']} outside {jm['outsideTolerance']} | windows-vs-mac maxdiff {max(diffs)} differing {sum(1 for d in diffs if d)}  {'PASS' if ok else 'FAIL'}")
        if n == runs[0] or not ok:
            for name, r in jw["regions"].items():
                mr = jm["regions"].get(name, {})
                flag = "" if r["outside"] == 0 else "  <-- windows outside tolerance"
                print(f"   {name:34s} tol {r['tol']} windows maxErr {r['maxErr']:7.3f} outside {r['outside']:6d} | mac maxErr {mr.get('maxErr')} outside {mr.get('outside')}{flag}")
    print("alpha gate:", "PASS" if allok else "FAIL")
    sys.exit(0 if allok else 1)


main()
