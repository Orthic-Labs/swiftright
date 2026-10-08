"""SR0-B batch-4 analysis: PID-joined PresentMon rows + harness v3 result file.

Usage: pm_an3.py <pm-batch4.csv> <result-desktop-v3-*.txt> <pm-batch4.console.txt>

Order of output:
  1. capture integrity (must pass before any budget claim): rows per harness PID, QPC join check,
     ETW status counters and loss warnings from the PresentMon console file.
  2. per-run table (valid and disturbed runs both printed, nothing dropped).
  3. per-variant budget verdict over valid runs (INVESTIGATION.md, Pass criteria).
  4. pairwise rank-sum tests on per-run displayed p95, only with >= 20 valid runs per variant.
Standard library only.
"""
import csv
import math
import re
import statistics
import sys

FRAME_MS = 16.664
BUDGET_P95_MS = 16.764          # §11 rev 1: 16.664 + 0.1
MISSED_MS = 1.5 * FRAME_MS      # 24.996
MIN_ROWS = 355
QPC_HZ_DEFAULT = 10_000_000

if len(sys.argv) != 4:
    print(__doc__)
    sys.exit(2)
pm_csv, result_txt, console_txt = sys.argv[1:4]

# ---------- harness result ----------
runs = {}
order = []
skips = []
qpc_hz = QPC_HZ_DEFAULT
cur = None
for line in open(result_txt, encoding='utf-8', errors='replace'):
    line = line.rstrip('\r\n')
    m = re.match(r'=== RUN (\S+) start=', line)
    if m:
        cur = m.group(1)
        order.append(cur)
        runs[cur] = {'changes': [], 'pid': None}
        continue
    m = re.match(r'skip_run id=(\S+) reason=(\S+)', line)
    if m:
        skips.append((m.group(1), m.group(2)))
        continue
    m = re.search(r'qpc_freq=(\d+)', line)
    if m and line.startswith('[frame-clock] monitor'):
        qpc_hz = int(m.group(1))
        continue
    m = re.match(r'pid run=(\S+) pid=(\d+) start_utc=\S+ qpc_start=(\d+) creation=(\S+)', line)
    if m and m.group(1) in runs:
        runs[m.group(1)].update(pid=m.group(2), qpc_start=int(m.group(3)), creation=m.group(4))
        continue
    m = re.match(r'pid_exit run=(\S+) pid=(\d+) qpc_end=(\d+) exit=(-?\d+)', line)
    if m and m.group(1) in runs:
        runs[m.group(1)].update(qpc_end=int(m.group(3)), exit=int(m.group(4)))
        continue
    m = re.match(r'window_ticks ws=(\d+) we=(\d+)', line)
    if m and cur:
        runs[cur].update(ws=int(m.group(1)), we=int(m.group(2)))
        continue
    m = re.match(r'run_state id=(\S+) valid=([01]) reason=(\S+) workload_samples=(\d+) probe_fg_wl=(\d+)', line)
    if m and m.group(1) in runs:
        runs[m.group(1)].update(valid=m.group(2) == '1', reason=m.group(3), wl_samples=int(m.group(4)))
        continue
    m = re.match(r'change run=(\S+) t=\+([\d.]+)s fg=(.*?) probe_fg=(\d)', line)
    if m and m.group(1) in runs:
        runs[m.group(1)]['changes'].append((float(m.group(2)), int(m.group(4)), line))

# ---------- capture integrity: console ----------
with open(console_txt, encoding='utf-8', errors='replace') as f:
    console = f.read().splitlines()
etw = [l for l in console if '[ETW Status]' in l]
lost_lines = [l for l in console if '[ETW Status]' not in l and re.search(r'lost', l, re.I)]
unrecognised = [l for l in console if re.search(r'unrecogni|unknown option|invalid option', l, re.I)]
etw_last = etw[-1] if etw else None
counters = {}
if etw_last:
    for k in ('EventsLost', 'BuffersLost', 'OverflowedPresents'):
        m = re.search(k + r'=(\d+)', etw_last)
        counters[k] = int(m.group(1)) if m else None
# --track_etw_status is not in PresentMon 2.6.0 (batch 4 drops it). Without the status line only the
# exit warnings ("ETW events/buffers were lost") can show loss, so say so explicitly.
if etw_last:
    console_ok = all(v == 0 for v in counters.values()) and not lost_lines and not unrecognised
else:
    console_ok = not lost_lines and not unrecognised
    print('NOTE: no [ETW Status] line (flag absent in 2.6.0); loss judged from exit warnings only')

# ---------- capture: CSV ----------
with open(pm_csv, newline='', encoding='utf-8-sig') as f:
    rd = csv.DictReader(f)
    header = rd.fieldnames or []
    rows = list(rd)
