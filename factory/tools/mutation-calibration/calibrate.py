#!/usr/bin/env python3
"""Run the mutation calibration. python3 calibrate.py [--gate G] [--only SUBSTR] [--out results.json]"""
import argparse, importlib, json, sys, time
from collections import OrderedDict
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from core import run_one, ROOT

SUITES = ["s_pixel", "s_text", "s_control", "s_semantic", "s_clock", "s_image", "s_textorigin", "s_multirun"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gate"); ap.add_argument("--only")
    ap.add_argument("--out", default=str(ROOT / "factory/pipeline/mutation-calibration/results.json"))
    a = ap.parse_args()
    muts = []
    for s in SUITES:
        try:
            muts += importlib.import_module(s).MUTATIONS
        except ModuleNotFoundError as e:
            if e.name != s: raise
    rows = []
    for m in muts:
        if (a.gate and m.gate != a.gate) or (a.only and a.only not in f"{m.base}/{m.name}"):
            continue
        t = time.time()
        res = run_one(m.base, m.fn)
        if m.kind == "catch": verdict = "caught" if not res["passed"] else "MISSED"
        elif m.kind == "near": verdict = "near-miss passed" if res["passed"] else "OVER-STRICT"
        else: verdict = "probe: " + ("fail" if not res["passed"] else "pass")
        target = m.name.split("/")[0] if m.gate == "multi-run" else m.gate
        own = [g for g in res["failedReports"] if g == target]
        if verdict == "caught" and not own and not res["crashed"]:
            verdict = "caught (by another gate only)"
        if verdict == "caught" and res["crashed"] and not own:
            verdict = "caught (comparator crashed)"
        row = OrderedDict(gate=m.gate, base=m.base, mutation=m.name, kind=m.kind, what=m.what, applied=res["desc"], exit=res["rc"], failedReports=res["failedReports"], verdict=verdict, design=m.design, why=res["tail"], secs=round(time.time() - t, 1))
        rows.append(row)
        flag = "" if verdict in ("caught", "near-miss passed") or verdict.startswith("probe") else "   <<<<<<"
        if verdict.startswith("caught ("): flag = "   <<"
        print(f"{m.gate:11s} {m.base:18s} {m.name:34s} {m.kind:5s} exit={res['exit'] if 'exit' in res else res['rc']} {verdict}{flag}", flush=True)
    if not (a.gate or a.only):
        import report
        from core import FIX
        baselines = {}
        for d in sorted(p for p in FIX.iterdir() if p.is_dir()):
            baselines[d.name] = run_one(d.name)["passed"]
        if not all(baselines.values()):
            sys.exit(f"unmutated baselines fail, calibration invalid: {[k for k, v in baselines.items() if not v]}")
        sources = {d.name: json.loads((d / "SOURCE.json").read_text()) for d in sorted(p for p in FIX.iterdir() if p.is_dir())}
        out = Path(a.out); out.parent.mkdir(parents=True, exist_ok=True)
        report.build(rows, baselines, sources, out, out.with_name("RESULTS.md"))
        print("wrote", out, out.with_name("RESULTS.md"))
    else:
        print(json.dumps([r for r in rows if r["verdict"] in ("MISSED", "OVER-STRICT")], indent=1)[:4000])


if __name__ == "__main__":
    main()
