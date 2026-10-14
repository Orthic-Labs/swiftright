#!/usr/bin/env python3
"""F1 manual-clock gate. usage: pair_clock_report.py <case-dir> <run-dir>

Reads <case>/pair.json "clockGate" and the per-frame captures of one pair.py run (mac/run-NN-fKK.png, windows/native-NN-fKK.png, windows/host-NN-fKK.stdout.txt with the
host's HOST_GEOMETRY line, mac-run-NN.log with MAC_FRAME lines = SwiftUI's own animation evaluation at each clock step).

clockGate = {
  "tracks": [ {"name": "bar", "kind": "Color", "index": 0,            # the index-th resolved node of that kind in pre-order (Windows geometry)
               "colour": [0,136,255],                                 # the shape's flat colour on the capture (Mac pixels); background is white
               "axis": "x",                                           # extent measured along x (a row through the shape) or y (a column)
               "line": 300,                                           # capture pixel row (axis x) / column (axis y) to measure on
               "from": 100, "to": 200,                                # progress 0 / 1 as a width (axis x) or height (axis y), points
               "leaf": 2}],                                           # index of the animated component in the Mac AnimationContext value (progress = result[leaf]/value[leaf])
  "extentTolerancePx": 1.0, "progressTolerance": 0.004,
  "edgeTolerancePx": 1.0,                                              # leading and trailing edge position (default: extentTolerancePx), sr1-decisions #18
  "stripPx": 1                                                         # pixel columns around a fractional edge excluded from the exact pixel comparison
}

Per (run, frame) the gate has four parts, all reported:
  extent   |mac extent - windows extent| <= extentTolerancePx, both measured the same way from the capture (coverage-integrated: partial-coverage edge pixels count by coverage).
           The Mac draws a fractional edge with anti-aliasing; the runtime snaps presented frames to the device pixel grid, so the two edges can differ by up to 1 px of extent.
  edges    |mac edge - windows edge| <= edgeTolerancePx for BOTH the leading and the trailing edge of every tracked shape, each edge read as a coverage-integrated position
           in capture px (a partial-coverage edge pixel counts by coverage). Extent alone cannot see a bar that is translated with the same width, and the strips below hide
           the pixels around a differing edge, so the positions themselves are gated; the strips only keep anti-aliasing out of the exact comparison.
  pixels   identical (all channels) everywhere except the strips around the tracked edges that are not on a whole device pixel on the Mac.
  progress SwiftUI's own progress at that step (from the Mac wrapper log: result/value, 1 once the animation has ended, 0 before it began) vs the runtime's presented frame
           (HOST_GEOMETRY, points) as a fraction of from..to; tolerance progressTolerance (snapping alone explains up to 0.5 px / ((to-from) * scale)).
Exit 0 when every pair passes."""
import json, re, sys
from pathlib import Path
from PIL import Image, ImageChops

SCALE = 2.5


def coverage_run(im, axis, line, colour):
    """(start, end, extent) in capture px of the coverage-integrated run of `colour` over white along a row (axis x) or column (axis y)."""
    w, h = im.size
    n = w if axis == "x" else h
    vals = [im.getpixel((i, line) if axis == "x" else (line, i)) for i in range(n)]
    # channel with the largest contrast against white
    ch = max(range(3), key=lambda c: 255 - colour[c])
    span = 255 - colour[ch]
    cov = [(255 - v[ch]) / span if span else 0.0 for v in vals]
    cov = [min(1.0, max(0.0, c)) for c in cov]
    idx = [i for i, c in enumerate(cov) if c > 0.02]
    if not idx:
        return None
    a, b = idx[0], idx[-1]
    return dict(start=a + (1 - cov[a]), end=b + cov[b], extent=sum(cov[a:b + 1]), cov0=cov[a], cov1=cov[b], first=a, last=b)


def nth_node(geom, kind, index):
    nodes = [n for n in geom["nodes"] if n["kind"] == kind]
    return nodes[index] if index < len(nodes) else None


