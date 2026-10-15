#!/usr/bin/env python3
"""Re-judges the N=3 rebaseline runs already captured on stage fc4a39a89-f623e43e (renderer r08final) under the current pair.json of each case (pair.py --recompare, no capture).
One record per case in rebase-recompare.jsonl: the pair.py exit code (0 = the case passes), the run dir, and the exit code of the previous judgement when recorded.
  rebase_recompare.py [--only SUBSTR]"""
import json, subprocess, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
PIPE = HERE.parent; REPO = PIPE.parents[1]
STAGE, LABEL = "fc4a39a89-f623e43e", "r08final"
OUT = HERE / "rebase-recompare.jsonl"
only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
rows = [json.loads(l) for l in (HERE / "results.jsonl").read_text().splitlines() if l.strip()]
latest = {}
for r in rows:
    if r["stage"] == STAGE and r["renderer"] == LABEL and r["n"] == 3 and r.get("out") and r.get("done"):
        latest[r["case"]] = r
cases = json.loads((HERE / "rebaseline-set.json").read_text())
done = []
for c in cases:
    if only and only not in c: continue
    if c not in latest: continue
    run = latest[c]["out"]
    cmd = [sys.executable, str(REPO / "factory/tools/pair.py"), str(PIPE / c), "--recompare", run]
    r = subprocess.run(cmd, capture_output=True, text=True)
    rec = dict(case=c, run=run, exit=r.returncode, tail=[l[:200] for l in (r.stdout + r.stderr).splitlines() if "pairs=" in l][-1:])
    done.append(rec)
    with OUT.open("a") as f: f.write(json.dumps(rec) + "\n")
    print(c, "exit", r.returncode, flush=True)
print("judged", len(done), "of", len(cases), "cases;", sum(1 for d in done if d["exit"] == 0), "pass")