qcol = next((c for c in ('CPUStartQPC', 'QPCTime') if c in header), None)
print('== capture integrity ==')
print(f'csv_header_time_columns: qpc={qcol} seconds={"TimeInSeconds" in header} rows_total={len(rows)}')
if qcol is None:
    print('FATAL: no QPC column in the CSV (capture needs --qpc_time); PID join by QPC is impossible.')
    print('header:', ','.join(header))
    sys.exit(2)
print(f'PresentMon console: etw_status_last={etw_last if etw_last else "NONE"}')
print(f'console counters={counters} lost_lines={len(lost_lines)} unrecognised_flag={len(unrecognised)}')
for l in lost_lines[:10]:
    print('  lost:', l)
print(f'console_ok={console_ok}')

by_pid = {}
for r in rows:
    if r.get('Application') != 'SwiftHost.exe':
        continue
    by_pid.setdefault(r['ProcessID'], []).append(r)
for k in by_pid:
    by_pid[k].sort(key=lambda r: int(r[qcol]))

rows_ok = True
join_ok = True
pid_seen = {}
for rid in order:
    run = runs[rid]
    pid = run.get('pid')
    if pid is None:
        print(f'{rid}: no pid line in result file (harness v2 output?)')
        rows_ok = False
        continue
    pid_seen.setdefault(pid, []).append(rid)
    rs = by_pid.get(pid, [])
    status = 'OK' if len(rs) >= MIN_ROWS else 'FAIL'
    if status == 'FAIL':
        rows_ok = False
    extra = ''
    if rs:
        first = int(rs[0][qcol]); last = int(rs[-1][qcol])
        d0 = (first - run['qpc_start']) * 1000 / qpc_hz
        d1 = (last - run['qpc_end']) * 1000 / qpc_hz
        extra = f' first_vs_start_ms={d0:.1f} last_vs_end_ms={d1:.1f}'
        if not (d0 >= -2000 and d1 <= 2000):  # first present not before start-2 s, last not after end+2 s
            join_ok = False
            extra += ' JOIN-OUT-OF-RANGE'
    else:
        join_ok = False
    print(f'  {rid} pid={pid} rows={len(rs)} {status}{extra}')
dups = {p: v for p, v in pid_seen.items() if len(v) > 1}
if dups:
    print('duplicate pids across runs (PID reuse?):', dups)
unmatched = [p for p in by_pid if p not in pid_seen]
if unmatched:
    print('SwiftHost pids in CSV with no harness run:', unmatched)
capture_ok = rows_ok and join_ok and console_ok
print(f'CAPTURE INTEGRITY: {"PASS" if capture_ok else "FAIL - budget claims are inconclusive for the affected runs"}')
print()

# ---------- per-run stats ----------
def pct(v, p):
    """Nearest-rank percentile, same convention as swr_report (ceil(p*n))."""
    if not v:
        return float('nan')
    s = sorted(v)
    return s[max(1, min(len(s), math.ceil(p * len(s)))) - 1]

def ac1(seq):
    if len(seq) < 3:
        return float('nan')
    dev = [x - FRAME_MS for x in seq]
    mu = sum(dev) / len(dev)
    den = sum((d - mu) ** 2 for d in dev) or 1.0
    return sum((dev[i] - mu) * (dev[i + 1] - mu) for i in range(len(dev) - 1)) / den