def main():
    case, out = Path(sys.argv[1]), Path(sys.argv[2])
    cfg = json.loads((case / "pair.json").read_text())
    gate = cfg["clockGate"]
    frames = len(cfg["clock"])
    runs = sorted({int(re.match(r"run-(\d+)-f", p.name).group(1)) for p in (out / "mac").glob("run-*-f*.png")})
    tol_e = gate.get("extentTolerancePx", 1.0)
    tol_p = gate.get("progressTolerance", 0.004)
    tol_edge = gate.get("edgeTolerancePx", tol_e)
    strip = gate.get("stripPx", 1)
    rows, fails = [], 0
    for run in runs:
        maclog = (out / f"mac-run-{run:02d}.log").read_text() if (out / f"mac-run-{run:02d}.log").is_file() else ""
        macframes = {int(m.group(1)): m.group(2) for m in re.finditer(r"MAC_FRAME index=(\d+) (.*)", maclog)}
        for k in range(frames):
            row = dict(run=run, frame=k, t=cfg["clock"][k])
            mp, wp = out / f"mac/run-{run:02d}-f{k:02d}.png", out / f"windows/native-{run:02d}-f{k:02d}.png"
            if not (mp.is_file() and wp.is_file()):   # a missing capture fails the pair cleanly (it used to crash the comparator before it wrote its report)
                row.update(ok=False, error=f"missing capture: mac {mp.is_file()} windows {wp.is_file()}", tracks=[], hostGeometry=False, pixelsDiffOutsideStrips=None, stripPixels=None)
                fails += 1; rows.append(row); continue
            mi = Image.open(mp).convert("RGB")
            wi = Image.open(wp).convert("RGB")
            hostlog = out / f"windows/host-{run:02d}-f{k:02d}.stdout.txt"
            geom = None
            if hostlog.is_file():
                m = re.search(r"HOST_GEOMETRY (\{.*\})", hostlog.read_text(errors="replace"))
                geom = json.loads(m.group(1)) if m else None
            row["hostGeometry"] = geom is not None
            mask = Image.new("L", mi.size, 0)
            ok = geom is not None
            tracks = []
            for tr in gate["tracks"]:
                t = dict(name=tr["name"])
                mrun = coverage_run(mi, tr["axis"], tr["line"], tr["colour"])
                wrun = coverage_run(wi, tr["axis"], tr["line"], tr["colour"])
                t["mac"] = mrun and {k2: round(v, 4) for k2, v in mrun.items()}
                t["win"] = wrun and {k2: round(v, 4) for k2, v in wrun.items()}
                if mrun is None or wrun is None:
                    t["extentOk"] = (mrun is None) == (wrun is None)   # both empty (fully transparent / not yet shown) passes
                    t["extentDelta"] = None
                else:
                    d = wrun["extent"] - mrun["extent"]
                    t["extentDelta"] = round(d, 4)
                    t["extentOk"] = abs(d) <= tol_e
                    t["startDelta"] = round(wrun["start"] - mrun["start"], 4)
                    t["endDelta"] = round(wrun["end"] - mrun["end"], 4)
                    t["edgesOk"] = abs(t["startDelta"]) <= tol_edge and abs(t["endDelta"]) <= tol_edge   # the rounded deltas: a whole-pixel shift is exactly 1.0, not 1.0000000000000002
                    # strips: every edge that sits on a fractional Mac position (partial-coverage pixel) or differs in either capture
                    for e in ("start", "end"):
                        for run_ in (mrun, wrun):
                            pos = run_[e]
                            lo, hi = int(pos) - strip, int(pos) + strip + 1
                            if tr["axis"] == "x":
                                mask.paste(255, (max(0, lo), 0, min(mi.size[0], hi), mi.size[1])) if abs(pos - round(pos)) > 1e-6 or abs(mrun[e] - wrun[e]) > 1e-6 else None
                            else:
                                mask.paste(255, (0, max(0, lo), mi.size[0], min(mi.size[1], hi))) if abs(pos - round(pos)) > 1e-6 or abs(mrun[e] - wrun[e]) > 1e-6 else None
                ok = ok and t["extentOk"] and t.get("edgesOk", True)
                # progress: SwiftUI (Mac wrapper log) vs runtime presented frame
                if geom is not None and "from" in tr:
                    node = nth_node(geom, tr["kind"], tr.get("index", 0))
                    prop = "w" if tr["axis"] == "x" else "h"
                    winp = None if node is None else (node[prop] - tr["from"]) / (tr["to"] - tr["from"])
                    macp = None
                    line = macframes.get(k, "")
                    mv = re.search(r"value=\[([^\]]*)\] result=\[([^\]]*)\] ended=(\w+)", line)
                    if mv:
                        v = [float(x) for x in mv.group(1).split(",") if x.strip()]
                        r = [float(x) for x in mv.group(2).split(",") if x.strip()]
                        lf = tr.get("leaf", 2)
                        if mv.group(3) == "true":
                            macp = 1.0
                        elif r and lf < len(v) and v[lf]:
                            macp = r[lf] / v[lf]
                    t["progress"] = dict(mac=macp, win=None if winp is None else round(winp, 5))
                    t["progressOk"] = macp is not None and winp is not None and abs(macp - winp) <= tol_p
                    t["progressDelta"] = None if not (macp is not None and winp is not None) else round(winp - macp, 5)
                    ok = ok and t["progressOk"]
                tracks.append(t)
            # exact pixels outside the strips
            diff = ImageChops.difference(mi, wi)
            diff = Image.composite(Image.new("RGB", diff.size, (0, 0, 0)), diff, mask)
            g = ImageChops.lighter(ImageChops.lighter(*diff.split()[:2]), diff.split()[2])
            npx = g.size[0] * g.size[1] - g.histogram()[0]
            row["pixelsDiffOutsideStrips"] = npx
            row["stripPixels"] = mask.histogram()[255]
            ok = ok and npx == 0
            row["tracks"] = tracks
            row["ok"] = ok
            fails += 0 if ok else 1
            rows.append(row)
    rep = dict(gate="clock", edgeTolerancePx=tol_edge, extentTolerancePx=tol_e, pairs=len(rows), fail=fails, runs=len(runs), frames=frames, rows=rows)
    (out / "clock-report.json").write_text(json.dumps(rep, indent=1))
    for r in rows:
        if r["run"] == runs[0] or not r["ok"]:
            tt = r["tracks"][0] if r["tracks"] else {}
            if "error" in r:
                print(f"  clock run {r['run']:02d} f{r['frame']:02d} FAIL {r['error']}"); continue
            print(f"  clock run {r['run']:02d} f{r['frame']:02d} t={r['t']:<5} {'ok  ' if r['ok'] else 'FAIL'} extentΔ={tt.get('extentDelta')} edgeΔ start={tt.get('startDelta')} end={tt.get('endDelta')} progress mac={tt.get('progress', {}).get('mac')} win={tt.get('progress', {}).get('win')} "
                  f"pixelsOutsideStrips={r['pixelsDiffOutsideStrips']} (strip px {r['stripPixels']})")
    print(f"clock gate: pairs={len(rows)} ok={len(rows) - fails} fail={fails}")
    sys.exit(0 if fails == 0 else 1)


if __name__ == "__main__":
    main()
