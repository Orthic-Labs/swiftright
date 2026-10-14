#!/usr/bin/env python3
"""python3 make_table.py <stage> : latest done record per (case, n) of the stage in closure/results.jsonl -> closure/closure-table.json
(per case: block, N, exit, the pair.py lines that carry the verdict, the Mac scale guard recorded in build.json, run dir) and a per-block roll-up printed to stdout."""
import json, re, sys
from collections import defaultdict
from pathlib import Path
HERE = Path(__file__).resolve().parent; stage = sys.argv[1]
recs = {}
for l in (HERE / "results.jsonl").read_text().splitlines():
    j = json.loads(l)
    if j["stage"] == stage and j.get("done"): recs[(j["case"], j["n"])] = j
rows = []
for (case, n), j in sorted(recs.items(), key=lambda kv: (kv[1]["block"], kv[0])):
    out = Path(j["out"]) if j.get("out") else None
    guard = None
    if out and (out / "build.json").is_file():
        try: guard = json.loads((out / "build.json").read_text())["mac"]["scaleGuard"]
        except Exception: pass
    rows.append({"block": j["block"], "case": case, "n": n, "exit": j["exit"], "summary": [x for x in j["tail"] if not re.match(r"\s+(semantic run|clock run|run) ", x)][-3:],
                 "scaleGuard": guard and {k: guard[k] for k in ("status", "captureScale", "reported", "distinct", "screens")}, "out": j["out"], "secs": j["secs"]})
(HERE / "closure-table.json").write_text(json.dumps({"stage": stage, "jobs": len(rows), "pass": sum(1 for r in rows if r["exit"] == 0), "rows": rows}, indent=1))
by = defaultdict(lambda: [0, 0, 0])
for r in rows:
    b = by[r["block"]]; b[0] += 1; b[1] += r["exit"] == 0; b[2] += r["n"]
for k, (jobs, ok, runs) in sorted(by.items(), key=lambda kv: (len(kv[0].split()[0]) , kv[0])): print(f"{k:40} jobs {jobs:3} pass {ok:3} runs {runs}")
print("total", len(rows), "pass", sum(1 for r in rows if r["exit"] == 0))
