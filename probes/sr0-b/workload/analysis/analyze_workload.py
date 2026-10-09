"""SR0 workload analyzer (plan v2 lane R10): architecture.md section 11 "Decision budgets".

Usage:
  analyze_workload.py --os windows|macos --root <run-root> [--out <dir>] [--expect-runs 3] [--expect-scale 2.5 (windows) | 2.0 (macos)]
                      [--expect-rows N] [--key-rate K]    (default: the rows= / rate_hz= the harness recorded, else 200 / 10)
                      [--incremental <incremental.json>] [--light-root <run-root of --instr light runs>]
  analyze_workload.py --selftest [--selftest-keep <dir>]   (synthetic data; keep writes windows-good/, windows-resources/ and macos-good/ run sets)

Emits every section 11 threshold per run with PASS / FAIL, writes raw-sample CSVs and report.json / report.md under --out,
and prints one OVERALL line:
  OVERALL: PASS         every run, every threshold, and every validity gate passed
  OVERALL: FAIL         at least one threshold failed on a valid run set
  OVERALL: INCOMPLETE   PASS REFUSED: a run is missing or invalid, calibration is absent or out of bounds, the
                        UI-only incremental build record is absent, or the runs were not the full instrumentation level.
  (exit codes: 0 PASS, 1 FAIL, 2 INCOMPLETE, 3 usage)

Stress series (R10): the harness records the row count and key rate it ran with (`exe= ... rows= rate_hz=` in result-workload.txt; defaults 200 and
10 for older runs; --expect-rows / --key-rate override). The row-count thresholds follow it, and a run whose app did not honour the requested row count
(meta.json total_rows) is invalid. Thresholds themselves are unchanged: a stress run is a normal gated run at a different size.

Lost-key accounting: keys posted after measure_end are outside the run (the app has asked its window to close by then; r2 of 20261009-224605-full lost
its 694th key that way, posted 21.9 ms after the end). They are reported but may be unapplied; every key posted up to measure_end must be applied.

Resources (informational): <run>/resources.csv + resources-meta.json from scripts/sample-resources.ps1 (CPU, per-thread CPU, working set, private bytes,
handles, threads, GPU engine utilisation and memory per DXGI adapter, the adapter the process rendered on). report.json `resources`, report.md "Resources".
Only a private-bytes growth slope > 5 MB/min over the measured window is a threshold (R, leak flag); a pinned thread (>= 90% of a core) is a flag.

Standard library only (python 3.11, run with -I).

Clock model. Windows: app, PostMessage injector and PresentMon all use QPC ticks. Mac: app and recorder use CLOCK_UPTIME_RAW ns.
Percentiles are nearest-rank, ceil(p*n), the convention of swr_report and pm_an3.py.

Visible-response join (Windows, CONTRACT section 5; PresentMon display time on the QPC clock):
  1. inject.csv key k (PostMessage QPC before the call) <-> app inputs.csv row k+1 (text-store replace in the app). The app stamped
     each input with the commit that carried it: commit_end QPC and the renderer paint counter read right after the commit.
  2. The renderer paints and commits on one UI thread, so the first paint AFTER that counter value (paint P = paints_at_commit+1)
     includes the response. ticks.csv maps a paint to its QPC (the renderer's tick timestamp, taken at the end of the paint, just
     before its Present call; the tick row whose `paints` equals P, else the first row with paints > P, flagged).
  3. The response present is the first PresentMon present (PID match, displayed) whose CPU start QPC >= paint P's tick QPC - 2 ms.
     Rule A (first present starting at or after commit_end) is computed too; the LATER of A and the tick rule is used, so the
     join can only overstate latency. When no tick row exists the rule A present is used and the sample is flagged.
  4. Display QPC = CPU start QPC + msUntilDisplayed. Latency = display QPC - PostMessage QPC.
  Clock calibration (mandatory): |tick QPC - nearest PresentMon present start| over the measured window must have p95 <= 2 ms
  (it proves the app and PresentMon share the QPC domain and the tick-to-present map); otherwise the run set is INCOMPLETE.

Visible-response (Mac, CONTRACT section 5): keys.csv from SckRecorder: key post time (mach uptime ns, immediately before
CGEvent.postToPid) to the displayTime of the first ScreenCaptureKit frame whose response region changed. calibration.csv
(recorder-owned flipping window) must be present and valid; its floor is reported next to the raw latencies. PASS uses raw latencies.
"""
import csv
import json
import math
import os
import re
import statistics
import sys
import tempfile

LIMITS = {
    'bridge_input_p95_ms': 1.0, 'bridge_input_p99_ms': 2.0,
    'bridge_frame_p95_ms': 2.0, 'bridge_frame_p99_ms': 4.0,
    'visible_p95_ms': 50.0, 'visible_p99_ms': 100.0,
    'presentation_p95_margin_ms': 0.1, 'presentation_missed_factor': 1.5,
    'mainactor_p99_ms': 16.7,
    'clock_corr_p95_ms': 2.0, 'calibration_floor_p95_ms': 34.0,
}
KEY_CYCLE = 'mwqogdhbnk'
EXPECT_TOTAL_ROWS = 200
EXPECT_KEY_RATE = 10.0
LEAK_SLOPE_MB_PER_MIN = 5.0
PINNED_THREAD_PCT = 90.0
MIN_RESOURCE_SAMPLES = 20
MIN_MAINACTOR_SAMPLES = 5000
MIN_PM_ROWS_FRACTION = 0.9


def pct(values, p):
    """Nearest-rank percentile."""
    if not values:
        return float('nan')
    s = sorted(values)
    return s[max(1, min(len(s), math.ceil(p * len(s)))) - 1]


def read_csv(path):
    if not os.path.isfile(path):
        return None
    with open(path, newline='', encoding='utf-8-sig') as f:
        return list(csv.DictReader(f))


def read_json(path):
    if not os.path.isfile(path):
        return None
    try:
        with open(path, encoding='utf-8-sig') as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def num(v, default=None):
    try:
        if v is None or v == '':
            return default
        return float(v)
    except ValueError:
        return default


class Check:
    """One threshold evaluation. status: PASS | FAIL | INFO | MISSING (MISSING blocks PASS)."""

    def __init__(self, tid, name, run, value, limit, op, detail=''):
        self.tid, self.name, self.run, self.value, self.limit, self.op, self.detail = tid, name, run, value, limit, op, detail
        if value is None or (isinstance(value, float) and math.isnan(value)):
            self.status = 'MISSING'
        elif op == '<=':
            self.status = 'PASS' if value <= limit else 'FAIL'
        elif op == '==':
            self.status = 'PASS' if value == limit else 'FAIL'
        elif op == 'info':
            self.status = 'INFO'
        elif op == 'bool':
            self.status = 'PASS' if value else 'FAIL'
        else:
            self.status = 'FAIL'

    def row(self):
        return {'id': self.tid, 'name': self.name, 'run': self.run, 'value': self.value, 'limit': self.limit,
                'op': self.op, 'status': self.status, 'detail': self.detail}

    def line(self):
        v = self.value
        vs = f'{v:.4f}' if isinstance(v, float) else str(v)
        return f'THRESHOLD {self.tid:<4} {self.run:<4} {self.status:<7} {self.name}: {vs} (limit {self.op} {self.limit}) {self.detail}'.rstrip()


class RunReport:
    def __init__(self, rid):
        self.rid = rid
        self.checks = []
        self.invalid = []      # reasons this run is not a valid measurement (blocks PASS)
        self.notes = []
        self.flags = []        # informational findings (pinned thread, leak slope, sampler gaps); never block PASS on their own
        self.raw = {}          # name -> (header, rows)
        self.summary = {}

    def add(self, *a, **k):
        c = Check(*a, **k)
        self.checks.append(c)
        return c


def stats_block(values):
    return {'n': len(values), 'p50': pct(values, 0.5), 'p95': pct(values, 0.95), 'p99': pct(values, 0.99),
            'max': max(values) if values else float('nan')}


# ------------------------------------------------------------------ shared integrity

def integrity_checks(rr, integ, meta, expect_ops=True, expect_rows=EXPECT_TOTAL_ROWS):
    g = lambda k, d=None: integ.get(k, d)
    rr.add('W1', 'wrong-node edits', rr.rid, g('wrong_node_edits'), 0, '==')
    rr.add('W1', 'stale-owner result commits', rr.rid, g('stale_committed'), 0, '==')
    rr.add('W1', 'commits after window close', rr.rid, g('commits_after_close', 0) + g('commits_after_close_backend', 0), 0, '==')
    rr.add('W1', f'row count constant (min=max={expect_rows})', rr.rid, bool(g('rows_min') == expect_rows and g('rows_max') == expect_rows),
           True, 'bool', f"min={g('rows_min')} max={g('rows_max')}")
    ran_rows = meta.get('total_rows')
    if ran_rows is not None and int(ran_rows) != int(expect_rows):
        rr.invalid.append(f'app ran {ran_rows} rows, the harness asked for {expect_rows} (app build without --rows support?)')
    rr.add('W1', 'unique stable row ids', rr.rid, bool(g('unique_ids')), True, 'bool')
    rr.add('W1', 'run completed (app_exit complete, window closed)', rr.rid, bool(g('app_exit') == 'complete' and g('closed')), True, 'bool')
    rr.add('W1', 'cancellation exercised (stale results rejected > 0)', rr.rid, (g('stale_rejected') or 0) > 0, True, 'bool')
    rr.add('W1', 'interrupted animation exercised', rr.rid, (g('anim_interrupts') or 0) > 0, True, 'bool')
    total_s = (num(meta.get('warmup_s'), 10) + num(meta.get('measure_s'), 60))
    if expect_ops:
        started = (g('updates_started') or 0) + (g('inserts_started') or 0)
        want = 0.95 * 20.0 * total_s
        rr.add('W0', 'async ops delivered (>= 95% of 20/s)', rr.rid, bool(started >= want), True, 'bool',
               f"started={started} want>={want:.0f} skipped={g('ops_skipped')}")
        rr.add('W0', 'reorders delivered (>= 1/s)', rr.rid, bool((g('reorders') or 0) >= total_s - 3), True, 'bool', f"reorders={g('reorders')}")


