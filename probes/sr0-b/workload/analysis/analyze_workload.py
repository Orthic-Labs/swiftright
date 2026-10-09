"""SR0 workload analyzer (plan v2 lane R10): architecture.md section 11 "Decision budgets".

Usage:
  analyze_workload.py --os windows|macos --root <run-root> [--out <dir>] [--expect-runs 3] [--expect-scale 2.5 (windows) | 2.0 (macos)]
                      [--incremental <incremental.json>] [--light-root <run-root of --instr light runs>]
  analyze_workload.py --selftest [--selftest-keep <dir>]   (synthetic data; keep writes windows-good/ and macos-good/ run sets)

Emits every section 11 threshold per run with PASS / FAIL, writes raw-sample CSVs and report.json / report.md under --out,
and prints one OVERALL line:
  OVERALL: PASS         every run, every threshold, and every validity gate passed
  OVERALL: FAIL         at least one threshold failed on a valid run set
  OVERALL: INCOMPLETE   PASS REFUSED: a run is missing or invalid, calibration is absent or out of bounds, the
                        UI-only incremental build record is absent, or the runs were not the full instrumentation level.
  (exit codes: 0 PASS, 1 FAIL, 2 INCOMPLETE, 3 usage)

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

def integrity_checks(rr, integ, meta, expect_ops=True):
    g = lambda k, d=None: integ.get(k, d)
    rr.add('W1', 'wrong-node edits', rr.rid, g('wrong_node_edits'), 0, '==')
    rr.add('W1', 'stale-owner result commits', rr.rid, g('stale_committed'), 0, '==')
    rr.add('W1', 'commits after window close', rr.rid, g('commits_after_close', 0) + g('commits_after_close_backend', 0), 0, '==')
    rr.add('W1', 'row count constant (min=max=200)', rr.rid, bool(g('rows_min') == EXPECT_TOTAL_ROWS and g('rows_max') == EXPECT_TOTAL_ROWS),
           True, 'bool', f"min={g('rows_min')} max={g('rows_max')}")
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


def analyze_windows_run(rr, rdir, harness_run, hz, pm_rows, expect_scale, raw_dir):
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
    pin_checks(rr, meta, 'windows', expect_scale)
    integrity_checks(rr, integ, meta)
    rr.add('W1', 'commit errors', rr.rid, integ.get('commit_errors'), 0, '==', str(integ.get('commit_error_first', '')))
    rr.add('W1', 'renderer commits rejected', rr.rid, integ.get('renderer_commits_rejected'), 0, '==')
    rr.add('W1', 'renderer live nodes after teardown', rr.rid, integ.get('renderer_live_nodes_final'), 0, '==')
    rr.add('W1', 'renderer host panics / thread violations / reentry / dropped events', rr.rid,
           sum(integ.get(k, 0) for k in ('renderer_host_panics', 'renderer_thread_violations', 'renderer_reentry_refused',
                                         'renderer_events_dropped_full')), 0, '==')
    rr.add('W1', 'measure/draw failures', rr.rid, integ.get('measurer_failures', 0) + integ.get('draw_failures', 0), 0, '==')

    # lost valid commits: every injected key that landed must be an app input, in order, text exact
    sent_rows = [r for r in inj if r['sent'] == '1' and r['fg_ok'] == '1']
    fg_lost_rows = [r for r in inj if r['fg_ok'] != '1']
    expected = ''.join(KEY_CYCLE[int(r['seq']) % len(KEY_CYCLE)] for r in sent_rows)
    typed = int(integ.get('typed_count', -1))
    rr.add('W1', 'lost valid edits (injected - applied)', rr.rid, len(sent_rows) - typed, 0, '==', f'injected={len(sent_rows)} typed={typed}')
    rr.add('W1', 'active text equals injected sequence', rr.rid, integ.get('active_text') == expected[:typed] and typed == len(expected), True, 'bool')
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
    rr.add('CAL', 'keys in window (script delivered 10/s)', rr.rid, n_win_keys >= 0.95 * 10 * (me - ms) / hz, True, 'bool', f'keys={n_win_keys}')

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


def analyze(platform, root, expect_runs, expect_scale, out, incremental, quiet=False, allow_light=False, light_root=None):
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
                    analyze_windows_run(rr, rdir, hr, harness['qpc_hz'], pm, expect_scale, out)
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
        'runs': {rr.rid: {'summary': rr.summary, 'invalid': rr.invalid, 'checks': [c.row() for c in rr.checks]} for rr in runs},
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
        with open(f'{out}/report.md', 'w') as f:
            f.write('\n'.join(md) + '\n')
    return overall, all_checks, reasons


def selftest(keep=None):
    """Builds synthetic Windows run sets and asserts the PASS / FAIL / INCOMPLETE behaviour of the analyzer."""
    import random
    import shutil
    hz = 10_000_000
    frame = hz / 60.0

    def make(root, runs=3, latency_extra_ms=0.0, drop_calibration=False, drop_incremental=False, light=False, drop_run=None, empty_refresh=False):
        os.makedirs(root, exist_ok=True)
        rnd = random.Random(7)
        res = ['harness=selftest', f'host qpc_freq={hz} input_struct=40 gpu=x driver=y refresh_hz={"" if empty_refresh else 60} res={"x" if empty_refresh else "1920x1080"}']
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
            res += [f'=== RUN {rid} start=x', f'pid run={rid} pid={pid} start_utc=x qpc_start={t0 - hz}', 'window run=%s hwnd=1 foreground=direct dpi=96 client_px=960x640' % rid,
                    f'inject run={rid} sent=720 fg_lost=0 send_fail=0 csv=x', f'pid_exit run={rid} pid={pid} qpc_end={t0 + 72 * hz} exit=0', f'run_state id={rid} valid=1 reason=ok']
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
            for k in range(720):
                qb = int(t0 + 0.5 * hz + k * hz / 10)
                rx = qb + 3000
                ce = rx + 5000
                pc = sum(1 for s in starts if s < ce)
                inputs.append(f'{k + 1},{rx},{k + 1},{ce},{pc},{k + 1}')
                inj.append(f'{k},{KEY_CYCLE[k % 10]},{qb},{qb + 200},1,1')
                bin_rows.append(f'{k + 1},400000,{int(rnd.uniform(200000, 800000))}')
                text += KEY_CYCLE[k % 10]
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
            json.dump({'run_id': rid, 'platform': 'windows', 'instr': 'light' if light else 'full', 'hz': hz, 't0_ticks': t0, 'measure_start_ticks': ms,
                       'measure_end_ticks': me, 'warmup_s': 10, 'measure_s': 60, 'scale': '1.0', 'window_dip': {'w': 960, 'h': 640}, 'abi_major': 0, 'abi_minor': 6,
                       'debugger_present': 'false'}, open(f'{rdir}/meta.json', 'w'))
            json.dump({'wrong_node_edits': 0, 'stale_committed': 0, 'stale_rejected': 50, 'commits_after_close': 0, 'commits_after_close_backend': 0,
                       'rows_min': 200, 'rows_max': 200, 'unique_ids': True, 'app_exit': 'complete', 'closed': True, 'anim_interrupts': 20,
                       'updates_started': 750, 'inserts_started': 750, 'ops_skipped': 0, 'reorders': 70, 'typed_count': 720, 'active_text': text,
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
        ]
        for name, kw, want in cases:
            root = f'{tmp}/{re.sub(r"[^a-z]", "", name)}'
            inc = make(root, **kw)
            res = analyze('windows', root, 3, 1.0, None, inc)
            overall, checks, reasons = finish('windows', res, f'{root}/report', None)
            ok = overall == want
            print(f'selftest {name}: {overall} (want {want}) {"ok" if ok else "MISMATCH"}')
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
    result = analyze(platform, root, expect_runs, expect_scale, out, incremental)
    overall, checks, reasons = finish(platform, result, out, opts.get('light-root'))
    for c in checks:
        print(c.line())
    for r in reasons:
        print('REFUSED:', r)
    print(f'OVERALL: {overall}')
    print(f'report: {out}/report.json, {out}/report.md, raw samples: {out}/raw/')
    return {'PASS': 0, 'FAIL': 1, 'INCOMPLETE': 2}[overall]


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
