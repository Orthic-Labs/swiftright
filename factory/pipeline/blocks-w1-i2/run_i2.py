#!/usr/bin/env python3
"""Runs the wave 1 I2 cases through factory/tools/pair.py (Mac ImageRenderer host and Windows Sandbox) and the resample gate, one case at a time, resumable.
  run_i2.py <stage> cal   [--n 3]          the calibration pages: report-only (the basis of the tolerance in tolerances.json)
  run_i2.py <stage> gate  [--n 20]         the gating cases against tolerances.json (make_cases.py must have been re-run after tolerances.json was written)
  run_i2.py <control-stage> control <name> [--n 3] [--cases ratios-alpha-v1,...]   a negative control: the gate must FAIL on every case
Appends one JSON line per (case, N, stage) to results.jsonl in this directory; skips a line already recorded as completed. The Sandbox is shared: each case is a queued job (client.py); never reset it."""
import json, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
GROUPS = {"cal": "swiftui.image-calibration", "gate": "swiftui.image-layout"}


def cases(kind):
    return sorted(p.name for p in (HERE / GROUPS[kind]).iterdir() if (p / "layout.json").is_file())


def done(stage, case, n, kind):
    f = HERE / "results.jsonl"
    if not f.is_file(): return False
    return any(json.loads(l).get("stage") == stage and json.loads(l).get("case") == case and json.loads(l).get("n") == n and json.loads(l).get("kind") == kind for l in f.read_text().splitlines() if l.strip())


def run(stage, kind, case, n, group):
    cdir = HERE / group / case
    t0 = time.time()
    p = subprocess.run([sys.executable, str(REPO / "factory/tools/pair.py"), str(cdir), "--runs", str(n), "--stage", stage, "--sandbox"], capture_output=True, text=True)
    out = next((l.split("out=", 1)[1].strip() for l in p.stdout.splitlines() if l.startswith("out=")), None)
    rec = dict(kind=kind, case=f"{group}/{case}".replace("swiftui.image-", ""), n=n, stage=stage, pairExit=p.returncode, out=out, secs=round(time.time() - t0), utc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
    if out is None:
        rec.update(completed=False, error=(p.stdout + p.stderr)[-600:])
    else:
        g = subprocess.run([sys.executable, str(REPO / "factory/tools/pair_resample_report.py"), str(cdir), out] + (["--calibrate"] if kind == "cal" else []), capture_output=True, text=True)
        rep = json.loads((Path(out) / "resample-report.json").read_text()) if (Path(out) / "resample-report.json").is_file() else {}
        rec.update(completed=True, gateExit=g.returncode, gateTail=g.stdout.strip().splitlines()[-2:], perLevel=rep.get("perLevel"), pairsPassing=sum(1 for r in rep.get("rows", []) if r["ok"]), pairs=len(rep.get("rows", [])))
    return rec


def main():
    stage, kind = sys.argv[1], sys.argv[2]
    n = int(sys.argv[sys.argv.index("--n") + 1]) if "--n" in sys.argv else (3 if kind in ("cal", "control") else 20)
    only = sys.argv[sys.argv.index("--cases") + 1].split(",") if "--cases" in sys.argv else None
    gk = "cal" if kind == "cal" else "gate"
    tag = kind + (":" + sys.argv[3] if kind == "control" else "")
    for case in cases(gk):
        if only and case not in only: continue
        if done(stage, case, n, tag): print("skip", case); continue
        rec = run(stage, tag, case, n, GROUPS[gk])
        with (HERE / "results.jsonl").open("a") as f: f.write(json.dumps(rec) + "\n")
        print(json.dumps({k: rec.get(k) for k in ("case", "n", "completed", "gateExit", "pairsPassing", "pairs", "secs")}), flush=True)


if __name__ == "__main__":
    main()