def pin_checks(rr, meta, platform, expect_scale):
    if platform == 'windows':
        scale = num(meta.get('scale'))
        rr.add('P', 'DPI scale pinned', rr.rid, scale, expect_scale, '==')
        rr.add('P', 'window size pinned (960x640 DIP)', rr.rid, bool(meta.get('window_dip') == {'w': 960, 'h': 640}), True, 'bool')
        rr.add('P', 'ABI 0.6', rr.rid, bool(meta.get('abi_major') == 0 and meta.get('abi_minor') == 6), True, 'bool',
               f"abi={meta.get('abi_major')}.{meta.get('abi_minor')}")
        dbg = meta.get('debugger_present')
        rr.add('P', 'no debugger attached', rr.rid, None if dbg is None else (dbg in ('false', False, '0')), True, 'bool')
    else:
        rr.add('P', 'window size pinned (960x640 pt)', rr.rid, bool(meta.get('window_pt') == {'w': 960, 'h': 640}), True, 'bool')
        rr.add('P', 'release build', rr.rid, bool(meta.get('release_build')), True, 'bool')
    rr.add('P', 'full instrumentation level', rr.rid, meta.get('instr') == 'full', True, 'bool', f"instr={meta.get('instr')}")


# ------------------------------------------------------------------ Windows

def parse_harness(path):
    runs, hz = {}, None
    cur = None
    host = {}
    if not os.path.isfile(path):
        return None
    for line in open(path, encoding='utf-8', errors='replace'):
        line = line.rstrip('\r\n')
        m = re.match(r'=== RUN (\S+) start=', line)
        if m:
            cur = m.group(1)
            runs[cur] = {'valid': None, 'reason': 'no run_state', 'inject_ok_through': None}
            continue
        m = re.match(r'exe=.* rows=(\d+)', line)
        if m:
            host['rows'] = int(m.group(1))
        m = re.match(r'exe=.* rate_hz=([\d.]+)', line)
        if m:
            host['key_rate'] = float(m.group(1))
        m = re.match(r'exe=.* resources=(on|off)', line)
        if m:
            host['resources'] = m.group(1)
        m = re.match(r'host qpc_freq=(\d+)', line)
        if m:
            hz = int(m.group(1))
            m2 = re.search(r'refresh_hz=(\d+)', line)    # informational only; empty when the first video controller has no active mode
            host['refresh_hz'] = int(m2.group(1)) if m2 else None
        m = re.match(r'pid run=(\S+) pid=(\d+) start_utc=\S+ qpc_start=(\d+)', line)
        if m and m.group(1) in runs:
            runs[m.group(1)].update(pid=m.group(2), qpc_start=int(m.group(3)))
        m = re.match(r'pid_exit run=(\S+) pid=(\d+) qpc_end=(\d+) exit=(-?\d+)', line)
        if m and m.group(1) in runs:
            runs[m.group(1)].update(qpc_end=int(m.group(3)), exit=int(m.group(4)))
        m = re.match(r'run_state id=(\S+) valid=([01]) reason=(\S+)', line)
        if m and m.group(1) in runs:
            runs[m.group(1)].update(valid=m.group(2) == '1', reason=m.group(3))
        m = re.match(r'window run=(\S+) hwnd=\d+ foreground=(\S+) dpi=(\d+)', line)
        if m and m.group(1) in runs:
            runs[m.group(1)].update(foreground=m.group(2), dpi=int(m.group(3)))
        m = re.match(r'inject run=(\S+) sent=(\d+) fg_lost=(\d+) send_fail=(\d+)', line)
        if m and m.group(1) in runs:
            runs[m.group(1)].update(inject_sent=int(m.group(2)), fg_lost=int(m.group(3)), send_fail=int(m.group(4)))
            m2 = re.search(r' stop=(\S+)', line)
            m3 = re.search(r' key_deadline_ms_from_start=(\d+)', line)
            runs[m.group(1)].update(inject_stop=m2.group(1) if m2 else None, key_deadline_ms=int(m3.group(1)) if m3 else None)
        m = re.match(r'resources run=(\S+) rows=(\d+) sampler_exit=(\S+)', line)
        if m and m.group(1) in runs:
            runs[m.group(1)].update(resources_rows=int(m.group(2)), sampler_exit=m.group(3))
        m = re.match(r'sampler run=(\S+) start_failed=(.*)', line)
        if m and m.group(1) in runs:
            runs[m.group(1)].update(sampler_start_failed=m.group(2))
        if line.startswith('finished='):
            host['finished'] = True
    return {'runs': runs, 'qpc_hz': hz, 'host': host}


def load_presentmon(path):
    """PID -> list of (start_qpc, display_qpc|None, dropped, ms_between_display_change|None), per hz applied later."""
    if not os.path.isfile(path):
        return None, 'presentmon.csv missing'
    with open(path, newline='', encoding='utf-8-sig') as f:
        rd = csv.DictReader(f)
        header = rd.fieldnames or []
        qcol = next((c for c in ('CPUStartQPC', 'QPCTime') if c in header), None)
        if qcol is None:
            return None, 'no QPC column in presentmon.csv (needs --qpc_time): ' + ','.join(header)
        byp = {}
        for r in rd:
            if r.get('Application') != 'WorkloadWin.exe':
                continue
            q = num(r.get(qcol))
            if q is None:
                continue
            byp.setdefault(r.get('ProcessID'), []).append({
                'q': int(q), 'until': num(r.get('msUntilDisplayed')), 'dropped': r.get('Dropped') == '1',
                'between': num(r.get('msBetweenDisplayChange')), 'screen': num(r.get('ScreenTimeQPC'))})
    for k in byp:
        byp[k].sort(key=lambda r: r['q'])
    return byp, ''


def console_loss(path):
    if not os.path.isfile(path):
        return None
    text = open(path, encoding='utf-8', errors='replace').read()
    lost = [l for l in text.splitlines() if re.search(r'lost', l, re.I) and 'ETW Status' not in l]
    bad = [l for l in text.splitlines() if re.search(r'unrecogni|unknown option|invalid option', l, re.I)]
    return {'lost_lines': len(lost), 'bad_flag_lines': len(bad)}


# ------------------------------------------------------------------ resources (informational)

def nz(v, nd=3):
    """NaN-safe rounding for the JSON report (NaN -> None)."""
    return None if v is None or (isinstance(v, float) and math.isnan(v)) else round(v, nd)


def avg_peak(vals, nd=3):
    if not vals:
        return {'avg': None, 'peak': None, 'n': 0}
    return {'avg': nz(sum(vals) / len(vals), nd), 'peak': nz(max(vals), nd), 'n': len(vals)}


def linreg_slope(xs, ys):
    """Least-squares slope dy/dx (NaN when it cannot be fitted)."""
    n = len(xs)
    if n < 3 or len(ys) != n:
        return float('nan')
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx <= 0:
        return float('nan')
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx


def parse_top_threads(txt):
    """'2152[name]:6.1;21292:0' -> [(tid, name, pct_of_one_core)]"""
    out = []
    for part in (txt or '').split(';'):
        head, _, pct = part.strip().rpartition(':')
        m = re.match(r'(\d+)(?:\[(.*)\])?$', head)
        if m:
            out.append((int(m.group(1)), m.group(2) or '', num(pct, 0.0)))
    return out


GPU_GROUPS = ('3d', 'compute', 'copy', 'video', 'other')


