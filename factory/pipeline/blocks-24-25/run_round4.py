#!/usr/bin/env python3
"""SR1 round 4 driver: every blocks-24-25 case at N=20 on ONE stage through the Sandbox, one results.jsonl record per case (same record format as
consolidation/run_all.py, so the consolidation table and docs/proven-controls.json read it). Resumable: skips (case, N) already done for the stage.
  python3 run_round4.py <stage> [--only substring] [--runs N]"""
import json, re, subprocess, sys, time
from pathlib import Path
HERE = Path(__file__).resolve().parent; PIPE = HERE.parent
RENDERER = r"D:\Claude\swiftright\.factory-work\inputs\renderer-0.7-baseline-22ad719b\swiftright_render.dll"
LABELS = {"swiftui.list-row-style": "24 list-row-style", "swiftui.font-custom": "25 font-custom"}


def main():
    stage = sys.argv[1]
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    n = int(sys.argv[sys.argv.index("--runs") + 1]) if "--runs" in sys.argv else 20
    res = PIPE / "consolidation/results.jsonl"
    done = set()
    mac_only = "--mac-only" in sys.argv
    force = "--force" in sys.argv or mac_only in sys.argv   # rerun cases that already passed (new Mac host pin, changed steps)
    if res.exists():
        for line in res.read_text().splitlines():
            j = json.loads(line)
            if not force and j["stage"] == stage and j.get("done") and j.get("exit") == 0: done.add((j["case"], j["n"]))
    for group, label in LABELS.items():
        for c in sorted((HERE / group).iterdir()):
            case = f"blocks-24-25/{group}/{c.name}"
            if not (c / "mac-source").is_dir() or (case, n) in done or (only and only not in case): continue
            t = time.time()
            if mac_only:
                # re-capture the Mac side (new host, decision C12 pin) against the Windows captures of the passing run on this stage, in the same run directory
                prev = [json.loads(l) for l in res.read_text().splitlines()]
                prev = [j for j in prev if j["stage"] == stage and j["case"] == case and j["n"] == n and j.get("exit") == 0 and j.get("out")]
                if not prev: continue
                cmd = [sys.executable, str(PIPE.parent / "tools/pair.py"), str(c), "--runs", str(n), "--stage", stage, "--skip-windows", "--out", prev[-1]["out"]]
            else:
                cmd = [sys.executable, str(PIPE.parent / "tools/pair.py"), str(c), "--runs", str(n), "--stage", stage, "--renderer", RENDERER, "--sandbox"]
            r = subprocess.run(cmd, capture_output=True, text=True)
            out = r.stdout + r.stderr
            m = re.search(r"out=(\S+)", out)
            rec = {"stage": stage, "block": label, "case": case, "n": n, "exit": r.returncode, "out": m.group(1) if m else None, "secs": round(time.time() - t),
                   "macRerun": mac_only, "tail": [l for l in out.splitlines() if "Deprecat" not in l and "return [" not in l][-6:], "done": True}
            with res.open("a") as f: f.write(json.dumps(rec) + "\n")
            print(label, case, n, "exit", r.returncode, rec["secs"], "s", flush=True)


main()