print('== per run (valid=0 runs are reported, never dropped) ==')
print('run | valid | reason | rows | dropped all/win | disp p50/p95/p99/max | min/p1/p5 | missed>24.996 | long->2T pairs | lag1 ac | first-ws ms | last-we ms | drops by probe_fg (segment)')
stats = {}
for rid in order:
    run = runs[rid]
    if run.get('pid') is None or run.get('ws') is None:
        print(f'{rid} | - | no-window-or-pid | - | - | - | - | - | - | - | - | - | -')
        continue
    rs = sorted(by_pid.get(run['pid'], []), key=lambda r: int(r[qcol]))
    ws, we = run['ws'], run['we']
    inwin = [r for r in rs if ws <= int(r[qcol]) <= we]
    drop_all = sum(1 for r in rs if r.get('Dropped') == '1')
    drop_win = [r for r in inwin if r.get('Dropped') == '1']
    seq = []
    for r in inwin:
        v = r.get('msBetweenDisplayChange', '')
        if v not in ('', 'NA'):
            x = float(v)
            if 0 < x < 100:
                seq.append(x)
    s = sorted(seq)
    p95 = pct(seq, 0.95)
    missed = sum(1 for x in seq if x > MISSED_MS)
    long_idx = [i for i, x in enumerate(seq) if x > 16.8 and i + 1 < len(seq)]
    near2t = sum(1 for i in long_idx if abs(seq[i] + seq[i + 1] - 2 * FRAME_MS) < 0.3)
    pair_txt = f'{near2t}/{len(long_idx)}'
    # drops by harness segment (probe_fg state in effect when the present was taken)
    segs = sorted((run['qpc_start'] + int(t * qpc_hz), fg) for t, fg, _ in run.get('changes', []))
    tally = {}
    for r in drop_win:
        q = int(r[qcol])
        state = 'pre'
        for sq, fg in segs:
            if sq <= q:
                state = str(fg)
        tally[state] = tally.get(state, 0) + 1
    drop_txt = ','.join(f'fg{k}:{v}' for k, v in sorted(tally.items())) or '-'
    first_off = (int(rs[0][qcol]) - ws) * 1000 / qpc_hz if rs else float('nan')
    last_off = (int(rs[-1][qcol]) - we) * 1000 / qpc_hz if rs else float('nan')
    valid = run.get('valid', False)
    reason = run.get('reason', 'NA')
    print(f'{rid} | {int(valid)} | {reason} | {len(rs)} | {drop_all}/{len(drop_win)} | '
          f'{pct(seq,.5):.3f}/{p95:.3f}/{pct(seq,.99):.3f}/{(s[-1] if s else float("nan")):.3f} | '
          f'{(s[0] if s else float("nan")):.3f}/{pct(seq,.01):.3f}/{pct(seq,.05):.3f} | {missed} | {pair_txt} | '
          f'{ac1(seq):.3f} | {first_off:.1f} | {last_off:.1f} | {drop_txt}')
    variant = rid.rsplit('-', 1)[0]
    stats.setdefault(variant, []).append({'id': rid, 'valid': valid, 'p95': p95, 'missed': missed,
                                          'drops_win': len(drop_win)})
print()

# ---------- budget verdict ----------
print('== budget verdict (§11 rev 1, valid runs only) ==')
for v, lst in stats.items():
    vr = [x for x in lst if x['valid']]
    zero_missed = all(x['missed'] == 0 and x['drops_win'] == 0 for x in vr)
    p95_ok = all(x['p95'] <= BUDGET_P95_MS for x in vr)
    enough = len(vr) >= 9  # of 10 scheduled per variant; skipped launches count against it
    skipped = sum(1 for sid, _why in skips if sid.rsplit('-', 1)[0] == v)
    verdict = 'PASS' if (capture_ok and vr and zero_missed and p95_ok and enough) else 'NOT MET'
    print(f'{v}: launched={len(lst)} valid={len(vr)} skipped={skipped} zero_missed_valid={zero_missed} '
          f'p95<=16.764_valid={p95_ok} enough_valid(>=9 of 10)={enough} -> {verdict}')
print()

# ---------- variant comparisons ----------
print('== variant comparisons (per-run displayed p95, valid runs) ==')
def mann_whitney_p(a, b):
    n1, n2 = len(a), len(b)
    combined = sorted([(x, 0) for x in a] + [(x, 1) for x in b])
    ranks = {}
    i = 0
    while i < len(combined):
        j = i
        while j + 1 < len(combined) and combined[j + 1][0] == combined[i][0]:
            j += 1
        avg = (i + j) / 2 + 1
        for k in range(i, j + 1):
            ranks.setdefault(k, avg)
        i = j + 1
    r1 = sum(ranks[k] for k, (x, g) in enumerate(combined) if g == 0)
    u1 = r1 - n1 * (n1 + 1) / 2
    mu = n1 * n2 / 2
    sd = math.sqrt(n1 * n2 * (n1 + n2 + 1) / 12)
    z = (u1 - mu) / sd if sd else 0.0
    return math.erfc(abs(z) / math.sqrt(2))

names = sorted(stats)
for i in range(len(names)):
    for j in range(i + 1, len(names)):
        a = [x['p95'] for x in stats[names[i]] if x['valid'] and not math.isnan(x['p95'])]
        b = [x['p95'] for x in stats[names[j]] if x['valid'] and not math.isnan(x['p95'])]
        label = f'{names[i]} vs {names[j]}'
        if len(a) < 20 or len(b) < 20:
            print(f'{label}: no test (valid n={len(a)}/{len(b)}, need >= 20 each); no effect shown')
            continue
        p = mann_whitney_p(a, b)
        pooled = statistics.pstdev(a + b)
        diff = statistics.median(a) - statistics.median(b)
        shown = p < 0.05 and abs(diff) > pooled
        print(f'{label}: median diff={diff:+.4f} ms pooled_sd={pooled:.4f} p={p:.4f} -> '
              f'{"difference shown" if shown else "no effect shown"}')
