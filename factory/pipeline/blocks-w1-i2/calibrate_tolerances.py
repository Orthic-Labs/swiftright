#!/usr/bin/env python3
"""Derives tolerances.json from the Windows-vs-Mac CALIBRATION runs (results.jsonl, kind cal): per level the maximum per-pixel and the maximum per-cell mean over every resampled
cell of every calibration page and run, excluding the cells the fit excludes (nearest ties; an odd side reduced more than 2:1 at medium/high: G51, G53). Each maximum is rounded up ONCE
(max to the next integer, mean to the next 0.05). usage: calibrate_tolerances.py [stage]"""
import json, math, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import i2fit
stage = sys.argv[1] if len(sys.argv) > 1 else "cf9d48dab-77823e0e"
recs = [json.loads(l) for l in (HERE / "results.jsonl").read_text().splitlines() if l.strip()]
recs = [r for r in recs if r.get("kind") == "cal" and r.get("stage") == stage and r.get("gateExit") is not None]
latest = {}
for r in recs: latest[r["case"]] = r
agg = {}
ncells = {}
for case, r in sorted(latest.items()):
    cdir = HERE / ("swiftui.image-" + r["case"])
    man = json.loads((cdir / "layout.json").read_text())
    rep = json.loads((Path(r["out"]) / "resample-report.json").read_text())
    cells = man["cells"]
    for run in rep["rows"]:
        for c, row in zip(cells, run["cells"]):
            if row["cls"] != "resampled" or c.get("mode") and False: continue
            lv = "low" if c["level"] == "default" else c["level"]
            if not c.get("mode"):
                if lv == "none" and i2fit.has_tie(c): continue
                if lv in ("medium", "high") and i2fit.odd_reduction(c): continue
            a = agg.setdefault(lv, dict(max=0, mean=0.0)); a["max"] = max(a["max"], row["max"]); a["mean"] = max(a["mean"], row["mean"])
            ncells[lv] = ncells.get(lv, 0) + 1
tol = {lv: dict(resampleMaxPerChannel=int(math.ceil(a["max"])), resampleMeanPerChannel=round(math.ceil(a["mean"] / 0.05) * 0.05, 2)) for lv, a in agg.items()}
for lv in ("none",):
    tol.setdefault(lv, dict(resampleMaxPerChannel=1, resampleMeanPerChannel=0.05))
fit = json.loads((HERE / "fit-result.json").read_text())
reason = ("Windows pipeline (host resample in Float, 8-bit straight alpha, GPU blend) against the Mac ImageRenderer on the CALIBRATION image set (swiftui.image-calibration, 3 runs of each page): per level the maximum per-pixel "
          "per-channel difference and the largest per-cell mean over every resampled cell, rounded up once (max to the next integer, mean to the next 0.05). The gating set (swiftui.image-layout) is different images and sizes. "
          "Excluded: nearest ties and odd sides reduced more than 2:1 at medium/high (not reproducible, G51 G53). Wave 1 block I2, docs/sr1-decisions.md G52 G56.")
out = dict(resampleTolerance=tol, resampleToleranceReason=reason, calibrationMaxima={k: dict(max=v["max"], meanOfCellMeansMax=round(v["mean"], 4), cells=ncells[k]) for k, v in agg.items()}, stage=stage,
           calibrationCases=sorted(latest), resampleFilter={lv: fit["levels"][lv]["chosen"] for lv in ("none", "low", "medium", "high")})
(HERE / "tolerances.json").write_text(json.dumps(out, indent=1) + "\n")
print(json.dumps(dict(tol=tol, maxima=out["calibrationMaxima"]), indent=1))
