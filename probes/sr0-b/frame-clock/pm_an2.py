"""Batch summary: PresentMon v1 CSV + run-desktop.ps1 result file -> per-run table.

Usage: pm_an2.py <pm.csv> <result.txt> [exclude_pid ...]
Processes are matched to runs by first-present time vs run start (assumes run 1 was captured).
"""
import csv, re, sys

pm_csv, result_txt, *exclude = sys.argv[1:]
rows = list(csv.DictReader(open(pm_csv, newline='', encoding='utf-8-sig')))
by = {}
for r in rows:
    if r['ProcessID'] in exclude:
        continue
    by.setdefault(r['ProcessID'], []).append(r)
order = sorted(by, key=lambda k: float(by[k][0]['TimeInSeconds']))
import datetime as _dt

runs = []
cur = None
for line in open(result_txt, encoding='utf-8', errors='replace'):
    m = re.match(r'=== RUN (\S+) start=(\S+?)[+-]\d\d:\d\d', line)
    if m:
        cur = {'id': m.group(1), 'start': _dt.datetime.fromisoformat(m.group(2)[:26])}
        runs.append(cur)
    m = re.match(r'focus_samples: total=(\d+) window_visible=(\d+) window_foreground=(\d+)', line)
    if m and cur:
        cur['vis'], cur['fg'] = int(m.group(2)), int(m.group(3))
    m = re.match(r'verdict=(\w+)', line)
    if m and cur:
        cur['verdict'] = m.group(1)


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def pct(a, p):
    a = sorted(a)
    return a[min(len(a) - 1, int(round(p / 100 * (len(a) - 1))))] if a else float('nan')


print(f"pm_processes={len(order)} runs={len(runs)} excluded={exclude}")
print("run | fg/vis | presents | dropped | disp p50/p95/p99 ms (n) | between-presents p95 | until_displayed p50/p95 | flags")
# Match each run to the PresentMon process whose first present is closest to the run's launch offset.
# Anchor: the first run with a process within 4 s of the first process (assumes run 1 was captured).
anchor = float(by[order[0]][0]['TimeInSeconds']) if order else 0.0
used = set()
for i, run in enumerate(runs):
    exp = anchor + (run['start'] - runs[0]['start']).total_seconds()
    cand = [p for p in order if p not in used and abs(float(by[p][0]['TimeInSeconds']) - exp) < 4]
    if not cand:
        print(f"{run['id']} | {run.get('fg')}/{run.get('vis')} | NO PRESENTMON ROWS")
        continue
    pid = cand[0]; used.add(pid); order_i = pid
    rs = by[pid]
    # within-workload display changes only: drop gaps > 100 ms (idle phases have no presents by design)
    disp = [x for x in (num(r.get('msBetweenDisplayChange')) for r in rs) if x and 0 < x < 100]
    pres = [x for x in (num(r.get('msBetweenPresents')) for r in rs) if x is not None and x < 100]
    lat = [x for x in (num(r.get('msUntilDisplayed')) for r in rs) if x and x > 0]
    dropped = sum(1 for r in rs if r.get('Dropped') == '1')
    flags = []
    if run.get('vis') and run['fg'] < 0.95 * run['vis']:
        flags.append('FG<95%')
    if run.get('verdict') != 'PASS':
        flags.append(f"probe={run.get('verdict')}")
    print(f"{run['id']} | {run.get('fg')}/{run.get('vis')} | {len(rs)} | {dropped} | "
          f"{pct(disp, 50):.3f}/{pct(disp, 95):.3f}/{pct(disp, 99):.3f} ({len(disp)}) | {pct(pres, 95):.3f} | "
          f"{pct(lat, 50):.2f}/{pct(lat, 95):.2f} | pid={order_i} {' '.join(flags)}")
extra = [p for p in order if p not in used]
if extra:
    print("unmatched pm processes:", extra)