def analyze_resources(rr, rdir, ms, me, hz, expected):
    """Informational resource section for one run from <run>/resources.csv (scripts/sample-resources.ps1), restricted to the measured window.
    Adds the leak threshold (R: private bytes growth slope) and flags (pinned thread, sampler gaps, GPU counters absent) to the run report."""
    rows = read_csv(f'{rdir}/resources.csv')
    meta = read_json(f'{rdir}/resources-meta.json') or {}
    if rows is None:
        rr.summary['resources'] = {'present': False, 'expected': expected}
        if expected:
            rr.flags.append('resources.csv absent although the harness was asked to sample (sampler failed to start or write)')
        return
    win = [r for r in rows if num(r.get('qpc')) is not None and ms <= num(r['qpc']) <= me]
    res = {'present': True, 'samples_total': len(rows), 'samples': len(win)}
    if len(win) < MIN_RESOURCE_SAMPLES:
        res['note'] = f'only {len(win)} samples in the measured window (need >= {MIN_RESOURCE_SAMPLES})'
        rr.flags.append(res['note'])
        rr.summary['resources'] = res
        if len(win) < 3:
            return
    col = lambda name: [v for v in (num(r.get(name)) for r in win) if v is not None]
    q0 = num(win[0]['qpc'])
    minutes = [(num(r['qpc']) - q0) / hz / 60.0 for r in win]
    dts = col('dt_s')
    res['period_s'] = nz(statistics.median(dts), 3) if dts else None
    res['total_cpu_pct'] = avg_peak(col('total_cpu_pct'), 2)
    res['max_core_pct'] = avg_peak(col('max_core_pct'), 2)
    res['proc_cpu_core_pct'] = avg_peak(col('proc_cpu_core_pct'), 2)    # 100 = one core fully busy
    res['proc_cpu_pct'] = avg_peak(col('proc_cpu_pct'), 3)              # of the whole machine
    res['sampler_cpu_core_pct'] = avg_peak(col('sampler_cpu_pct'), 2)   # the measurement's own overhead

    # threads: pinned core flag and the busiest threads (a thread outside the top 5 in a sample counts as 0 there)
    tstat = {}
    pinned = []
    for r in win:
        for tid, name, pct in parse_top_threads(r.get('top_threads')):
            t = tstat.setdefault(tid, {'tid': tid, 'name': name, 'sum': 0.0, 'peak': 0.0, 'n': 0})
            t['sum'] += pct
            t['peak'] = max(t['peak'], pct)
            t['n'] += 1
            if name and not t['name']:
                t['name'] = name
        pp = num(r.get('pinned_pct'), 0.0)
        if pp >= PINNED_THREAD_PCT and r.get('pinned_tid'):
            pinned.append((int(float(r['pinned_tid'])), pp))
    top = sorted(tstat.values(), key=lambda t: -t['sum'])[:5]
    res['top_threads'] = [{'tid': t['tid'], 'name': t['name'], 'avg_pct_of_core': nz(t['sum'] / len(win), 1), 'peak_pct_of_core': nz(t['peak'], 1)} for t in top]
    res['pinned_samples'] = len(pinned)
    res['pinned_threads'] = sorted({t for t, _ in pinned})
    if pinned:
        rr.flags.append(f"pinned core: thread(s) {', '.join(str(t) for t in sorted({t for t, _ in pinned}))} used >= {PINNED_THREAD_PCT:g}% of a core in "
                        f"{len(pinned)}/{len(win)} samples (peak {max(p for _, p in pinned):.0f}%)")

    # memory (MB), growth slope per minute over the measured window
    for key, colname in (('working_set_mb', 'working_set_bytes'), ('private_mb', 'private_bytes')):
        vals = [v / 1048576.0 for v in col(colname)]
        if len(vals) == len(win) and vals:
            d = avg_peak(vals, 2)
            d.update({'first': nz(vals[0], 2), 'last': nz(vals[-1], 2), 'growth': nz(vals[-1] - vals[0], 2),
                      'slope_mb_per_min': nz(linreg_slope(minutes, vals), 3)})
            res[key] = d
    for key, colname in (('handles', 'handles'), ('threads', 'threads')):
        vals = col(colname)
        if vals:
            res[key] = {'max': int(max(vals)), 'first': int(vals[0]), 'last': int(vals[-1]), 'growth': int(vals[-1] - vals[0])}
    slope = (res.get('private_mb') or {}).get('slope_mb_per_min')
    if slope is not None and len(win) >= MIN_RESOURCE_SAMPLES:
        c = rr.add('R', 'private bytes growth slope in the measured window (MB/min), leak flag', rr.rid, float(slope), LEAK_SLOPE_MB_PER_MIN, '<=',
                   f"n={len(win)} first={res['private_mb']['first']}MB last={res['private_mb']['last']}MB ws_slope={(res.get('working_set_mb') or {}).get('slope_mb_per_min')}MB/min")
        if c.status == 'FAIL':
            rr.flags.append(f'LEAK: private bytes grow {slope:.2f} MB/min (> {LEAK_SLOPE_MB_PER_MIN:g})')

    # GPU: per adapter, per engine type (summed over the process's engine instances of that type)
    names = {int(a['index']): a for a in (meta.get('adapters') or []) if isinstance(a, dict) and 'index' in a}
    idxs = sorted({m.group(1) for c in (rows[0].keys() if rows else []) for m in [re.match(r'gpu(\d+|x)_3d_pct$', c)] if m},
                  key=lambda x: (x == 'x', int(x) if x != 'x' else 0))
    adapters = []
    for ai in idxs:
        info = names.get(int(ai)) if ai != 'x' else None
        util = {g: avg_peak(col(f'gpu{ai}_{g}_pct'), 2) for g in GPU_GROUPS}
        busy = sum((util[g]['avg'] or 0.0) for g in GPU_GROUPS)
        ded = [v / 1048576.0 for v in col(f'gpu{ai}_ded_bytes')]
        shr = [v / 1048576.0 for v in col(f'gpu{ai}_shared_bytes')]
        adapters.append({'index': ai, 'name': (info or {}).get('name', 'unmapped LUID' if ai == 'x' else f'adapter {ai}'), 'luid': (info or {}).get('luid'),
                         'util_pct': util, 'busy_avg_pct': nz(busy, 2), 'dedicated_mb': avg_peak(ded, 1), 'shared_mb': avg_peak(shr, 1)})
    counter_rows = sum(1 for r in win if (num(r.get('gpu_n'), 0) or 0) > 0)
    used = None
    if adapters and counter_rows:
        by_busy = max(adapters, key=lambda a: a['busy_avg_pct'] or 0.0)
        if (by_busy['busy_avg_pct'] or 0.0) >= 0.05:
            used = {'index': by_busy['index'], 'name': by_busy['name'], 'luid': by_busy['luid'], 'basis': 'highest summed engine utilisation'}
        else:
            by_mem = max(adapters, key=lambda a: (a['dedicated_mb']['avg'] or 0.0) + (a['shared_mb']['avg'] or 0.0))
            if ((by_mem['dedicated_mb']['avg'] or 0.0) + (by_mem['shared_mb']['avg'] or 0.0)) > 0:
                used = {'index': by_mem['index'], 'name': by_mem['name'], 'luid': by_mem['luid'], 'basis': 'engines idle; largest GPU memory usage'}
    active = [a['name'] for a in adapters if (a['busy_avg_pct'] or 0.0) >= 0.5]
    res['gpu'] = {'adapters': adapters, 'adapter_used': used, 'adapters_active': active, 'counter_rows': counter_rows,
                  'enumeration': meta.get('adapter_enumeration', 'unknown')}
    if not counter_rows:
        rr.flags.append('GPU counters returned no instances for the process in the measured window (adapter used unknown)')
    elif used is None:
        rr.flags.append('GPU adapter used could not be determined (no engine activity or memory attributed to the process)')
    rr.summary['resources'] = res
    rr.raw['resources_window'] = (list(rows[0].keys()), [[r.get(k, '') for k in rows[0].keys()] for r in win])


