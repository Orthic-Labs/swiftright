#!/usr/bin/env python3
"""F2 driver: pair.py over a list of cases on ONE stage and ONE renderer through the shared Sandbox, a few cases at a time (the Windows builds of different cases overlap; the Sandbox
queue is FIFO and shared with other lanes, so capture jobs wait their turn: SANDBOX_QUEUE_WAIT_S is set for the client). One record per case in results.jsonl (resumable).

  run_f2.py --stage S --renderer-label r08 [--renderer WINPATH] --runs N [--workers K] [--cases new|rebase|all-substring ...] [--only substring]

--set new      the F2 cases of this directory (N=20 by convention)
--set rebase   the cases of rebaseline-set.json (N=3 by convention): every case whose Windows run draws Text through the measurer (list built by rebaseline_set.py)"""
import argparse, json, os, re, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
HERE = Path(__file__).resolve().parent; PIPE = HERE.parent; REPO = PIPE.parents[1]
R08 = r"D:\Claude\swiftright\.factory-work\inputs\renderer-0.8-0407efcb\swiftright_render_v08_0407efcb.dll"
R07 = r"D:\Claude\swiftright\.factory-work\inputs\renderer-0.7-baseline-22ad719b\swiftright_render.dll"
RES = HERE / "results.jsonl"


def cases(kind):
    if kind == "new":
        return [str(p.parent.relative_to(PIPE)) for p in sorted((HERE / "swiftui.system-font-f2").glob("*/mac-source"))]
    return json.loads((HERE / "rebaseline-set.json").read_text())


def one(case, a, done):
    if (case, a.runs) in done: return None
    t = time.time()
    cmd = [sys.executable, str(REPO / "factory/tools/pair.py"), str(PIPE / case), "--runs", str(a.runs), "--stage", a.stage, "--renderer", a.renderer, "--sandbox"]
    env = dict(os.environ, SANDBOX_QUEUE_WAIT_S=os.environ.get("SANDBOX_QUEUE_WAIT_S", "14400"))
    for attempt in range(3):   # the Sandbox client races when several jobs are submitted in the same second (Move-Item .part): a submit failure is retried, a gate verdict never is
        r = subprocess.run(cmd, capture_output=True, text=True, env=env)
        out = r.stdout + r.stderr
        if r.returncode == 0 or "out=" in out or "Move-Item" not in out: break
        time.sleep(5 + 7 * attempt)
    m = re.search(r"out=(\S+)", out)
    rec = {"stage": a.stage, "renderer": a.renderer_label, "case": case, "n": a.runs, "exit": r.returncode, "out": m.group(1) if m else None, "secs": round(time.time() - t),
           "tail": [l[:400] for l in out.splitlines() if "Deprecat" not in l and "getdata" not in l][-8:], "done": m is not None}
    with RES.open("a") as f: f.write(json.dumps(rec) + "\n")
    print(case, a.runs, "exit", r.returncode, rec["secs"], "s", flush=True)
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", required=True); ap.add_argument("--renderer", default=R08); ap.add_argument("--renderer-label", default="r08")
    ap.add_argument("--runs", type=int, default=20); ap.add_argument("--workers", type=int, default=3); ap.add_argument("--set", default="new", choices=["new", "rebase"])
    ap.add_argument("--only"); ap.add_argument("--force", action="store_true")
    ap.add_argument("--list", help="JSON list of case paths (relative to the pipeline dir) to run instead of --set")
    a = ap.parse_args()
    done = set()
    if RES.exists() and not a.force:
        for l in RES.read_text().splitlines():
            j = json.loads(l)
            if j["stage"] == a.stage and j["renderer"] == a.renderer_label and j.get("done") and j.get("exit") == 0: done.add((j["case"], j["n"]))
    todo = [c for c in (json.loads(Path(a.list).read_text()) if a.list else cases(a.set)) if not a.only or a.only in c]
    with ThreadPoolExecutor(a.workers) as ex:
        list(ex.map(lambda c: one(c, a, done), todo))


main()
