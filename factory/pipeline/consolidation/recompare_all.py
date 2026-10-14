#!/usr/bin/env python3
"""Offline re-evaluation of every real run of the latest stage with the CURRENT gates, never in place.

  python3 recompare_all.py <stage> --scratch DIR [--trash DIR] [--only substring] [-j N] [--out results.json]

For each case in results.jsonl (latest done record on <stage>) the committed run dir (reports + run-01 PNGs) is COPIED into DIR, the files the trim
tool moved to the Trash (logs, AX/UIA dumps, run-02..N PNGs) are overlaid on the copy when --trash holds them, and `pair.py <case> --recompare <copy>` runs on
the copy. The committed run dir is never written. Prints one line per case and writes a JSON table (case, n, exit, gate lines)."""
import argparse, json, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PAIR = ROOT / "factory/tools/pair.py"


def latest(stage):
    rec = {}
    for l in (HERE / "results.jsonl").read_text().splitlines():
        j = json.loads(l)
        if j["stage"] == stage and j.get("done"):
            rec[j["case"]] = j
    return rec


def one(job):
    case, j, scratch, trash = job
    src = Path(j["out"])
    rel = src.relative_to(ROOT)
    dst = scratch / case.replace("/", "__")
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    if trash and (trash / rel).is_dir():
        shutil.copytree(trash / rel, dst, dirs_exist_ok=True)
    n = len({p.name[:6] for p in (dst / "mac").glob("run-*.png")})
    r = subprocess.run([sys.executable, str(PAIR), str(ROOT / "factory/pipeline" / case), "--recompare", str(dst)], capture_output=True, text=True)
    lines = [l for l in (r.stdout + r.stderr).splitlines() if "Deprecat" not in l and "return [" not in l]
    return dict(case=case, runs=n, committedExit=j["exit"], exit=r.returncode, tail=lines[-6:], fails=[l.strip()[:300] for l in lines if "FAIL" in l or "Traceback" in l][:8])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stage"); ap.add_argument("--scratch", required=True); ap.add_argument("--trash"); ap.add_argument("--only"); ap.add_argument("-j", type=int, default=4); ap.add_argument("--out", default="recompare-results.json")
    a = ap.parse_args()
    scratch = Path(a.scratch); scratch.mkdir(parents=True, exist_ok=True)
    trash = Path(a.trash) if a.trash else None
    jobs = [(c, j, scratch, trash) for c, j in sorted(latest(a.stage).items()) if not a.only or a.only in c]
    with ThreadPoolExecutor(a.j) as ex:
        res = list(ex.map(one, jobs))
    for r in res:
        print(("ok  " if r["exit"] == 0 else "FAIL"), f"(committed {r['committedExit']})", r["runs"], r["case"])
    Path(a.out).write_text(json.dumps(res, indent=1))
    bad = [r for r in res if r["exit"]]
    print(f"cases={len(res)} pass={len(res) - len(bad)} fail={len(bad)}; changed vs committed verdict: {[r['case'] for r in res if (r['exit'] == 0) != (r['committedExit'] == 0)]}")


if __name__ == "__main__":
    main()