def analyze_windows_run(rr, rdir, harness_run, hz, pm_rows, expect_scale, raw_dir, host=None, expect_rows=None, key_rate=None):
    if harness_run.get('valid') is not True:
        rr.invalid.append(f"harness run_state valid={harness_run.get('valid')} reason={harness_run.get('reason')}")
    meta = read_json(f'{rdir}/meta.json')
    integ = read_json(f'{rdir}/integrity.json')
    inputs = read_csv(f'{rdir}/inputs.csv')
    frames = read_csv(f'{rdir}/frames.csv')
    bin_in = read_csv(f'{rdir}/bridge_input.csv')
    ticks = read_csv(f'{rdir}/ticks.csv')
    mact = read_csv(f'{rdir}/mainactor.csv')
    inj = read_csv(f'{rdir}/inject.csv')
    if inj is None and harness_run.get('valid') is not True:
        inj = []    # the harness never injected (foreground-failed / no-window): the run is already invalid, still report the other thresholds
    over = read_csv(f'{rdir}/overhead_probe.csv')
    missing = [n for n, v in (('meta.json', meta), ('integrity.json', integ), ('inputs.csv', inputs), ('frames.csv', frames),
                              ('bridge_input.csv', bin_in), ('ticks.csv', ticks), ('mainactor.csv', mact), ('inject.csv', inj)) if v is None]
    if missing:
        rr.invalid.append('missing files: ' + ', '.join(missing))
        return
    if int(meta['hz']) != hz:
        rr.invalid.append(f"app QPC hz {meta['hz']} != harness qpc_freq {hz}")
        return
    ms, me = int(meta['measure_start_ticks']), int(meta['measure_end_ticks'])
    tick_per_ms = hz / 1000.0
    host = host or {}
    expect_rows = int(expect_rows or host.get('rows') or EXPECT_TOTAL_ROWS)
    key_rate = float(key_rate or host.get('key_rate') or EXPECT_KEY_RATE)
    rr.summary['rows'] = expect_rows
    rr.summary['key_rate_hz'] = key_rate
    pin_checks(rr, meta, 'windows', expect_scale)
    integrity_checks(rr, integ, meta, expect_rows=expect_rows)
    rr.add('W1', 'commit errors', rr.rid, integ.get('commit_errors'), 0, '==', str(integ.get('commit_error_first', '')))
    rr.add('W1', 'renderer commits rejected', rr.rid, integ.get('renderer_commits_rejected'), 0, '==')
    rr.add('W1', 'renderer live nodes after teardown', rr.rid, integ.get('renderer_live_nodes_final'), 0, '==')
    rr.add('W1', 'renderer host panics / thread violations / reentry / dropped events', rr.rid,
           sum(integ.get(k, 0) for k in ('renderer_host_panics', 'renderer_thread_violations', 'renderer_reentry_refused',
                                         'renderer_events_dropped_full')), 0, '==')
    rr.add('W1', 'measure/draw failures', rr.rid, integ.get('measurer_failures', 0) + integ.get('draw_failures', 0), 0, '==')

    # lost valid commits: every key posted up to the end of the measured run must be an app input, in order, text exact. A key posted AFTER measure_end
    # reaches a window the app has already asked to close (20261009-224605-full r2: posted +21.9 ms, never delivered to the app): it may be unapplied, and
    # is reported, not counted as lost. Any other shortfall (a hole in the text, or fewer applied than posted in the run) is a lost edit.
    sent_rows = [r for r in inj if r['sent'] == '1' and r['fg_ok'] == '1']
    fg_lost_rows = [r for r in inj if r['fg_ok'] != '1']
    expected = ''.join(KEY_CYCLE[int(r['seq']) % len(KEY_CYCLE)] for r in sent_rows)
    typed = int(integ.get('typed_count', -1))
    in_run = [r for r in sent_rows if int(r['qpc_before']) <= me]
    post_run = len(sent_rows) - len(in_run)
    text_ok = integ.get('active_text') == expected[:typed]
    if text_ok and len(in_run) <= typed <= len(sent_rows):
        lost = 0
    elif text_ok and typed < len(in_run):
        lost = len(in_run) - typed
    else:
        lost = len(sent_rows) - typed
    rr.add('W1', 'lost valid edits (posted up to measure end - applied)', rr.rid, lost, 0, '==',
           f'injected={len(sent_rows)} in_run={len(in_run)} post_run={post_run} typed={typed}')
    rr.add('W1', 'active text equals injected sequence', rr.rid, bool(text_ok and len(in_run) <= typed <= len(sent_rows)), True, 'bool')
    rr.summary['keys'] = {'injected': len(sent_rows), 'in_run': len(in_run), 'post_run': post_run, 'typed': typed,
                          'post_run_unapplied': max(0, len(sent_rows) - typed) if lost == 0 else None, 'inject_stop': harness_run.get('inject_stop')}
    first_loss = int(fg_lost_rows[0]['seq']) if fg_lost_rows else None
    loss_before_end = False
    if fg_lost_rows and sent_rows:
        last_q = int(sent_rows[-1]['qpc_before'])
        loss_before_end = last_q < me - int(0.2 * hz)
    rr.add('P', 'window stayed foreground through the measured run (no foreground loss)', rr.rid, not loss_before_end, True, 'bool',
           f'first_loss_seq={first_loss}')

    # window filters
    in_inputs = {int(r['seq']): r for r in inputs}
    win_inputs = [r for r in inputs if ms <= int(r['rx_ticks']) <= me]
    in_frames = [r for r in frames if ms <= int(r['end_ticks']) <= me]
    rr.summary['inputs_in_window'] = len(win_inputs)
    rr.summary['frames_in_window'] = len(in_frames)

    # W2 bridge per input event
    b_in = [int(r['bridge_ns']) / 1e6 for r in bin_in if int(r['seq']) in in_inputs and ms <= int(in_inputs[int(r['seq'])]['rx_ticks']) <= me]
    h_in = [int(r['handler_ns']) / 1e6 for r in bin_in if int(r['seq']) in in_inputs and ms <= int(in_inputs[int(r['seq'])]['rx_ticks']) <= me]
    if len(b_in) < 0.9 * len(win_inputs) or not b_in:
        rr.add('W2', 'bridge time per input: samples cover the inputs', rr.rid, False, True, 'bool', f'samples={len(b_in)} inputs={len(win_inputs)}')
    rr.add('W2', 'bridge time per input p95 (ms)', rr.rid, pct(b_in, 0.95), LIMITS['bridge_input_p95_ms'], '<=', f'n={len(b_in)}')
    rr.add('W2', 'bridge time per input p99 (ms)', rr.rid, pct(b_in, 0.99), LIMITS['bridge_input_p99_ms'], '<=')
    rr.summary['bridge_input_ms'] = stats_block(b_in)
    rr.summary['handler_input_ms'] = stats_block(h_in)
    rr.raw['bridge_per_input'] = (['seq', 'rx_ticks', 'bridge_ms', 'handler_ms'],
                                  [[r['seq'], in_inputs[int(r['seq'])]['rx_ticks'], int(r['bridge_ns']) / 1e6, int(r['handler_ns']) / 1e6]
                                   for r in bin_in if int(r['seq']) in in_inputs and ms <= int(in_inputs[int(r['seq'])]['rx_ticks']) <= me])

    # W3 aggregate bridge time per committed frame
    b_fr = [int(r['bridge_ns']) / 1e6 for r in in_frames]
    rr.add('W3', 'bridge time per committed frame p95 (ms)', rr.rid, pct(b_fr, 0.95), LIMITS['bridge_frame_p95_ms'], '<=', f'n={len(b_fr)}')
    rr.add('W3', 'bridge time per committed frame p99 (ms)', rr.rid, pct(b_fr, 0.99), LIMITS['bridge_frame_p99_ms'], '<=')
    rr.summary['bridge_frame_ms'] = stats_block(b_fr)
    rr.summary['frame_upserts_max'] = max((int(r['upserts']) for r in in_frames), default=0)
    rr.raw['bridge_per_frame'] = (['version', 'end_ticks', 'bridge_ms', 'measure_calls', 'upserts'],
                                  [[r['version'], r['end_ticks'], int(r['bridge_ns']) / 1e6, r['measure_calls'], r['upserts']] for r in in_frames])

    # W6 main-actor enqueue -> execution
    ma = [(int(r['exec_ticks']) - int(r['enqueue_ticks'])) / tick_per_ms for r in mact if ms <= int(r['enqueue_ticks']) <= me]
    rr.add('W6', 'main-actor samples sufficient (starvation guard)', rr.rid, len(ma) >= MIN_MAINACTOR_SAMPLES, True, 'bool', f'n={len(ma)} need>={MIN_MAINACTOR_SAMPLES}')
    rr.add('W6', 'main-actor enqueue->exec p99 (ms)', rr.rid, pct(ma, 0.99), LIMITS['mainactor_p99_ms'], '<=', f'n={len(ma)} max={max(ma) if ma else float("nan"):.2f}')
    rr.summary['mainactor_ms'] = stats_block(ma)
    rr.raw['mainactor'] = (['enqueue_ticks', 'wait_ms'], [[r['enqueue_ticks'], (int(r['exec_ticks']) - int(r['enqueue_ticks'])) / tick_per_ms]
                                                         for r in mact if ms <= int(r['enqueue_ticks']) <= me])

    # resources (informational; the one threshold is the private-bytes leak slope)
    try:
        analyze_resources(rr, rdir, ms, me, hz, expected=(host.get('resources') == 'on' or harness_run.get('resources_rows') is not None))
    except Exception as ex:    # informational data must never void a run, but it must not vanish either
        rr.flags.append(f'resources analysis error: {type(ex).__name__}: {ex}')
        rr.summary['resources'] = {'present': True, 'error': f'{type(ex).__name__}: {ex}'}

    # PresentMon rows for this run's pid
    pid = harness_run.get('pid')
    rows = pm_rows.get(pid, []) if pm_rows else []
    q0, q1 = harness_run.get('qpc_start', 0), harness_run.get('qpc_end', 1 << 62)
    rows = [r for r in rows if q0 - 2 * hz <= r['q'] <= q1 + 2 * hz]
    win_rows = [r for r in rows if ms <= r['q'] <= me]
    expected_rows = (me - ms) / hz * 60.0
    rr.add('C', 'PresentMon rows in measured window (capture integrity)', rr.rid, len(win_rows) >= MIN_PM_ROWS_FRACTION * expected_rows, True, 'bool',
           f'rows={len(win_rows)} expect~{expected_rows:.0f} pid={pid}')
    if not win_rows:
        rr.invalid.append('no PresentMon rows for this run pid')
        return

    # W5 presentation interval
    # Every displayed interval counts (a >=100 ms stall is a missed vblank, never discarded); the refresh period is the median
    # of the steady (<100 ms) intervals, else of all of them (a run that never presents at frame rate then fails the 60 Hz check).
    intervals = [r['between'] for r in win_rows if not r['dropped'] and r['between'] and r['between'] > 0]
    steady = [x for x in intervals if x < 100]
    refresh = statistics.median(steady or intervals) if intervals else float('nan')
    missed = sum(1 for x in intervals if x > LIMITS['presentation_missed_factor'] * refresh)
    rr.add('W5', 'refresh period measured (ms) within 60 Hz +-0.5%', rr.rid, bool(abs(1000.0 / refresh - 60.0) <= 0.3) if refresh == refresh else None,
           True, 'bool', f'refresh_ms={refresh:.3f} hz={1000.0 / refresh if refresh == refresh else float("nan"):.3f}')
    rr.add('W5', 'missed vblanks (interval > 1.5 x refresh)', rr.rid, missed if intervals else None, 0, '==', f'n={len(intervals)}')
    p95i = pct(intervals, 0.95)
    rr.add('W5', 'presented interval p95 (ms) <= refresh + 0.1', rr.rid, p95i, refresh + LIMITS['presentation_p95_margin_ms'], '<=',
           f'p50={pct(intervals, 0.5):.3f} p99={pct(intervals, 0.99):.3f} max={max(intervals) if intervals else float("nan"):.3f}')
    rr.summary['presented_interval_ms'] = stats_block(intervals)
    rr.summary['refresh_ms'] = refresh
    rr.summary['missed_vblanks'] = missed if intervals else None
    # frame rate as presented: p50 from the median interval, p95 = the rate at the 95th-percentile (slow-tail) interval, mean = displayed presents per second
    p50i = pct(intervals, 0.5)
    rr.summary['fps'] = {'p50': 1000.0 / p50i if intervals and p50i > 0 else None, 'p95_tail': 1000.0 / p95i if intervals and p95i > 0 else None,
                         'mean': len(intervals) / ((me - ms) / hz) if intervals else None}
    rr.summary['pm_dropped_in_window'] = sum(1 for r in win_rows if r['dropped'])
    rr.raw['presented_intervals'] = (['cpu_start_qpc', 'ms_between_display_change', 'dropped'], [[r['q'], r['between'], int(r['dropped'])] for r in win_rows])

    # display time of each row
    disp = []
    for r in rows:
        if r['dropped']:
            continue
        if r['screen']:
            d = int(r['screen'])
        elif r['until'] is not None and r['until'] > 0:
            d = r['q'] + int(r['until'] * tick_per_ms)
        else:
            continue
        disp.append((r['q'], d))
    starts = [x[0] for x in disp]

    # clock calibration: tick QPC vs nearest present start
    import bisect
    tk = [(int(t['ts_ns']) * hz // 1_000_000_000, int(t['paints'])) for t in ticks if ms <= int(t['rx_ticks']) <= me]
    offs = []
    for tq, _ in tk:
        i = bisect.bisect_left(starts, tq)
        cand = [abs(starts[j] - tq) for j in (i - 1, i) if 0 <= j < len(starts)]
        if cand:
            offs.append(min(cand) / tick_per_ms)
    corr95 = pct(offs, 0.95)
    rr.add('CAL', 'clock correlation: |tick QPC - nearest present start| p95 (ms)', rr.rid, corr95, LIMITS['clock_corr_p95_ms'], '<=',
           f'n={len(offs)} p50={pct(offs, 0.5):.3f}')
    rr.summary['clock_correlation_ms'] = stats_block(offs)
    if not offs or corr95 != corr95 or corr95 > LIMITS['clock_corr_p95_ms']:
        rr.invalid.append('clock calibration absent or out of bounds')

    # W4 input -> visible response
    paint_to_q = {}
    for tq, p in sorted(tk, key=lambda x: x[1]):
        paint_to_q.setdefault(p, tq)
    paints_sorted = sorted(paint_to_q)
    lat, rawrows, unresolved, fallback, gaps = [], [], 0, 0, 0
    for r in inj:
        if r['sent'] != '1' or r['fg_ok'] != '1':
            continue
        qb = int(r['qpc_before'])
        if not (ms <= qb <= me):
            continue
        a = in_inputs.get(int(r['seq']) + 1)
        if a is None or int(a['commit_ticks']) == 0:
            unresolved += 1
            rawrows.append([r['seq'], r['char'], qb, '', '', 'no-app-input'])
            continue
        commit_end = int(a['commit_ticks'])
        ia = bisect.bisect_left(starts, commit_end)
        idx = ia
        target_paint = int(a['paints_at_commit']) + 1
        tq = paint_to_q.get(target_paint)
        used = 'tick'
        if tq is None:
            j = bisect.bisect_left(paints_sorted, target_paint)
            if j < len(paints_sorted):
                tq = paint_to_q[paints_sorted[j]]
                gaps += 1
                used = 'tick-gap'
        if tq is not None:
            ib = bisect.bisect_left(starts, tq - int(0.002 * hz))
            idx = max(ia, ib)
        else:
            fallback += 1
            used = 'commit-end'
        if idx >= len(disp):
            unresolved += 1
            rawrows.append([r['seq'], r['char'], qb, '', '', 'no-present'])
            continue
        latency = (disp[idx][1] - qb) / tick_per_ms
        lat.append(latency)
        rawrows.append([r['seq'], r['char'], qb, disp[idx][0], f'{latency:.4f}', used])
    n_win_keys = len(rawrows)
    rr.add('W4', 'every injected key in the window has a visible response', rr.rid, unresolved if n_win_keys else None, 0, '==', f'keys={n_win_keys}')
    rr.add('W4', 'input->visible p95 (ms)', rr.rid, pct(lat, 0.95), LIMITS['visible_p95_ms'], '<=', f'n={len(lat)} p50={pct(lat, 0.5):.2f}')
    rr.add('W4', 'input->visible p99 (ms)', rr.rid, pct(lat, 0.99), LIMITS['visible_p99_ms'], '<=', f'max={max(lat) if lat else float("nan"):.2f}')
    rr.summary['visible_ms'] = stats_block(lat)
    rr.summary['visible_join'] = {'commit_end_fallbacks': fallback, 'tick_gap_rows': gaps}
    rr.raw['visible_response'] = (['seq', 'char', 'sendinput_qpc', 'present_cpu_start_qpc', 'latency_ms', 'join_rule'], rawrows)
    # the schedule ends at the harness's key deadline (process start + warm-up + measured - tail); older runs have none and key to the end
    deadline_q = None
    if harness_run.get('key_deadline_ms') is not None and harness_run.get('qpc_start') is not None:
        deadline_q = harness_run['qpc_start'] + harness_run['key_deadline_ms'] * hz / 1000.0
    sched_s = max(0.0, (min(me, deadline_q) if deadline_q else me) - ms) / hz
    window_s = (me - ms) / hz
    need = 0.95 * key_rate * sched_s
    rr.add('CAL', f'keys in window (script delivered {key_rate:g}/s)', rr.rid, n_win_keys >= need, True, 'bool',
           f'keys={n_win_keys} need>={need:.0f} (key schedule covers {sched_s:.1f} of {window_s:.1f} s)')
    rr.add('CAL', 'key schedule covers >= 90% of the measured window', rr.rid, sched_s >= 0.9 * window_s, True, 'bool', f'{sched_s:.1f} of {window_s:.1f} s')

    # overhead (reported)
    if over:
        rr.summary['instrumentation_microbench_ns'] = {o['name']: num(o['ns_per_pair']) for o in over}
        pair = next((num(o['ns_per_pair']) for o in over if o['name'] == 'timestamp_pair'), None)
        if pair is not None and in_frames:
            calls = integ.get('bridge_timed_calls', 0)
            rr.summary['instrumentation_estimate_ms_per_frame'] = (calls * pair / 1e6) / max(1, len(frames))
    rr.summary['renderer'] = {k: integ.get(k) for k in ('renderer_paints', 'renderer_commits_accepted', 'renderer_commits_deferred',
                                                        'renderer_measure_calls', 'renderer_measure_cache_hits',
                                                        'max_upserts_per_commit', 'max_primitives_per_commit')}


# ------------------------------------------------------------------ macOS

def analyze_mac_run(rr, rdir, expect_scale):
    appd = f'{rdir}/app'
    meta = read_json(f'{appd}/meta.json')
    integ = read_json(f'{appd}/integrity.json')
    mact = read_csv(f'{appd}/mainactor.csv')
    keys = read_csv(f'{rdir}/keys.csv')
    frames = read_csv(f'{rdir}/frames_display.csv')
    calib = read_csv(f'{rdir}/calibration.csv')
    rmeta = read_json(f'{rdir}/recorder_meta.json')
    missing = [n for n, v in (('app/meta.json', meta), ('app/integrity.json', integ), ('app/mainactor.csv', mact), ('keys.csv', keys),
                              ('frames_display.csv', frames), ('calibration.csv', calib), ('recorder_meta.json', rmeta)) if v is None]
    if missing:
        rr.invalid.append('missing files: ' + ', '.join(missing))
        return
    ms, me = int(meta['measure_start_ticks']), int(meta['measure_end_ticks'])
    pin_checks(rr, meta, 'macos', expect_scale)
    integrity_checks(rr, integ, meta)
    sent = int(rmeta.get('keys_sent', 0))
    typed = int(integ.get('typed_count', -1))
    ok_keys = [k for k in keys if k['status'] == 'ok']
    rr.add('W1', 'lost valid edits (keys posted - applied)', rr.rid, sent - typed, 0, '==', f'posted={sent} typed={typed}')
    expected = ''.join(KEY_CYCLE[i % len(KEY_CYCLE)] for i in range(typed))
    rr.add('W1', 'active text equals posted sequence', rr.rid, integ.get('active_text') == expected and sent == typed, True, 'bool')

    # calibration gate
    cal = read_json(f'{rdir}/recorder_meta.json').get('calibration', {})
    cl = [float(c['latency_ms']) for c in calib if num(c.get('latency_ms')) is not None]
    rr.add('CAL', 'recorder calibration present and valid', rr.rid, bool(cal.get('valid')) and len(cl) >= 0.9 * int(cal.get('flips', 120)), True, 'bool',
           f"detected={len(cl)}/{cal.get('flips')}")
    rr.add('CAL', 'recorder latency floor p95 (ms)', rr.rid, pct(cl, 0.95), LIMITS['calibration_floor_p95_ms'], '<=', f'p50={pct(cl, 0.5):.2f}')
    rr.summary['calibration_floor_ms'] = stats_block(cl)
    if not cl or not cal.get('valid') or pct(cl, 0.95) > LIMITS['calibration_floor_p95_ms']:
        rr.invalid.append('recorder calibration absent or out of bounds')
    rr.add('CAL', 'response-region self-check (>= 90% of keys resolved)', rr.rid, bool(rmeta.get('region_selfcheck_ok')), True, 'bool')
    cs, es = rmeta.get('captured_size_px') or {}, rmeta.get('expected_size_px') or {}
    rr.add('CAL', 'captured frame size equals window pixel size (+-2 px)', rr.rid,
           bool(cs and es and abs(cs.get('w', 0) - es.get('w', 0)) <= 2 and abs(cs.get('h', 0) - es.get('h', 0)) <= 2), True, 'bool', f'captured={cs} expected={es}')
    rr.add('P', 'recorder permissions', rr.rid, bool(rmeta.get('permissions', {}).get('screen_capture_access') and rmeta.get('permissions', {}).get('post_event_access')), True, 'bool')

    # W4
    lat, rawrows, unresolved = [], [], 0
    for k in keys:
        t = int(k['t_post_ns'])
        if not (ms <= t <= me):
            continue
        if k['status'] != 'ok':
            unresolved += 1
            rawrows.append([k['seq'], k['char'], t, '', '', k['status']])
            continue
        lat.append(float(k['latency_ms']))
        rawrows.append([k['seq'], k['char'], t, k['t_display_ns'], k['latency_ms'], 'ok'])
    rr.add('W4', 'every key in the window has a visible response', rr.rid, unresolved, 0, '==', f'keys={len(rawrows)}')
    rr.add('W4', 'input->visible p95 (ms)', rr.rid, pct(lat, 0.95), LIMITS['visible_p95_ms'], '<=', f'n={len(lat)} p50={pct(lat, 0.5):.2f} (raw, uncorrected)')
    rr.add('W4', 'input->visible p99 (ms)', rr.rid, pct(lat, 0.99), LIMITS['visible_p99_ms'], '<=', f'max={max(lat) if lat else float("nan"):.2f}')
    rr.add('CAL', 'keys in window (script delivered 10/s)', rr.rid, len(rawrows) >= 0.95 * 10 * (me - ms) / 1e9, True, 'bool')
    rr.summary['visible_ms'] = stats_block(lat)
    rr.raw['visible_response'] = (['seq', 'char', 'post_uptime_ns', 'display_uptime_ns', 'latency_ms', 'status'], rawrows)

    # W5 presentation proxy from SCK display times
    disp = sorted(int(f['display_ns']) for f in frames if ms <= int(f['display_ns']) <= me)
    intervals = [(b - a) / 1e6 for a, b in zip(disp, disp[1:])]
    hz_disp = num((rmeta.get('app_ready') or {}).get('display_refresh_hz'), 60.0) or 60.0
    refresh = 1000.0 / hz_disp
    missed = sum(1 for x in intervals if x > LIMITS['presentation_missed_factor'] * refresh)
    rr.add('W5', 'display refresh 60 Hz (CGDisplayMode)', rr.rid, abs(hz_disp - 60.0) <= 0.5, True, 'bool', f'hz={hz_disp}')
    rr.add('W5', 'missed vblanks (SCK display-time interval > 1.5 x refresh)', rr.rid, missed, 0, '==', f'n={len(intervals)} (SCK proxy; frames only on change)')
    rr.add('W5', 'presented interval p95 (ms) <= refresh + 0.1', rr.rid, pct(intervals, 0.95), refresh + LIMITS['presentation_p95_margin_ms'], '<=',
           f'p50={pct(intervals, 0.5):.3f} p99={pct(intervals, 0.99):.3f}')
    rr.summary['presented_interval_ms'] = stats_block(intervals)
    rr.raw['presented_intervals'] = (['display_uptime_ns', 'interval_ms'], [[d, f'{i:.4f}'] for d, i in zip(disp[1:], intervals)])

    # W6 informational on Mac
    ma = [(int(r['exec_ticks']) - int(r['enqueue_ticks'])) / 1e6 for r in mact if ms <= int(r['enqueue_ticks']) <= me]
    rr.add('W6', 'main-actor enqueue->exec p99 (ms) (Windows-only threshold; reported)', rr.rid, pct(ma, 0.99), LIMITS['mainactor_p99_ms'], 'info', f'n={len(ma)}')
    rr.summary['mainactor_ms'] = stats_block(ma)
    rr.summary['bridge'] = 'not applicable on macOS (no bridge)'


# ------------------------------------------------------------------ driver

def incremental_check(path):
    inc = read_json(path) if path else None
    rep = RunReport('--')
    if inc is None:
        rep.add('W7', 'UI-only incremental build record present', 'set', None, True, 'bool', f'{path} missing: run scripts/build-incremental.*')
        return rep
    rep.add('W7', 'Rust compiler invocations during UI-only incremental builds', 'set', inc.get('rust_invocations_total'), 0, '==', f"edits={inc.get('edits')}")
    rep.add('W7', 'renderer / engine artifact hashes identical', 'set', bool(inc.get('hashes_identical')), True, 'bool')
    rep.add('W7', 'incremental builds succeeded', 'set', bool(inc.get('builds_ok')), True, 'bool')
    return rep


def write_raw(outdir, rr):
    os.makedirs(f'{outdir}/raw', exist_ok=True)
    for name, (header, rows) in rr.raw.items():
        with open(f'{outdir}/raw/{rr.rid}-{name}.csv', 'w', newline='') as f:
            w = csv.writer(f)
            w.writerow(header)
            w.writerows(rows)


def overhead_ab(full_runs, light_root, platform):
    """Overhead of the full instrumentation = delta of full vs light on presented interval p95 and input->visible p95."""
    if not light_root:
        return {'measured': False, 'note': 'no --light-root: A/B overhead not measured; per-run micro-benchmark costs are in each run summary'}
    light = analyze(platform, light_root, 3, None, None, None, quiet=True, allow_light=True)
    out = {'measured': True, 'light_root': light_root}
    for key in ('presented_interval_ms', 'visible_ms'):
        f = [r.summary.get(key, {}).get('p95') for r in full_runs if r.summary.get(key)]
        l = [r.summary.get(key, {}).get('p95') for r in light['runs'] if r.summary.get(key)]
        if f and l:
            out[key + '_p95_delta'] = statistics.mean(f) - statistics.mean(l)
    return out


def analyze(platform, root, expect_runs, expect_scale, out, incremental, quiet=False, allow_light=False, light_root=None, expect_rows=None, key_rate=None):
    runs = []
    global_invalid = []
    pm = harness = None
    if platform == 'windows':
        harness = parse_harness(f'{root}/result-workload.txt')
        if harness is None:
            global_invalid.append('result-workload.txt missing (harness did not run)')
        elif not harness['host'].get('finished'):
            global_invalid.append('harness did not finish (no finished= line)')
        if harness is not None and not harness['qpc_hz']:
            global_invalid.append('harness host line has no qpc_freq (per-run analysis cannot run)')
        pm, err = load_presentmon(f'{root}/presentmon.csv')
        if pm is None:
            global_invalid.append(err)
        loss = console_loss(f'{root}/presentmon.console.txt')
        if loss is None:
            global_invalid.append('presentmon.console.txt missing (capture integrity unknown)')
        elif loss['lost_lines'] or loss['bad_flag_lines']:
            global_invalid.append(f'PresentMon console reports loss/bad flags: {loss}')
        build = read_json(f'{root}/build.json')
        if build is None:
            global_invalid.append('build.json missing (release build and artifact identity unbound)')
        elif build.get('configuration') != 'release':
            global_invalid.append('build is not release')
    else:
        build = read_json(f'{root}/build-mac.json')
        if build is None:
            global_invalid.append('build-mac.json missing (release build and artifact identity unbound)')
        elif build.get('configuration') != 'release':
            global_invalid.append('build is not release')

    for i in range(1, expect_runs + 1):
        rid = f'r{i}'
        rdir = f'{root}/{rid}'
        rr = RunReport(rid)
        if not os.path.isdir(rdir):
            rr.invalid.append('run directory missing')
        elif platform == 'windows':
            hr = (harness or {'runs': {}})['runs'].get(rid)
            if not hr:
                rr.invalid.append('run absent from harness result file')
            elif not harness['qpc_hz']:
                rr.invalid.append('no harness qpc_freq: run not analyzed')
            else:
                try:
                    analyze_windows_run(rr, rdir, hr, harness['qpc_hz'], pm, expect_scale, out, harness['host'], expect_rows, key_rate)
                except Exception as ex:    # a crash must surface as an invalid run, never as an empty report or a missing one
                    import traceback
                    rr.invalid.append(f'analyzer error: {type(ex).__name__}: {ex} @ ' + traceback.format_exc().strip().splitlines()[-3].strip())
        else:
            analyze_mac_run(rr, rdir, expect_scale)
        if not allow_light:
            instr = (read_json(f'{rdir}/meta.json') if platform == 'windows' else read_json(f'{rdir}/app/meta.json')) or {}
            if instr and instr.get('instr') != 'full':
                rr.invalid.append(f"instrumentation level {instr.get('instr')} is a baseline run, not a PASS-eligible run")
        runs.append(rr)
    inc = incremental_check(incremental) if not allow_light else None
    return {'runs': runs, 'global_invalid': global_invalid, 'incremental': inc, 'build': build, 'harness': harness}


def fmt(v, nd=1, unit=''):
    return '-' if v is None else (f'{v:.{nd}f}{unit}' if isinstance(v, float) else f'{v}{unit}')


def resources_md(runs):
    """Markdown "Resources" section (informational). One row per run, then per-adapter GPU detail and the flags."""
    have = [rr for rr in runs if rr.summary.get('resources')]
    if not have and not any(rr.flags for rr in runs):
        return []
    md = ['', '## Resources (informational; only a private-bytes slope above %g MB/min is a threshold)' % LEAK_SLOPE_MB_PER_MIN, '',
          'CPU: machine total %, our process in % of ONE core (100 = one core busy). Memory in MB with growth slope MB/min over the measured window. '
          'GPU: our process only, % summed per engine type per adapter.', '',
          '| run | samples | CPU total avg/peak % | process avg/peak (core %) | busiest thread | pinned samples | working set avg/peak MB (slope/min) | '
          'private avg/peak MB (slope/min) | handles max | threads max | GPU adapter used | sampler overhead (core %) |',
          '|---|---|---|---|---|---|---|---|---|---|---|---|']
    for rr in runs:
        r = rr.summary.get('resources')
        if not r or not r.get('present'):
            md.append(f'| {rr.rid} | not sampled | | | | | | | | | | |')
            continue
        ws, pv = r.get('working_set_mb') or {}, r.get('private_mb') or {}
        tt = (r.get('top_threads') or [{}])[0]
        used = ((r.get('gpu') or {}).get('adapter_used') or {}).get('name', 'unknown')
        md.append('| {rid} | {n} | {c1}/{c2} | {p1}/{p2} | {tid}{nm} {tp}% | {pin} | {w1}/{w2} ({ws}) | {v1}/{v2} ({vs}) | {h} | {t} | {used} | {so} |'.format(
            rid=rr.rid, n=r.get('samples'), c1=fmt((r.get('total_cpu_pct') or {}).get('avg')), c2=fmt((r.get('total_cpu_pct') or {}).get('peak')),
            p1=fmt((r.get('proc_cpu_core_pct') or {}).get('avg')), p2=fmt((r.get('proc_cpu_core_pct') or {}).get('peak')),
            tid=tt.get('tid', '-'), nm=f"[{tt['name']}]" if tt.get('name') else '', tp=fmt(tt.get('avg_pct_of_core')),
            pin=r.get('pinned_samples', 0), w1=fmt(ws.get('avg')), w2=fmt(ws.get('peak')), ws=fmt(ws.get('slope_mb_per_min'), 2),
            v1=fmt(pv.get('avg')), v2=fmt(pv.get('peak')), vs=fmt(pv.get('slope_mb_per_min'), 2),
            h=(r.get('handles') or {}).get('max', '-'), t=(r.get('threads') or {}).get('max', '-'), used=used,
            so=fmt((r.get('sampler_cpu_core_pct') or {}).get('avg'))))
    md += ['', '| run | adapter | 3D avg/peak % | compute | copy | video | other | dedicated MB avg/peak | shared MB avg/peak |', '|---|---|---|---|---|---|---|---|---|']
    for rr in runs:
        r = rr.summary.get('resources')
        if not r or not r.get('present'):
            continue
        for a in (r.get('gpu') or {}).get('adapters', []):
            u = a['util_pct']
            cell = lambda g: f"{fmt(u[g]['avg'], 2)}/{fmt(u[g]['peak'], 1)}"
            used = ((r.get('gpu') or {}).get('adapter_used') or {}).get('index') == a['index']
            md.append(f"| {rr.rid} | {'**' if used else ''}{a['name']}{'** (used)' if used else ''} | {cell('3d')} | {cell('compute')} | {cell('copy')} | "
                      f"{cell('video')} | {cell('other')} | {fmt(a['dedicated_mb']['avg'])}/{fmt(a['dedicated_mb']['peak'])} | "
                      f"{fmt(a['shared_mb']['avg'])}/{fmt(a['shared_mb']['peak'])} |")
    flags = [f'- {rr.rid}: {f}' for rr in runs for f in rr.flags]
    md += [''] + (['Flags:'] + flags if flags else ['Flags: none']) + ['']
    return md


def finish(platform, result, out, light_root):
    runs = result['runs']
    reasons = list(result['global_invalid'])
    for rr in runs:
        for r in rr.invalid:
            reasons.append(f'{rr.rid}: {r}')
    all_checks = [c for rr in runs for c in rr.checks] + (result['incremental'].checks if result['incremental'] else [])
    missing = [c for c in all_checks if c.status == 'MISSING']
    for c in missing:
        reasons.append(f'{c.run}: {c.tid} {c.name} not measurable')
    failed = [c for c in all_checks if c.status == 'FAIL']
    if reasons:
        overall = 'INCOMPLETE'
    elif failed:
        overall = 'FAIL'
    else:
        overall = 'PASS'
    report = {
        'platform': platform, 'overall': overall, 'refusal_reasons': reasons, 'limits': LIMITS,
        'failed': [c.row() for c in failed],
        'runs': {rr.rid: {'summary': rr.summary, 'invalid': rr.invalid, 'flags': rr.flags, 'checks': [c.row() for c in rr.checks]} for rr in runs},
        'resources': {rr.rid: rr.summary.get('resources') for rr in runs},
        'flags': [f'{rr.rid}: {f}' for rr in runs for f in rr.flags],
        'incremental': [c.row() for c in result['incremental'].checks] if result['incremental'] else [],
        'build': result['build'], 'overhead_ab': overhead_ab([r for r in runs], light_root, platform) if light_root else {'measured': False},
    }
    if out:
        os.makedirs(out, exist_ok=True)
        for rr in runs:
            write_raw(out, rr)
        with open(f'{out}/report.json', 'w') as f:
            json.dump(report, f, indent=2, default=str)
        md = [f'# SR0 workload report ({platform}): {overall}', '']
        if reasons:
            md += ['PASS refused:'] + [f'- {r}' for r in reasons] + ['']
        md += ['| id | run | status | check | value | limit |', '|---|---|---|---|---|---|']
        for c in all_checks:
            v = f'{c.value:.4f}' if isinstance(c.value, float) else c.value
            md.append(f'| {c.tid} | {c.run} | {c.status} | {c.name} | {v} | {c.op} {c.limit} |')
        md += resources_md(runs)
        with open(f'{out}/report.md', 'w') as f:
            f.write('\n'.join(md) + '\n')
    return overall, all_checks, reasons


def selftest(keep=None):
    """Builds synthetic Windows run sets and asserts the PASS / FAIL / INCOMPLETE behaviour of the analyzer."""
    import random
    import shutil
    hz = 10_000_000
    frame = hz / 60.0

    def make_resources(rdir, t0, kind, rnd):
        """Synthetic sampler output: ~1.05 s rows from t0 to t0+76 s; adapters 0 Intel (display copy), 1 NVIDIA (renders), 2 WARP; kind: good|leak|pinned|sparse."""
        names = [{'index': 0, 'luid': '0x00000000_0x00017e7d', 'name': 'Intel(R) Iris(R) Xe Graphics', 'dedicated_mb': 128, 'vendor_id': 32902, 'flags': 0},
                 {'index': 1, 'luid': '0x00000000_0x00018254', 'name': 'NVIDIA GeForce RTX 4070 Laptop GPU', 'dedicated_mb': 7949, 'vendor_id': 4318, 'flags': 0},
                 {'index': 2, 'luid': '0x00000000_0x0001821f', 'name': 'Microsoft Basic Render Driver', 'dedicated_mb': 0, 'vendor_id': 5140, 'flags': 2}]
        json.dump({'run_id': 'x', 'target_pid': 1, 'qpc_hz': hz, 'logical_cpus': 20, 'adapters': names, 'adapter_enumeration': 'dxgi'}, open(f'{rdir}/resources-meta.json', 'w'))
        cols = ['t_s', 'qpc', 'dt_s', 'total_cpu_pct', 'max_core_pct', 'max_core', 'proc_cpu_pct', 'proc_cpu_core_pct', 'top_threads', 'pinned_tid', 'pinned_pct',
                'working_set_bytes', 'private_bytes', 'handles', 'threads']
        for i in ('0', '1', '2', 'x'):
            cols += [f'gpu{i}_{k}' for k in ('3d_pct', 'compute_pct', 'copy_pct', 'video_pct', 'other_pct', 'ded_bytes', 'shared_bytes')]
        cols += ['gpu_n', 'gpu_engines', 'sampler_cpu_pct']
        lines = [','.join(cols)]
        n = 6 if kind == 'sparse' else 72
        slope = 8.0 if kind == 'leak' else 0.4          # MB per minute
        for k in range(n):
            ts = k * 1.05 + 1.0 if kind != 'sparse' else k * 10.0 + 11.0
            q = int(t0 + ts * hz)
            priv = (300 + slope * ts / 60.0 + rnd.uniform(-0.3, 0.3)) * 1048576
            pinned = kind == 'pinned' and k % 3 == 0
            top = '100[render]:%.1f;101:5.1;102:1.2' % (96.0 if pinned else 35.0)
            row = [f'{ts:.3f}', str(q), '1.05', f'{rnd.uniform(8, 14):.2f}', '60.1', '3', '1.9', '38.1', f'"{top}"', '100' if pinned else '', '96' if pinned else '0',
                   str(int(priv * 1.2)), str(int(priv)), '420', '36']
            row += ['0.1', '0', '0.8', '0', '0', '26661351424', '0']                                    # adapter 0: display copy
            row += [f'{rnd.uniform(10, 15):.3f}', '0', '0', '0', '0', '812646400', '319488']            # adapter 1: renders
            row += ['0'] * 7 + ['0'] * 7                                                               # adapter 2 and unmapped
            row += ['40', '"a1.3d#0=12.5;a0.copy#2=0.8"', f'{rnd.uniform(1, 5):.2f}']
            lines.append(','.join(row))
        open(f'{rdir}/resources.csv', 'w').write('\n'.join(lines) + '\n')

    def make(root, runs=3, latency_extra_ms=0.0, drop_calibration=False, drop_incremental=False, light=False, drop_run=None, empty_refresh=False,
             rows=200, key_rate=10.0, resources=None, res_expected=None, tail_unapplied=False, lost_inrun=False, rows_ignored=False, deadline=False):
        os.makedirs(root, exist_ok=True)
        rnd = random.Random(7)
        res_on = resources is not None if res_expected is None else res_expected
        res = ['harness=selftest', f'host qpc_freq={hz} input_struct=40 gpu=x driver=y refresh_hz={"" if empty_refresh else 60} res={"x" if empty_refresh else "1920x1080"}',
               f'exe=x exe_sha256=a dll_sha256=b instr=full runs=3 warmup_s=10 measure_s=60 rate_hz={key_rate:g} rows={rows} key_tail_s=0.5 resources={"on" if res_on else "off"} key_mode=char foreground_s=8']
        pm_rows = ['Application,ProcessID,CPUStartQPC,Dropped,msBetweenDisplayChange,msUntilDisplayed']
        base = 5_000_000_000
        for n in range(1, runs + 1):
            if drop_run == n:
                continue
            rid = f'r{n}'
            rdir = f'{root}/{rid}'
            os.makedirs(rdir, exist_ok=True)
            pid = 1000 + n
            t0 = base + n * 1000 * hz
            ms, me = t0 + 10 * hz, t0 + 70 * hz
            n_keys = int(72 * key_rate) if not deadline else int(68.5 * key_rate)
            res += [f'=== RUN {rid} start=x', f'pid run={rid} pid={pid} start_utc=x qpc_start={t0 - hz}', 'window run=%s hwnd=1 foreground=direct dpi=96 client_px=960x640' % rid,
                    f'inject run={rid} sent={n_keys} fg_lost=0 send_fail=0 fg_events=0 fg_recovered=0 stop={"deadline" if deadline else "limit"} csv=x key_mode=char rate_hz={key_rate:g}'
                    + (' key_deadline_ms_from_start=70000' if deadline else ''),
                    f'pid_exit run={rid} pid={pid} qpc_end={t0 + 72 * hz} exit=0', f'run_state id={rid} valid=1 reason=ok']
            # presents at 60 Hz for the whole run; paint k at start time
            n_paints = int((75 * hz) / frame)
            starts = [int(t0 - hz + k * frame + rnd.uniform(-2000, 2000)) for k in range(n_paints)]
            prev = None
            for k, s in enumerate(starts):
                between = '' if prev is None else f'{(s - prev) / (hz / 1000):.3f}'
                pm_rows.append(f'WorkloadWin.exe,{pid},{s},0,{16.667 if prev is not None else ""},{20.0}')
                prev = s
            ticks = ['ts_ns,rx_ticks,paints,commits'] + [f'{int((s - 3000) * 1e9 / hz)},{s + 100},{k + 1},{k}' for k, s in enumerate(starts)]
            inputs = ['seq,rx_ticks,text_len,commit_ticks,paints_at_commit,commit_version']
            inj = ['seq,char,qpc_before,qpc_after,sent,fg_ok']
            bin_rows = ['seq,handler_ns,bridge_ns']
            text = ''
            import bisect as _bs
            for k in range(n_keys):
                qb = int(t0 + 0.5 * hz + k * hz / key_rate)
                rx = qb + 3000
                ce = rx + 5000
                pc = _bs.bisect_left(starts, ce)
                inj.append(f'{k},{KEY_CYCLE[k % 10]},{qb},{qb + 200},1,1')
                if tail_unapplied and qb > me:
                    continue                    # posted after measure_end: the app was already closing and never saw it
                inputs.append(f'{k + 1},{rx},{k + 1},{ce},{pc},{k + 1}')
                bin_rows.append(f'{k + 1},400000,{int(rnd.uniform(200000, 800000))}')
                text += KEY_CYCLE[k % 10]
            typed_n = len(text)
            if lost_inrun:
                text = text[:300] + text[301:]   # one in-run key never reached the text: a hole, later keys applied
                typed_n = len(text)
            if latency_extra_ms:
                inputs = [inputs[0]] + [l for l in inputs[1:]]
            frames = ['version,start_ticks,end_ticks,bridge_ns,measure_calls,upserts,paints'] + [
                f'{k + 1},{s - 9000},{s - 5000},{int(rnd.uniform(500000, 1500000))},40,2000,{k}' for k, s in enumerate(starts)]
            mact = ['enqueue_ticks,exec_ticks'] + [f'{int(t0 + k * hz / 200)},{int(t0 + k * hz / 200 + rnd.uniform(500, 40000))}' for k in range(int(75 * 200))]
            for name, lines in (('inputs.csv', inputs), ('frames.csv', frames), ('bridge_input.csv', bin_rows), ('ticks.csv', ticks), ('mainactor.csv', mact),
                                ('inject.csv', inj), ('overhead_probe.csv', ['name,ns_per_pair,iterations', 'timestamp_pair,60,1000', 'recorder_append,30,1000'])):
                open(f'{rdir}/{name}', 'w').write('\n'.join(lines) + '\n')
            if drop_calibration:
                open(f'{rdir}/ticks.csv', 'w').write('ts_ns,rx_ticks,paints,commits\n')
            app_rows = 200 if rows_ignored else rows
            json.dump({'run_id': rid, 'platform': 'windows', 'instr': 'light' if light else 'full', 'hz': hz, 't0_ticks': t0, 'measure_start_ticks': ms,
                       'measure_end_ticks': me, 'warmup_s': 10, 'measure_s': 60, 'scale': '1.0', 'window_dip': {'w': 960, 'h': 640}, 'abi_major': 0, 'abi_minor': 6,
                       'debugger_present': 'false', 'total_rows': app_rows}, open(f'{rdir}/meta.json', 'w'))
            if resources:
                make_resources(rdir, t0, resources, rnd)
            json.dump({'wrong_node_edits': 0, 'stale_committed': 0, 'stale_rejected': 50, 'commits_after_close': 0, 'commits_after_close_backend': 0,
                       'rows_min': app_rows, 'rows_max': app_rows, 'unique_ids': True, 'app_exit': 'complete', 'closed': True, 'anim_interrupts': 20,
                       'updates_started': 750, 'inserts_started': 750, 'ops_skipped': 0, 'reorders': 70, 'typed_count': typed_n, 'active_text': text,
                       'commit_errors': 0, 'renderer_commits_rejected': 0, 'renderer_live_nodes_final': 0, 'renderer_host_panics': 0,
                       'renderer_thread_violations': 0, 'renderer_reentry_refused': 0, 'renderer_events_dropped_full': 0, 'measurer_failures': 0,
                       'draw_failures': 0, 'bridge_timed_calls': 90000}, open(f'{rdir}/integrity.json', 'w'))
        res.append('finished=x runs_valid=3 of 3')
        open(f'{root}/result-workload.txt', 'w').write('\n'.join(res) + '\n')
        open(f'{root}/presentmon.csv', 'w').write('\n'.join(pm_rows) + '\n')
        open(f'{root}/presentmon.console.txt', 'w').write('Started recording.\n')
        json.dump({'configuration': 'release'}, open(f'{root}/build.json', 'w'))
        inc = None if drop_incremental else f'{root}/incremental.json'
        if inc:
            json.dump({'rust_invocations_total': 0, 'hashes_identical': True, 'builds_ok': True, 'edits': 3}, open(inc, 'w'))
        return inc


    def make_mac(root, calib=True, runs=3):
        os.makedirs(root, exist_ok=True)
        rnd = random.Random(11)
        json.dump({'configuration': 'release'}, open(f'{root}/build-mac.json', 'w'))
        json.dump({'rust_invocations_total': 0, 'hashes_identical': True, 'builds_ok': True, 'edits': 3}, open(f'{root}/incremental.json', 'w'))
        for n in range(1, runs + 1):
            rd = f'{root}/r{n}'
            os.makedirs(f'{rd}/app', exist_ok=True)
            t0 = 10_000_000_000 * n
            ms, me = t0 + 10 * 10**9, t0 + 70 * 10**9
            text = ''.join(KEY_CYCLE[k % 10] for k in range(720))
            keys = ['seq,char,t_post_ns,t_display_ns,latency_ms,status']
            for k in range(720):
                tp = t0 + 500_000_000 + k * 100_000_000
                lat = rnd.uniform(25, 40)
                keys.append(f'{k + 1},{KEY_CYCLE[k % 10]},{tp},{int(tp + lat * 1e6)},{lat:.3f},ok')
            frames = ['display_ns'] + [str(int(t0 + k * 16_666_667)) for k in range(int(75 * 60))]
            open(f'{rd}/keys.csv', 'w').write('\n'.join(keys) + '\n')
            open(f'{rd}/frames_display.csv', 'w').write('\n'.join(frames) + '\n')
            cal = ['flip_seq,t_flip_ns,display_ns,latency_ms,arrival_ns'] + [f'{i},0,0,{rnd.uniform(8, 20):.3f},0' for i in range(120)]
            if calib:
                open(f'{rd}/calibration.csv', 'w').write('\n'.join(cal) + '\n')
            json.dump({'permissions': {'screen_capture_access': True, 'post_event_access': True}, 'keys_sent': 720, 'region_selfcheck_ok': True,
                       'calibration': {'valid': True, 'flips': 120}, 'captured_size_px': {'w': 1920, 'h': 1336}, 'expected_size_px': {'w': 1920, 'h': 1336},
                       'app_ready': {'display_refresh_hz': 60.0}}, open(f'{rd}/recorder_meta.json', 'w'))
            json.dump({'run_id': f'r{n}', 'instr': 'full', 'measure_start_ticks': ms, 'measure_end_ticks': me, 'warmup_s': 10, 'measure_s': 60,
                       'window_pt': {'w': 960, 'h': 640}, 'release_build': True}, open(f'{rd}/app/meta.json', 'w'))
            json.dump({'wrong_node_edits': 0, 'stale_committed': 0, 'stale_rejected': 50, 'commits_after_close': 0, 'rows_min': 200, 'rows_max': 200,
                       'unique_ids': True, 'app_exit': 'complete', 'closed': True, 'anim_interrupts': 20, 'updates_started': 750, 'inserts_started': 750,
                       'ops_skipped': 0, 'reorders': 70, 'typed_count': 720, 'active_text': text}, open(f'{rd}/app/integrity.json', 'w'))
            open(f'{rd}/app/mainactor.csv', 'w').write('enqueue_ticks,exec_ticks\n' + '\n'.join(f'{t0 + k * 5_000_000},{t0 + k * 5_000_000 + 40000}' for k in range(15000)) + '\n')

    failures = []
    tmp = tempfile.mkdtemp(prefix='sr0wl-selftest-')
    if keep:
        shutil.rmtree(keep, ignore_errors=True)
    try:
        cases = [
            ('good', dict(), 'PASS'),
            ('missing run', dict(drop_run=3), 'INCOMPLETE'),
            ('no calibration', dict(drop_calibration=True), 'INCOMPLETE'),
            ('no incremental record', dict(drop_incremental=True), 'INCOMPLETE'),
            ('light baseline', dict(light=True), 'INCOMPLETE'),
            ('empty refresh_hz in host line', dict(empty_refresh=True), 'PASS'),   # R10 regression: the run analysis was silently skipped
            # --- stress / resources / lost-key additions (R10)
            ('resources good', dict(resources='good'), 'PASS', lambda res: [] if all(
                (rr.summary['resources']['gpu']['adapter_used'] or {}).get('name', '').startswith('NVIDIA') and not rr.flags
                and abs(rr.summary['resources']['private_mb']['slope_mb_per_min'] - 0.4) < 0.3 and rr.summary['resources']['samples'] >= 55
                and rr.summary['resources']['gpu']['adapters_active'] == ['Intel(R) Iris(R) Xe Graphics', 'NVIDIA GeForce RTX 4070 Laptop GPU']
                and rr.summary['resources']['top_threads'][0]['name'] == 'render' for rr in res['runs']) else ['resources summary wrong']),
            ('resources leak', dict(resources='leak'), 'FAIL', lambda res: [] if all(
                any('LEAK' in f for f in rr.flags) and any(c.tid == 'R' and c.status == 'FAIL' for c in rr.checks) for rr in res['runs']) else ['leak not flagged']),
            ('resources pinned thread', dict(resources='pinned'), 'PASS', lambda res: [] if all(
                any('pinned core' in f for f in rr.flags) and rr.summary['resources']['pinned_threads'] == [100] for rr in res['runs']) else ['pinned not flagged']),
            ('resources sparse', dict(resources='sparse'), 'PASS', lambda res: [] if all(any('only' in f for f in rr.flags) for rr in res['runs']) else ['sparse not flagged']),
            ('resources expected but absent', dict(res_expected=True), 'PASS', lambda res: [] if all(
                any('absent' in f for f in rr.flags) for rr in res['runs']) else ['absence not flagged']),
            ('stress 1000 rows 30 keys', dict(rows=1000, key_rate=30.0, resources='good', deadline=True), 'PASS', lambda res: [] if all(
                rr.summary['rows'] == 1000 and rr.summary['key_rate_hz'] == 30.0 and rr.summary['keys']['typed'] > 1800 for rr in res['runs']) else ['stress params lost']),
            ('stress rows not honoured by the app', dict(rows=1000, rows_ignored=True), 'INCOMPLETE'),
            ('key posted after measure end not applied', dict(tail_unapplied=True), 'PASS', lambda res: [] if all(
                rr.summary['keys']['post_run'] > 0 and rr.summary['keys']['post_run_unapplied'] == rr.summary['keys']['post_run'] for rr in res['runs']) else ['tail accounting wrong']),
            ('key lost inside the run', dict(lost_inrun=True), 'FAIL'),
            ('key schedule with harness deadline', dict(deadline=True), 'PASS'),
        ]
        for case in cases:
            name, kw, want = case[:3]
            extra = case[3] if len(case) > 3 else None
            root = f'{tmp}/{re.sub(r"[^a-z]", "", name)}'
            inc = make(root, **kw)
            res = analyze('windows', root, 3, 1.0, None, inc)
            overall, checks, reasons = finish('windows', res, f'{root}/report', None)
            ok = overall == want
            more = extra(res) if extra else []
            if more:
                ok = False
            print(f'selftest {name}: {overall} (want {want}) {"ok" if ok else "MISMATCH"}' + (f' {more}' if more else ''))
            if not ok:
                failures.append(name)
                for c in checks:
                    if c.status in ('FAIL', 'MISSING'):
                        print('   ', c.line())
                for r in reasons[:6]:
                    print('    reason:', r)
        for name, kw, want in (('mac good', {}, 'PASS'), ('mac no calibration', {'calib': False}, 'INCOMPLETE'), ('mac missing run', {'runs': 2}, 'INCOMPLETE')):
            root = f'{tmp}/{re.sub(r"[^a-z]", "", name)}'
            make_mac(root, **kw)
            res = analyze('macos', root, 3, 2.0, None, f'{root}/incremental.json')
            overall, checks, reasons = finish('macos', res, None, None)
            ok = overall == want
            print(f'selftest {name}: {overall} (want {want}) {"ok" if ok else "MISMATCH"}')
            if not ok:
                failures.append(name)
                for c in checks:
                    if c.status in ('FAIL', 'MISSING'):
                        print('   ', c.line())
                for r in reasons[:6]:
                    print('    reason:', r)
        # a failing threshold: bridge time too high
        root = f'{tmp}/slow'
        inc = make(root)
        for n in (1, 2, 3):
            p = f'{root}/r{n}/bridge_input.csv'
            lines = open(p).read().splitlines()
            open(p, 'w').write('\n'.join([lines[0]] + [f'{l.split(",")[0]},400000,5000000' for l in lines[1:]]) + '\n')
        res = analyze('windows', root, 3, 1.0, None, inc)
        overall, checks, reasons = finish('windows', res, None, None)
        print(f'selftest slow bridge: {overall} (want FAIL)')
        if overall != 'FAIL':
            failures.append('slow bridge')
    finally:
        if keep:
            shutil.copytree(f'{tmp}/good', f'{keep}/windows-good')
            shutil.copytree(f'{tmp}/macgood', f'{keep}/macos-good')
            shutil.copytree(f'{tmp}/resourcesgood', f'{keep}/windows-resources')
            print(f'kept synthetic run sets in {keep}')
        shutil.rmtree(tmp, ignore_errors=True)
    print('SELFTEST ' + ('FAIL ' + ', '.join(failures) if failures else 'PASS'))
    return 1 if failures else 0


def main(argv):
    if '--selftest' in argv:
        k = argv.index('--selftest-keep') if '--selftest-keep' in argv else -1
        return selftest(argv[k + 1] if k >= 0 else None)
    opts = {}
    i = 0
    while i < len(argv):
        if argv[i].startswith('--'):
            k = argv[i][2:]
            if i + 1 < len(argv) and not argv[i + 1].startswith('--'):
                opts[k] = argv[i + 1]
                i += 1
            else:
                opts[k] = '1'
        i += 1
    platform = opts.get('os')
    root = opts.get('root')
    if platform not in ('windows', 'macos') or not root:
        print(__doc__)
        return 3
    out = opts.get('out', os.path.join(root, 'report'))
    expect_runs = int(opts.get('expect-runs', 3))
    expect_scale = float(opts.get('expect-scale', 2.5 if platform == 'windows' else 2.0))    # Dell tuple is 250% (scale 2.5); Mac is 2.0
    incremental = opts.get('incremental') or next((p for p in (f'{root}/incremental.json', f'{root}/../../incremental.json') if os.path.isfile(p)), f'{root}/incremental.json')
    result = analyze(platform, root, expect_runs, expect_scale, out, incremental,
                     expect_rows=int(opts['expect-rows']) if opts.get('expect-rows') else None, key_rate=float(opts['key-rate']) if opts.get('key-rate') else None)
    overall, checks, reasons = finish(platform, result, out, opts.get('light-root'))
    for c in checks:
        print(c.line())
    for rr in result['runs']:
        r = rr.summary.get('resources')
        if r and r.get('present') and r.get('samples'):
            used = ((r.get('gpu') or {}).get('adapter_used') or {}).get('name', 'unknown')
            print(f"RESOURCES {rr.rid} samples={r['samples']} cpu_total_avg={(r.get('total_cpu_pct') or {}).get('avg')} proc_core_avg={(r.get('proc_cpu_core_pct') or {}).get('avg')} "
                  f"proc_core_peak={(r.get('proc_cpu_core_pct') or {}).get('peak')} private_mb_peak={(r.get('private_mb') or {}).get('peak')} "
                  f"private_slope_mb_min={(r.get('private_mb') or {}).get('slope_mb_per_min')} gpu_adapter={used}")
        elif r is not None:
            print(f'RESOURCES {rr.rid} not sampled')
        for f in rr.flags:
            print(f'FLAG {rr.rid}: {f}')
    for r in reasons:
        print('REFUSED:', r)
    print(f'OVERALL: {overall}')
    print(f'report: {out}/report.json, {out}/report.md, raw samples: {out}/raw/')
    return {'PASS': 0, 'FAIL': 1, 'INCOMPLETE': 2}[overall]


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
