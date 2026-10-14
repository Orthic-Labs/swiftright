#!/usr/bin/env python3
"""Resumable checker for the W08 long-run retry test (feed-down that stays down; guard retry ladder +2, +5, +15, +60 min, hourly to 24 h after the first failure, then one attempt per 24 h).

  python3 longrun_check.py            take a snapshot from the Sandbox (read-only `client.py command`), save it under snapshots/, print the summary
  python3 longrun_check.py --offline  summarise the saved snapshots only (no Sandbox access)

State lives in this folder: snapshots/<UTC>.json (raw guard files + repair.log at that time). Nothing else is needed to resume; run it at any time, any number of times. The newest snapshot's repair.log is the
source of truth (the log is append-only), earlier snapshots only show what had been seen when. It never touches the Sandbox state and queues one small job (a lane that is using the worker delays it, nothing more)."""
import argparse, json, re, subprocess, sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
CLIENT = HERE.parents[4] / "factory/tools/sandbox/client.py"
LADDER = [2, 5, 15, 60]
TS = re.compile(r"^(\d{4}-\d\d-\d\dT[\d:.]+(?:[+-]\d\d:\d\d|Z))\s+\[(\w+)\]\s+(.*)$")


def parse_ts(s):
    s = re.sub(r"(\.\d{6})\d+", r"\1", s)
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def take_snapshot():
    script = (HERE / "guard-snapshot.ps1").read_text()
    r = subprocess.run([sys.executable, str(CLIENT), "command", script, "--out", str(HERE / ".cmd-out")], capture_output=True, text=True, timeout=900)
    text = r.stdout
    m = re.search(r"JSON-BEGIN\s*(\{.*\})\s*JSON-END", text, re.S)
    if not m:
        sys.exit("no snapshot in the command output (is the worker up? `client.py status`)\n" + (text + r.stderr)[-1500:])
    snap = json.loads(m.group(1))
    (HERE / "snapshots").mkdir(exist_ok=True)
    name = re.sub(r"[^0-9TZ]", "", snap["nowUtc"])[:15] + "Z.json"
    (HERE / "snapshots" / name).write_text(json.dumps(snap, indent=1))
    return snap


def summarise(snap):
    out = []
    runs, cur = [], None
    for line in snap["repairLog"]:
        m = TS.match(line)
        if not m:
            continue
        t, who, msg = parse_ts(m.group(1)), m.group(2), m.group(3)
        if who != "repair":
            continue
        if "package NOT healthy" in msg or "ignored:" in msg or "another repair run is active" in msg:
            cur = {"start": t, "outcome": None, "retry": None}
            runs.append(cur)
        elif cur is not None:
            mr = re.match(r"retry (\d+) scheduled in (\d+) min at (\S+)(.*)", msg)
            if mr:
                cur["retry"] = (int(mr.group(1)), int(mr.group(2)), mr.group(3), "daily" in mr.group(4))
            if msg.startswith(("FAILED", "REPAIRED", "HEALTHY", "REFUSED")):
                cur["outcome"] = msg.split(" ", 1)[0].rstrip(":")
    out.append(f"snapshot {snap['nowUtc']}  package={snap['packages']}  feed_up={snap['feedUp']}  guard_file_sha256={snap.get('guardFileSha256')}")
    if snap.get("task"):
        tk = snap["task"]
        out.append(f"task {tk['name']} state={tk['state']} lastRun={tk['lastRun']} lastResult={tk['lastResult']} nextRun={tk['nextRun']} triggers={tk['triggers']}")
    else:
        out.append("task: NOT PRESENT")
    rj = json.loads(snap["retry.json"]) if snap.get("retry.json") else None
    lr = json.loads(snap["last-result.json"]) if snap.get("last-result.json") else None
    out.append(f"retry.json: {rj}")
    out.append(f"last-result.json: status={lr and lr.get('status')} attemptLaunched={lr and lr.get('attemptLaunched')} launchFailure={lr and lr.get('launchFailure')!r} lastLaunchUtc={lr and lr.get('lastLaunchUtc')} guardSha256Lf={lr and lr.get('guardSha256Lf')}")
    out.append("")
    out.append(f"{'run':>3}  {'start (log tz)':<26} {'outcome':<8} {'since first':>12} {'gap from prev':>14} {'expected gap':>13}  scheduled next")
    first = runs[0]["start"] if runs else None
    prev = None
    for i, r in enumerate(runs, 1):
        gap = (r["start"] - prev["start"]) if prev else None
        exp = ""
        if prev and prev["retry"]:
            n, delay, _, daily = prev["retry"]
            exp = f"{delay} min" + (" (daily)" if daily else "")
        nxt = "-" if not r["retry"] else f"#{r['retry'][0]} in {r['retry'][1]} min at {r['retry'][2]}" + (" daily" if r["retry"][3] else "")
        since = str(r["start"] - first).split(".")[0] if first else ""
        gaps = "-" if gap is None else f"{gap.total_seconds() / 60:.1f} min"
        out.append(f"{i:>3}  {r['start'].isoformat(timespec='seconds'):<26} {str(r['outcome']):<8} {since:>12} {gaps:>14} {exp:>13}  {nxt}")
        prev = r
    fired = {1 + k: any(r["retry"] and r["retry"][0] == k and r["retry"][1] == LADDER[k - 1] for r in runs) for k in range(1, 5)}
    out.append("")
    out.append("ladder steps scheduled as designed (+2, +5, +15, +60): " + ", ".join(f"+{LADDER[k - 1]}={'yes' if fired[1 + k] else 'not yet'}" for k in range(1, 5)))
    hourly = [r for r in runs if r["retry"] and r["retry"][0] > 4 and not r["retry"][3]]
    daily = [r for r in runs if r["retry"] and r["retry"][3]]
    out.append(f"hourly attempts so far: {len(hourly)}   daily-mode attempts so far: {len(daily)}   (first failure + 24 h = " + (str(first + timedelta(hours=24)) if first else "n/a") + ")")
    out.append("fired attempts follow their schedule when 'gap from prev' is close to 'expected gap' (a run takes about 15-25 s before it schedules the next, so the gap is the delay plus that, plus up to ~10 s of Task Scheduler latency).")
    out.append("PASS criteria: ladder +2/+5/+15/+60, then hourly until first failure + 24 h, then retry.json dailyMode=true with one attempt per 24 h; package stays NeedsRemediation (feed stays down); no attempt launched an installer (attemptLaunched=false).")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--offline", action="store_true")
    a = ap.parse_args()
    if a.offline:
        files = sorted((HERE / "snapshots").glob("*.json"))
        if not files:
            sys.exit("no snapshots yet")
        snap = json.loads(files[-1].read_text())
    else:
        snap = take_snapshot()
    print(summarise(snap))


if __name__ == "__main__":
    main()
