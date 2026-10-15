#!/usr/bin/env python3
"""python3 summarise_round5.py : merges the round-5 blocks (26 and up) into factory/pipeline/consolidation/consolidation-table.json.
The rows of blocks 21-25 (round 4, one stage) stay as they are. Round 5 ran per block on the stage that block was developed on, so unlike summarise_results.py this takes, per case,
the LATEST done record at N=20 that passed (exit 0) from consolidation/results.jsonl, whatever its stage (the stage is in the row's `out` build.json and in docs/sr1-status.md)."""
import json, re
from pathlib import Path
HERE = Path(__file__).resolve().parent; CONS = HERE.parent / "consolidation"
recs = {}
for l in (CONS / "results.jsonl").read_text().splitlines():
    j = json.loads(l)
    if "blocks-26-34/" not in j["case"] or not j.get("done") or j["n"] != 20 or j.get("exit") != 0 or not j.get("out"): continue
    recs[j["case"]] = j
rows = [r for r in json.loads((CONS / "consolidation-table.json").read_text()) if "blocks-26-34/" not in r["case"]]
for case, j in sorted(recs.items()):
    rows.append({"block": j["block"], "case": case, "n": 20, "exit": 0, "stage": j["stage"], "out": j["out"],
                 "summary": [x for x in j["tail"] if not re.match(r"\s+(semantic run|clock run|run) ", x) and "Deprecat" not in x and "getdata" not in x][-3:]})
(CONS / "consolidation-table.json").write_text(json.dumps(rows, indent=1))
by = {}
for r in rows:
    if "blocks-26-34/" in r["case"]: by.setdefault(r["block"], []).append((r["case"].split("/", 2)[2], r["stage"]))
for b, cs in sorted(by.items()): print(b, len(cs), sorted({s for _, s in cs}))
