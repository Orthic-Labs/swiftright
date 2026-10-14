#!/usr/bin/env python3
"""python3 summarise_results.py <stage> : latest done record per (case, n) from results.jsonl -> consolidation-table.json (summary = the pair.py output lines that carry the verdict)."""
import json, sys, re
from pathlib import Path
HERE = Path(__file__).resolve().parent; stage = sys.argv[1]
recs = {}
for l in (HERE/"results.jsonl").read_text().splitlines():
    j = json.loads(l)
    if j["stage"] == stage and j.get("done"): recs[(j["case"], j["n"])] = j
rows = [{"block": j["block"], "case": case, "n": n, "exit": j["exit"], "summary": [x for x in j["tail"] if not re.match(r"\s+(semantic run|clock run|run) ", x)][-3:], "out": j["out"]} for (case, n), j in recs.items()]
json.dump(rows, open(HERE/"consolidation-table.json", "w"), indent=1)
for r in rows: print(r["exit"], r["n"], r["case"].split("/", 1)[1], "|", r["summary"][-1][:140])
