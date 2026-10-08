"""Batch summary: PresentMon v1 CSV + run-desktop.ps1 result file -> per-run table.

Usage: pm_an2.py <pm.csv> <result.txt> [exclude_pid ...]
Processes are matched to runs in launch order (one SwiftHost.exe per run).
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

runs = []
cur = None
for line in open(result_txt, encoding='utf-8', errors='replace'):
    m = re.match(r'=== RUN (\S+)', line)
    if m:
        cur = {'id': m.group(1)}
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
for i, run in enumerate(runs):
    if i >= len(order):
        print(f"{run['id']} | {run.get('fg')}/{run.get('vis')} | NO PRESENTMON ROWS")
        continue
    rs = by[order[i]]
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
          f"{pct(lat, 50):.2f}/{pct(lat, 95):.2f} | pid={order[i]} {' '.join(flags)}")
if len(order) > len(runs):
    print("extra pm processes:", order[len(runs):])
