#!/usr/bin/env python3
"""Layout rules regression (decisions L1-L8): every delivered case whose witness has an HStack or VStack with a Text, rerun at N=3 on ONE stage through the Sandbox.
Case lists: closure/run_final.py JOBS (the SR1 closure set) filtered by witness, plus the round 4-5 / wave 0 cases that passed in consolidation/results.jsonl.
  python3 run_regression.py <stage> [--list] [--only substring] [--tier closure|other]
Records go to results.jsonl here (one line per case: stage, case, n, exit, out, prior verdict, changed). Resumable: skips (case, stage) with a record."""
import json, re, subprocess, sys, time
from pathlib import Path
HERE = Path(__file__).resolve().parent; PIPE = HERE.parent
RENDERER = r"D:\Claude\swiftright\.factory-work\inputs\renderer-0.7-baseline-22ad719b\swiftright_render.dll"


def witness(case):
    d = PIPE / case / "mac-source"
    return "\n".join(x.read_text() for x in d.rglob("*.swift") if "CaptureHost" not in x.name)


def selected():
    src = (PIPE / "closure/run_final.py").read_text(); src = src[:src.index("def main():")]
    ns = {"__file__": str(PIPE / "closure/run_final.py")}; exec(compile(src, "rf", "exec"), ns)
    closure = [(l, c) for l, c, _ in ns["JOBS"]]
    cset = {c for _, c in closure}
    has = lambda t: re.search(r"\b(HStack|VStack)\b", t) and re.search(r"\bText\(", t)
    tier1 = [(l, c, "closure") for l, c in closure if has(witness(c))]
    passing = {}
    for line in (PIPE / "consolidation/results.jsonl").read_text().splitlines():
        j = json.loads(line)
        if j.get("exit") == 0 and j.get("done"): passing[j["case"]] = j
    tier2 = [(passing[c]["block"], c, "other") for c in sorted(passing) if c not in cset and (PIPE / c / "mac-source").is_dir() and has(witness(c))]
    return tier1 + tier2


def prior(case):
    """The last recorded verdict of the case before this lane: closure (final stage 6459bb8cd) or consolidation."""
    for f in ("closure/results.jsonl", "consolidation/results.jsonl"):
        last = None
        for line in (PIPE / f).read_text().splitlines():
            j = json.loads(line)
            if j.get("case") == case and j.get("done"): last = j
        if last: return dict(file=f, stage=last["stage"], n=last["n"], exit=last["exit"])
    return None


def main():
    stage = sys.argv[1]
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    tier = sys.argv[sys.argv.index("--tier") + 1] if "--tier" in sys.argv else None
    jobs = [j for j in selected() if (not only or only in j[1]) and (not tier or j[2] == tier)]
    if "--list" in sys.argv:
        for l, c, t in jobs: print(t, l, c)
        print(len(jobs)); return
    res = HERE / "results.jsonl"; done = set()
    if res.exists():
        for line in res.read_text().splitlines():
            j = json.loads(line)
            if j["stage"] == stage and j.get("done"): done.add(j["case"])
    for label, case, t in jobs:
        if case in done: continue
        t0 = time.time()
        r = subprocess.run([sys.executable, str(PIPE.parent / "tools/pair.py"), str(PIPE / case), "--runs", "3", "--stage", stage, "--renderer", RENDERER, "--sandbox", "--scale-guard", "strict"], capture_output=True, text=True)
        out = r.stdout + r.stderr
        m = re.search(r"out=(\S+)", out); p = prior(case)
        rec = {"stage": stage, "tier": t, "block": label, "case": case, "n": 3, "exit": r.returncode, "out": m.group(1) if m else None, "secs": round(time.time() - t0),
               "prior": p, "changed": (p is not None and (p["exit"] == 0) != (r.returncode == 0)), "done": m is not None,
               "tail": [l for l in out.splitlines() if "Deprecat" not in l and "return [" not in l and not re.match(r"\s+(semantic run|clock run|run|block run) ", l)][-6:]}
        with res.open("a") as f: f.write(json.dumps(rec) + "\n")
        print(t, label, case, "exit", r.returncode, rec["secs"], "s", "CHANGED" if rec["changed"] else "", flush=True)


main()
